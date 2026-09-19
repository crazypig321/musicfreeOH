import { MenuItem, MENU_CONFIG } from '../common/model/TabsModels';
import { appState } from '../entryability/AppState';

/**
 * PC 风格侧边导航栏（平板/PC/大窗 lg 布局专用）：
 * - 展开显示 图标+页面名（220vp），收起仅显示图标（72vp）
 * - 点击导航项切换主页面（复用 MENU_CONFIG 五个主页面）
 * - 顶部按钮切换展开/收起，选中项以主题色高亮
 */
@ComponentV2
export struct SideBar {
  @Param expanded: boolean = true;
  @Event onSelect: (index: number) => void = (_index: number): void => {
  };
  @Event onToggle: () => void = (): void => {
  };

  /** 导航项 */
  @Builder
  NavItem(item: MenuItem, index: number) {
    Row({ space: 12 }) {
      SymbolGlyph(item.icon)
        .fontSize(22)
        .fontColor([appState.currTabsIndex === index ?
          appState.accentColor : $r('sys.color.icon_primary')])
      if (this.expanded) {
        Text(item.label)
          .fontSize(15)
          .fontWeight(appState.currTabsIndex === index ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(appState.currTabsIndex === index ?
            appState.accentColor : $r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .height(46)
    .borderRadius(12)
    .justifyContent(this.expanded ? FlexAlign.Start : FlexAlign.Center)
    .padding({ left: this.expanded ? 13 : 0, right: this.expanded ? 13 : 0 })
    .backgroundColor(appState.currTabsIndex === index ?
      $r('sys.color.comp_background_tertiary') : Color.Transparent)
    .onClick(() => {
      this.onSelect(index);
    })
  }

  build() {
    Column() {
      // 顶部：应用名 + 展开/收起开关
      Row() {
        if (this.expanded) {
          Text($r('app.string.home_subtitle'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        Row(){
          SymbolGlyph(this.expanded ? $r('sys.symbol.chevron_left') : $r('sys.symbol.chevron_right'))
            .fontSize(18)
            .fontColor([$r('sys.color.icon_secondary')])
        }.alignItems(VerticalAlign.Center).justifyContent(FlexAlign.Center)
        .width(34).height(34)
        .borderRadius(100)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .onClick(() => {
          this.onToggle();
        })
      }
      .width('100%')
      .height(44)
      .alignItems(VerticalAlign.Center)
      .padding({ left: this.expanded ? 13 : 19, right: this.expanded ? 13 : 19 })
      .margin({ top: appState.topRect > 0 ? 4 : 12 })

      // 页面导航项
      Column({ space: 4 }) {
        ForEach(MENU_CONFIG, (item: MenuItem, i: number) => {
          this.NavItem(item, i)
        }, (item: MenuItem, i: number) => 'side_' + i.toString())
      }
      .width('100%')
      .margin({ top: 10 })
      .alignItems(HorizontalAlign.Center)

      Blank()
    }
    .width(this.expanded ? 220 : 72)
    .height('100%')
    .padding({ top: appState.topRect, bottom: appState.bottomRect })
    .backgroundColor($r('sys.color.comp_background_primary'))
    .border({ width: { right: 1 }, color: $r('sys.color.comp_divider') })
    .animation({ duration: 250, curve: Curve.Smooth })
  }
}
