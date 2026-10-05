import { ParsedLrcItem } from '../utils/LyricParser';
import { LengthMetrics, curves, MeasureOptions } from '@kit.ArkUI';
import { displaySync } from '@kit.ArkGraphics2D';

/**
 * 自定义歌词组件
 * 支持：逐行扫光（linearGradient+blendMode 裁切字形，按测宽切行、词时间轴分段推进，
 * 多行歌词按显示行依次点亮）、翻译显示、上下渐隐、滑动 seek、字号调节
 */
@ComponentV2
export struct LyricView {
  /** 歌词列表 */
  @Param lyrics: Array<ParsedLrcItem> = [];
  /** 播放进度获取函数（返回秒），避免高频 @Param 刷新 */
  @Param positionProvider: () => number = () => 0;
  /** 是否正在播放 */
  @Param isPlaying: boolean = false;
  /** 字体缩放系数 */
  @Param fontScale: number = 1;
  /** 主题高亮色 */
  @Param highlightColor: ResourceColor = $r('sys.color.icon_emphasize');
  /** 是否显示翻译 */
  @Param showTranslation: boolean = false;
  /** 是否含翻译 */
  @Param hasTranslation: boolean = false;
  /** 歌词时间偏移（秒），定位时从播放进度中扣除 */
  @Param lyricOffset: number = 0;

  /** seek 回调（秒） */
  @Event onSeek: (time: number) => void = () => {};
  /** 当前行变化回调 */
  @Event onLyricLineChange: (item: ParsedLrcItem | null) => void = () => {};

  /** 当前行索引 */
  @Local currentIndex: number = -1;
  /** 内容区宽度（vp），onAreaChange 采样，用于预切显示行 */
  @Local viewWidth: number = 0;
  /** 当前行预切出的显示行文本 */
  @Local rowTexts: Array<string> = [];
  /** 每个显示行的扫光前沿 0~1 */
  @Local rowFronts: Array<number> = [];
  /** 用户手动滑动中 */
  @Local isUserScrolling: boolean = false;
  /** 滑动 seek 目标时间（秒） */
  @Local scrollTargetTime: number = -1;

  private scroller: Scroller = new Scroller();
  /** 弹簧动画曲线（参考 misc-utils 链式歌词参数：质量0.3/刚度200/阻尼15） */
  private springCurve: ICurve = curves.springCurve(0, 0.3, 200, 15);
  /** 首次定位标记：进入歌词模式先无动画跳到当前行，之后的切换才播弹簧滚动 */
  private hasLocated: boolean = false;
  private scrollTimer: number = -1;
  /** vsync 逐帧动画器：按显示帧率逐帧刷新扫光前沿 */
  private frameAnimator: displaySync.DisplaySync = displaySync.create();
  /** 最近一次引擎上报的原始位置（秒）与采样墙钟（毫秒），用于播放中外推 */
  private anchorRawPos: number = -1;
  private anchorWallMs: number = 0;
  /** 当前行拼接文本每个字符的时间窗（秒），与词内线性插值对齐 */
  private charTimes: number[] = [];
  private charEndTimes: number[] = [];
  /** 每个字符的显示宽度（vp），用于行内前沿按像素加权 */
  private charWidths: number[] = [];
  /** 每个显示行对应的字符区间 [start, end) */
  private rowCharRanges: Array<[number, number]> = [];
  /** 行模型缓存键：行索引_宽度_字号 */
  private cacheKey: string = '';

  aboutToAppear(): void {
    this.frameAnimator.setExpectedFrameRateRange({ min: 0, max: 120, expected: 60 });
    this.frameAnimator.on('frame', (info: displaySync.IntervalInfo): void => {
      this.updateProgress();
    });
    this.frameAnimator.start();
  }

  aboutToDisappear(): void {
    this.frameAnimator.stop();
    this.frameAnimator.off('frame');
    if (this.scrollTimer !== -1) {
      clearTimeout(this.scrollTimer);
      this.scrollTimer = -1;
    }
  }

  /** 歌词/字号变化时使行模型缓存失效，下一帧重建 */
  @Monitor('lyrics', 'fontScale')
  onRowSourceChange(): void {
    this.cacheKey = '';
  }

