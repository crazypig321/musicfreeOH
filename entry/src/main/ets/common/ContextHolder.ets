import common from '@ohos.app.ability.common';

/**
 * 全局应用上下文持有者
 * 在 EntryAbility.onCreate 时初始化
 */
export class ContextHolder {
  private static context: common.UIAbilityContext | null = null;
  static uiContext?: UIContext;
  static applicationContext?: common.ApplicationContext
  static ctx?: Context;

  static initUiContext(uiContext: UIContext, applicationContext: common.ApplicationContext) {
    ContextHolder.uiContext = uiContext;
    ContextHolder.applicationContext = applicationContext
  }

  static getUiContext(){
    if (ContextHolder.uiContext === undefined) {
      throw new Error('ContextHolder.uiContext 未初始化，请先在 Ability onCreate 中调用 init');
    }
    return ContextHolder.uiContext;
  }

  static getApplicationContext(){
    if (ContextHolder.applicationContext === undefined) {
      throw new Error('ContextHolder.applicationContext 未初始化，请先在 Ability onCreate 中调用 init');
    }
    return ContextHolder.applicationContext;
  }

  static initContext(ctx: Context) {
    ContextHolder.ctx = ctx;
  }

  static getCtx(){
    if (ContextHolder.ctx === undefined) {
      throw new Error('ContextHolder.uiContext 未初始化，请先在 Ability onCreate 中调用 init');
    }
    return ContextHolder.ctx;
  }

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
    return ContextHolder.context !== null && ContextHolder.uiContext !== undefined && ContextHolder.applicationContext !== undefined;
  }
}
