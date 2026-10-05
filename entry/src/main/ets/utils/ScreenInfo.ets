import window from '@ohos.window';
import { display } from '@kit.ArkUI';
import { ContextHolder } from '../common/ContextHolder';
import { appState } from '../entryability/AppState';
import { playerAnim, PlayerExpandAnimController } from './PlayerExpandAnim';

@ObservedV2
class ScreenInfo{
  async info(windowStage: window.WindowStage){
    try {
      if (windowStage) {
        const win = await windowStage.getMainWindow();
        const windowClass: window.Window = windowStage.getMainWindowSync();
        await windowClass.setWindowLayoutFullScreen(true);
        // PC/平板自由窗口：隐藏系统标题栏，页面扩展至标题栏区域，右上角仅保留系统三键（下沉到页面内），
        // 与 PcTitleBar 合并为一条横栏；读取三键区宽度供 PcTitleBar 右侧避让
        try {
          windowClass.setWindowDecorVisible(false);
        } catch (e) {
          // 手机/全屏等无标题栏形态不支持（801），忽略
        }
        try {
          const buttonRect = windowClass.getTitleButtonRect();
          appState.decorButtonWidth = buttonRect.right + buttonRect.width;
        } catch (e) {
          appState.decorButtonWidth = 0;
        }
        try {
          windowClass.on('windowTitleButtonRectChange', (rect: window.TitleButtonRect) => {
            appState.decorButtonWidth = rect.right + rect.width;
          });
        } catch (e) {
          // 不支持窗口三键区的设备忽略
        }
        if (win) {
          appState.topRect = ContextHolder.getUiContext().px2vp(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height)
          appState.bottomRect = ContextHolder.getUiContext().px2vp(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height)
          console.info('屏幕信息 #状态栏避让高度：', appState.topRect + 'vp', '#导航栏避让高度：', appState.bottomRect + 'vp');
        }

        windowClass.on('avoidAreaChange', (data) => {
          if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
            appState.topRect = ContextHolder.getUiContext().px2vp(data.area.topRect.height)
          } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
            appState.bottomRect = ContextHolder.getUiContext().px2vp(data.area.bottomRect.height)
          }
          console.info('屏幕信息 #状态栏避让高度：', appState.topRect + 'vp', '#导航栏避让高度：', appState.bottomRect + 'vp');
        });

        /* 断点获取 */
        windowStage.getMainWindow().then((data: window.Window) => {
          const uiContext = data.getUIContext()
          // 物理屏宽度（vp）：与窗口宽度差值判定是否以自由窗口方式运行
          const d = display.getDefaultDisplaySync()
          appState.displayWidth = uiContext.px2vp(d.width)
          // 获取窗口断点
          appState.WidthBp = uiContext.getWindowWidthBreakpoint()
          appState.HeightBp = uiContext.getWindowHeightBreakpoint()
          const rect = data.getWindowProperties().windowRect
          appState.screenWidth = uiContext.px2vp(rect.width)
          appState.screenHeight = uiContext.px2vp(rect.height)
          // 播放页覆盖层初始基准用窗口尺寸（自由窗口模式下 display 为物理屏，两者不相等）
          playerAnim.screenWidth = appState.screenWidth
          playerAnim.screenHeight = appState.screenHeight
          const initOffset = appState.screenHeight + 100
          if (playerAnim.pageTranslateY === playerAnim.collapsedOffset) {
            playerAnim.pageTranslateY = initOffset
          }
          playerAnim.collapsedOffset = initOffset
          // 监听屏幕改变
          data.on('windowSizeChange', async (data) => {
            // 获取窗口断点
            appState.WidthBp = uiContext.getWindowWidthBreakpoint()
            appState.HeightBp = uiContext.getWindowHeightBreakpoint()
            // 窗口 vp 尺寸（旋转/分屏/折叠时更新，供断点布局计算）
            appState.screenWidth = uiContext.px2vp(data.width)
            appState.screenHeight = uiContext.px2vp(data.height)
            // 播放页覆盖层常驻 Index 顶层：同步屏幕尺寸与收起偏移，避免旋转后收起位置失效
            playerAnim.screenWidth = appState.screenWidth
            playerAnim.screenHeight = appState.screenHeight
            const newOffset = appState.screenHeight + 100
            if (playerAnim.pageTranslateY === playerAnim.collapsedOffset) {
              playerAnim.pageTranslateY = newOffset
            }
            playerAnim.collapsedOffset = newOffset
            // 展开静止态：重测一镜到底几何并对齐新窗口尺寸，防止收起/拖拽用过期坐标
            PlayerExpandAnimController.refreshIfExpanded()
            console.info(`#屏幕信息: 横断点：${appState.WidthBp}， 竖断点：${appState.HeightBp}`)

          })
        }).catch((err: BusinessError) => {
          console.error(`Failed to obtain the main window. Cause code: ${err.code}, message: ${err.message}`);
        })
      }
    } catch (error) {
      // TODO: Implement error handling.
    }
  }
}

export const screenInfo: ScreenInfo = new ScreenInfo()