import { KVStore } from '../infra/KVStore';
import { JsonUtil, JsonRecord } from '../common/JsonUtil';

/**
 * 插件元数据（移植自 meta.ts，去掉旧版本迁移逻辑）
 * 存储：order（排序）、disabledPlugins、<platform>.userVariables、<platform>.alternativePlugin
 */
export class PluginMeta {
  private static cachedDisabled: Set<string> | null = null;

  private static store(): KVStore {
    return KVStore.getOrCreate('plugin-meta');
  }

  static getPluginOrder(): Record<string, number> {
    const rec = JsonUtil.parseRecord(PluginMeta.store().get('order'));
    const order: Record<string, number> = {};
    if (rec === null) {
      return order;
    }
    for (const k of Object.keys(rec)) {
      const v = rec[k];
      if (typeof v === 'number') {
        order[k] = v;
      }
    }
    return order;
  }

  static setPluginOrder(orderMap: Record<string, number>): void {
    const rec: JsonRecord = {};
    for (const k of Object.keys(orderMap)) {
      rec[k] = orderMap[k];
    }
    PluginMeta.store().set('order', JsonUtil.safeStringify(rec));
  }

  private static getDisabledSet(): Set<string> {
    if (PluginMeta.cachedDisabled !== null) {
      return PluginMeta.cachedDisabled;
    }
    const set = new Set<string>();
    const list = JsonUtil.parseAny(PluginMeta.store().get('disabledPlugins'));
    if (typeof list === 'object' && list !== null && Array.isArray(list)) {
      const arr = list as Array<Object>;
      for (const it of arr) {
        if (typeof it === 'string') {
          set.add(it);
        }
      }
    }
    PluginMeta.cachedDisabled = set;
    return set;
  }

  static isPluginEnabled(pluginPlatform: string): boolean {
    return !PluginMeta.getDisabledSet().has(pluginPlatform);
  }

  static setPluginEnabled(pluginPlatform: string, enabled: boolean): void {
    const set = PluginMeta.getDisabledSet();
    if (enabled) {
      set.delete(pluginPlatform);
    } else {
      set.add(pluginPlatform);
    }
    const arr: Array<string> = [];
    for (const it of set) {
      arr.push(it);
    }
    PluginMeta.store().set('disabledPlugins', JSON.stringify(arr));
    PluginMeta.cachedDisabled = set;
  }

  static getUserVariables(pluginPlatform: string): Record<string, string> {
    const rec = JsonUtil.parseRecord(PluginMeta.store().get(pluginPlatform + '.userVariables'));
    return JsonUtil.toStringMap(rec);
  }

  static setUserVariables(pluginPlatform: string, userVariables: Record<string, string>): void {
    PluginMeta.store().set(pluginPlatform + '.userVariables',
      JsonUtil.safeStringify(JsonUtil.fromStringMap(userVariables)));
  }

  static setAlternativePlugin(pluginPlatform: string, alternativePluginPlatform: string): void {
    PluginMeta.store().set(pluginPlatform + '.alternativePlugin',
      JsonUtil.safeStringify(alternativePluginPlatform));
  }

  static getAlternativePlugin(pluginPlatform: string): string | null {
    const v = JsonUtil.parseString(PluginMeta.store().get(pluginPlatform + '.alternativePlugin'));
    if (v !== null && v.length > 0) {
      return v;
    }
    return null;
  }
}

export const pluginMeta = new PluginMeta();
