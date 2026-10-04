import { DialogManager } from '../../utils/DialogUtils';

/** 「跳转排序」弹窗内容：目标序号输入框 */
@ComponentV2
export struct SortJumpDialogContent {
  build() {
    TextInput({ text: DialogManager.sortJumpValue, placeholder: '目标序号（1-' + DialogManager.sortJumpMax.toString() + '）' })
      .type(InputType.Number)
      .width('100%')
      .height(44)
      .fontSize(14)
      .fontColor($r('sys.color.font_primary'))
      .placeholderColor($r('sys.color.font_tertiary'))
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .borderRadius(10)
      .onChange((v: string): void => {
        DialogManager.sortJumpValue = v;
      })
  }
}
