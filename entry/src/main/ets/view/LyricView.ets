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

  /** seek 回调（秒） */
  @Event onSeek: (time: number) => void = () => {};
  /** 当前行变化回调 */
  @Event onLyricLineChange: (item: ParsedLrcItem | null) => void = () => {};

  /** 当前行索引 */
  @Local currentIndex: number = -1;
  /** 当前行已唱到的词索引（-1=尚未开始） */
  @Local currentWordIndex: number = -1;
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
      this.progressTimer = setInterval((): void => this.updateProgress(), 30);
    }
  }

  private stopProgressTimer(): void {
    if (this.progressTimer !== -1) {
      clearInterval(this.progressTimer);
      this.progressTimer = -1;
    }
  }

  /** 30ms 采样：更新当前行索引和渐变进度 */
  private updateProgress(): void {
    const pos = this.positionProvider();
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
      this.currentWordIndex = this.calcWordIndex(this.lyrics[idx], pos);
    } else {
      this.currentWordIndex = -1;
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
                  Text() {
                    if (item.words.length > 0) {
                      ForEach(item.words, (word: LyricWord, i: number) => {
                        Span(word.text)
                          .fontColor(i <= this.currentWordIndex
                            ? this.highlightColor : $r('sys.color.font_secondary'))
                          .animation({ duration: 200, curve: Curve.EaseOut })
                      }, (word: LyricWord, i: number) => i.toString())
                    } else {
                      Span(item.lrc)
                        .fontColor(this.highlightColor)
                    }
                  }
                  .fontSize(Math.round(20 * this.fontScale))
                  .fontWeight(FontWeight.Bold)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .animation({ duration: 300, curve: Curve.EaseInOut })
                } else {
                  Text(item.lrc)
                    .fontSize(Math.round(16 * this.fontScale))
                    .fontColor($r('sys.color.font_secondary'))
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
