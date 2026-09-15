import { KVStore } from '../infra/KVStore';
import { JsonUtil, JsonRecord } from '../common/JsonUtil';
import { MusicItem } from '../model/MediaTypes';
import { EventEmitter } from '../common/EventBus';

/**
 * 媒体附加属性（移植自 mediaExtra.ts）
 * 按平台分库存储：MediaExtra.<platform>，key=id
 */
export class MediaExtraProperties {
  /** 是否已下载 */
  downloaded?: boolean;
  /** 本地路径 */
  localPath?: string;
  /** 歌词偏移 */
  lyricOffset?: number;
  /** 关联歌词（完整的音乐项 record） */
  associatedLrc?: JsonRecord;

  static fromRecord(rec: JsonRecord): MediaExtraProperties {
    const p = new MediaExtraProperties();
    const downloaded = rec['downloaded'];
    if (typeof downloaded === 'boolean') {
      p.downloaded = downloaded;
    }
    const localPath = rec['localPath'];
    if (typeof localPath === 'string') {
      p.localPath = localPath;
    }
    const lyricOffset = rec['lyricOffset'];
    if (typeof lyricOffset === 'number') {
      p.lyricOffset = lyricOffset;
    }
    const associated = JsonUtil.recRecord(rec, 'associatedLrc');
    if (associated !== null) {
      p.associatedLrc = associated;
    }
    return p;
  }

  toRecord(): JsonRecord {
    const rec: JsonRecord = {};
    if (this.downloaded !== undefined) {
      rec['downloaded'] = this.downloaded;
    }
    if (this.localPath !== undefined) {
      rec['localPath'] = this.localPath;
    }
    if (this.lyricOffset !== undefined) {
      rec['lyricOffset'] = this.lyricOffset;
    }
    if (this.associatedLrc !== undefined) {
      rec['associatedLrc'] = this.associatedLrc;
    }
    return rec;
  }
}

/** 附加属性变更事件 payload */
export class MediaExtraChangedEvent {
  platform: string = '';
  id: string = '';
  extra: MediaExtraProperties | null = null;
}

const changeEmitter = new EventEmitter();

function getPluginStore(platform: string): KVStore {
  return KVStore.getOrCreate('MediaExtra.' + platform);
}

export class MediaExtra {
  /** 获取媒体全部附加属性 */
  static getMediaExtra(item: MusicItem): MediaExtraProperties | null {
    if (item.platform.length === 0 || item.id.length === 0) {
      return null;
    }
    const raw = getPluginStore(item.platform).get(item.id);
    if (raw.length === 0) {
      return null;
    }
    const rec = JsonUtil.parseRecord(raw);
    return rec === null ? null : MediaExtraProperties.fromRecord(rec);
  }

  static getMediaExtraProperty(item: MusicItem, key: string): Object | null {
    const extra = MediaExtra.getMediaExtra(item);
    if (extra === null) {
      return null;
    }
    const rec = extra.toRecord();
    const v = rec[key];
    return v === undefined ? null : v;
  }

  /** 增量更新附加属性 */
  static patchMediaExtra(item: MusicItem, patch: MediaExtraProperties): MediaExtraProperties | null {
    if (item.platform.length === 0 || item.id.length === 0) {
      return null;
    }
    const original = MediaExtra.getMediaExtra(item);
    const merged: JsonRecord = original === null ? {} : original.toRecord();
    const patchRec = patch.toRecord();
    for (const k of Object.keys(patchRec)) {
      merged[k] = patchRec[k];
    }
    getPluginStore(item.platform).set(item.id, JsonUtil.safeStringify(merged));
    const result = MediaExtraProperties.fromRecord(merged);
    MediaExtra.notifyChanged(item, result);
    return result;
  }

  /** 直接替换附加属性 */
  static setMediaExtra(item: MusicItem, extra: MediaExtraProperties): void {
    if (item.platform.length === 0 || item.id.length === 0) {
      return;
    }
    getPluginStore(item.platform).set(item.id, JsonUtil.safeStringify(extra.toRecord()));
    MediaExtra.notifyChanged(item, extra);
  }

  static removeMediaExtra(item: MusicItem): void {
    if (item.platform.length === 0 || item.id.length === 0) {
      return;
    }
    getPluginStore(item.platform).delete(item.id);
    MediaExtra.notifyChanged(item, null);
  }

  /** 删除单个附加属性（对应 RN patchMediaExtra 传 undefined 的删除语义） */
  static removeMediaExtraProperty(item: MusicItem, key: string): void {
    if (item.platform.length === 0 || item.id.length === 0) {
      return;
    }
    const store = getPluginStore(item.platform);
    const raw = store.get(item.id);
    if (raw.length === 0) {
      return;
    }
    const rec = JsonUtil.parseRecord(raw);
    if (rec === null) {
      return;
    }
    const merged = JsonUtil.omitKeys(rec, [key]);
    store.set(item.id, JsonUtil.safeStringify(merged));
    MediaExtra.notifyChanged(item, MediaExtraProperties.fromRecord(merged));
  }

  /** 删除某平台全部附加属性（卸载插件时） */
  static removeAllMediaExtra(platform: string): void {
    getPluginStore(platform).clearAll();
  }

  /** 监听附加属性变化 */
  static onChanged(cb: (event: MediaExtraChangedEvent) => void): void {
    const wrapper = (payload?: Object) => {
      if (payload instanceof MediaExtraChangedEvent) {
        cb(payload);
      }
    };
    changeEmitter.on('changed', wrapper);
  }

  private static notifyChanged(item: MusicItem, extra: MediaExtraProperties | null): void {
    const event = new MediaExtraChangedEvent();
    event.platform = item.platform;
    event.id = item.id;
    event.extra = extra;
    changeEmitter.emit('changed', event);
  }
}
