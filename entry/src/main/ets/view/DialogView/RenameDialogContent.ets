import { DialogManager } from '../../utils/DialogUtils';

/** 「重命名」弹窗内容：名称输入框 */
@ComponentV2
export struct RenameDialogContent {
  build() {
    TextInput({ text: DialogManager.renameValue, placeholder: '名称（清空则恢复默认）' })
      .width('100%')
      .height(44)
      .fontSize(14)
      .fontColor($r('sys.color.font_primary'))
      .placeholderColor($r('sys.color.font_tertiary'))
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .borderRadius(10)
      .onChange((v: string): void => {
        DialogManager.renameValue = v;
      })
  }
}
