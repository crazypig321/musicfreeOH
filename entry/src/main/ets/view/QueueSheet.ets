import { MusicItem } from '../common/model/MediaTypes';
import { trackPlayer } from '../core/TrackPlayer';
import { PlayState } from '../core/PlayerEngine';
import { MusicRepeatMode } from '../common/Consts';
import { MusicDataSource } from '../common/model/MusicDataSource';
import { MediaUtils } from '../utils/MediaUtils';
import { appState } from '../entryability/AppState';
import { sheetTopAvoidVp } from '../utils/BreakpointUtils';

/** 播放中指示器：5 根随机高度跳动的方柱（仅播放中跳动，暂停/停止时静止） */
@ComponentV2
struct PlayingBars {
  @Local heights: Array<number> = [8, 12, 10, 14, 9];
  private timerId: number = -1;
  private offState: () => void = (): void => {
  };

  aboutToAppear(): void {
    this.offState = trackPlayer.onPlayStateChanged((state: PlayState): void => {
      if (state === PlayState.Playing) {
        this.startTimer();
      } else {
        this.stopTimer();
      }
    });
    if (trackPlayer.playState === PlayState.Playing) {
      this.startTimer();
    }
  }

  aboutToDisappear(): void {
    this.stopTimer();
    this.offState();
  }

  private startTimer(): void {
    if (this.timerId !== -1) {
      return;
    }
    this.timerId = setInterval((): void => {
      const next: Array<number> = [];
      for (let i = 0; i < 5; i++) {
        next.push(4 + Math.random() * 14);
      }
      this.getUIContext().animateTo({ duration: 380, curve: Curve.EaseInOut }, (): void => {
        this.heights = next;
      });
    }, 400);
  }

  private stopTimer(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    // 暂停/停止时恢复静止高度
    this.heights = [8, 12, 10, 14, 9];
  }

  build() {
    Row({ space: 2 }) {
      Column().width(3).height(this.heights[0]).borderRadius(1.5)
        .backgroundColor(appState.accentColor)
      Column().width(3).height(this.heights[1]).borderRadius(1.5)
        .backgroundColor(appState.accentColor)
      Column().width(3).height(this.heights[2]).borderRadius(1.5)
        .backgroundColor(appState.accentColor)
      Column().width(3).height(this.heights[3]).borderRadius(1.5)
        .backgroundColor(appState.accentColor)
      Column().width(3).height(this.heights[4]).borderRadius(1.5)
        .backgroundColor(appState.accentColor)
    }
    .height(18)
    .alignItems(VerticalAlign.Bottom)
  }
}

/**
 * 队列条目：自行订阅当前歌曲变化，确保高亮/播放中动效即时刷新
 * （LazyForEach 缓存条目不随父组件状态变化重渲染，需条目自行维护状态）
 */
@ComponentV2
struct QueueRow {
  @Require @Param item: MusicItem;
  @Param index: number = 0;
  @Param isLast: boolean = false;
  @Event onPlay: (item: MusicItem) => void = (item: MusicItem): void => {
  };
  @Event onRemove: (item: MusicItem) => void = (item: MusicItem): void => {
  };
  @Local currentMusic: MusicItem | null = null;
  private offCurrent: () => void = (): void => {
  };

  aboutToAppear(): void {
    this.currentMusic = trackPlayer.currentMusic;
    this.offCurrent = trackPlayer.onCurrentMusicChanged((music: MusicItem | null) => {
      this.currentMusic = music;
    });
  }

  aboutToDisappear(): void {
    this.offCurrent();
  }

