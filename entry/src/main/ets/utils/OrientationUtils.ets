import { window } from '@kit.ArkUI';
import { ContextHolder } from '../common/ContextHolder';
import { appConfig } from '../core/AppConfig';

/**
 * 屏幕方向统一入口（外观设置 / 车载模式共用）：
 * - 车载模式（CarModeView 驾驶界面）强制横屏
 * - 非车载模式按外观设置：竖屏 / 横屏 / 跟随系统
 * 由 Bootstrap 启动恢复、设置页切换、AppState.refreshCarMode 车载模式开关时调用
 */
export class OrientationUtils {
  /** 应用屏幕方向：车载模式强制横屏，否则按外观设置 */
  static apply(carModeActive: boolean): void {
    window.getLastWindow(ContextHolder.get()).then((win: window.Window): Promise<void> => {
      let orientation = window.Orientation.AUTO_ROTATION_RESTRICTED;
      if (carModeActive) {
        // 驾驶界面仅横屏展示
        orientation = window.Orientation.LANDSCAPE;
      } else if (appConfig.getAppearanceOrientation() === 'portrait') {
        orientation = window.Orientation.PORTRAIT;
      } else if (appConfig.getAppearanceOrientation() === 'landscape') {
        orientation = window.Orientation.LANDSCAPE;
      }
      // AUTO_ROTATION_RESTRICTED：跟随传感器旋转，且受系统控制中心「自动旋转」开关控制
      return win.setPreferredOrientation(orientation);
    }).catch((): void => {
      // 静默失败（无窗口等场景）
    });
  }
}
