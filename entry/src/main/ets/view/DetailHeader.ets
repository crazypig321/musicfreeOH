import { ArtworkCache } from '../utils/ArtworkCache';
import { appState } from '../entryability/AppState';

/**
 * 详情页头部：封面渐变图 + 标题 + 副标题 + 简介 + 全部播放/导入/批量操作
 * 智感握姿：左手握持时 全部播放与右侧图标互换
 */
@ComponentV2
export struct DetailHeader {
  @Require @Param coverUrl: string;
  @Require @Param title: string;
  @Param subTitle: string = '';
  @Param description: string = '';
  @Param musicCount: number = 0;
  @Param showImport: boolean = true;
  @Event onPlayAll: () => void = (): void => {};
  @Event onImport: () => void = (): void => {};
  @Event onBatchMode: () => void = (): void => {};

  build() {
    Column() {
      Stack({ alignContent: Alignment.Bottom }) {
        Image(ArtworkCache.resolve(this.coverUrl))
          .width('100%')
          .height(240)
          .objectFit(ImageFit.Cover)
          .alt($r('app.media.altImage'))
        Column()
          .width('100%')
          .height(240)
          .linearGradient({
            angle: 180,
            colors: [
              ['transparent', 0.0],
              ['transparent', 0.45],
              [$r('sys.color.background_secondary'), 1.0]
            ]
          })
      }
      .width('100%')

      Text(this.title)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ top: 12 })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.subTitle.length > 0) {
        Text(this.subTitle)
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .padding({ left: 16, right: 16 })
          .margin({ top: 6 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (this.description.length > 0) {
        Text(this.description)
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .padding({ left: 16, right: 16 })
          .margin({ top: 8 })
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      Row({ space: 12 }) {
        if (appState.holdingHand !== 'left') {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.play_circle_fill'))
              .fontSize(36)
              .fontColor([$r('sys.color.font')])
            Text('全部播放' + (this.musicCount > 0 ? ' · ' + this.musicCount.toString() : ''))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.font'))
          }
          .layoutWeight(1)
          .height(40)
          .onClick(() => {
            this.onPlayAll();
          })
        }

        if (this.showImport) {
          SymbolGlyph($r('sys.symbol.music_note_list_square'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
            .onClick(() => {
              this.onImport();
            })
        }

        SymbolGlyph($r('sys.symbol.list_checkmask'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
          .onClick(() => {
            this.onBatchMode();
          })

        if (appState.holdingHand === 'left') {
          Row({ space: 6 }) {
            Text('全部播放' + (this.musicCount > 0 ? ' · ' + this.musicCount.toString() : ''))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.font'))
            SymbolGlyph($r('sys.symbol.play_circle_fill'))
              .fontSize(36)
              .fontColor([$r('sys.color.font')])
          }
          .layoutWeight(1)
          .height(40)
          .justifyContent(FlexAlign.End)
          .onClick(() => {
            this.onPlayAll();
          })
        }
      }
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .padding({ left: 16, right: 16 })
      .margin({ top: 16 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
