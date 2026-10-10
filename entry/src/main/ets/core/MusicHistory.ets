import { KVStore } from '../infra/KVStore';
import { JsonUtil, JsonRecord } from '../utils/JsonUtil';
import { MusicItem } from '../common/model/MediaTypes';
import { MediaUtils } from '../utils/MediaUtils';
import { appConfig } from './AppConfig';
import { appMeta } from './AppMeta';
import { EventEmitter, EventListenerFn } from '../common/EventBus';

/** 播放历史更新事件 */
export class MusicHistoryUpdatedEvent {
}

/** 播放统计条目（次数 + 最近播放时间；心动模式偏好加权用） */
export class MusicHistoryStat {
  count: number = 0;
  lastAt: number = 0;

  static fromRecord(rec: JsonRecord): MusicHistoryStat {
    const s = new MusicHistoryStat();
    s.count = JsonUtil.recNum(rec, 'count', 0);
    s.lastAt = JsonUtil.recNum(rec, 'lastAt', 0);
    return s;
  }

  toRecord(): JsonRecord {
    return {
      'count': this.count,
      'lastAt': this.lastAt,
    };
  }
}

/**
 * 播放历史（移植自 musicHistory.ts）
 * 存储：KVStore('music.MusicHistory') 键 'history'
 */
export class MusicHistory {
  private historyItems: Array<MusicItem> = [];
  /** 播放统计（键为 platform@id；独立于 'history' 键存储，向后兼容） */
  private stats: Map<string, MusicHistoryStat> = new Map<string, MusicHistoryStat>();
  private store: KVStore | null = null;
  private ee: EventEmitter = new EventEmitter();

  private getStore(): KVStore {
    if (this.store === null) {
      this.store = KVStore.getOrCreate('music.MusicHistory');
    }
    return this.store;
  }

  get history(): Array<MusicItem> {
    return this.historyItems;
  }

  setup(): Promise<void> {
    // 全新平台无 AsyncStorage 旧数据，直接标记版本
    if (appMeta.historySheetVersion < 1) {
      appMeta.setHistorySheetVersion(1);
    }
    const raw = this.getStore().get('history');
    const arr = JsonUtil.parseRecordArray(raw);
    const items: Array<MusicItem> = [];
    if (arr !== null) {
      for (const rec of arr) {
        items.push(MusicItem.fromRecord(rec));
      }
    }
    this.historyItems = items;
    this.loadStats();
    return Promise.resolve();
  }

  /** 加载播放统计（'stats' 键；缺失/损坏时容错为空表） */
  private loadStats(): void {
    this.stats = new Map<string, MusicHistoryStat>();
    const raw = this.getStore().get('stats');
    const rec = JsonUtil.parseRecord(raw);
    if (rec === null) {
      return;
    }
    for (const key of Object.keys(rec)) {
      const statRec = JsonUtil.recRecord(rec, key);
      if (statRec === null) {
        continue;
      }
      this.stats.set(key, MusicHistoryStat.fromRecord(statRec));
    }
  }

  /** 持久化播放统计到 'stats' 键（同一 store 内，随备份/恢复自动覆盖） */
  private persistStats(): void {
    const rec: JsonRecord = {};
    for (const key of this.stats.keys()) {
      const stat = this.stats.get(key);
      if (stat !== undefined) {
        rec[key] = stat.toRecord();
      }
    }
    this.getStore().set('stats', JsonUtil.safeStringify(rec));
  }

  /** 获取播放统计（无记录返回 null；供心动模式等偏好加权使用） */
  getStat(musicItem: MusicItem): MusicHistoryStat | null {
    const stat = this.stats.get(MediaUtils.getMediaUniqueKey(musicItem));
    return stat !== undefined ? stat : null;
  }

  private persist(): void {
    const arr: Array<Object> = [];
    for (const it of this.historyItems) {
      arr.push(it.toPersistRecord());
    }
    this.getStore().set('history', JSON.stringify(arr));
    this.ee.emit('UpdateHistory', new MusicHistoryUpdatedEvent());
  }

  /** 添加播放记录（去重置顶，截断到最大长度） */
  addMusic(musicItem: MusicItem): Promise<void> {
    const rest: Array<MusicItem> = [];
    for (const it of this.historyItems) {
      if (!MediaUtils.isSameMediaItem(it, musicItem)) {
        rest.push(it);
      }
    }
    const maxLen = appConfig.getMaxHistoryLen();
    const newHistory: Array<MusicItem> = [musicItem].concat(rest).slice(0, maxLen);
    this.historyItems = newHistory;
    this.persist();
    // 播放统计：次数 +1、刷新最近播放时间（不影响 'history' 键的既有格式）
    const statKey = MediaUtils.getMediaUniqueKey(musicItem);
    const stat = this.stats.get(statKey) ?? new MusicHistoryStat();
    stat.count += 1;
    stat.lastAt = Date.now();
    this.stats.set(statKey, stat);
    this.persistStats();
    return Promise.resolve();
  }

  /** 移除播放记录 */
  removeMusic(musicItem: MusicItem): Promise<void> {
    const newHistory: Array<MusicItem> = [];
    for (const it of this.historyItems) {
      if (!MediaUtils.isSameMediaItem(it, musicItem)) {
        newHistory.push(it);
      }
    }
    this.historyItems = newHistory;
    this.stats.delete(MediaUtils.getMediaUniqueKey(musicItem));
    this.persistStats();
    this.persist();
    return Promise.resolve();
  }

  /** 清空播放记录 */
  clearMusic(): Promise<void> {
    this.historyItems = [];
    this.stats.clear();
    this.persistStats();
    this.persist();
    return Promise.resolve();
  }

  /** 覆盖播放历史 */
  setHistory(newHistory: Array<MusicItem>): Promise<void> {
    this.historyItems = newHistory.slice();
    // 同步清理不在新历史中的统计条目（恢复备份后保持一致）
    const validKeys = new Set<string>();
    for (const it of newHistory) {
      validKeys.add(MediaUtils.getMediaUniqueKey(it));
    }
    const staleKeys: Array<string> = [];
    for (const key of this.stats.keys()) {
      if (!validKeys.has(key)) {
        staleKeys.push(key);
      }
    }
    for (const key of staleKeys) {
      this.stats.delete(key);
    }
    this.persistStats();
    this.persist();
    return Promise.resolve();
  }

  onHistoryUpdated(cb: () => void): void {
    const wrapper: EventListenerFn = (_payload?: Object) => {
      cb();
    };
    this.ee.on('UpdateHistory', wrapper);
  }
}

export const musicHistory = new MusicHistory();
