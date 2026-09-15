import preferences from '@ohos.data.preferences';
import { ContextHolder } from '../common/ContextHolder';

/**
 * KV 存储（替代 react-native-mmkv）
 * 底层使用 @ohos.data.preferences，实例按 name 缓存
 * 所有写入均为 string（JSON），与 MusicFree 的 MMKV 用法一致
 */
export class KVStore {
  private static cache: Map<string, KVStore> = new Map();

  readonly name: string;
  private pref: preferences.Preferences;

  private constructor(name: string, pref: preferences.Preferences) {
    this.name = name;
    this.pref = pref;
  }

  /** 获取或创建 KV 存储（同步） */
  static getOrCreate(name: string): KVStore {
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
    } catch (e) {
      // 忽略写入失败
    }
  }

  /** 删除 key */
  delete(key: string): void {
    try {
      this.pref.deleteSync(key);
    } catch (e) {
      // 忽略删除失败
    }
  }

  /** 清空 */
  clearAll(): void {
    try {
      this.pref.clearSync();
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
}
