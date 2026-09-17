import web_webview from '@ohos.web.webview';
import { WebPluginExecutor } from '../plugin/WebPluginExecutor';
import { Bootstrap } from '../core/Bootstrap';
import { trackPlayer } from '../core/TrackPlayer';
import {
  HdsBarStyle,
  HdsNavigation, HdsNavigationTitleMode, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { appState } from '../entryability/AppState';
import { IsApiVersion_24 } from '../utils/BarScrollHelper';
import { MENU_CONFIG, MenuItem, tabBarSymbolOf } from '../common/model/TabsModels';
import { ROUTE_SEARCH, ROUTE_DOWNLOAD, ROUTE_LOCAL_MUSIC, ROUTE_RECOMMEND_SHEETS, ROUTE_SHEET_DETAIL, ROUTE_PLAYER } from '../common/model/NavModels';
import { DownloadPage } from './DownloadPage';
import { PluginPage } from './PluginPage';
import { MySheetsPage } from './MySheetsPage';
import { SettingsPage } from './SettingsPage';
import { SearchPage } from './SearchPage';
import { SubscriptionPage } from './SubscriptionPage';
import { LocalMusicPage } from './LocalMusicPage';
import { RecommendSheetsPage } from './RecommendSheetsPage';
import { SheetDetailPage } from './SheetDetailPage';
import { PlayerPage } from './PlayerPage';
import { PlayBar } from '../view/PlayBar';
import { HomePage } from './HomePage';
import { CustomContentDialog } from '@kit.ArkUI';
import { DialogManager, UsageDialogContent, VarFieldsDialogContent, RenameDialogContent, SortJumpDialogContent } from '../utils/DialogUtils';

@Entry
@ComponentV2
struct Index {
  private controller: web_webview.WebviewController = new web_webview.WebviewController();
  private tabsController: HdsTabsController = new HdsTabsController();
  @Local bootReady: boolean = false;

  aboutToAppear(): void {
    WebPluginExecutor.getInstance().attachController(this.controller);
    // 公共弹窗：注册打开动作与轻提示
    DialogManager.Register((): void => {
      this.dataDialog.open();
    }, (message: string): void => {
      this.notifyToast(message);
    });
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
                HomePage({ bootReady: this.bootReady })
              } else if (i === 1) {
                MySheetsPage()
              } else if (i === 2) {
                PluginPage()
              } else if (i === 3) {
                SubscriptionPage()
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
        // 批量操作模式下隐藏 tab 栏
        .barHeight(appState.isBatchMode ? 0 : 56)
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
            barLayoutMode: IsApiVersion_24() ? appState.hdsBarLayoutMode : undefined,
            miniBarStyle: appState.miniBarStyle,
            onBarStyleChange: (miniBarStyle: HdsBarStyle) => {
              if (!IsApiVersion_24()) {
                appState.miniBarStyle = miniBarStyle
              } else {
                // API>=24：点击折叠时切换回上下两排
                if (miniBarStyle === HdsBarStyle.COLLAPSE) {
                  this.getUIContext().animateTo({ duration: 300, curve: Curve.Smooth }, () => {
                    appState.hdsBarLayoutMode = 1
                    appState.miniBarStyle = miniBarStyle
                  })
                }
              }
            },
          },
        })
        .animationDuration(500)
        .onSelected((index: number) => {
          appState.currTabsIndex = index
        })
      }
      .titleMode(HdsNavigationTitleMode.FREE)
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

  /** 返回键：批量操作模式下先退出批量模式 */
  onBackPress(): boolean {
    if (appState.isBatchMode) {
      appState.isBatchMode = false;
      return true;
    }
    return false;
  }

  @Builder
  pageMap(name: string) {
    if (name === ROUTE_SEARCH) {
      SearchPage({ bootReady: this.bootReady })
    } else if (name === ROUTE_DOWNLOAD) {
      DownloadPage()
    } else if (name === ROUTE_LOCAL_MUSIC) {
      LocalMusicPage()
    } else if (name === ROUTE_RECOMMEND_SHEETS) {
      RecommendSheetsPage()
    } else if (name === ROUTE_SHEET_DETAIL) {
      SheetDetailPage()
    } else if (name === ROUTE_PLAYER) {
      PlayerPage()
    }
  }

  @Builder
  miniBarBuilder() {
    PlayBar()
  }

  /** 轻提示（供公共弹窗逻辑使用） */
  private notifyToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  /**
   * 公共弹窗
   */
  private dataDialog: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: DialogManager.DialogTitle(DialogManager.dialogChangeKey),
      contentBuilder: () => {
        this.DialogContentBuilder(DialogManager.dialogChangeKey)
      },
      buttons: DialogManager.DialogButtons(DialogManager.dialogChangeKey),
      contentAreaPadding: {
        top: 15,
        bottom: 15,
        left: 24,
        right: 24
      },
    }),
    onWillDismiss: (dis) => {
      dis.dismiss()
    },
    onWillAppear: () => {
      DialogManager.AppearDialog(DialogManager.dialogChangeKey)
    },
    onWillDisappear: ()=>{
      DialogManager.DisappearDialog(DialogManager.dialogChangeKey)
    }
  });

  // 弹窗中间自定义组件
  @Builder
  DialogContentBuilder(key: string) {
    if (key === '使用说明') {
      UsageDialogContent()
    } else if (key === '配置变量') {
      VarFieldsDialogContent()
    } else if (key === '创建分组') {
      // 预留：分组名称输入框
    } else if (key === '重命名') {
      RenameDialogContent()
    } else if (key === '跳转排序') {
      SortJumpDialogContent()
    }
  }
}
