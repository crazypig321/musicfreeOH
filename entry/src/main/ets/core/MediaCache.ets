import { KVStore } from '../infra/KVStore';
import { JsonUtil, JsonRecord } from '../common/JsonUtil';
import { MusicItem } from '../common/model/MediaTypes';
import { MEDIA_CACHE_MAX, MEDIA_CACHE_EVICT } from '../common/Consts';
import { FileUtils } from '../utils/FileUtils';
import { Log } from '../utils/Log';

/**
 * 媒体缓存（移植自 mediaCache.ts）
 * 缓存音源/歌词解析结果，key = platform@id，上限800条，超限淘汰前400条
 * 歌词文件路径挂在缓存的 $localLyric（rawLrc/translation）上，与 RN 存储结构一致
 */
class MediaCacheEntry {
  musicItem: MusicItem = new MusicItem();
  /** 缓存的本地歌词文件路径（$localLyric.rawLrc） */
  localLyricPath: string = '';
  /** 缓存的本地翻译歌词文件路径（$localLyric.translation） */
  localLyricTransPath: string = '';
  /** 缓存的远程歌词文本（遗留字段 lyric.rawLrc，仅读取兼容） */
  cachedLyricRaw: string = '';
  /** 缓存的远程翻译歌词文本（遗留字段 lyric.translation） */
  cachedLyricTrans: string = '';
  /** 遗留 lyric 字段是否存在（RN getLyric 依赖 musicItemCache?.lyric 的 truthy 判断） */
  hasLyricField: boolean = false;

  toRecord(): JsonRecord {
    const rec: JsonRecord = { 'item': this.musicItem.toPersistRecord() };
    if (this.localLyricPath.length > 0 || this.localLyricTransPath.length > 0) {
      const localLyric: JsonRecord = {};
      if (this.localLyricPath.length > 0) {
        localLyric['rawLrc'] = this.localLyricPath;
      }
      if (this.localLyricTransPath.length > 0) {
        localLyric['translation'] = this.localLyricTransPath;
      }
      rec['$localLyric'] = localLyric;
    }
    if (this.cachedLyricRaw.length > 0 || this.cachedLyricTrans.length > 0) {
      const lyric: JsonRecord = {};
      if (this.cachedLyricRaw.length > 0) {
        lyric['rawLrc'] = this.cachedLyricRaw;
      }
      if (this.cachedLyricTrans.length > 0) {
        lyric['translation'] = this.cachedLyricTrans;
      }
      rec['lyric'] = lyric;
    }
    return rec;
  }

  static fromRecord(rec: JsonRecord): MediaCacheEntry | null {
    const itemRec = JsonUtil.recRecord(rec, 'item');
    if (itemRec === null) {
      return null;
    }
    const e = new MediaCacheEntry();
    e.musicItem = MusicItem.fromRecord(itemRec);
    const localLyric = JsonUtil.recRecord(rec, '$localLyric');
    if (localLyric !== null) {
      e.localLyricPath = JsonUtil.recStr(localLyric, 'rawLrc');
      e.localLyricTransPath = JsonUtil.recStr(localLyric, 'translation');
    }
    const lyric = JsonUtil.recRecord(rec, 'lyric');
    if (lyric !== null) {
      e.cachedLyricRaw = JsonUtil.recStr(lyric, 'rawLrc');
      e.cachedLyricTrans = JsonUtil.recStr(lyric, 'translation');
    }
    e.hasLyricField = rec['lyric'] !== undefined && rec['lyric'] !== null;
    return e;
  }

  /** 删除本地歌词缓存文件 */
  clearLocalCaches(): void {
    if (this.localLyricPath.length > 0) {
      FileUtils.unlink(this.localLyricPath);
    }
    if (this.localLyricTransPath.length > 0) {
      FileUtils.unlink(this.localLyricTransPath);
    }
  }
}

/** 歌词缓存信息（getLyricCacheInfo 的返回） */
export class LyricCacheInfo {
  /** 本地歌词文件路径 */
  rawLrcPath: string = '';
  /** 本地翻译歌词文件路径 */
  transPath: string = '';
  /** 缓存的远程歌词文本 */
  cachedRawLrc: string = '';
  /** 缓存的远程翻译文本 */
  cachedTrans: string = '';
  /** 遗留 lyric 字段是否存在 */
  hasLyricField: boolean = false;
}

export class MediaCache {
  private static store(): KVStore {
    return KVStore.getOrCreate('cache.MediaCache');
  }