  /** vsync 逐帧采样：墙钟外推抹平引擎位置的阶梯上报，更新当前行与各行扫光前沿 */
  private updateProgress(): void {
    const nowMs = Date.now();
    const rawPos = this.positionProvider();
    if (rawPos !== this.anchorRawPos) {
      this.anchorRawPos = rawPos;
      this.anchorWallMs = nowMs;
    }
    let pos = this.anchorRawPos;
    if (this.isPlaying) {
      pos += (nowMs - this.anchorWallMs) / 1000;
    }
    pos -= this.lyricOffset;
    if (this.lyrics.length === 0) {
      return;
    }
    let idx = -1;
    for (let i = 0; i < this.lyrics.length; i++) {
      if (this.lyrics[i].time <= pos && pos < this.lyrics[i].endTime) {
        idx = i;
        break;
      }
    }
    if (idx !== this.currentIndex) {
      this.currentIndex = idx;
      this.onLyricLineChange(idx >= 0 ? this.lyrics[idx] : null);
      if (!this.isUserScrolling && idx >= 0) {
        if (this.hasLocated) {
          // 原生 smooth 滚动由滚动管线驱动，与切行重排并发无快照残影
          this.scroller.scrollToIndex(idx + 1, true, ScrollAlign.CENTER);
        } else {
          this.hasLocated = true;
          this.scroller.scrollToIndex(idx + 1, false, ScrollAlign.CENTER);
        }
      }
    }
    this.ensureRowModel(idx);
    if (idx >= 0 && this.lyrics[idx].words.length > 0) {
      const fronts = this.calcRowFronts(pos);
      if (!LyricView.frontsEqual(fronts, this.rowFronts)) {
        this.rowFronts = fronts;
      }
    } else if (this.rowFronts.length > 0) {
      this.rowFronts = [];
    }
  }

  /** 行模型（显示行切分 + 字符时间轴/宽度）按 行索引+宽度+字号 缓存重建 */
  private ensureRowModel(idx: number): void {
    const key = idx.toString() + '_' + Math.round(this.viewWidth).toString() + '_' + this.fontScale.toString();
    if (key === this.cacheKey) {
      return;
    }
    this.cacheKey = key;
    this.rebuildRowModel(idx);
  }

  /** 重建当前行模型：拼接词文本与字符时间窗，按测宽贪心切分为显示行 */
  private rebuildRowModel(idx: number): void {
    this.charTimes = [];
    this.charEndTimes = [];
    this.charWidths = [];
    this.rowCharRanges = [];
    this.rowTexts = [];
    this.rowFronts = [];
    if (idx < 0 || idx >= this.lyrics.length) {
      return;
    }
    const words = this.lyrics[idx].words;
    if (words.length === 0) {
      return;
    }
    let full = '';
    for (let w = 0; w < words.length; w++) {
      const word = words[w];
      const count = word.text.length;
      const span = word.endTime - word.startTime;
      for (let j = 0; j < count; j++) {
        const startT = span > 0 ? word.startTime + span * (j / count) : word.startTime;
        const endT = span > 0
          ? (j === count - 1 ? word.endTime : word.startTime + span * ((j + 1) / count))
          : word.startTime;
        full += word.text.charAt(j);
        this.charTimes.push(startT);
        this.charEndTimes.push(Math.max(endT, startT));
      }
    }
    const fp = Math.round(20 * this.fontScale);
    const maxW = this.viewWidth - 2;
    if (maxW <= 0) {
      // 宽度未知时整行兜底（首帧），拿到 onAreaChange 后下一帧即重切
      this.rowTexts = [full];
      this.rowCharRanges = [[0, full.length]];
      this.charWidths = new Array<number>(full.length).fill(1);
      return;
    }
    const utils = this.getUIContext().getMeasureUtils();
    const rows: string[] = [];
    const ranges: Array<[number, number]> = [];
    let lineStart = 0;
    let lineW = 0;
    let i = 0;
    while (i < full.length) {
      if (lineW === 0 && full.charAt(i) === ' ') {
        i++;
        continue;
      }
      const token = LyricView.nextToken(full, i);
      const tokenText = token[0];
      const tokenEnd = token[1];
      const options: MeasureOptions = {
        textContent: tokenText,
        fontSize: fp,
        fontWeight: FontWeight.Bold
      };
      const w = this.getUIContext().px2vp(utils.measureText(options));
      if (lineW > 0 && lineW + w > maxW) {
        rows.push(full.substring(lineStart, i));
        ranges.push([lineStart, i]);
        lineW = 0;
        continue;
      }
      if (lineW === 0) {
        lineStart = i;
      }
      const perChar = w / tokenText.length;
      for (let k = 0; k < tokenText.length; k++) {
        this.charWidths.push(perChar);
      }
      lineW += w;
      i = tokenEnd;
    }
    if (lineStart < full.length) {
      rows.push(full.substring(lineStart));
      ranges.push([lineStart, full.length]);
    }
    this.rowTexts = rows;
    this.rowCharRanges = ranges;
  }

