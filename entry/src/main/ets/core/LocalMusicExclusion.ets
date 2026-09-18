import { KVStore } from '../infra/KVStore';
import { JsonUtil } from '../common/JsonUtil';
import { MusicItem } from '../common/model/MediaTypes';
import { MediaUtils } from '../utils/MediaUtils';
import { FileUtils } from '../utils/FileUtils';

/**
 * 本地音乐移出排除名单（KV 'LocalExcludedFiles'，存文件名集合）
 * 被用户「移出本地音乐」的文件保留在磁盘上，但启动扫描/手动刷新时跳过，
 * 避免移出后重新扫描又复活；重新导入同名文件时清除对应排除项
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

  /** 当前排除名单快照 */
  static getExcludedFiles(): Set<string> {
    return LocalMusicExclusion.readSet();
  }

  /** 将某首本地音乐对应的文件加入排除名单 */
  static excludeItem(item: MusicItem): void {
    const localPath = MediaUtils.getLocalPath(item);
    if (localPath === null) {
      return;
    }
    const name = FileUtils.getFileName(FileUtils.normalizePath(localPath));
    if (name.length === 0) {
      return;
    }
    const set = LocalMusicExclusion.readSet();
    set.add(name);
    LocalMusicExclusion.writeSet(set);
  }

  /** 清除某文件名的排除（重新导入时使用） */
  static clearExclusion(filename: string): void {
    if (filename.length === 0) {
      return;
    }
    const set = LocalMusicExclusion.readSet();
    if (set.delete(filename)) {
      LocalMusicExclusion.writeSet(set);
    }
  }
}
