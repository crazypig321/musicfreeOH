import { MusicItem } from '../common/model/MediaTypes';
import { trackPlayer } from '../core/TrackPlayer';
import { PlayState } from '../core/PlayerEngine';

@ComponentV2
export struct PlayBar {
  @Local currentMusic: MusicItem | null = null;
  @Local isPlaying: boolean = false;
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

  build() {
    Row({ space: 12 }) {
      if (this.currentMusic !== null && this.currentMusic.artwork.length > 0) {
        Image(this.currentMusic.artwork)
          .width(44)
          .height(44)
          .borderRadius(11)
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.music_note_list'))
            .fontSize(22)
            .fontColor([$r('sys.color.icon_secondary')])
        }
        .width(44)
        .height(44)
        .borderRadius(11)
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
    }
    .width('100%')
    .height(52)
    .padding({ left: 8, right: 12 })
    .alignItems(VerticalAlign.Center)
  }
}
