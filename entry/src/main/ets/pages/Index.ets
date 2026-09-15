import web_webview from '@ohos.web.webview';
import { WebPluginExecutor } from '../plugin/WebPluginExecutor';
import { Bootstrap } from '../core/Bootstrap';
import { trackPlayer } from '../core/TrackPlayer';
import {
  HdsBarStyle,
  HdsNavigation, HdsNavigationTitleMode, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { appState } from '../entryability/AppState';
import { MENU_CONFIG, MenuItem, tabBarSymbolOf } from '../model/TabsModels';
import { ROUTE_SEARCH } from '../model/NavModels';
import { Home } from './Home';
import { DownloadPage } from './DownloadPage';
import { PluginPage } from './PluginPage';
import { SettingsPage } from './SettingsPage';
import { SearchPage } from './SearchPage';
import { PlayBar } from '../view/PlayBar';

@Entry
@ComponentV2
struct Index {
  private controller: web_webview.WebviewController = new web_webview.WebviewController();
  private tabsController: HdsTabsController = new HdsTabsController();
  @Local bootReady: boolean = false;

  aboutToAppear(): void {
    WebPluginExecutor.getInstance().attachController(this.controller);
    trackPlayer.onCellularForbidden(() => {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '移动网络下播放已被禁止', duration: 2000 });
      } catch (error) {
        // TODO: Implement error handling.
      }
    });
    this.initApp();
  }

  private async initApp(): Promise<void> {
    try {
      await Bootstrap.setup();
      this.bootReady = true;
    } catch (e) {
      const message = e instanceof Error ? e.message : '未知错误';
      try {
        this.getUIContext().getPromptAction().showToast({ message: '初始化失败: ' + message, duration: 3000 });
      } catch (err) {
        console.error('showToast failed: ' + (err instanceof Error ? err.message : String(err)));
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavigation(appState.pageInfos) {
        HdsTabs({ controller: this.tabsController }) {
          ForEach(MENU_CONFIG, (item: MenuItem, i: number) => {
            TabContent() {
              if (i === 0) {
                Home({ bootReady: this.bootReady })
              } else if (i === 1) {
                DownloadPage()
              } else if (i === 2) {
                PluginPage()
              } else {
                SettingsPage()
              }
            }
            .tabBar(new BottomTabBarStyle(tabBarSymbolOf(item), item.label))
          }, (item: MenuItem, i: number) => 'tab_' + i.toString())
        }
        .barOverlap(true)
        .vertical(false)
        .scrollable(false)
        .barPosition(BarPosition.End)
        .barFloatingStyle({
          barBottomMargin: 28,
          systemMaterialEffect: {
            materialType: appState.materialType,
            materialLevel: appState.materialLevel
          },
          adaptToHandedness: true,
          miniBar: {
            miniBarBuilder: () => {
              this.miniBarBuilder()
            },
            miniBarStyle: appState.miniBarStyle,
            onBarStyleChange: (miniBarStyle: HdsBarStyle) => {
              appState.miniBarStyle = miniBarStyle
            },
          },
        })
        .animationDuration(500)
        .onSelected((index: number) => {
          appState.currTabsIndex = index
        })
      }
      .titleMode(HdsNavigationTitleMode.MINI)
      .mode(NavigationMode.Stack)
      .navBarWidth('40%')
      .hideBackButton(true)
      .hideTitleBar(true)
      .navDestination(this.pageMap)
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.background_secondary'))
      .foregroundBlurStyle(appState.isForegroundBlur ? BlurStyle.Thin : BlurStyle.NONE,
        { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT, scale: 0.3 })

      Web({ src: 'resource://rawfile/plugin_host.html?v=4', controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .javaScriptProxy({
          object: WebPluginExecutor.getInstance().bridge,
          name: 'mfNative',
          methodList: ['onPluginResult', 'markReady', 'getUserVariables', 'httpRequest', 'log'],
          controller: this.controller
        })
        .width(1)
        .height(1)
        .opacity(0)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  pageMap(name: string) {
    if (name === ROUTE_SEARCH) {
      SearchPage({ bootReady: this.bootReady })
    }
  }

  @Builder
  miniBarBuilder() {
    PlayBar()
  }
}
