import { pasteboard } from '@kit.BasicServicesKit';
import { MusicItem } from '../common/model/MediaTypes';
import { trackPlayer } from '../core/TrackPlayer';
import { PlayState } from '../core/PlayerEngine';
import { MusicRepeatMode } from '../common/Consts';
import { musicSheet } from '../core/MusicSheet';
import { lyricManager, LyricState } from '../core/LyricManager';
import { ParsedLrcItem } from '../utils/LyricParser';
import { MediaUtils } from '../utils/MediaUtils';
import { appState } from '../entryability/AppState';
import { NavPathUtils } from '../utils/NavPathUtils';
import { QueueSheet } from '../view/QueueSheet';

/**
 * 全屏播放页（结构参考官方多设备音乐最佳实践）：
 * 顶部栏（收起/分享）+ 封面区 + 当前行歌词 + 进度条 + 播放控制 + 辅助功能（循环/收藏/队列）
 * 背景为当前封面高斯模糊 + 主题色蒙层
 */
@ComponentV2
export struct PlayerPage {
  @Local currentMusic: MusicItem | null = null;
  @Local isPlaying: boolean = false;
  @Local currentPosition: number = 0;
  @Local duration: number = 0;
  @Local repeatMode: MusicRepeatMode = MusicRepeatMode.QUEUE;
  @Local isFavorited: boolean = false;
  @Local lyricLoading: boolean = true;
  @Local currentLyric: ParsedLrcItem | null = null;
  /** 播放队列半模态 */
  @Local showQueue: boolean = false;
  /** 用户拖动进度条期间不回写进度事件 */
  private isSeeking: boolean = false;
  private offCurrent: () => void = (): void => {
  };
  private offState: () => void = (): void => {
  };
  private offProgress: () => void = (): void => {
  };
  private offLyricState: () => void = (): void => {
  };
  private offCurrentLyric: () => void = (): void => {
  };

  aboutToAppear(): void {
    this.currentMusic = trackPlayer.currentMusic;
    this.isPlaying = trackPlayer.playState === PlayState.Playing;
    const progress = trackPlayer.getProgress();
    this.currentPosition = progress.position;
    this.duration = progress.duration;
    this.repeatMode = trackPlayer.repeatMode;
    this.refreshFavorite();
    this.syncLyricState(lyricManager.lyricState);
    this.currentLyric = lyricManager.currentLyricItem;

    this.offCurrent = trackPlayer.onCurrentMusicChanged((music: MusicItem | null) => {
      this.currentMusic = music;
      this.currentPosition = 0;
      this.refreshFavorite();
    });
    this.offState = trackPlayer.onPlayStateChanged((state: PlayState) => {
      this.isPlaying = state === PlayState.Playing;
    });
    this.offProgress = trackPlayer.onProgressChanged((position: number, duration: number) => {
      if (duration > 0) {
        this.duration = duration;
      }
      if (!this.isSeeking) {
        this.currentPosition = position;
      }
    });
    this.offLyricState = lyricManager.onLyricStateChanged((state: LyricState) => {
      this.syncLyricState(state);
    });
    this.offCurrentLyric = lyricManager.onCurrentLyricChanged((item: ParsedLrcItem | null) => {
      this.currentLyric = item;
    });
  }

  aboutToDisappear(): void {
    this.offCurrent();
    this.offState();
    this.offProgress();
    this.offLyricState();
    this.offCurrentLyric();
  }

  private syncLyricState(state: LyricState): void {
    this.lyricLoading = state.loading;
  }

  private refreshFavorite(): void {
    const current = this.currentMusic;
    if (current === null) {
      this.isFavorited = false;
      return;
    }
    const favList = musicSheet.getMusicList(musicSheet.defaultSheet.id);
    for (const it of favList) {
      if (MediaUtils.isSameMediaItem(it, current)) {
        this.isFavorited = true;
        return;
      }
    }
    this.isFavorited = false;
  }

