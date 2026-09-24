import { componentUtils } from '@kit.ArkUI';
import { MusicItem } from '../../common/model/MediaTypes';
import { ArtworkCache } from '../../utils/ArtworkCache';
import { trackPlayer } from '../../core/TrackPlayer';
import { PlayState } from '../../core/PlayerEngine';
import { appState } from '../../entryability/AppState';
import { playerAnim, PlayerExpandAnimController } from '../../view/PlayerExpandAnim';
import { QueueSheet } from '../../view/QueueSheet';
import { MusicRepeatMode } from '../../common/Consts';
import { musicSheet } from '../../core/MusicSheet';
import { MediaUtils } from '../../utils/MediaUtils';
import { ControlButtonConfig } from '../../common/model/home/HomeModel';

/** 实例序号：组件测量 id 必须全局唯一 */
export let pcPlayBarSeq: number = 0;

/**
 * PC 底部通栏播放条（参考 BiliMusic PlayerBar 思路）：
 * - 左：封面 + 曲目信息（点击一镜到底展开播放页）
 * - 中：上一首/播放暂停/下一首 + 进度条（拖动松手 seek）
 * - 右：播放队列半模态入口 + 展开播放页入口
 */
@ComponentV2
export struct PcPlayerBar {
  @Local currentMusic: MusicItem | null = null;
  @Local isPlaying: boolean = false;
  @Local playPosition: number = 0;
  @Local playDuration: number = 0;
  /** 进度条拖动中：暂停进度回写，松手 seek */
  @Local isSeeking: boolean = false;
  @Local seekValue: number = 0;
  /** 播放队列半模态 */
  @Local showQueue: boolean = false;
  @Local queueHover: boolean = false;
  @Local expandHover: boolean = false;
  /** 循环模式 */
  @Local repeatMode: MusicRepeatMode = MusicRepeatMode.QUEUE;
  /** 当前歌曲是否已收藏 */
  @Local isFavorited: boolean = false;
  /** 本实例测量 id 前缀（getRectangleById 用） */
  private readonly myId: string = 'pcb_' + (pcPlayBarSeq++).toString();
  /** 根布局窗口位置与尺寸（onAreaChange 捕获；测量失败时的兜底锚点） */
  private barX: number = 0;
  private barY: number = 0;
  private barW: number = 0;
  private barH: number = 64;
  private offCurrent: () => void = (): void => {
  };
  private offState: () => void = (): void => {
  };
  private offProgress: () => void = (): void => {
  };
  private offRepeatMode: () => void = (): void => {
  };

  /** 获取播放控制按钮配置列表 */
  private getControlButtons(): ControlButtonConfig[] {
    const buttons: ControlButtonConfig[] = [
      {
        symbol: this.repeatMode === MusicRepeatMode.SHUFFLE ? $r('sys.symbol.shuffle') :
          (this.repeatMode === MusicRepeatMode.SINGLE ? $r('sys.symbol.repeat_1') : $r('sys.symbol.repeat')),
        fontSize: 20,
        fontColor: [$r('sys.color.icon_primary')],
        action: (): void => {
          this.toggleRepeatMode();
        }
      },
      {
        symbol: $r('sys.symbol.backward_end_fill'),
        fontSize: 20,
        fontColor: [$r('sys.color.icon_primary')],
        action: (): void => {
          this.skipToPrevious();
        }
      },
      {
        symbol: $r('sys.symbol.play_fill'),
        fontSize: 28,
        fontColor: [appState.accentColor],
        action: (): void => {
          this.togglePlay();
        }
      },
      {
        symbol: $r('sys.symbol.forward_end_fill'),
        fontSize: 20,
        fontColor: [$r('sys.color.icon_primary')],
        action: (): void => {
          this.skipToNext();
        }
      },
      {
        symbol: this.isFavorited ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
        fontSize: 20,
        fontColor: [this.isFavorited ? '#E84026' : $r('sys.color.icon_primary')],
        action: (): void => {
          this.toggleFavorite();
        }
      }
    ];
    return buttons;
  }

