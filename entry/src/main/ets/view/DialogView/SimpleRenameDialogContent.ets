import { DialogManager } from '../../utils/DialogUtils';
import { appState } from '../../entryability/AppState';

/** 「转换简洁命名」弹窗内容：确认文案 + 自定义按钮（支持 loading 态，重命名完成后手动关闭弹窗） */
@ComponentV2
export struct SimpleRenameDialogContent {
  build() {
    Column({ space: 12 }) {
      Text(DialogManager.simpleRenameMessage)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .fontColor(appState.accentColor)
          .backgroundColor(Color.Transparent)
          .borderRadius(100)
          .enabled(!appState.isDialogSaving)
          .onClick(() => {
            DialogManager.CloseDialog();
          })
        if (appState.isDialogSaving) {
          Column() {
            LoadingProgress()
              .width(24)
              .height(24)
              .color(Color.White)
          }
          .layoutWeight(1)
          .height(40)
          .justifyContent(FlexAlign.Center)
          .borderRadius(100)
          .backgroundColor(appState.accentColor)
        } else {
          Button('转换')
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .fontColor(Color.White)
            .backgroundColor(appState.accentColor)
            .borderRadius(100)
            .onClick(() => {
              if (DialogManager.simpleRenameConfirm !== null) {
                DialogManager.simpleRenameConfirm();
              }
            })
        }
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