  private toggleFavorite(): void {
    const current = this.currentMusic;
    if (current === null) {
      return;
    }
    if (this.isFavorited) {
      musicSheet.removeMusic(musicSheet.defaultSheet.id, [current]).then((): void => {
        this.isFavorited = false;
        this.showToast('已取消收藏');
      });
    } else {
      musicSheet.addMusic(musicSheet.defaultSheet.id, current).then((): void => {
        this.isFavorited = true;
        this.showToast('已收藏到我喜欢的音乐');
      });
    }
  }

  /** 切换循环模式 */
  private toggleRepeatMode(): void {
    trackPlayer.toggleRepeatMode();
    this.repeatMode = trackPlayer.repeatMode;
    this.showToast(this.repeatMode === MusicRepeatMode.SHUFFLE ? '随机播放' :
      (this.repeatMode === MusicRepeatMode.SINGLE ? '单曲循环' : '列表循环'));
  }

  private togglePlay(): void {
    if (this.isPlaying) {
      trackPlayer.pause().catch((): void => {
      });
    } else {
      trackPlayer.play().catch((): void => {
      });
    }
  }

  private skipToPrevious(): void {
    trackPlayer.skipToPrevious().catch((): void => {
    });
  }

  private skipToNext(): void {
    trackPlayer.skipToNext().catch((): void => {
    });
  }