  static getMediaCache(item: MusicItem): MusicItem | null {
    const raw = MediaCache.store().get(MediaCache.keyOf(item));
    if (raw.length === 0) {
      return null;
    }
    const rec = JsonUtil.parseRecord(raw);
    if (rec === null) {
      return null;
    }
    const entry = MediaCacheEntry.fromRecord(rec);
    return entry === null ? null : entry.musicItem;
  }

  static setMediaCache(item: MusicItem): void {
    try {
      const store = MediaCache.store();
      const key = MediaCache.keyOf(item);
      const entry = new MediaCacheEntry();
      entry.musicItem = item;
      // 读取旧缓存，保留歌词缓存信息（对应 RN 的 {...musicItem, ...mediaCache} 合并语义）
      const oldRaw = store.get(key);
      if (oldRaw.length > 0) {
        const oldRec = JsonUtil.parseRecord(oldRaw);
        if (oldRec !== null) {
          const oldEntry = MediaCacheEntry.fromRecord(oldRec);
          if (oldEntry !== null) {
            entry.localLyricPath = oldEntry.localLyricPath;
            entry.localLyricTransPath = oldEntry.localLyricTransPath;
            entry.cachedLyricRaw = oldEntry.cachedLyricRaw;
            entry.cachedLyricTrans = oldEntry.cachedLyricTrans;
          }
        }
      }
      store.set(key, JsonUtil.safeStringify(entry.toRecord()));
      MediaCache.evictIfNeeded();
    } catch (e) {
      Log.error('写媒体缓存失败');
    }
  }

  static removeMediaCache(item: MusicItem): void {
    const store = MediaCache.store();
    const key = MediaCache.keyOf(item);
    const raw = store.get(key);
    if (raw.length > 0) {
      const rec = JsonUtil.parseRecord(raw);
      if (rec !== null) {
        const entry = MediaCacheEntry.fromRecord(rec);
        if (entry !== null) {
          entry.clearLocalCaches();
        }
      }
    }
    store.delete(key);
  }

  /** 获取歌词缓存信息（本地文件路径 + 遗留缓存文本） */
  static getLyricCacheInfo(item: MusicItem): LyricCacheInfo | null {
    const raw = MediaCache.store().get(MediaCache.keyOf(item));
    if (raw.length === 0) {
      return null;
    }
    const rec = JsonUtil.parseRecord(raw);
    if (rec === null) {
      return null;
    }
    const entry = MediaCacheEntry.fromRecord(rec);
    if (entry === null) {
      return null;
    }
    const info = new LyricCacheInfo();
    info.rawLrcPath = entry.localLyricPath;
    info.transPath = entry.localLyricTransPath;
    info.cachedRawLrc = entry.cachedLyricRaw;
    info.cachedTrans = entry.cachedLyricTrans;
    info.hasLyricField = entry.hasLyricField;
    return info;
  }

  /** 设置歌词缓存文件路径（空串表示清除该项） */
  static setLyricCachePaths(item: MusicItem, rawLrcPath: string, transPath: string): void {
    const store = MediaCache.store();
    const key = MediaCache.keyOf(item);
    const raw = store.get(key);
    let entry: MediaCacheEntry | null = null;
    if (raw.length > 0) {
      const rec = JsonUtil.parseRecord(raw);
      if (rec !== null) {
        entry = MediaCacheEntry.fromRecord(rec);
      }
    }
    if (entry === null) {
      entry = new MediaCacheEntry();
      entry.musicItem = item;
    }
    entry.localLyricPath = rawLrcPath;
    entry.localLyricTransPath = transPath;
    store.set(key, JsonUtil.safeStringify(entry.toRecord()));
  }

  private static keyOf(item: MusicItem): string {
    return item.platform + '@' + item.id;
  }

  private static evictIfNeeded(): void {
    const store = MediaCache.store();
    const keys = store.getAllKeys();
    if (keys.length <= MEDIA_CACHE_MAX) {
      return;
    }
    let evicted = 0;
    for (const key of keys) {
      if (evicted >= MEDIA_CACHE_EVICT) {
        break;
      }
      const raw = store.get(key);
      if (raw.length > 0) {
        const rec = JsonUtil.parseRecord(raw);
        if (rec !== null) {
          const entry = MediaCacheEntry.fromRecord(rec);
          if (entry !== null) {
            entry.clearLocalCaches();
          }
        }
      }
      store.delete(key);
      evicted += 1;
    }
  }
}
