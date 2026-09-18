import common from '@ohos.app.ability.common';
import { ContextHolder } from '../common/ContextHolder';

/**
 * 网页跳转工具：拉起系统浏览器打开指定网址
 */
export class WebUtils {
  /** appLinkingOnly 为 false 时未匹配应用则拉起浏览器打开 */
  static open(url: string, onFailure: (message: string) => void): void {
    const ctx: common.UIAbilityContext = ContextHolder.get();
    ctx.openLink(url, { appLinkingOnly: false }).catch((_e: Object): void => {
      onFailure('打开链接失败');
    });
  }
}
