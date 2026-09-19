/**
 * 断点适配工具：基于 appState.WidthBp / appState.HeightBp
 * （WindowBreakpoint：0=sm，1=md，2=lg）统一输出各设备的布局参数
 */
import { deviceInfo } from '@kit.BasicServicesKit';

/** 推荐歌单网格列数：手机 3 列 / 折叠展开(md) 4 列 / 平板与大屏(lg) 5 列 */
export function sheetGridColumns(widthBp: number): number {
  if (widthBp >= 2) {
    return 5;
  }
  return widthBp === 1 ? 4 : 3;
}

/** 页面内容最大宽度（vp）：lg 限宽居中避免列表行被拉满全屏，其余断点不限 */
export function contentMaxWidthVp(widthBp: number): number {
  return widthBp >= 2 ? 600 : 100000;
}

/** 是否为横屏/矮窗口布局（高度断点为 sm 且宽度不小于 md）：播放页左右分栏 */
export function isLandscapeLayout(widthBp: number, heightBp: number): boolean {
  return heightBp === 0 && widthBp >= 1;
}

/**
 * 是否为 PC 风格侧边栏布局：
 * - 2in1/PC 设备恒为侧边栏布局
 * - 其余设备仅在以窗口方式运行时启用（窗口宽度小于物理屏宽且不小于 md）；
 *   手机横屏/平板全屏等全屏断点不启用
 */
export function useSidebarLayout(widthBp: number, windowWidthVp: number, displayWidthVp: number): boolean {
  if (deviceInfo.deviceType === '2in1') {
    return true;
  }
  return widthBp >= 1 && windowWidthVp > 0 && displayWidthVp > 0 &&
    displayWidthVp - windowWidthVp > 4;
}
