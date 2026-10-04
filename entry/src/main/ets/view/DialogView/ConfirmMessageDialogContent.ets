import { DialogManager } from '../../utils/DialogUtils';

/** 通用确认弹窗内容（清除缓存/确认删除/确认导入/发现新版本）：确认文案 */
@ComponentV2
export struct ConfirmMessageDialogContent {
  build() {
    Text(DialogManager.confirmMessage)
      .fontSize(14)
      .fontColor($r('sys.color.font_primary'))
      .width('100%')
  }
}
