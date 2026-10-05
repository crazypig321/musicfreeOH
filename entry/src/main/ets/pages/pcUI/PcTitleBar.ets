import window from '@ohos.window';
import { appState } from '../../entryability/AppState';
import { NavPathUtils } from '../../utils/NavPathUtils';
import { ROUTE_SEARCH } from '../../common/model/NavModels';
import { ContextHolder } from '../../common/ContextHolder';

/**
 * PC 顶部标题栏（与窗口标题栏合一）：
 * - 自由窗口模式下系统标题栏已隐藏（setWindowDecorVisible(false)），本栏即为窗口标题栏
 * - 左侧品牌区：应用图标 + 应用名；中部空白区可按下拖拽移动窗口
 * - 右侧：全局搜索入口 + 右上角系统三键（最小化/最大化/关闭，下沉到页面内）避让区
 * - 底部分隔线与侧边栏/内容区分隔保持一致
 */
@ComponentV2
export struct PcTitleBar {
  /** 搜索入口 hover 态 */
  @Local searchHover: boolean = false;
  /** 窗口拖拽按下标记：Down 后 Move 才触发移动，避免点击误拖 */
  private dragPressed: boolean = false;

  /** 标题栏空白/品牌区按下拖拽移动窗口（仅自由窗口生效，其余形态静默失败） */
  private onDragZoneTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.dragPressed = true;
    } else if (event.type === TouchType.Move && this.dragPressed) {
      this.dragPressed = false;
      try {
        const win: window.Window = ContextHolder.get().windowStage.getMainWindowSync();
        win.startMoving().catch((): void => {
        });
      } catch (e) {
        // 非自由窗口形态不支持拖动窗口，忽略
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.dragPressed = false;
    }
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        // 品牌区：主题色圆角图标 + 应用名（空白可拖拽移动窗口）
        Row({ space: 10 }) {
          Image($r('app.media.startIcon'))
            .width(26)
            .height(26)
            .borderRadius(8)

          Text($r('app.string.home_subtitle'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
        }
        .alignItems(VerticalAlign.Center)
        .onTouch((event: TouchEvent): void => {
          this.onDragZoneTouch(event);
        })

        // 中部空白拖拽区
        Blank()
          .onTouch((event: TouchEvent): void => {
            this.onDragZoneTouch(event);
          })

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

        // 右上角系统三键（最小化/最大化/关闭）避让区：标题栏隐藏后三键下沉到页面内
        if (appState.decorButtonWidth > 0) {
          Row()
            .width(appState.decorButtonWidth)
            .height(44)
        }
      }
      .width('100%')
      .height(44)
      .padding({ left: 16, right: appState.decorButtonWidth > 0 ? 8 : 16 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ top: appState.topRect })
    .backgroundColor($r('sys.color.comp_background_primary'))
    .border({ width: { bottom: 1 }, color: $r('sys.color.comp_divider') })
  }
}
