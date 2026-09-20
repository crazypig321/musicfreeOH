import { motion } from '@kit.MultimodalAwarenessKit';
import { Callback } from '@kit.BasicServicesKit';
import { appConfig } from '../core/AppConfig';
import { appState } from '../entryability/AppState';
import { ContextHolder } from '../common/ContextHolder';
import { Log } from './Log';

/**
 * 智感握姿（适人握持）：
 * 订阅系统握持手识别（holdingHandChanged），左手握持时列表条目镜像布局
 * （封面/更多按钮换边、文本右对齐），其余状态保持常规布局。
 * 需声明 ohos.permission.DETECT_GESTURE 权限；设备不支持时静默保持默认布局。
 */
export class SmartReach {
  private static active: boolean = false;

  private static readonly callback: Callback<motion.HoldingHandStatus> =
    (status: motion.HoldingHandStatus): void => {
      const next = status === motion.HoldingHandStatus.LEFT_HAND_HELD ? 'left' : 'right';
      if (appState.holdingHand === next) {
        return;
      }
      try {
        ContextHolder.getUiContext().animateTo({ duration: 250, curve: Curve.Smooth }, (): void => {
          appState.holdingHand = next;
        });
      } catch (e) {
        appState.holdingHand = next;
      }
    };

  /** 启动时按设置恢复订阅 */
  static setup(): void {
    if (appConfig.getSmartReachEnabled()) {
      SmartReach.start();
    }
  }

  /** 设置开关 */
  static setEnabled(enabled: boolean): void {
    // 同步全局状态（底部栏 handedness 适配等据此渲染）
    appState.smartReachEnabled = enabled;
    if (enabled) {
      SmartReach.start();
    } else {
      SmartReach.stop();
    }
  }

  private static start(): void {
    if (SmartReach.active) {
      return;
    }
    if (!canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      Log.warn('SmartReach: 设备不支持动作感知能力');
      return;
    }
    try {
      motion.on('holdingHandChanged', SmartReach.callback);
      SmartReach.active = true;
    } catch (e) {
      Log.warn('SmartReach: 订阅握持手失败 ' + (e instanceof Error ? e.message : ''));
    }
  }

  private static stop(): void {
    if (!SmartReach.active) {
      return;
    }
    try {
      motion.off('holdingHandChanged', SmartReach.callback);
    } catch (e) {
      // 静默失败
    }
    SmartReach.active = false;
    appState.holdingHand = 'right';
  }
}
