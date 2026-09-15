import window from '@ohos.window';
import { appState } from '../common/AppState';
import { ContextHolder } from '../common/ContextHolder';

@ObservedV2
class ScreenInfo{
  winStage?: window.WindowStage = undefined;

  init(windowStage: window.WindowStage){
    this.winStage = windowStage;
  }

  async info(){
    try {
      if (this.winStage) {
        const win = await this.winStage.getMainWindow();
        const windowClass: window.Window = this.winStage.getMainWindowSync();
        await windowClass.setWindowLayoutFullScreen(true);
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
        this.winStage.getMainWindow().then((data: window.Window) => {
          const uiContext = data.getUIContext()
          // 获取窗口断点
          appState.WidthBp = uiContext.getWindowWidthBreakpoint()
          appState.HeightBp = uiContext.getWindowHeightBreakpoint()
          // 监听屏幕改变
          data.on('windowSizeChange', async (data) => {
            // 获取窗口断点
            appState.WidthBp = uiContext.getWindowWidthBreakpoint()
            appState.HeightBp = uiContext.getWindowHeightBreakpoint()
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