  private isCurrent(): boolean {
    return MediaUtils.isSameMediaItem(this.item, this.currentMusic);
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        // 序号（当前曲目高亮）
        Text((this.index + 1).toString())
          .fontSize(12)
          .fontColor(this.isCurrent() ? appState.accentColor : $r('sys.color.font_tertiary'))
          .width(20)
          .textAlign(TextAlign.Start)

        Column({ space: 2 }) {
          Text(this.item.title)
            .fontSize(15)
            .fontWeight(this.isCurrent() ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.isCurrent() ? appState.accentColor : $r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.item.artist + (this.item.album.length > 0 ? ' · ' + this.item.album : ''))
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // 播放中：跳动方柱
        if (this.isCurrent()) {
          PlayingBars()
        }

        // 来源标签（样式同首页来源标签）
        if (this.item.platform.length > 0) {
          Text(this.item.platform)
            .fontSize(10)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 64 })
            .padding({ top: 3, bottom: 3, left: 5, right: 5 })
            .borderRadius(3)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
        }

        // 从队列移除
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(16)
          .fontColor([$r('sys.color.icon_secondary')])
          .onClick(() => {
            this.onRemove(this.item);
          })
      }
      .width('100%')
      .height(52)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (!this.isCurrent()) {
          this.onPlay(this.item);
        }
      })

      // 条目间分割线（避开序号区域，与标题对齐）
      if (!this.isLast) {
        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.comp_divider'))
          .margin({ left: 28 })
      }
    }
    .width('100%')
  }
}

/**
 * 播放队列半模态内容（自管理队列数据）：供 PlayBar / PlayerPage 通过 bindSheet 使用，
 * 可见性（show）与 sheet 外观由宿主控制
 */
@ComponentV2
export struct QueueSheet {
  /** 队列条目数（驱动头部/空态刷新） */
  @Local queueCount: number = 0;
  /** 循环模式（切换后本地同步以刷新图标） */
  @Local repeatMode: MusicRepeatMode = MusicRepeatMode.QUEUE;
  /** 当前播放歌曲（头部「当前播放：序号.歌曲名」显示） */
  @Local currentMusic: MusicItem | null = null;
  /** 播放队列数据源（LazyForEach） */
  private queueDataSource: MusicDataSource = new MusicDataSource();
  private queueScroller: Scroller = new Scroller();
  private offPlayList: () => void = (): void => {
  };
  private offCurrent: () => void = (): void => {
  };
  private offRepeatMode: () => void = (): void => {
  };

  aboutToAppear(): void {
    this.repeatMode = trackPlayer.repeatMode;
    this.currentMusic = trackPlayer.currentMusic;
    this.refreshQueue();
    this.offPlayList = trackPlayer.onPlayListChanged(() => {
      this.refreshQueue();
    });
    this.offCurrent = trackPlayer.onCurrentMusicChanged((music: MusicItem | null) => {
      this.currentMusic = music;
    });
    // 播放页等其他入口切换播放方式时同步本组件按钮
    this.offRepeatMode = trackPlayer.onRepeatModeChanged((mode: MusicRepeatMode) => {
      this.repeatMode = mode;
    });
  }

  aboutToDisappear(): void {
    this.offPlayList();
    this.offCurrent();
    this.offRepeatMode();
  }

  /** 刷新播放队列数据源 */
  private refreshQueue(): void {
    const list = trackPlayer.playList.slice();
    this.queueDataSource.clear();
    this.queueDataSource.appendData(list);
    this.queueCount = list.length;
  }

  /** 当前播放歌曲在队列中的下标 */
  private currentQueueIndex(): number {
    const current = trackPlayer.currentMusic;
    if (current === null) {
      return -1;
    }
    const items = this.queueDataSource.getItems();
    for (let i = 0; i < items.length; i++) {
      if (MediaUtils.isSameMediaItem(items[i], current)) {
        return i;
      }
    }
    return -1;
  }

  /** 循环模式图标：随机 / 单曲循环 / 列表循环 */
  private repeatIcon(): Resource {
    if (this.repeatMode === MusicRepeatMode.SHUFFLE) {
      return $r('sys.symbol.shuffle');
    }
    if (this.repeatMode === MusicRepeatMode.SINGLE) {
      return $r('sys.symbol.repeat_1');
    }
    return $r('sys.symbol.repeat');
  }

