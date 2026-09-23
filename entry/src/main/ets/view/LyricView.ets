import { ParsedLrcItem, LyricWord } from '../utils/LyricParser';
import { LengthMetrics } from '@kit.ArkUI';

/**
 * 自定义歌词组件
 * 支持：逐字渐变变色、翻译显示、上下渐隐、滑动 seek、字号调节
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
  /** 当前行已唱到的词索引（-1=尚未开始） */
  @Local currentWordIndex: number = -1;
  /** 正在唱的词渐变进度 0~1 */
  @Local wordProgress: number = 0;
  /** 用户手动滑动中 */
  @Local isUserScrolling: boolean = false;
  /** 滑动 seek 目标时间（秒） */
  @Local scrollTargetTime: number = -1;

  private scroller: Scroller = new Scroller();
  private scrollTimer: number = -1;
  private progressTimer: number = -1;

  aboutToAppear(): void {
    this.startProgressTimer();
  }

  aboutToDisappear(): void {
    this.stopProgressTimer();
    if (this.scrollTimer !== -1) {
      clearTimeout(this.scrollTimer);
      this.scrollTimer = -1;
    }
  }

  private startProgressTimer(): void {
    if (this.progressTimer === -1) {
      this.progressTimer = setInterval((): void => this.updateProgress(), 16);
    }
  }

  private stopProgressTimer(): void {
    if (this.progressTimer !== -1) {
      clearInterval(this.progressTimer);
      this.progressTimer = -1;
    }
  }

  /** 16ms 采样：更新当前行索引和渐变进度 */
  private updateProgress(): void {
    const pos = this.positionProvider() - this.lyricOffset;
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
        this.scroller.scrollToIndex(idx + 1, true, ScrollAlign.CENTER);
      }
    }
    if (idx >= 0) {
      const newWordIndex = this.calcWordIndex(this.lyrics[idx], pos);
      const newProgress = this.calcWordProgress(this.lyrics[idx], pos, newWordIndex);
      if (newWordIndex === this.currentWordIndex) {
        // 同一词内：用 animateTo 平滑插值渐变进度，避免 linearGradient 硬切顿挫
        this.getUIContext().animateTo({ duration: 48, curve: Curve.Linear }, (): void => {
          this.wordProgress = newProgress;
        });
      } else {
        // 词切换：直接更新，不做插值（避免从 1 回退到 0 的回扫动画）
        this.currentWordIndex = newWordIndex;
        this.wordProgress = newProgress;
      }
    } else {
      this.currentWordIndex = -1;
      this.wordProgress = 0;
    }
  }

  /** 计算当前唱到第几个词（-1=尚未开始） */
  private calcWordIndex(item: ParsedLrcItem, pos: number): number {
    if (item.words.length === 0) {
      return pos >= item.time ? 0 : -1;
    }
    let idx = -1;
    for (let i = 0; i < item.words.length; i++) {
      if (pos >= item.words[i].startTime) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  /** 计算正在唱的词内渐变进度 0~1 */
  private calcWordProgress(item: ParsedLrcItem, pos: number, wordIdx: number): number {
    if (wordIdx < 0 || wordIdx >= item.words.length) {
      return 0;
    }
    const w = item.words[wordIdx];
    const duration = w.endTime - w.startTime;
    return duration > 0 ? Math.min(1, Math.max(0, (pos - w.startTime) / duration)) : 1;
  }

  /** 渐变色 stops：已唱=高亮，未唱=次要色（边界加微小过渡区间柔化硬切） */
  private gradientColors(value: number): Array<[ResourceColor, number]> {
    const v = Math.max(0, Math.min(1, value));
    const smooth = 0.012;
    return [
      [this.highlightColor, 0.0],
      [this.highlightColor, Math.max(0, v - smooth)],
      [$r('sys.color.font_secondary'), Math.min(1, v + smooth)],
      [$r('sys.color.font_secondary'), 1.0]
    ];
  }

  /** 第 i 个词的渐变进度：已唱完=1，正在唱=wordProgress，未唱=0 */
  private wordProgressAt(i: number): number {
    if (i < this.currentWordIndex) {
      return 1;
    } else if (i === this.currentWordIndex) {
      return this.wordProgress;
    } else {
      return 0;
    }
  }

  /** 第 i 个词的线性渐变样式（直接作用于 Text 文字像素，无需 blendMode 离屏渲染） */
  private wordShader(i: number): ShaderStyle {
    const opts: LinearGradientOptions = {
      direction: GradientDirection.Right,
      colors: this.gradientColors(this.wordProgressAt(i))
    };
    return new LinearGradientStyle(opts);
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
                    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center}) {
                      ForEach(item.words, (word: LyricWord, i: number) => {
                        Text(word.text)
                          .fontSize(Math.round(20 * this.fontScale))
                          .fontWeight(FontWeight.Bold)
                          .shaderStyle(this.wordShader(i))
                          .animation({ duration: 200, curve: Curve.Linear })
                      }, (word: LyricWord, i: number) => i.toString())
                    }.width('100%')
                  } else {
                    Text(item.lrc)
                      .fontSize(Math.round(20 * this.fontScale))
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.highlightColor)
                      .textAlign(TextAlign.Center)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .animation({ duration: 300, curve: Curve.EaseInOut })
                  }
                } else {
                  Text(item.lrc)
                    .fontSize(Math.round(16 * this.fontScale))
                    .fontColor($r('sys.color.font_secondary'))
                    .textAlign(TextAlign.Center)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .animation({ duration: 300, curve: Curve.EaseInOut })
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
                    .animation({ duration: 300, curve: Curve.EaseInOut })
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 10, bottom: 10 })
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
