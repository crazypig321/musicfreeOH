import { appState } from '../entryability/AppState';

@ComponentV2
export struct SettingsPage {
  build() {
    Column({ space: 12 }) {
      Text($r('app.string.tab_settings'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
      SymbolGlyph($r('sys.symbol.gearshape'))
        .fontSize(48)
        .fontColor([$r('sys.color.icon_tertiary')])
      Text($r('app.string.page_under_construction'))
        .fontSize(14)
        .fontColor($r('sys.color.font_tertiary'))
    }
    .width('100%')
    .height('100%')
    .padding({ top: appState.topRect + 48, bottom: 180 })
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
  }
}
