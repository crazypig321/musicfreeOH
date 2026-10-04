import { DialogManager } from '../../utils/DialogUtils';
import { appState } from '../../entryability/AppState';
import { EQ_GAIN_MIN, EQ_GAIN_MAX } from '../../core/EqualizerManager';

/** 「均衡器增益」弹窗内容：数值输入框（限数字与负号）+ 自定义按钮（校验失败提示错误，弹窗保持打开） */
@ComponentV2
export struct EqGainDialogContent {
  build() {
    Column({ space: 12 }) {
      TextInput({
        text: DialogManager.eqGainValue,
        placeholder: '请输入 ' + EQ_GAIN_MIN.toString() + ' 到 ' + EQ_GAIN_MAX.toString() + ' 之间的整数'
      })
        .width('100%')
        .height(44)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(10)
        .inputFilter('[-0-9]')
        .onChange((v: string): void => {
          DialogManager.eqGainValue = v;
        })
      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .fontColor(appState.accentColor)
          .backgroundColor(Color.Transparent)
          .borderRadius(100)
          .onClick(() => {
            DialogManager.CloseDialog();
          })
        Button('确定')
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor(appState.accentColor)
          .borderRadius(100)
          .onClick(() => {
            EqGainDialogContent.confirmGain();
          })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 校验输入（-12 ~ 12 整数）：非法提示错误且不关闭弹窗，合法则执行回调并关闭 */
  private static confirmGain(): void {
    const n = parseInt(DialogManager.eqGainValue, 10);
    if (isNaN(n) || n < EQ_GAIN_MIN || n > EQ_GAIN_MAX) {
      DialogManager.Toast('填写错误，请输入 ' + EQ_GAIN_MIN.toString() + ' 到 ' + EQ_GAIN_MAX.toString() + ' 之间的整数');
      return;
    }
    if (DialogManager.eqGainConfirm !== null) {
      DialogManager.eqGainConfirm(n);
    }
    DialogManager.CloseDialog();
  }
}
