import { CommonNav, titleBarOf } from '../view/CommonNav';

@ComponentV2
export struct SettingsPage {
  build() {
    CommonNav({
      titleBarOp: titleBarOf($r('app.string.tab_settings')),
      isHideBackButton: true
    }) {
      Column({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(48)
          .fontColor([$r('sys.color.icon_tertiary')])
        Text($r('app.string.page_under_construction'))
          .fontSize(14)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      .height('100%')
      .padding({ top: 96, bottom: 180 })
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center)
    }
  }
}
