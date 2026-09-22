import web_webview from '@ohos.web.webview';
import { display } from '@kit.ArkUI';
import { WebPluginExecutor } from '../plugin/WebPluginExecutor';
import { Bootstrap } from '../core/Bootstrap';
import { trackPlayer } from '../core/TrackPlayer';
import {
  HdsBarStyle,
  HdsNavigation, HdsNavigationTitleMode, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { appState } from '../entryability/AppState';
import { IsApiVersion_24 } from '../utils/BarScrollHelper';
import { MENU_CONFIG, MenuItem, tabBarSymbolOf } from '../common/model/TabsModels';
  import { ROUTE_SEARCH, ROUTE_DOWNLOAD, ROUTE_LOCAL_MUSIC, ROUTE_RECOMMEND_SHEETS, ROUTE_SHEET_DETAIL, ROUTE_ALBUM_DETAIL, ROUTE_ARTIST_DETAIL, ROUTE_ABOUT, ROUTE_CACHE, ROUTE_PLAY_SETTING, ROUTE_DOWNLOAD_SETTING, ROUTE_LYRIC_SETTING, ROUTE_PLUGIN_SETTING, ROUTE_BACKUP_SETTING, ROUTE_WEBDAV_SETTING, ROUTE_APPEARANCE_SETTING } from '../common/model/NavModels';
import { ArtworkCache } from '../utils/ArtworkCache';
import { DownloadPage } from './DownloadPage';
import { PluginPage } from './PluginPage';
import { MySheetsPage } from './MySheetsPage';
import { SettingsPage } from './SettingsPage';
import { SearchPage } from './SearchPage';
import { SubscriptionPage } from './SubscriptionPage';
import { LocalMusicPage } from './LocalMusicPage';
import { RecommendSheetsPage } from './RecommendSheetsPage';
import { SheetDetailPage } from './SheetDetailPage';
import { MediaDetailPage } from './MediaDetailPage';
import { AboutPage } from './settingSecPage/AboutPage';
import { CachePage } from './settingSecPage/CachePage';
import { PlaySettingPage } from './settingSecPage/PlaySettingPage';
import { DownloadSettingPage } from './settingSecPage/DownloadSettingPage';
import { LyricSettingPage } from './settingSecPage/LyricSettingPage';
import { PluginSettingPage } from './settingSecPage/PluginSettingPage';
import { BackupSettingPage } from './settingSecPage/BackupSettingPage';
import { WebDavSettingPage } from './settingSecPage/WebDavSettingPage';
import { AppearanceSettingPage } from './settingSecPage/AppearanceSettingPage';
import { PlayerPage } from './PlayerPage';
import { PlayBar } from '../view/PlayBar';
import { SideBar } from '../view/SideBar';
import { useSidebarLayout } from '../utils/BreakpointUtils';
import { playerAnim, PlayerExpandAnimController } from '../view/PlayerExpandAnim';
import { HomePage } from './HomePage';
import { CustomContentDialog } from '@kit.ArkUI';
  import { DialogManager, UsageDialogContent, VarFieldsDialogContent, RenameDialogContent, SortJumpDialogContent, DownloadFolderDialogContent, TextPickerDialogContent, ChangeSourceDialogContent, DisclaimerDialogContent, CacheInputDialogContent, ClearCacheDialogContent, ConfirmDeleteDialogContent } from '../utils/DialogUtils';
  import { ContextHolder } from '../common/ContextHolder';
import { PaySupport } from '../view/CommonCom';

@Entry
@ComponentV2
struct Index {
  private controller: web_webview.WebviewController = new web_webview.WebviewController();
  private tabsController: HdsTabsController = new HdsTabsController();
  /** PC 侧边栏布局下的主页面容器（barHeight 0 仅保活页面） */
  private sideTabsController: TabsController = new TabsController();
  @Local bootReady: boolean = false;

  aboutToAppear(): void {
    // 播放页覆盖层初始平移到屏幕外（此时 UIContext 尚未初始化，用 densityPixels 换算 vp）
    const d = display.getDefaultDisplaySync();
    playerAnim.collapsedOffset = d.height / d.densityPixels + 100;
    playerAnim.screenWidth = d.width / d.densityPixels;
    playerAnim.screenHeight = d.height / d.densityPixels;
    playerAnim.density = d.densityPixels;
    playerAnim.pageTranslateY = playerAnim.collapsedOffset;
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

  /** 底部 tab：文本选中色直接适配主题色 */
  private tabBarOf(item: MenuItem): BottomTabBarStyle {
    const style = new BottomTabBarStyle(tabBarSymbolOf(item), item.label);
    style.labelStyle({ selectedColor: appState.accentColor });
    return style;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (useSidebarLayout(appState.WidthBp, appState.screenWidth, appState.displayWidth)) {
        // PC 风格布局：Navigation 置于根部，二级页面（设置子页/搜索/歌单详情等）覆盖整个窗口；
        // 悬浮 PlayBar 在最上层常驻
        Stack({ alignContent: Alignment.Bottom }) {
          HdsNavigation(appState.pageInfos) {
            Row() {
              SideBar({
                expanded: appState.sidebarExpanded,
                onSelect: (index: number): void => {
                  this.sideTabsController.changeIndex(index);
                },
                onToggle: (): void => {
                  this.getUIContext().animateTo({ duration: 250, curve: Curve.Smooth }, () => {
                    appState.sidebarExpanded = !appState.sidebarExpanded;
                  });
                }
              })
              Column() {
                Tabs({ controller: this.sideTabsController }) {
                  this.MainTabContents()
                }
                .barHeight(0)
                .vertical(false)
                .scrollable(false)
                .animationDuration(appState.tabSwitchAnim ? 500 : 0)
                .onChange((index: number) => {
                  appState.currTabsIndex = index
                  appState.swipeResetTick = appState.swipeResetTick + 1
                })
              }
              .layoutWeight(1)
              .height('100%')
            }
            .width('100%')
            .height('100%')
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

          // 悬浮迷你播放条：窗口底部居中，二级页面覆盖时仍常驻（批量操作模式下隐藏）
          if (!appState.isBatchMode) {
            this.FloatingPlayBar()
          }
        }
        .width('100%')
        .height('100%')
      } else {
        HdsNavigation(appState.pageInfos) {
          HdsTabs({ controller: this.tabsController }) {
            this.MainTabContents()
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
            // 智感握姿：随设置开关 handedness 适配
            adaptToHandedness: appState.smartReachEnabled,
            // 批量操作模式下移除迷你栏，避免遮挡批量底栏
            miniBar: appState.isBatchMode ? undefined : {
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
          .animationDuration(appState.tabSwitchAnim ? 500 : 0)
          .onSelected((index: number) => {
            appState.currTabsIndex = index
            // 切换 tab 时递增计数，触发左滑条目（key 引用 tick）重建复位滑动状态
            appState.swipeResetTick = appState.swipeResetTick + 1
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
      }

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

      // 播放页覆盖层：一镜到底动画宿主（常驻挂载；收起时整体平移到屏幕外，不参与命中测试）
      // 锚点展开：页面固定在最终位置，clip 窗口从迷你条矩形生长到全屏
      Column() {
        PlayerPage()
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.background_secondary'))
      .clipShape(new Path({ commands: playerAnim.clipCommands() }))
      .translate({ y: playerAnim.pageTranslateY })
      .opacity(playerAnim.pageOpacity)

      // 飞行封面：迷你条封面与播放页大封面之间逐帧插值，动画期间可见
      // 不加 PRIMARY 阴影：封面逐帧缩放会导致主色提取逐帧像素回读，严重掉帧
      Image(ArtworkCache.resolve(trackPlayer.currentMusic === null ? '' : trackPlayer.currentMusic.artwork))
        .position({ x: playerAnim.coverX, y: playerAnim.coverY })
        .width(playerAnim.coverSize)
        .height(playerAnim.coverSize)
        .borderRadius(playerAnim.coverRadius)
        .objectFit(ImageFit.Cover)
        .opacity(playerAnim.coverOpacity)
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
  }

  /** 返回键：展开态先收起播放页；批量操作先退出；tab 搜索框先收起；非主页 tab 回主页；主页弹退出确认 */
  onBackPress(): boolean {
    if (playerAnim.isExpand || playerAnim.isAnimating) {
      PlayerExpandAnimController.collapse();
      return true;
    }
    if (appState.isBatchMode) {
      this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
        appState.isBatchMode = false;
      });
      return true;
    }
    // 当前 tab 标题栏搜索框展开时，返回手势优先收起搜索框
    if (appState.tabSearchClose !== null) {
      const closeSearch = appState.tabSearchClose;
      appState.tabSearchClose = null;
      closeSearch();
      return true;
    }
    // 非「主页」tab：返回手势回到主页 tab
    if (appState.currTabsIndex !== 0) {
      if (useSidebarLayout(appState.WidthBp, appState.screenWidth, appState.displayWidth)) {
        this.sideTabsController.changeIndex(0);
      } else {
        this.tabsController.changeIndex(0);
      }
      return true;
    }
    // 主页：弹出退出确认弹窗，确认后彻底退出应用
    this.showExitConfirm();
    return true;
  }

  /** 退出确认弹窗：确认后终止应用 */
  private showExitConfirm(): void {
    this.getUIContext().showAlertDialog({
      title: '退出应用',
      message: '是否确认退出软件？',
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '退出',
        fontColor: Color.Red,
        action: (): void => {
          ContextHolder.get().terminateSelf().catch((_e: Object): void => {
          });
        }
      }
    });
  }

  /** 主页面 TabContent（手机 HdsTabs 与 PC 侧边栏 Tabs 共用，保持页面状态不丢失） */
  @Builder
  MainTabContents() {
    ForEach(MENU_CONFIG, (item: MenuItem, i: number) => {
      TabContent() {
        if (i === 0) {
          HomePage({ bootReady: this.bootReady })
        } else if (i === 1) {
          MySheetsPage({ hostTabIndex: appState.currTabsIndex })
        } else if (i === 2) {
          PluginPage({ hostTabIndex: appState.currTabsIndex })
        } else if (i === 3) {
          SubscriptionPage()
        } else {
          SettingsPage()
        }
      }
      .tabBar(this.tabBarOf(item))
    }, (item: MenuItem, i: number) => 'tab_' + i.toString())
  }

  /** 悬浮迷你播放条（PC 侧边栏布局）：内容区底部居中 */
  @Builder
  FloatingPlayBar() {
    Column() {
      PlayBar({ floating: true })
    }
    .backdropBlur(60)
    .padding({ top: 7, bottom: 7 })
    .width(520)
    .constraintSize({ maxWidth: '90%' })
    .borderRadius(100)
    .borderWidth(1)
    .borderColor('#99ffffff')
    .backgroundColor('#80ffffff')
    .shadow({ radius: 24, color: 'rgba(0,0,0,0.15)', offsetX: 0, offsetY: 4 })
    .margin({ bottom: appState.bottomRect > 0 ? 16 : 12, left: 16, right: 16 })
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
    } else if (name === ROUTE_ALBUM_DETAIL || name === ROUTE_ARTIST_DETAIL) {
      MediaDetailPage()
    } else if (name === ROUTE_ABOUT) {
      AboutPage()
    } else if (name === ROUTE_CACHE) {
      CachePage()
    } else if (name === ROUTE_PLAY_SETTING) {
      PlaySettingPage()
    } else if (name === ROUTE_DOWNLOAD_SETTING) {
      DownloadSettingPage()
    } else if (name === ROUTE_LYRIC_SETTING) {
      LyricSettingPage()
    } else if (name === ROUTE_PLUGIN_SETTING) {
      PluginSettingPage()
    } else if (name === ROUTE_BACKUP_SETTING) {
      BackupSettingPage()
    } else if (name === ROUTE_WEBDAV_SETTING) {
      WebDavSettingPage()
    } else if (name === ROUTE_APPEARANCE_SETTING) {
      AppearanceSettingPage()
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
    } else if (key === '下载到文件夹' || key === '移动到文件夹' ||
      key === '添加标签' || key === '编辑标签') {
      DownloadFolderDialogContent()
    } else if (key === '选择器') {
      TextPickerDialogContent()
    } else if (key === '更换音源') {
      ChangeSourceDialogContent()
    } else if (key === '免责声明') {
      DisclaimerDialogContent()
    } else if (key === '设置缓存') {
      CacheInputDialogContent()
    } else if (key === '清除缓存') {
      ClearCacheDialogContent()
    } else if (key === '确认删除') {
      ConfirmDeleteDialogContent()
    } else if (key === '捐赠') {
      PaySupport()
    }
  }
}
