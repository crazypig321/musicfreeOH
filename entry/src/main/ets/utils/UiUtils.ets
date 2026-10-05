/**
 * 公共 UI 工具：Toast 提示与时长格式化（收敛各页面重复实现）
 */

import { deviceInfo } from '@kit.BasicServicesKit';
import { uiMaterial } from '@kit.ArkUI';
import { ArtistItem } from '../common/model/SheetTypes';

/** 歌手统计行：作品数 + 粉丝数 */
export function formatArtistStats(artist: ArtistItem): string {
  const parts: Array<string> = [];
  if (artist.worksNum > 0) {
    parts.push(artist.worksNum.toString() + '首歌曲');
  }
  if (artist.fans > 0) {
    parts.push(artist.fans >= 10000 ?
      (artist.fans / 10000).toFixed(1) + '万粉丝' : artist.fans.toString() + '粉丝');
  }
  return parts.join(' · ');
}

/** 页面内统一 Toast（1.5s）：传入 this.getUIContext() */
export function showUiToast(context: UIContext, message: string): void {
  try {
    context.getPromptAction().showToast({ message: message, duration: 1500 });
  } catch (error) {
    // UI 上下文不可用时忽略
  }
}

/** 秒 → mm:ss */
export function formatDuration(sec: number): string {
  const s = Math.max(0, Math.floor(sec));
  const m = Math.floor(s / 60);
  const r = s % 60;
  const mStr = m < 10 ? '0' + m.toString() : m.toString();
  const rStr = r < 10 ? '0' + r.toString() : r.toString();
  return mStr + ':' + rStr;
}

/** 设备系统 API 是否 >= 26.0.0（沉浸式材质 systemMaterial / ImmersiveMaterial 最低版本） */
export function IsApiVersion_26(): boolean {
  return deviceInfo.distributionOSApiVersion >= 260000;
}

/** THICK 沉浸式材质（bindMenu 菜单用）；API < 26 时返回 undefined，低版本设备不构造材质对象、不会闪退 */
export function thickImmersiveMaterial(): uiMaterial.ImmersiveMaterial | undefined {
  return IsApiVersion_26()
    ? new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THICK })
    : undefined;
}

/** Slider 沉浸式材质（ULTRA_THIN）版本兼容适配器：仅在 API >= 26 时调用 systemMaterial，低版本不执行、不会闪退 */
export class SliderImmersiveModifier implements AttributeModifier<SliderAttribute> {
  applyNormalAttribute(instance: SliderAttribute): void {
    if (IsApiVersion_26()) {
      instance.systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN
      }));
    }
  }
}

/** 共享的无状态 Slider 材质适配器实例 */
export const sliderImmersiveModifier: SliderImmersiveModifier = new SliderImmersiveModifier();

/** Search 沉浸式材质（ULTRA_THIN + colorInvert）版本兼容适配器：仅在 API >= 26 时生效 */
export class SearchImmersiveModifier implements AttributeModifier<SearchAttribute> {
  applyNormalAttribute(instance: SearchAttribute): void {
    if (IsApiVersion_26()) {
      instance.systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true
      }));
    }
  }
}

/** 共享的无状态 Search 材质适配器实例 */
export const searchImmersiveModifier: SearchImmersiveModifier = new SearchImmersiveModifier();

/** Row 沉浸式材质（ULTRA_THIN + colorInvert）版本兼容适配器：仅在 API >= 26 时生效 */
export class RowImmersiveModifier implements AttributeModifier<RowAttribute> {
  applyNormalAttribute(instance: RowAttribute): void {
    if (IsApiVersion_26()) {
      instance.systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true
      }));
    }
  }
}

/** 共享的无状态 Row 材质适配器实例 */
export const rowImmersiveModifier: RowImmersiveModifier = new RowImmersiveModifier();

/** Stack 沉浸式材质（ULTRA_THIN + colorInvert）版本兼容适配器：仅在 API >= 26 时生效 */
export class StackImmersiveModifier implements AttributeModifier<StackAttribute> {
  applyNormalAttribute(instance: StackAttribute): void {
    if (IsApiVersion_26()) {
      instance.systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true
      }));
    }
  }
}

/** 共享的无状态 Stack 材质适配器实例 */
export const stackImmersiveModifier: StackImmersiveModifier = new StackImmersiveModifier();
