import preferences from '@ohos.data.preferences';
import { ContextHolder } from '../common/ContextHolder';
import { JsonUtil } from '../common/JsonUtil';
import { Log } from '../utils/Log';

/**
 * KV 存储（替代 react-native-mmkv）
 * 底层使用 @ohos.data.preferences，实例按 name 缓存
 * 所有写入均为 string（JSON），与 MusicFree 的 MMKV 用法一致
 */
export class KVStore {
  private static cache: Map<string, KVStore> = new Map();
  /** 已创建的存储名注册表（备份时枚举所有 KV 数据用） */
  private static registeredNames: Set<string> = new Set();

  readonly name: string;
  private pref: preferences.Preferences;

  private constructor(name: string, pref: preferences.Preferences) {
    this.name = name;
    this.pref = pref;
  }

  /** 获取或创建 KV 存储（同步） */
  static getOrCreate(name: string): KVStore {
    KVStore.registeredNames.add(name);
    let store = KVStore.cache.get(name);
    if (store !== undefined) {
      return store;
    }
    const ctx = ContextHolder.get();
    let pref: preferences.Preferences;
    try {
      pref = preferences.getPreferencesSync(ctx, { name: name });
    } catch (e) {
      // 加载失败时使用内存实例兜底（写入不持久化，但不阻断流程）
      pref = preferences.getPreferencesSync(ctx, { name: name + '.fallback' });
    }
    const newStore = new KVStore(name, pref);
    KVStore.cache.set(name, newStore);
    return newStore;
  }

  /** 读取字符串（不存在返回空串） */
  get(key: string): string {
    try {
      const v: preferences.ValueType = this.pref.getSync(key, '');
      if (typeof v === 'string') {
        return v;
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  /** 是否包含 key */
  contains(key: string): boolean {
    try {
      return this.pref.hasSync(key);
    } catch (e) {
      return false;
    }
  }

  /** 写入字符串 */
  set(key: string, value: string): void {
    try {
      this.pref.putSync(key, value);
      this.flushToDisk();
    } catch (e) {
      // 忽略写入失败
    }
  }

  /** 删除 key */
  delete(key: string): void {
    try {
      this.pref.deleteSync(key);
      this.flushToDisk();
    } catch (e) {
      // 忽略删除失败
    }
  }

  /** 清空 */
  clearAll(): void {
    try {
      this.pref.clearSync();
      this.flushToDisk();
    } catch (e) {
      // 忽略
    }
  }

  /** 所有 key */
  getAllKeys(): Array<string> {
    try {
      const all = this.pref.getAllSync();
      return Object.keys(all);
    } catch (e) {
      return [];
    }
  }

  /**
   * 将内存数据异步落盘
   * preferences 的 put/delete 只写内存，必须 flush 才写入文件；
   * 否则进程被杀（强杀/崩溃）时数据丢失
   */
  private flushToDisk(): void {
    try {
      this.pref.flush().catch((_e: Object): void => {
        Log.error('KV 存储落盘失败: ' + this.name);
      });
    } catch (e) {
      // ignore
    }
  }

  /** 导出全部键值（备份用） */
  exportData(): Record<string, string> {
    const data: Record<string, string> = {};
    try {
      const all = this.pref.getAllSync();
      const rec = JsonUtil.parseRecord(JsonUtil.safeStringify(all));
      if (rec !== null) {
        for (const key of Object.keys(rec)) {
          data[key] = JsonUtil.recStr(rec, key);
        }
      }
    } catch (e) {
      // ignore
    }
    return data;
  }

  /** 整体导入键值并落盘（恢复用：先清空再写入） */
  importData(data: Record<string, string>): void {
    try {
      this.pref.clearSync();
      for (const key of Object.keys(data)) {
        this.pref.putSync(key, data[key]);
      }
    } catch (e) {
      // ignore
    }
    this.flushToDisk();
  }

  /** 已创建的全部存储名（备份枚举用，含 DataManifest 未登记的动态实例） */
  static getRegisteredNames(): Array<string> {
    const names: Array<string> = [];
    for (const n of KVStore.registeredNames) {
      names.push(n);
    }
    return names;
  }
}
