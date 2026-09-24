import { appState } from '../../entryability/AppState';
import { NavPathUtils } from '../../utils/NavPathUtils';
import { ROUTE_SEARCH } from '../../common/model/NavModels';

/**
 * PC 顶部标题栏（参考 BiliMusic TitleBar 思路）：
 * - 左侧品牌区：应用图标 + 应用名
 * - 右侧全局搜索入口：点击在内容区打开搜索页（二级路由）
 * - 底部分隔线与侧边栏/内容区分隔保持一致
 */
@ComponentV2
export struct PcTitleBar {
  /** 搜索入口 hover 态 */
  @Local searchHover: boolean = false;

  build() {
    Column() {
      Row({ space: 10 }) {
        // 品牌区：主题色圆角图标 + 应用名
        Image($r('app.media.startIcon'))
          .width(26)
          .height(26)
          .borderRadius(8)
          .backgroundColor(appState.accentColor)

        Text($r('app.string.home_subtitle'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)

        Blank()

        // 全局搜索入口：进入搜索二级页（内容区展示，侧边栏与播放栏常驻）
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(15)
            .fontColor([$r('sys.color.icon_secondary')])
          Text($r('app.string.home_search_placeholder'))
            .fontSize(13)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 220 })
        }
        .height(30)
        .padding({ left: 12, right: 14 })
        .borderRadius(100)
        .backgroundColor(this.searchHover ?
          $r('sys.color.interactive_hover') : $r('sys.color.comp_background_tertiary'))
        .alignItems(VerticalAlign.Center)
        .onHover((hover: boolean): void => {
          this.searchHover = hover;
        })
        .onClick((): void => {
          NavPathUtils.push(ROUTE_SEARCH);
        })
      }
      .width('100%')
      .height(44)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ top: appState.topRect })
    .backgroundColor($r('sys.color.comp_background_primary'))
    .border({ width: { bottom: 1 }, color: $r('sys.color.comp_divider') })
  }
}
