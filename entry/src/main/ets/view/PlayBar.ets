import { MusicItem } from '../common/model/MediaTypes';
import { trackPlayer } from '../core/TrackPlayer';
import { PlayState } from '../core/PlayerEngine';
import { appState } from '../entryability/AppState';
import { playerAnim, PlayerExpandAnimController } from './PlayerExpandAnim';
import { QueueSheet } from './QueueSheet';
import { HdsBarStyle } from '@kit.UIDesignKit';
import { IsApiVersion_24 } from '../utils/BarScrollHelper';

/**
 * 迷你播放条（参考 ting_read TabsPlayBar）：
 * - API>=24：单排(HORIZONTAL)时封面 44，上下两排(VERTICAL)时封面略小 30，动效过渡
 * - 按钮在 API>=24 恒显示，API<24 仅展开时显示
 * - 封面/标题区点击进入全屏播放页；播放队列半模态复用 QueueSheet
 */
/** 实例序号：PlayBar 存在多实例（Index 悬浮条/DownloadPage tabBar 槽），测量 id 必须唯一 */
let playBarSeq: number = 0;

@ComponentV2
export struct PlayBar {
  @Local currentMusic: MusicItem | null = null;
  @Local isPlaying: boolean = false;
  /** 播放队列半模态 */
  @Local showQueue: boolean = false;
  @Param isTwoPage: boolean = false
  /** 二级页 tabbar 槽位尺寸（CommonNav 测得；首页实例不使用） */
  @Param barSlotW: number = 0
  @Param barSlotH: number = 0
  /** 本实例测量 id 前缀（getRectangleById 用，避免多实例同 id 测错对象） */
  private readonly myId: string = 'pb_' + (playBarSeq++).toString();
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

  /** 封面尺寸：单排 44 / 上下两排略小 30；API<24 恒 44 */
  private coverSize(): number {
    if (!IsApiVersion_24()) {
      return 44;
    }
    return appState.hdsBarLayoutMode === 0 || this.isTwoPage ? 44 : 30;
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

  /** 根布局尺寸（onAreaChange 捕获；translate 不影响布局尺寸，尺寸可信） */
  private barW: number = 0;
  private barH: number = 52;

  /** 进入全屏播放页（一镜到底展开）：
   * 锚点从点击事件的窗口坐标推算——HdsTabs 对迷你条做过平移摆放，
   * getRectangleById 的 windowOffset 不含 translate，测到的是布局占位而非视觉位置 */
  private openPlayer(event: ClickEvent): void {
    if (this.currentMusic === null) {
      return;
    }
    const size = this.coverSize();
    const rowX = event.windowX - event.x;
    const rowY = event.windowY - event.y;
    const rowH = event.target.area.height;
    const rowHNum = typeof rowH === 'number' ? rowH : this.barH;
    // 飞行封面：点击行首子节点、行内垂直居中
    const coverY = rowY + (rowHNum - size) / 2;
    if (this.isTwoPage) {
      // 二级页：PlayBar 无根 padding、高度不固定，锚点矩形用 CommonNav 测得的 tabbar 槽位
      const slotW = this.barSlotW > 0 ? this.barSlotW : this.barW;
      const slotH = this.barSlotH > 0 ? this.barSlotH : this.barH;
      const barY = rowY - (slotH - rowHNum) / 2;
      PlayerExpandAnimController.expand(rowX, coverY, size, rowX, barY, slotW, slotH);
      return;
    }
    // 首页：根左 padding 8，子行在根内垂直居中
    const barY = rowY - (this.barH - rowHNum) / 2;
    PlayerExpandAnimController.expand(rowX, coverY, size, rowX - 8, barY, this.barW, this.barH);
  }

  build() {
    Row({ space: 12 }) {
      // 封面 + 曲目信息：点击进入播放页
      Row({ space: 12 }) {
        if (this.currentMusic !== null && this.currentMusic.artwork.length > 0) {
          Image(this.currentMusic.artwork)
            .width(this.coverSize())
            .height(this.coverSize())
            .borderRadius(100)
            .objectFit(ImageFit.Cover)
            .animation({ duration: 500, curve: Curve.Smooth })
            .id(this.myId + '_cover')
            .opacity(playerAnim.miniCoverOpacity)
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.music'))
              .fontSize(22)
              .fontColor([$r('sys.color.icon_secondary')])
          }
          .width(this.coverSize())
          .height(this.coverSize())
          .borderRadius(100)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .justifyContent(FlexAlign.Center)
          .animation({ duration: 500, curve: Curve.Smooth })
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
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      .onClick((event: ClickEvent) => {
        // API<24：折叠态点击先展开；其余进入播放页
        if (!IsApiVersion_24() && appState.miniBarStyle === HdsBarStyle.COLLAPSE) {
          this.getUIContext().animateTo({ duration: 300, curve: Curve.Smooth }, () => {
            appState.miniBarStyle = HdsBarStyle.EXPAND
          })
        } else {
          this.openPlayer(event);
        }
      })

      if ((appState.miniBarStyle === HdsBarStyle.EXPAND) || IsApiVersion_24()) {
        SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause') : $r('sys.symbol.play_fill'))
          .fontSize(26)
          .fontColor([$r('sys.color.icon_primary')])
          .animation({ duration: 500, curve: Curve.Smooth })
          .onClick(() => {
            this.togglePlay()
          })

        SymbolGlyph($r('sys.symbol.forward_end_fill'))
          .fontSize(22)
          .fontColor([$r('sys.color.icon_primary')])
          .animation({ duration: 500, curve: Curve.Smooth })
          .onClick(() => {
            this.skipToNext()
          })

        // 播放队列入口
        SymbolGlyph($r('sys.symbol.music_note_list'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_primary')])
          .animation({ duration: 500, curve: Curve.Smooth })
          .onClick(() => {
            this.showQueue = true;
          })
      }
    }
    .width('100%')
    .padding(this.isTwoPage ? 0 : { left: 8, right: 12 })
    .alignItems(VerticalAlign.Center)
    .animation({ duration: 500, curve: Curve.Smooth })
    .id(this.myId + '_root')
    .onAreaChange((_old: Area, newArea: Area): void => {
      if (typeof newArea.width === 'number' && typeof newArea.height === 'number') {
        this.barW = newArea.width;
        this.barH = newArea.height;
      }
    })
    .opacity(playerAnim.miniBarOpacity)
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