  /** 循环模式文本 */
  private repeatLabel(): string {
    if (this.repeatMode === MusicRepeatMode.SHUFFLE) {
      return '随机';
    }
    if (this.repeatMode === MusicRepeatMode.SINGLE) {
      return '单曲循环';
    }
    return '列表循环';
  }

  /** 头部「当前播放：序号.歌曲名」 */
  private currentPlayText(): string {
    const idx = this.currentQueueIndex();
    if (this.currentMusic === null || idx === -1) {
      return '正在播放';
    }
    return '正在播放：' + (idx + 1).toString() + '. ' + this.currentMusic.title;
  }

  /** 切换循环模式 */
  private toggleRepeatMode(): void {
    trackPlayer.toggleRepeatMode();
    this.repeatMode = trackPlayer.repeatMode;
    this.showToast(this.repeatMode === MusicRepeatMode.SHUFFLE ? '随机播放' :
      (this.repeatMode === MusicRepeatMode.SINGLE ? '单曲循环' : '列表循环'));
  }

  /** 清空播放队列 */
  private clearQueue(): void {
    if (this.queueCount === 0) {
      return;
    }
    trackPlayer.clearPlayList().then((): void => {
      this.showToast('已清空播放队列');
    }).catch((_e: Object): void => {
      this.showToast('清空失败');
    });
  }

  /** 从队列中移除单个条目 */
  private removeFromQueue(item: MusicItem): void {
    trackPlayer.remove(item).catch((_e: Object): void => {
      this.showToast('移除失败');
    });
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  build() {
    Column() {
      // 固定头部：不随列表滚动
      Column() {
        Column({ space: 2 }) {
          Text('当前播放队列')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          Text('共 ' + this.queueCount.toString() + ' 首')
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .margin({ top: 4, bottom: 4 })

        // 当前播放 + 循环模式/清空（图标带文字标签）
        if (this.queueCount > 0) {
          Row() {
            Text(this.currentPlayText())
              .fontSize(12)
              .fontColor($r('sys.color.font_tertiary'))
              .maxLines(1)
           //   .fontWeight(FontWeight.Bold)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .padding({right: 10})

            Row({ space: 10 }) {
              Row({ space: 4 }) {
                SymbolGlyph(this.repeatIcon())
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text(this.repeatLabel())
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
              }
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.toggleRepeatMode();
              })

              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('清空')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
              }
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.clearQueue();
              })
            }
            .alignItems(VerticalAlign.Center)
          }
          .justifyContent(FlexAlign.SpaceBetween)
          .width('100%')
          .margin({ top: 12, bottom: 8 })
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12 + sheetTopAvoidVp() })
      .backgroundColor($r('sys.color.background_secondary'))

      if (this.queueCount === 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.music_note_list'))
            .fontSize(44)
            .fontColor([$r('sys.color.icon_tertiary')])
          Text('播放队列为空')
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ scroller: this.queueScroller }) {
          LazyForEach(this.queueDataSource, (item: MusicItem, index: number) => {
            ListItem() {
              QueueRow({
                item: item,
                index: index,
                isLast: index === this.queueDataSource.totalCount() - 1,
                onPlay: (playItem: MusicItem): void => {
                  trackPlayer.play(playItem).catch((_e: Object): void => {
                    this.showToast('播放失败');
                  });
                },
                onRemove: (removeItem: MusicItem): void => {
                  this.removeFromQueue(removeItem);
                }
              })
            }
          }, (item: MusicItem, index: number) => item.platform + '_' + item.id + '_' + index.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 20, right: 20, bottom: 32 })
        .scrollBar(BarState.Off)
        .nestedScroll({
          scrollForward: NestedScrollMode.PARENT_FIRST,
          scrollBackward: NestedScrollMode.SELF_FIRST
        })
        .onAppear(() => {
          // 打开时定位到当前播放曲目
          const idx = this.currentQueueIndex();
          if (idx > 0) {
            this.queueScroller.scrollToIndex(idx, false, ScrollAlign.CENTER);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_secondary'))
    .alignItems(HorizontalAlign.Start)
  }
}
