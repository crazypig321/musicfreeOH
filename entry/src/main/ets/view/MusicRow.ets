import { MusicItem } from '../common/model/MediaTypes';
import { ArtworkCache } from '../utils/ArtworkCache';
import { appState } from '../entryability/AppState';

/**
 * 音乐条目行（首页本地音乐 / 歌单详情 / 媒体详情页共用）
 * 有封面用封面，无封面用音符图标（40x40 一致）；条目间分割线由 showDivider 控制
 * 智感握姿：左手握持时 更多按钮 镜像到行首，文本右对齐，封面镜像到最右
 * 可选特性（默认关闭以保持首页行为）：批量勾选、时长、来源标签、长按手势、宽分割线
 */
@ComponentV2
export struct MusicRow {
  @Require @Param item: MusicItem;
  @Param showDivider: boolean = false;
  @Param showCheckbox: boolean = false;
  @Param selected: boolean = false;
  @Param showDuration: boolean = false;
  @Param showPlatform: boolean = false;
  @Param showMore: boolean = true;
  @Param usePaddingHeight: boolean = false;
  @Param wideDivider: boolean = false;
  @Event onTap: () => void = (): void => {};
  @Event onMore: () => void = (): void => {};
  @Event onLongPress: () => void = (): void => {};

  @Builder
  RowContent() {
    if (this.showCheckbox) {
      SymbolGlyph(this.selected ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
        .fontSize(24)
        .fontColor([this.selected ? appState.accentColor : $r('sys.color.icon_tertiary')])
        .transition(TransitionEffect.OPACITY)
    }
    if (appState.holdingHand === 'left') {
      if (this.showMore && !this.showCheckbox) {
        SymbolGlyph($r('sys.symbol.ellipsis_circle'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
          .transition(TransitionEffect.OPACITY)
          .onClick(() => {
            this.onMore();
          })
      }
      if (this.showDuration) {
        Text(MusicRow.formatDuration(this.item.duration))
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
      }
    }
    if (appState.holdingHand !== 'left') {
      if (this.item.artwork.length > 0) {
        Image(ArtworkCache.resolve(this.item.artwork))
          .width(40)
          .height(40)
          .borderRadius(10)
          .objectFit(ImageFit.Cover)
          .alt($r('app.media.altImage'))
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.music'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
        }
        .width(40)
        .height(40)
        .borderRadius(10)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .justifyContent(FlexAlign.Center)
      }
    }
    Column({ space: 2 }) {
      Text(this.item.title)
        .fontSize(15)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row({ space: 5 }) {
        if (this.showPlatform && appState.holdingHand !== 'left' && this.item.platform.length > 0) {
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
        Text(this.item.artist + (this.item.album.length > 0 ? ' · ' + this.item.album : ''))
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
        if (this.showPlatform && appState.holdingHand === 'left' && this.item.platform.length > 0) {
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
      }
      .width('100%')
    }
    .layoutWeight(1)
    .alignItems(appState.holdingHand === 'left' ? HorizontalAlign.End : HorizontalAlign.Start)
    if (appState.holdingHand !== 'left') {
      if (this.showDuration) {
        Text(MusicRow.formatDuration(this.item.duration))
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
      }
      if (this.showMore && !this.showCheckbox) {
        SymbolGlyph($r('sys.symbol.ellipsis_circle'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
          .transition(TransitionEffect.OPACITY)
          .onClick(() => {
            this.onMore();
          })
      }
    }
    if (appState.holdingHand === 'left') {
      if (this.item.artwork.length > 0) {
        Image(ArtworkCache.resolve(this.item.artwork))
          .width(40)
          .height(40)
          .borderRadius(10)
          .objectFit(ImageFit.Cover)
          .alt($r('app.media.altImage'))
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.music'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
        }
        .width(40)
        .height(40)
        .borderRadius(10)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .justifyContent(FlexAlign.Center)
      }
    }
  }

  build() {
    Column() {
      if (this.usePaddingHeight) {
        Row({ space: 12 }) {
          this.RowContent()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .gesture(
          LongPressGesture({ repeat: false, duration: 500 })
            .onAction((_event: GestureEvent) => {
              this.onLongPress();
            })
        )
        .onClick(() => {
          this.onTap();
        })
      } else {
        Row({ space: 12 }) {
          this.RowContent()
        }
        .width('100%')
        .height(56)
        .onClick(() => {
          this.onTap();
        })
      }

      if (this.showDivider) {
        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.comp_divider'))
          .margin(this.wideDivider
            ? (appState.holdingHand === 'left' ? { left: 20, right: 68 } : { left: 68, right: 20 })
            : (appState.holdingHand === 'left' ? { left: 4, right: 52 } : { left: 52, right: 4 }))
      }
    }
    .width('100%')
  }

  private static formatDuration(sec: number): string {
    const s = Math.max(0, Math.floor(sec));
    const m = Math.floor(s / 60);
    const r = s % 60;
    const mStr = m < 10 ? '0' + m.toString() : m.toString();
    const rStr = r < 10 ? '0' + r.toString() : r.toString();
    return mStr + ':' + rStr;
  }
}
