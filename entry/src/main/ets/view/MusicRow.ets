import { MusicItem } from '../common/model/MediaTypes';
import { ArtworkCache } from '../utils/ArtworkCache';

/**
 * 音乐条目行（首页本地音乐 / 本地音乐页共用）
 * 有封面用封面，无封面用音符图标（40x40 一致）；条目间分割线由 showDivider 控制
 */
@ComponentV2
export struct MusicRow {
  @Require @Param item: MusicItem;
  @Param showDivider: boolean = false;
  @Event onTap: () => void = (): void => {};
  @Event onMore: () => void = (): void => {};

  build() {
    Column() {
      Row({ space: 12 }) {
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
        Column({ space: 2 }) {
          Text(this.item.title)
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
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
        SymbolGlyph($r('sys.symbol.ellipsis_circle'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
          .onClick(() => {
            this.onMore();
          })
      }
      .width('100%')
      .height(56)
      .onClick(() => {
        this.onTap();
      })

      if (this.showDivider) {
        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.comp_divider'))
          .margin({ left: 52, right: 4 })
      }
    }
    .width('100%')
  }
}
