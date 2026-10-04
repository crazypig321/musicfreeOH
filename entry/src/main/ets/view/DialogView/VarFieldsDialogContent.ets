import { DialogManager, PluginVarField } from '../../utils/DialogUtils';

/** 「配置变量」弹窗内容：所有变量统一填写（cookie 类字段用多行 TextArea，其余单行输入） */
@ComponentV2
export struct VarFieldsDialogContent {
  /** 是否为 cookie 类字段（key/name 含 cookie，不区分大小写）：值较长，用多行输入 */
  private static isCookieField(f: PluginVarField): boolean {
    return f.key.toLowerCase().indexOf('cookie') !== -1 ||
      f.name.toLowerCase().indexOf('cookie') !== -1;
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        ForEach(DialogManager.varFields, (f: PluginVarField) => {
          Column({ space: 6 }) {
            Text(f.name)
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
              //.maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (VarFieldsDialogContent.isCookieField(f)) {
              TextArea({ text: f.value, placeholder: f.key })
                .width('100%')
                .constraintSize({ minHeight: 72, maxHeight: 160 })
                .fontSize(14)
                .fontColor($r('sys.color.font_primary'))
                .placeholderColor($r('sys.color.font_tertiary'))
                .backgroundColor($r('sys.color.comp_background_tertiary'))
                .borderRadius(10)
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .alignSelf(ItemAlign.Start)
                .onChange((v: string): void => {
                  f.value = v;
                })
            } else {
              TextInput({ text: f.value, placeholder: f.key })
                .width('100%')
                .height(42)
                .fontSize(14)
                .fontColor($r('sys.color.font_primary'))
                .placeholderColor($r('sys.color.font_tertiary'))
                .backgroundColor($r('sys.color.comp_background_tertiary'))
                .borderRadius(10)
                .onChange((v: string): void => {
                  f.value = v;
                })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }, (f: PluginVarField, index: number) => f.key + '_' + index.toString())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .scrollBar(BarState.Off)
    .constraintSize({ maxHeight: 360 })
    .nestedScroll({
      scrollForward: NestedScrollMode.PARALLEL,
      scrollBackward: NestedScrollMode.PARALLEL
    })
    .width('100%')
  }
}