  aboutToAppear(): void {
    this.currentMusic = trackPlayer.currentMusic;
    this.isPlaying = trackPlayer.playState === PlayState.Playing;
    this.repeatMode = trackPlayer.repeatMode;
    this.refreshFavorite();
    this.offCurrent = trackPlayer.onCurrentMusicChanged((music: MusicItem | null): void => {
      this.currentMusic = music;
      this.playPosition = 0;
      this.playDuration = 0;
      this.isSeeking = false;
      this.refreshFavorite();
    });
    this.offState = trackPlayer.onPlayStateChanged((state: PlayState): void => {
      this.isPlaying = state === PlayState.Playing;
    });
    this.offProgress = trackPlayer.onProgressChanged((position: number, duration: number): void => {
      this.playDuration = duration;
      if (!this.isSeeking) {
        this.playPosition = position;
      }
    });
    this.offRepeatMode = trackPlayer.onRepeatModeChanged((mode: MusicRepeatMode): void => {
      this.repeatMode = mode;
    });
  }

  aboutToDisappear(): void {
    this.offCurrent();
    this.offState();
    this.offProgress();
    this.offRepeatMode();
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

  /** 切换循环模式 */
  private toggleRepeatMode(): void {
    trackPlayer.toggleRepeatMode();
  }

  /** 刷新当前歌曲收藏状态 */
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

  /** 切换收藏 */
  private toggleFavorite(): void {
    const current = this.currentMusic;
    if (current === null) {
      return;
    }
    if (this.isFavorited) {
      musicSheet.removeMusic(musicSheet.defaultSheet.id, [current]).then((): void => {
        this.isFavorited = false;
      });
    } else {
      musicSheet.addMusic(musicSheet.defaultSheet.id, current).then((): void => {
        this.isFavorited = true;
      });
    }
  }

  /** 秒 → m:ss */
  private formatTime(sec: number): string {
    const total = Math.max(0, Math.floor(sec));
    const minute = Math.floor(total / 60);
    const second = total % 60;
    return minute.toString() + ':' + (second < 10 ? '0' : '') + second.toString();
  }

  /** 一镜到底展开播放页：锚点按组件 id 实测（本条固定于窗口底部，无平移摆放，测量可信） */
  private openPlayer(): void {
    if (this.currentMusic === null) {
      return;
    }
    try {
      const ui = this.getUIContext();
      const cover = componentUtils.getRectangleById(this.myId + '_cover');
      const root = componentUtils.getRectangleById(this.myId + '_root');
      PlayerExpandAnimController.expand(
        ui.px2vp(cover.windowOffset.x), ui.px2vp(cover.windowOffset.y), ui.px2vp(cover.size.width),
        ui.px2vp(root.windowOffset.x), ui.px2vp(root.windowOffset.y),
        ui.px2vp(root.size.width), ui.px2vp(root.size.height), this.myId);
    } catch (error) {
      // 测量失败：用 onAreaChange 捕获的布局位置作兜底锚点
      PlayerExpandAnimController.expand(
        this.barX, this.barY + (this.barH - 44) / 2, 44,
        this.barX, this.barY, this.barW, this.barH, this.myId);
    }
  }

  build() {
    Row({ space: 16 }) {
      // 左：封面 + 曲目信息（点击进入播放页）
      Row({ space: 10 }) {
        if (this.currentMusic !== null && this.currentMusic.artwork.length > 0) {
          Image(ArtworkCache.resolve(this.currentMusic.artwork))
            .width(44)
            .height(44)
            .borderRadius(100)
            .objectFit(ImageFit.Cover)
            .id(this.myId + '_cover')
            .opacity(playerAnim.miniCoverOpacity)
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.music'))
              .fontSize(20)
              .fontColor([$r('sys.color.icon_secondary')])
          }
          .width(44)
          .height(44)
          .borderRadius(100)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .justifyContent(FlexAlign.Center)
          .id(this.myId + '_cover')
          .opacity(playerAnim.miniCoverOpacity)
        }

        Column({ space: 2 }) {
          Text(this.currentMusic === null ? $r('app.string.playbar_no_music') : this.currentMusic.title)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.currentMusic !== null) {
            Text(this.currentMusic.artist)
              .fontSize(11)
              .fontColor($r('sys.color.font_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ maxWidth: 220 })
      }
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        this.openPlayer();
      })
      // 中：控制按钮 + 进度条
      Column({ space: 0 }) {
        Row({ space: 24 }) {
          ForEach(this.getControlButtons(), (item: ControlButtonConfig, index: number) => {
            SymbolGlyph(index === 2 ? (this.isPlaying ? $r('sys.symbol.pause') : $r('sys.symbol.play_fill')) :
              index === 4 ? this.isFavorited ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart') :
              item.symbol)
              .fontSize(item.fontSize)
              .fontColor(index === 4 ? (this.isFavorited ? ['#E84026'] : [$r('sys.color.icon_primary')]) : item.fontColor)
              .onClick((): void => {
                item.action();
              })
          }, (item: ControlButtonConfig, index: number) => index.toString())
        }
        .alignItems(VerticalAlign.Center)
        .padding({ top: 10 })

        Row({ space: 8 }) {
          Text(this.formatTime(this.isSeeking ? this.seekValue : this.playPosition))
            .fontSize(11)
            .fontColor($r('sys.color.font_tertiary'))
          Slider({
            value: this.isSeeking ? this.seekValue : this.playPosition,
            min: 0,
            max: Math.max(this.playDuration, 1),
            step: 1,
            style: SliderStyle.OutSet
          })
            .layoutWeight(1)
            .selectedColor(appState.accentColor)
            .trackColor($r('sys.color.comp_divider'))
            .blockColor(appState.accentColor)
            .onChange((value: number, mode: SliderChangeMode): void => {
              if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
                this.isSeeking = true;
                this.seekValue = value;
              } else {
                this.isSeeking = false;
                this.playPosition = value;
                trackPlayer.seekTo(value);
              }
            })
          Text(this.formatTime(this.playDuration))
            .fontSize(11)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .constraintSize({ maxWidth: 560 })

      // 右：播放队列 + 展开播放页
      Row({ space: 4 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.music_note_list'))
            .fontSize(18)
            .fontColor([this.queueHover ? appState.accentColor : $r('sys.color.icon_primary')])
        }
        .width(34)
        .height(34)
        .borderRadius(10)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.queueHover ? $r('sys.color.interactive_hover') : Color.Transparent)
        .onHover((hover: boolean): void => {
          this.queueHover = hover;
        })
        .onClick((): void => {
          this.showQueue = true;
        })

        Row() {
          SymbolGlyph($r('sys.symbol.chevron_up'))
            .fontSize(18)
            .fontColor([this.expandHover ? appState.accentColor : $r('sys.color.icon_primary')])
        }
        .width(34)
        .height(34)
        .borderRadius(10)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.expandHover ? $r('sys.color.interactive_hover') : Color.Transparent)
        .onHover((hover: boolean): void => {
          this.expandHover = hover;
        })
        .onClick((): void => {
          this.openPlayer();
        })
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .border({ width: { top: 1 }, color: $r('sys.color.comp_divider') })
    .id(this.myId + '_root')
    .opacity(playerAnim.miniBarOpacity)
    .onAreaChange((_old: Area, newArea: Area): void => {
      if (typeof newArea.width === 'number' && typeof newArea.height === 'number') {
        this.barW = newArea.width;
        this.barH = newArea.height;
      }
      const gp = newArea.globalPosition;
      if (gp !== undefined && typeof gp.x === 'number') {
        this.barX = gp.x;
        if (typeof gp.y === 'number') {
          this.barY = gp.y;
        }
      }
    })
    .bindSheet(!!this.showQueue, this.QueueSheetBuilder(), {
      scrollSizeMode: ScrollSizeMode.CONTINUOUS, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      backgroundColor: $r('sys.color.background_secondary'),
      onWillDisappear: (): void => {
        this.showQueue = false;
        appState.isForegroundBlur = false;
      },
      onWillAppear: (): void => {
        appState.isForegroundBlur = true;
      }
    })
  }

  @Builder
  QueueSheetBuilder() {
    QueueSheet()
  }
}
