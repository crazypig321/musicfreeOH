import common from '@ohos.app.ability.common';

/**
 * 全局应用上下文持有者
 * 在 EntryAbility.onCreate 时初始化
 */
export class ContextHolder {
  private static context: common.UIAbilityContext | null = null;

  static init(context: common.UIAbilityContext): void {
    ContextHolder.context = context;
  }

  static get(): common.UIAbilityContext {
    if (ContextHolder.context === null) {
      throw new Error('ContextHolder 未初始化，请先在 Ability onCreate 中调用 init');
    }
    return ContextHolder.context;
  }

  static isReady(): boolean {
    return ContextHolder.context !== null;
  }
}
