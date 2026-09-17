import { HdsBarStyle } from '@kit.UIDesignKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { curves } from '@kit.ArkUI';
import { appState } from '../entryability/AppState';

/** 设备系统 API 是否 >= 6.1.1(24)（minibar/tabbar 上下排列模式所需） */
export function IsApiVersion_24(): boolean {
  return deviceInfo.distributionOSApiVersion >= 60101;
}

/**
 * 底部 minibar/tabbar 滚动切换样式（参考 ting_read）：
 * - 向下滚动浏览：收为单排（HORIZONTAL + 迷你栏展开整排）
 * - 向上滚动回看：恢复上下两排（VERTICAL + 迷你栏折叠）
 * 每帧以弹簧动效跟随切换
 */
export class BarScrollHelper {
  static notifyScrollDelta(ctx: UIContext, offset: number): void {
    if (appState.WidthBp < 2 && IsApiVersion_24()) {
      ctx.animateTo({ duration: 500, curve: curves.springMotion(0.5, 0.7, 0.6) }, (): void => {
        if (offset < -2) {
          appState.hdsBarLayoutMode = 1;
          appState.miniBarStyle = HdsBarStyle.COLLAPSE;
        } else if (offset > 2) {
          appState.hdsBarLayoutMode = 0;
          appState.miniBarStyle = HdsBarStyle.EXPAND;
        }
      });
    }
  }
}
