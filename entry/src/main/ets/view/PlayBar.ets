import { MusicItem } from '../common/model/MediaTypes';
import { trackPlayer } from '../core/TrackPlayer';
import { PlayState } from '../core/PlayerEngine';
import { appState } from '../entryability/AppState';
import { ROUTE_PLAYER } from '../common/model/NavModels';
import { NavPathUtils } from '../utils/NavPathUtils';
import { QueueSheet } from './QueueSheet';

/**
 * 迷你播放条：封面/标题区（非按钮区）点击进入全屏播放页；
 * 播放队列半模态内容复用 QueueSheet
 */
@ComponentV2
export struct PlayBar {
  @Local currentMusic: MusicItem | null = null;
  @Local isPlaying: boolean = false;
  /** 播放队列半模态 */
  @Local showQueue: boolean = false;
  private offCurrent: () => void = (): void => {
  };
  private offState: () => void = (): void => {
  };

  aboutToAppear(): void {
    this.currentMusic = trackPlayer.currentMusic;
    this.isPlaying = trackPlayer.playState === PlayState.Playing;
    this.offCurrent = trackPlayer.onCurrentMusicChanged((music: MusicItem | null) => {
      this.currentMusic = music;
    });
    this.offState = trackPlayer.onPlayStateChanged((state: PlayState) => {
      this.isPlaying = state === PlayState.Playing;
    });
  }

  aboutToDisappear(): void {
    this.offCurrent();
    this.offState();
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

  private skipToNext(): void {
    trackPlayer.skipToNext().catch((): void => {
    });
  }

  /** 进入全屏播放页 */
  private openPlayer(): void {
    if (this.currentMusic !== null) {
      NavPathUtils.push(ROUTE_PLAYER);
    }
  }

  build() {
    Row({ space: 12 }) {
      // 封面 + 曲目信息：点击进入播放页
      Row({ space: 12 }) {
        if (this.currentMusic !== null && this.currentMusic.artwork.length > 0) {
          Image(this.currentMusic.artwork)
            .width(44)
            .height(44)
            .borderRadius(100)
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.music'))
              .fontSize(22)
              .fontColor([$r('sys.color.icon_secondary')])
          }
          .width(44)
          .height(44)
          .borderRadius(100)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .justifyContent(FlexAlign.Center)
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
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.openPlayer();
      })

      SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause') : $r('sys.symbol.play_fill'))
        .fontSize(26)
        .fontColor([$r('sys.color.icon_primary')])
        .onClick(() => {
          this.togglePlay()
        })

      SymbolGlyph($r('sys.symbol.forward_end_fill'))
        .fontSize(22)
        .fontColor([$r('sys.color.icon_primary')])
        .onClick(() => {
          this.skipToNext()
        })

      // 播放队列入口
      SymbolGlyph($r('sys.symbol.music_note_list'))
        .fontSize(20)
        .fontColor([$r('sys.color.icon_primary')])
        .onClick(() => {
          this.showQueue = true;
        })
    }
    .width('100%')
    .height(52)
    .padding({ left: 8, right: 12 })
    .alignItems(VerticalAlign.Center)
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

  @Builder
  QueueSheetBuilder() {
    QueueSheet()
  }
}