  /** 分享：复制歌曲信息 */
  private shareCurrent(): void {
    const current = this.currentMusic;
    if (current === null) {
      return;
    }
    const text = '「' + current.title + '」 - ' + current.artist + '（来自 ' + current.platform + '）';
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      this.showToast('已复制歌曲信息，可粘贴分享');
    }).catch((_e: Object): void => {
      this.showToast('复制失败');
    });
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

  /** 进度条最大值（时长未知时保持 1 避免除零） */
  private sliderMax(): number {
    return this.duration > 0 ? this.duration : 1;
  }

  private static formatDuration(sec: number): string {
    const s = Math.max(0, Math.floor(sec));
    const m = Math.floor(s / 60);
    const r = s % 60;
    const mStr = m < 10 ? '0' + m.toString() : m.toString();
    const rStr = r < 10 ? '0' + r.toString() : r.toString();
    return mStr + ':' + rStr;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  build() {
    NavDestination() {
      Stack() {
        // 背景：封面高斯模糊 + 主题色蒙层
        if (this.currentMusic !== null && this.currentMusic.artwork.length > 0) {
          Image(this.currentMusic.artwork)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .blur(80)
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor($r('sys.color.background_secondary'))
            .opacity(0.82)
        }

        if (this.currentMusic === null) {
          // 空态
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.music_note_list'))
              .fontSize(48)
              .fontColor([$r('sys.color.icon_tertiary')])
            Text('还没有正在播放的歌曲')
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Column() {
            // 顶部栏：收起 + 分享
            Row() {
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(26)
                .fontColor([$r('sys.color.icon_primary')])
                .onClick(() => {
                  NavPathUtils.pop();
                })
              Blank()
              SymbolGlyph($r('sys.symbol.share'))
                .fontSize(20)
                .fontColor([$r('sys.color.icon_primary')])
                .onClick(() => {
                  this.shareCurrent();
                })
            }
            .width('100%')
            .height(32)

            // 封面区
            Column() {
              if (this.currentMusic.artwork.length > 0) {
                Image(this.currentMusic.artwork)
                  .width(280)
                  .height(280)
                  .borderRadius(24)
                  .objectFit(ImageFit.Cover)
              } else {
                Column() {
                  SymbolGlyph($r('sys.symbol.music'))
                    .fontSize(64)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                .width(280)
                .height(280)
                .borderRadius(24)
                .backgroundColor($r('sys.color.comp_background_tertiary'))
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
              }
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)

            // 歌曲信息
            Column({ space: 6 }) {
              Text(this.currentMusic.title)
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('sys.color.font_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(this.currentMusic.artist +
                (this.currentMusic.album.length > 0 ? ' · ' + this.currentMusic.album : ''))
                .fontSize(13)
                .fontColor($r('sys.color.font_tertiary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .margin({ top: 20 })

            // 当前行歌词
            Column({ space: 3 }) {
              if (this.lyricLoading) {
                Text('歌词加载中…')
                  .fontSize(13)
                  .fontColor($r('sys.color.font_tertiary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              } else if (this.currentLyric === null) {
                Text('暂无歌词')
                  .fontSize(13)
                  .fontColor($r('sys.color.font_tertiary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              } else {
                Text(this.currentLyric.lrc)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.currentLyric.translation.length > 0) {
                  Text(this.currentLyric.translation)
                    .fontSize(12)
                    .fontColor($r('sys.color.font_tertiary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
            }
            .width('100%')
            .height(42)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .margin({ top: 10 })

            // 进度条
            Column({ space: 0 }) {
              Slider({
                value: Math.min(this.currentPosition, this.sliderMax()),
                min: 0,
                max: this.sliderMax()
              })
                .selectedColor($r('sys.color.icon_emphasize'))
                .trackColor($r('sys.color.comp_background_tertiary'))
                .blockColor($r('sys.color.icon_emphasize'))
                .width('100%')
                .onChange((value: number, mode: SliderChangeMode) => {
                  if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
                    this.isSeeking = true;
                    this.currentPosition = value;
                  } else {
                    // End（拖动结束）/ Click（点按）：提交进度
                    this.isSeeking = false;
                    this.currentPosition = value;
                    trackPlayer.seekTo(value);
                  }
                })
              Row() {
                Text(PlayerPage.formatDuration(this.currentPosition))
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                Text(this.duration > 0 ? PlayerPage.formatDuration(this.duration) : '--:--')
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)
              .margin({ top: 2 })
            }
            .width('100%')
            .margin({ top: 6 })

            // 播放控制
            Row() {
              SymbolGlyph($r('sys.symbol.backward_end_fill'))
                .fontSize(30)
                .fontColor([$r('sys.color.icon_primary')])
                .padding(8)
                .onClick(() => {
                  this.skipToPrevious();
                })

              Column() {
                SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause') : $r('sys.symbol.play_fill'))
                  .fontSize(30)
                  .fontColor([Color.White])
              }
              .width(68)
              .height(68)
              .borderRadius(34)
              .backgroundColor($r('sys.color.background_emphasize'))
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .onClick(() => {
                this.togglePlay();
              })

              SymbolGlyph($r('sys.symbol.forward_end_fill'))
                .fontSize(30)
                .fontColor([$r('sys.color.icon_primary')])
                .padding(8)
                .onClick(() => {
                  this.skipToNext();
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)
            .padding({ left: 24, right: 24 })
            .margin({ top: 16 })

            // 辅助功能：循环模式 / 收藏 / 播放队列
            Row() {
              SymbolGlyph(this.repeatIcon())
                .fontSize(22)
                .fontColor([$r('sys.color.icon_secondary')])
                .padding(6)
                .onClick(() => {
                  this.toggleRepeatMode();
                })

              SymbolGlyph(this.isFavorited ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                .fontSize(22)
                .fontColor([this.isFavorited ? $r('sys.color.icon_emphasize') : $r('sys.color.icon_secondary')])
                .padding(6)
                .onClick(() => {
                  this.toggleFavorite();
                })

              SymbolGlyph($r('sys.symbol.music_note_list'))
                .fontSize(22)
                .fontColor([$r('sys.color.icon_secondary')])
                .padding(6)
                .onClick(() => {
                  this.showQueue = true;
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)
            .padding({ left: 40, right: 40 })
            .margin({ top: 18 })
          }
          .width('100%')
          .height('100%')
          .padding({
            left: 24,
            right: 24,
            top: appState.topRect + 8,
            bottom: appState.bottomRect + 20
          })
        }
      }
      .width('100%')
      .height('100%')
      .bindSheet(!!this.showQueue, this.QueueSheetBuilder(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        dragBar: true,
        backgroundColor: $r('sys.color.background_secondary'),
        onWillDisappear: () => {
          this.showQueue = false;
          appState.isForegroundBlur = false;
        },
        onWillAppear: () => {
          appState.isForegroundBlur = true;
        }
      })
    }
    .hideTitleBar(true)
    .backgroundColor($r('sys.color.background_secondary'))
    .width('100%')
    .height('100%')
  }

  @Builder
  QueueSheetBuilder() {
    QueueSheet()
  }
}