  /** 取从 from 开始的排版 token：连续拉丁字母/数字为一个词，其余单字成 token */
  private static nextToken(text: string, from: number): [string, number] {
    const first = text.charAt(from);
    if (LyricView.isLatinChar(first)) {
      let end = from + 1;
      while (end < text.length && LyricView.isLatinChar(text.charAt(end))) {
        end++;
      }
      return [text.substring(from, end), end];
    }
    return [first, from + 1];
  }

  private static isLatinChar(c: string): boolean {
    const code = c.charCodeAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) ||
      (code >= 48 && code <= 57) || code === 39 || code === 45;
  }

  /** 第 i 个字符的着色进度 0~1（在其时间窗内线性推进） */
  private charProgressAt(i: number, pos: number): number {
    if (i < 0 || i >= this.charTimes.length) {
      return 0;
    }
    if (pos < this.charTimes[i]) {
      return 0;
    }
    const endT = this.charEndTimes[i];
    if (pos >= endT) {
      return 1;
    }
    const span = endT - this.charTimes[i];
    return span > 0 ? (pos - this.charTimes[i]) / span : 1;
  }

  /** 每个显示行的扫光前沿：行内字符进度按像素宽度加权，唱满为 1 */
  private calcRowFronts(pos: number): Array<number> {
    const fronts: number[] = [];
    for (let r = 0; r < this.rowCharRanges.length; r++) {
      const s = this.rowCharRanges[r][0];
      const e = this.rowCharRanges[r][1];
      let weighted = 0;
      let totalW = 0;
      for (let i = s; i < e; i++) {
        const w = i < this.charWidths.length ? this.charWidths[i] : 1;
        weighted += this.charProgressAt(i, pos) * w;
        totalW += w;
      }
      fronts.push(totalW > 0 ? Math.max(0, Math.min(1, weighted / totalW)) : 1);
    }
    return fronts;
  }

  private static frontsEqual(a: Array<number>, b: Array<number>): boolean {
    if (a.length !== b.length) {
      return false;
    }
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) {
        return false;
      }
    }
    return true;
  }

  /** 显示行渐变色标：高亮→前沿过渡带→次要色，从左至右扫光 */
  private rowGradientColors(rowIndex: number): Array<[ResourceColor, number]> {
    let v = 0;
    if (rowIndex < this.rowFronts.length) {
      v = Math.max(0, Math.min(1, this.rowFronts[rowIndex]));
    }
    if (v >= 1) {
      const done: Array<[ResourceColor, number]> = [[this.highlightColor, 0.0], [this.highlightColor, 1.0]];
      return done;
    }
    if (v <= 0) {
      const pending: Array<[ResourceColor, number]> =
        [[$r('sys.color.font_secondary'), 0.0], [$r('sys.color.font_secondary'), 1.0]];
      return pending;
    }
    const smooth = 0.02;
    const colors: Array<[ResourceColor, number]> = [
      [this.highlightColor, 0.0],
      [this.highlightColor, Math.max(0, v - smooth)],
      [$r('sys.color.font_secondary'), Math.min(1, v + smooth)],
      [$r('sys.color.font_secondary'), 1.0]
    ];
    return colors;
  }

  /** 用户触摸：按下暂停自动滚动，松手 3 秒后恢复 */
  private handleTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.isUserScrolling = true;
      if (this.scrollTimer !== -1) {
        clearTimeout(this.scrollTimer);
        this.scrollTimer = -1;
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.scrollTimer !== -1) {
        clearTimeout(this.scrollTimer);
      }
      this.scrollTimer = setTimeout((): void => {
        this.isUserScrolling = false;
        this.scrollTargetTime = -1;
        this.scrollTimer = -1;
      }, 3000);
    }
  }

  /** 时间格式化 mm:ss */
  private static formatTime(sec: number): string {
    const s = Math.max(0, Math.floor(sec));
    const m = Math.floor(s / 60);
    const r = s % 60;
    return m.toString().padStart(2, '0') + ':' + r.toString().padStart(2, '0');
  }

  @Builder
  SeekIndicator() {
    if (this.isUserScrolling && this.scrollTargetTime >= 0) {
      Row({ space: 12 }) {
        Text(LyricView.formatTime(this.scrollTargetTime))
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))

        Column()
          .layoutWeight(1)
          .height(1)
          .backgroundColor($r('sys.color.font_tertiary'))

        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(20)
          .fontColor([this.highlightColor])
          .onClick(() => {
            this.onSeek(this.scrollTargetTime);
            this.isUserScrolling = false;
            this.scrollTargetTime = -1;
            if (this.scrollTimer !== -1) {
              clearTimeout(this.scrollTimer);
              this.scrollTimer = -1;
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)
      .transition(TransitionEffect.OPACITY)
    }
  }

  build() {
    if (this.lyrics.length === 0) {
      Column() {
        Text('暂无歌词')
          .fontSize(14)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      Stack() {
        List({ scroller: this.scroller }) {
          ListItem() {
            Column().width('100%').height(120)
          }
          ForEach(this.lyrics, (item: ParsedLrcItem, index: number) => {
            ListItem() {
              Column({ space: 4 }) {
                if (index === this.currentIndex) {
                  if (item.words.length > 0) {
                    // 逐行扫光：预切显示行，每行独立渐变+blendMode 裁切字形，前沿按词时间轴依次推进
                    Column() {
                      ForEach(this.rowTexts, (rowText: string, rowIdx: number) => {
                        Row() {
                          Text(rowText)
                            .fontSize(Math.round(20 * this.fontScale))
                            .fontWeight(FontWeight.Bold)
                            .maxLines(1)
                            .blendMode(BlendMode.DST_IN, BlendApplyType.OFFSCREEN)
                        }
                        .linearGradient({
                          direction: GradientDirection.Right,
                          colors: this.rowGradientColors(rowIdx)
                        })
                        .blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN)
                      }, (rowText: string, rowIdx: number) => rowIdx.toString() + '_' + rowText)
                    }
                    .width('100%')
                    .alignItems(HorizontalAlign.Center)
                  } else {
                    Text(item.lrc)
                      .fontSize(Math.round(20 * this.fontScale))
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.highlightColor)
                      .textAlign(TextAlign.Center)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .animation({ duration: 400, curve: Curve.EaseOut })
                  }
                } else {
                  Text(item.lrc)
                    .fontSize(Math.round(16 * this.fontScale))
                    .fontColor($r('sys.color.font_secondary'))
                    .textAlign(TextAlign.Center)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .animation({ duration: 400, curve: Curve.EaseOut })
                }
                if (this.showTranslation && this.hasTranslation && item.translation.length > 0) {
                  Text(item.translation)
                    .fontSize(index === this.currentIndex
                      ? Math.round(14 * this.fontScale) : Math.round(12 * this.fontScale))
                    .fontColor(index === this.currentIndex
                      ? $r('sys.color.font_secondary') : $r('sys.color.font_tertiary'))
                    .textAlign(TextAlign.Center)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .animation({ duration: 400, curve: Curve.EaseOut })
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              // 高亮行间距呼吸 + 非高亮行整体缩小，均随弹簧曲线过渡
              .padding({
                top: index === this.currentIndex ? 14 : 8,
                bottom: index === this.currentIndex ? 14 : 8
              })
              .scale({
                x: index === this.currentIndex ? 1 : 0.88,
                y: index === this.currentIndex ? 1 : 0.88
              })
              .animation({ curve: this.springCurve })
              .onClick(() => {
                this.onSeek(item.time);
              })
            }
          }, (item: ParsedLrcItem) => item.index.toString() + '_' + item.time.toString())
          ListItem() {
            Column().width('100%').height(120)
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .alignListItem(ListItemAlign.Center)
        .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(60) })
        .onAreaChange((_old: Area, newArea: Area) => {
          const w = newArea.width;
          if (typeof w === 'number') {
            this.viewWidth = w;
          }
        })
        .onTouch((event: TouchEvent): void => {
          this.handleTouch(event);
        })
        .onScrollIndex((start: number, end: number, center: number) => {
          if (this.isUserScrolling && center > 0 && center <= this.lyrics.length) {
            this.scrollTargetTime = this.lyrics[center - 1].time;
          }
        })

        this.SeekIndicator()
      }
      .width('100%')
      .height('100%')
    }
  }
}
