import { KVStore } from '../infra/KVStore';
import { JsonUtil } from '../common/JsonUtil';
import { MusicItem } from '../common/model/MediaTypes';
import { MediaUtils } from '../utils/MediaUtils';
import { FileUtils } from '../utils/FileUtils';

/**
 * 本地音乐移出排除名单（KV 'LocalExcludedFiles'）
 * 被用户「移出本地音乐」的文件保留在磁盘上，但启动扫描/手动刷新时跳过，
 * 避免移出后重新扫描又复活；重新导入对应文件时清除对应排除项。
 * 新条目按归一化完整路径存储（按文件名排除会误伤子文件夹中的同名文件）；
 * 历史版本存储的文件名条目保留兼容，匹配时按路径优先、文件名兜底
 */
export class LocalMusicExclusion {
  private static readonly STORE_KEY = 'LocalExcludedFiles';

  private static readSet(): Set<string> {
    const set = new Set<string>();
    const raw = KVStore.getOrCreate('storage').get(LocalMusicExclusion.STORE_KEY);
    if (raw.length > 0) {
      const arr = JsonUtil.parseStringArray(raw);
      if (arr !== null) {
        for (const name of arr) {
          set.add(name);
        }
      }
    }
    return set;
  }

  private static writeSet(set: Set<string>): void {
    const arr: Array<string> = [];
    for (const name of set) {
      arr.push(name);
    }
    KVStore.getOrCreate('storage').set(LocalMusicExclusion.STORE_KEY, JSON.stringify(arr));
  }

  /** 当前排除名单快照（完整路径 + 历史遗留的文件名条目） */
  static getExcludedFiles(): Set<string> {
    return LocalMusicExclusion.readSet();
  }

  /** 文件是否被排除：按完整路径匹配，历史文件名条目兜底（file:// 前缀自动剥离） */
  static isExcluded(set: Set<string>, path: string): boolean {
    const normalized = FileUtils.normalizePath(path);
    if (normalized.length === 0) {
      return false;
    }
    if (set.has(normalized)) {
      return true;
    }
    const name = FileUtils.getFileName(normalized);
    return name.length > 0 && set.has(name);
  }

  /** 将某首本地音乐对应的文件加入排除名单（存归一化完整路径） */
  static excludeItem(item: MusicItem): void {
    const localPath = MediaUtils.getLocalPath(item);
    if (localPath === null) {
      return;
    }
    const normalized = FileUtils.normalizePath(localPath);
    if (normalized.length === 0) {
      return;
    }
    const set = LocalMusicExclusion.readSet();
    set.add(normalized);
    LocalMusicExclusion.writeSet(set);
  }

  /** 清除某文件的排除（重新导入时使用；路径条目与历史文件名条目一并清除） */
  static clearExclusion(path: string): void {
    if (path.length === 0) {
      return;
    }
    const normalized = FileUtils.normalizePath(path);
    const set = LocalMusicExclusion.readSet();
    let changed = set.delete(normalized);
    const name = FileUtils.getFileName(normalized);
    if (name.length > 0 && name !== normalized && set.delete(name)) {
      changed = true;
    }
    if (changed) {
      LocalMusicExclusion.writeSet(set);
    }
  }
}
