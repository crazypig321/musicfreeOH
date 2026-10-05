import web_webview from '@ohos.web.webview';
import { display } from '@kit.ArkUI';
import { WebPluginExecutor } from '../plugin/WebPluginExecutor';
import { Bootstrap } from '../core/Bootstrap';
import { MusicWidgetManager } from '../core/MusicWidgetManager';
import { trackPlayer } from '../core/TrackPlayer';
import {
  HdsBarStyle,
  HdsNavigation, HdsNavigationTitleMode, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { appState } from '../entryability/AppState';
import { IsApiVersion_24 } from '../utils/BarScrollHelper';
import { ArtworkCache } from '../utils/ArtworkCache';
import { PlayerPage } from './PlayerPage';
import { PlayBar } from '../view/PlayBar';
import { sheetPreferType, useSidebarLayout } from '../utils/BreakpointUtils';
import { playerAnim, PlayerExpandAnimController } from '../utils/PlayerExpandAnim';
import { PcMainLayout } from './pcUI/PcMainLayout';
import { CarModeView } from '../view/CarModeView';
import { MainTabPagesBuilder, PageMapBuilder } from '../view/AppPages';
import { CustomContentDialog } from '@kit.ArkUI';
  import { DialogManager } from '../utils/DialogUtils';
import { UsageDialogContent } from '../view/DialogView/UsageDialogContent';
import { VarFieldsDialogContent } from '../view/DialogView/VarFieldsDialogContent';
import { RenameDialogContent } from '../view/DialogView/RenameDialogContent';
import { SortJumpDialogContent } from '../view/DialogView/SortJumpDialogContent';
import { DownloadFolderDialogContent } from '../view/DialogView/DownloadFolderDialogContent';
import { TextPickerDialogContent } from '../view/DialogView/TextPickerDialogContent';
import { ChangeSourceDialogContent } from '../view/DialogView/ChangeSourceDialogContent';
import { CoverPickDialogContent } from '../view/DialogView/CoverPickDialogContent';
import { DisclaimerDialogContent } from '../view/DialogView/DisclaimerDialogContent';
import { CacheInputDialogContent } from '../view/DialogView/CacheInputDialogContent';
import { ConfirmMessageDialogContent } from '../view/DialogView/ConfirmMessageDialogContent';
import { SimpleRenameDialogContent } from '../view/DialogView/SimpleRenameDialogContent';
import { LyricSourceDialogContent } from '../view/DialogView/LyricSourceDialogContent';
import { EqGainDialogContent } from '../view/DialogView/EqGainDialogContent';
import { SheetIntroDialogContent } from '../view/DialogView/SheetIntroDialogContent';
import { MetaEditDialogContent } from '../view/DialogView/MetaEditDialogContent';
import { ContextHolder } from '../common/ContextHolder';
import { AppMeta } from '../core/AppMeta';
import { appConfig } from '../core/AppConfig';
import { ChangelogSheet } from '../view/ChangelogSheet';
import { PaySupport } from '../view/PaySuport';

@Entry
@ComponentV2
struct Index {
  private controller: web_webview.WebviewController = new web_webview.WebviewController();
  private tabsController: HdsTabsController = new HdsTabsController();
  /** PC 侧边栏布局下的主页面容器（barHeight 0 仅保活页面） */
  private sideTabsController: TabsController = new TabsController();
  /** 升级后首次冷启动自动弹出的更新日志半模态 */
  @Local showChangelogSheet: boolean = false;

  aboutToAppear(): void {
    // 播放页覆盖层初始平移到屏幕外（此时 UIContext 尚未初始化，用 densityPixels 换算 vp）
    const d = display.getDefaultDisplaySync();
    playerAnim.collapsedOffset = d.height / d.densityPixels + 100;
    playerAnim.screenWidth = d.width / d.densityPixels;
    playerAnim.screenHeight = d.height / d.densityPixels;
    playerAnim.density = d.densityPixels;
    playerAnim.pageTranslateY = playerAnim.collapsedOffset;
    WebPluginExecutor.getInstance().attachController(this.controller);
    // 公共弹窗：注册打开动作、轻提示与关闭动作
    DialogManager.Register((): void => {
      this.dataDialog.open();
    }, (message: string): void => {
      this.notifyToast(message);
    }, (): void => {
      this.dataDialog.close();
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
      appState.bootReady = true;
      // 启动恢复的当前歌曲不触发事件，主动推送一次桌面卡片状态
      MusicWidgetManager.refresh();
      this.checkChangelogOnLaunch();
    } catch (e) {
      const message = e instanceof Error ? e.message : '未知错误';
      try {
        this.getUIContext().getPromptAction().showToast({ message: '初始化失败: ' + message, duration: 3000 });
      } catch (err) {
        console.error('showToast failed: ' + (err instanceof Error ? err.message : String(err)));
      }
    }
  }

  /** 版本升级后首次冷启动弹出更新日志（首次安装仅记录版本不弹出；非升级冷启动不弹出） */
  private checkChangelogOnLaunch(): void {
    // 驾驶模式期间不弹打扰性弹窗
    if (appState.carModeActive) {
      appConfig.setUpdateLastChangelogVersion(AppMeta.appVersion);
      return;
    }
    const lastShown = appConfig.getUpdateLastChangelogVersion();
    if (lastShown === AppMeta.appVersion) {
      return;
    }
    appConfig.setUpdateLastChangelogVersion(AppMeta.appVersion);
    if (lastShown.length === 0) {
      return;
    }
    // 延迟弹出，等待主页渲染完成
    setTimeout(() => {
      this.showChangelogSheet = true;
    }, 600);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (appState.carModeActive) {
        // 驾驶模式（HiCar 车机屏自动进入 / 设置页手动开启）：大按钮简布局
        CarModeView()
      } else if (useSidebarLayout(appState.WidthBp, appState.screenWidth, appState.displayWidth)) {
        // PC 风格布局（参考 BiliMusic MainLayout）：标题栏 + (侧边栏 + 内容区) + 底部播放栏；
        // 二级页面仅覆盖内容区，标题栏/侧边栏/播放栏跨页面常驻
        PcMainLayout({ tabsController: this.sideTabsController })
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
    .bindSheet(!!this.showChangelogSheet, this.ChangelogSheetBuilder(), {
      detents: [SheetSize.LARGE],
      dragBar: true, preferType: sheetPreferType(),
      backgroundColor: $r('sys.color.background_secondary'),
      onWillDisappear: () => {
        appState.isForegroundBlur = false
        this.showChangelogSheet = false;
      },
      onWillAppear: () => {
        appState.isForegroundBlur = true
      },
    })
  }

  @Builder
  ChangelogSheetBuilder() {
    ChangelogSheet({ focusVersion: AppMeta.appVersion })
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

  /** 主页面 TabContent（手机 HdsTabs 使用；页面装配提取到 AppPages 与 PC 布局共用） */
  @Builder
  MainTabContents() {
    MainTabPagesBuilder()
  }

  @Builder
  pageMap(name: string) {
    PageMapBuilder(name)
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
    } else if (key === '歌单说明') {
      SheetIntroDialogContent()
    } else if (key === '下载到文件夹' || key === '移动到文件夹' ||
      key === '添加标签' || key === '编辑标签') {
      DownloadFolderDialogContent()
    } else if (key === '选择器') {
      TextPickerDialogContent()
    } else if (key === '更换音源') {
      ChangeSourceDialogContent()
    } else if (key === '选择封面') {
      CoverPickDialogContent()
    } else if (key === '选择歌词音源') {
      LyricSourceDialogContent()
    } else if (key === '免责声明') {
      DisclaimerDialogContent()
    } else if (key === '设置缓存') {
      CacheInputDialogContent()
    } else if (key === '清除缓存' || key === '确认删除' || key === '确认移出' || key === '确认导入' ||
      key === '发现新版本') {
      ConfirmMessageDialogContent()
    } else if (key === '转换简洁命名') {
      SimpleRenameDialogContent()
    } else if (key === '均衡器增益') {
      EqGainDialogContent()
    } else if (key === '编辑信息') {
      MetaEditDialogContent()
    } else if (key === '捐赠'){
      PaySupport()
    }
  }
}
