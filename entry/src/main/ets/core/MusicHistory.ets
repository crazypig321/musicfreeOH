import { KVStore } from '../infra/KVStore';
import { JsonUtil } from '../common/JsonUtil';
import { MusicItem } from '../common/model/MediaTypes';
import { MediaUtils } from '../utils/MediaUtils';
import { appConfig } from './AppConfig';
import { appMeta } from './AppMeta';
import { EventEmitter, EventListenerFn } from '../common/EventBus';

/** 播放历史更新事件 */
export class MusicHistoryUpdatedEvent {
}

/**
 * 播放历史（移植自 musicHistory.ts）
 * 存储：KVStore('music.MusicHistory') 键 'history'
 */
export class MusicHistory {
  private historyItems: Array<MusicItem> = [];
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
    return Promise.resolve();
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
    this.persist();
    return Promise.resolve();
  }

  /** 清空播放记录 */
  clearMusic(): Promise<void> {
    this.historyItems = [];
    this.persist();
    return Promise.resolve();
  }

  /** 覆盖播放历史 */
  setHistory(newHistory: Array<MusicItem>): Promise<void> {
    this.historyItems = newHistory.slice();
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
