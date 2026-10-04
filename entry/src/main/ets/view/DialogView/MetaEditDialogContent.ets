import { DialogManager, MetaEditFieldDesc } from '../../utils/DialogUtils';
import { appState } from '../../entryability/AppState';

/** 「编辑信息」弹窗内容：标签输入框组（ForEach 循环渲染）+ 自定义按钮
 *  （校验失败提示错误并保持弹窗打开，保存中显示 loading） */
@ComponentV2
export struct MetaEditDialogContent {
  build() {
    Column({ space: 12 }) {
      ForEach(DialogManager.editMetaFields, (field: MetaEditFieldDesc) => {
        Column({ space: 6 }) {
          Text(field.label)
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
          TextInput({ text: field.value, placeholder: field.placeholder })
            .width('100%')
            .height(44)
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
            .placeholderColor($r('sys.color.font_tertiary'))
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .borderRadius(10)
            .enabled(!appState.isDialogSaving)
            .onChange((v: string): void => {
              field.value = v;
            })
            .onSubmit((_enterKey: EnterKeyType) => {
              DialogManager.ConfirmButtonDialog('编辑信息');
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }, (field: MetaEditFieldDesc) => field.label)
      // 自定义按钮（支持 loading 态，异步写入完成后手动关闭弹窗）
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
          Button('保存')
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .fontColor(Color.White)
            .backgroundColor(appState.accentColor)
            .borderRadius(100)
            .onClick(() => {
              DialogManager.ConfirmButtonDialog('编辑信息');
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
