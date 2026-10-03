import { SheetItem } from '../common/model/SheetTypes';
import { musicSheet, SheetBasePatch } from '../core/MusicSheet';
import { appState } from '../entryability/AppState';
import { sheetTopAvoidVp } from '../utils/BreakpointUtils';

/**
 * 批量「添加到歌单」歌单选择半模态内容
 */
@ComponentV2
export struct BatchSheetPicker {
  @Require @Param sheets: SheetItem[];
  @Event onPick: (sheet: SheetItem) => void = (_sheet: SheetItem): void => {};

  build() {
    Column() {
      Text('添加到歌单')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .margin({ bottom: 12 })

      if (this.sheets.length === 0) {
        Text('暂无自建歌单，请先在歌单页创建')
          .fontSize(14)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Center)
      } else {
        List() {
          ForEach(this.sheets, (sheet: SheetItem, index: number) => {
            ListItem() {
              Row({ space: 12 }) {
                Text(sheet.title)
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(sheet.worksNum.toString() + ' 首')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.onPick(sheet);
              })
            }
          }, (sheet: SheetItem, index: number) => sheet.id + '_' + index.toString())
        }
        .width('100%')
        .nestedScroll({
          scrollForward: NestedScrollMode.PARENT_FIRST,
          scrollBackward: NestedScrollMode.SELF_FIRST
        })
        .divider({
          strokeWidth: 0.5,
          color: $r('sys.color.comp_divider')
        })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12 + sheetTopAvoidVp(), bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }
}
