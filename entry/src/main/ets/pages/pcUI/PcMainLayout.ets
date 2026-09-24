import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { appState } from '../../entryability/AppState';
import { MainTabPagesBuilder, PageMapBuilder } from '../../view/AppPages';
import { PcTitleBar } from './PcTitleBar';
import { PcSideBar } from './PcSideBar';
import { PcPlayerBar } from './PcPlayerBar';
import { NavPathUtils } from '../../utils/NavPathUtils';

/**
 * PC 主布局（参考 BiliMusic MainLayout 思路，2in1/平板窗口模式使用）：
 * - 顶部标题栏（品牌 + 搜索入口）
 * - 左侧导航栏（展开/收起）+ 右侧内容区（Navigation：主页面 Tabs 与二级路由页都在内容区切换，
 *   标题栏/侧边栏/播放栏跨页面常驻）
 * - 底部通栏播放条（批量操作模式下隐藏）
 */
@ComponentV2
export struct PcMainLayout {
  /** 主页面 Tabs 控制器（Index 持有：返回手势切回主页 tab） */
  @Param tabsController: TabsController = new TabsController();

  @Builder
  pageMap(name: string) {
    PageMapBuilder(name)
  }

  build() {
    Column() {
      PcTitleBar()

      Row() {
        PcSideBar({
          expanded: appState.sidebarExpanded,
          onSelect: (index: number): void => {
            NavPathUtils.pop()
            this.tabsController.changeIndex(index);
          },
          onToggle: (): void => {
            this.getUIContext().animateTo({ duration: 250, curve: Curve.Smooth }, (): void => {
              appState.sidebarExpanded = !appState.sidebarExpanded;
            });
          }
        })

        // 内容区：二级页面（搜索/详情/设置子页等）仅覆盖内容区，侧边栏与播放栏保持可见
        HdsNavigation(appState.pageInfos) {
          Tabs({ controller: this.tabsController }) {
            MainTabPagesBuilder()
          }
          .barHeight(0)
          .vertical(false)
          .scrollable(false)
          // PC 侧边栏切换瞬切：500ms 横滑会与路由渐隐转场叠加，产生"左滑"观感（手机端 Tabs 不受影响）
          .animationDuration(0)
          .onChange((index: number): void => {
            appState.currTabsIndex = index;
            // 切换 tab 时递增计数，触发左滑条目（key 引用 tick）重建复位滑动状态
            appState.swipeResetTick = appState.swipeResetTick + 1;
          })
        }
        .titleMode(HdsNavigationTitleMode.FREE)
        .mode(NavigationMode.Stack)
        .navBarWidth('40%')
        .hideBackButton(true)
        .hideTitleBar(true)
        .navDestination(this.pageMap)
        // PC 布局路由转场接管（仅本文件 = 仅 PC 布局生效）：
        // - 进场（push/replace）：返回 undefined 走系统转场，即 CommonNav 的 systemTransition(EXPLODE)；
        // - 退场（pop）：自定义退场——退场页中心缩小渐隐（EXPLODE 逆过程），NavBar 侧静止。
        //   必须 Navigation 级接管：NavDestination 级转场属性管不到 pop 的入场方 NavBar，此前退出一直滑动即此原因
        .customNavContentTransition((from: NavContentInfo, to: NavContentInfo,
          operation: NavigationOperation): NavigationAnimatedTransition | undefined => {
          if (operation !== NavigationOperation.POP) {
            appState.pcNavExitScale = 1
            appState.pcNavExitOpacity = 1
            return undefined
          }
          const exitAnim: NavigationAnimatedTransition = {
            timeout: 400,
            transition: (proxy: NavigationTransitionProxy): void => {
              this.getUIContext().animateTo({
                duration: 300,
                curve: Curve.Smooth,
                onFinish: (): void => {
                  proxy.finishTransition()
                  // 退场页已卸载，全局参数归位，避免残留 0 值影响后续绑定实例
                  appState.pcNavExitScale = 1
                  appState.pcNavExitOpacity = 1
                }
              }, (): void => {
                appState.pcNavExitScale = 0.9
                appState.pcNavExitOpacity = 0
              })
            }
          }
          return exitAnim
        })
        .layoutWeight(1)
        .height('100%')
        .backgroundColor($r('sys.color.background_secondary'))
        .foregroundBlurStyle(appState.isForegroundBlur ? BlurStyle.Thin : BlurStyle.NONE,
          { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT, scale: 0.3 })
      }
      .width('100%')
      .layoutWeight(1)

      // 底部通栏播放条（批量操作模式下隐藏，避免遮挡批量底栏）
      if (!appState.isBatchMode) {
        PcPlayerBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_secondary'))
  }
}
