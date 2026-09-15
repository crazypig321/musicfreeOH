import { JsonUtil, JsonRecord, JsonArray } from '../JsonUtil';
import { INTERNAL_SERIALIZE_KEY } from '../Consts';

/** 音质键 */
export type QualityKey = 'low' | 'standard' | 'high' | 'super';

export const QUALITY_KEYS: Array<QualityKey> = ['low', 'standard', 'high', 'super'];

/** 媒体引用形状（仅需 platform/id 的最小结构） */
export interface MediaRefLike {
  platform: string;
  id: string;
}

export function qualityFromStr(s: string, def: QualityKey = 'high'): QualityKey {
  for (const q of QUALITY_KEYS) {
    if (q === s) {
      return q;
    }
  }
  return def;
}

/** 已解析的音源 */
export class MediaSource {
  url: string = '';
  headers: Record<string, string> = {};
  userAgent: string = '';
  quality: QualityKey = 'high';
  size: number = 0;

  static fromRecord(rec: JsonRecord): MediaSource {
    const src = new MediaSource();
    src.url = JsonUtil.recStr(rec, 'url');
    src.userAgent = JsonUtil.recStr(rec, 'userAgent');
    src.quality = qualityFromStr(JsonUtil.recStr(rec, 'quality'));
    src.size = JsonUtil.recNum(rec, 'size');
    const headers = JsonUtil.recRecord(rec, 'headers');
    if (headers !== null) {
      const h: Record<string, string> = {};
      for (const k of Object.keys(headers)) {
        const v = headers[k];
        if (typeof v === 'string') {
          h[k] = v;
        }
      }
      src.headers = h;
    }
    return src;
  }

  toRecord(): JsonRecord {
    const rec: JsonRecord = { 'url': this.url };
    if (this.userAgent.length > 0) {
      rec['userAgent'] = this.userAgent;
    }
    rec['quality'] = this.quality;
    if (this.size > 0) {
      rec['size'] = this.size;
    }
    if (Object.keys(this.headers).length > 0) {
      const h: JsonRecord = {};
      for (const k of Object.keys(this.headers)) {
        h[k] = this.headers[k];
      }
      rec['headers'] = h;
    }
    return rec;
  }
}

/** 歌词源 */
export class LyricSource {
  /** 歌词url（已弃用字段，仅做兼容） */
  lrc: string = '';
  /** 带时间戳的歌词文本 */
  rawLrc: string = '';
  /** 翻译 */
  translation: string = '';

  static fromRecord(rec: JsonRecord): LyricSource {
    const l = new LyricSource();
    l.lrc = JsonUtil.recStr(rec, 'lrc');
    l.rawLrc = JsonUtil.recStr(rec, 'rawLrc');
    l.translation = JsonUtil.recStr(rec, 'translation');
    return l;
  }

  toRecord(): JsonRecord {
    const rec: JsonRecord = {};
    if (this.lrc.length > 0) {
      rec['lrc'] = this.lrc;
    }
    if (this.rawLrc.length > 0) {
      rec['rawLrc'] = this.rawLrc;
    }
    if (this.translation.length > 0) {
      rec['translation'] = this.translation;
    }
    return rec;
  }

  isEmpty(): boolean {
    return this.lrc.length === 0 && this.rawLrc.length === 0 && this.translation.length === 0;
  }
}

/**
 * 音乐项（对应 IMusic.IMusicItem）
 * - 已知字段为强类型
 * - 插件自定义字段存于 extras（序列化时平铺到顶层）
 * - 内部字段（timeStamp/sortIndex）仅应用内部使用，不会传给插件
 */
export class MusicItem implements MediaRefLike {
  id: string = '';
  platform: string = '';
  title: string = '';
  artist: string = '';
  album: string = '';
  artwork: string = '';
  alias: string = '';
  /** 时长(s) */
  duration: number = 0;
  /** 默认音源 */
  url: string = '';
  /** 歌词url（已弃用字段，仅做兼容） */
  lrc: string = '';
  /** 原始歌词文本（已弃用，仅做兼容） */
  rawLrc: string = '';
  /** 插件提供的音质信息，原始 JSON Record */
  qualities: JsonRecord = {};
  /** 已解析音源缓存 quality -> MediaSource */
  source: Record<string, MediaSource> = {};
  /** 插件自定义字段 */
  extras: JsonRecord = {};
  /** 内部：加入播放列表的时间戳 */
  timeStamp: number = 0;
  /** 内部：加入播放列表的顺序 */
  sortIndex: number = 0;

  static fromRecord(rec: JsonRecord): MusicItem {
    const item = new MusicItem();
    item.id = JsonUtil.recStr(rec, 'id');
    item.platform = JsonUtil.recStr(rec, 'platform');
    item.title = JsonUtil.recStr(rec, 'title');
    item.artist = JsonUtil.recStr(rec, 'artist');
    item.album = JsonUtil.recStr(rec, 'album');
    item.artwork = JsonUtil.recStr(rec, 'artwork');
    item.alias = JsonUtil.recStr(rec, 'alias');
    item.duration = JsonUtil.recNum(rec, 'duration');
    item.url = JsonUtil.recStr(rec, 'url');
    item.lrc = JsonUtil.recStr(rec, 'lrc');
    item.rawLrc = JsonUtil.recStr(rec, 'rawLrc');

    const qualities = JsonUtil.recRecord(rec, 'qualities');
    if (qualities !== null) {
      item.qualities = qualities;
    }
    const source = JsonUtil.recRecord(rec, 'source');
    if (source !== null) {
      const s: Record<string, MediaSource> = {};
      for (const q of Object.keys(source)) {
        const msRec = JsonUtil.objToRecord(source[q]);
        if (msRec !== null) {
          s[q] = MediaSource.fromRecord(msRec);
        }
      }
      item.source = s;
    }
    const stamp = rec[INTERNAL_SERIALIZE_KEY + 'timestamp'];
    if (typeof stamp === 'number') {
      item.timeStamp = stamp;
    }
    const sortIdx = rec[INTERNAL_SERIALIZE_KEY + 'sortIndex'];
    if (typeof sortIdx === 'number') {
      item.sortIndex = sortIdx;
    }

    // 其余字段进 extras
    const known: Set<string> = new Set<string>([
      'id', 'platform', 'title', 'artist', 'album', 'artwork', 'alias',
      'duration', 'url', 'lrc', 'rawLrc', 'qualities', 'source',
      INTERNAL_SERIALIZE_KEY + 'timestamp', INTERNAL_SERIALIZE_KEY + 'sortIndex',
    ]);
    const extras: JsonRecord = {};
    for (const k of Object.keys(rec)) {
      if (!known.has(k)) {
        extras[k] = rec[k];
      }
    }
    item.extras = extras;
    return item;
  }

  /**
   * 序列化为可持久化的 Record（含内部字段 $timestamp/$sortIndex）
   */
  toPersistRecord(): JsonRecord {
    const rec: JsonRecord = this.toPluginRecord();
    rec[INTERNAL_SERIALIZE_KEY + 'timestamp'] = this.timeStamp;
    rec[INTERNAL_SERIALIZE_KEY + 'sortIndex'] = this.sortIndex;
    return rec;
  }

  /**
   * 序列化为传给插件的 Record（不含内部字段）
   */
  toPluginRecord(): JsonRecord {
    const rec: JsonRecord = {
      'id': this.id,
      'platform': this.platform,
      'title': this.title,
      'artist': this.artist,
      'album': this.album,
      'artwork': this.artwork,
      'duration': this.duration,
    };
    if (this.alias.length > 0) {
      rec['alias'] = this.alias;
    }
    if (this.url.length > 0) {
      rec['url'] = this.url;
    }
    if (this.lrc.length > 0) {
      rec['lrc'] = this.lrc;
    }
    if (this.rawLrc.length > 0) {
      rec['rawLrc'] = this.rawLrc;
    }
    if (Object.keys(this.qualities).length > 0) {
      rec['qualities'] = this.qualities;
    }
    if (Object.keys(this.source).length > 0) {
      const s: JsonRecord = {};
      for (const q of Object.keys(this.source)) {
        s[q] = this.source[q].toRecord();
      }
      rec['source'] = s;
    }
    for (const k of Object.keys(this.extras)) {
      rec[k] = this.extras[k];
    }
    return rec;
  }

  /** 深拷贝 */
  clone(): MusicItem {
    return MusicItem.fromRecord(this.toPersistRecord());
  }
}

export class MusicItemSerializer {
  static serialize(items: Array<MusicItem>): string {
    const arr: JsonArray = [];
    for (const it of items) {
      arr.push(it.toPersistRecord());
    }
    return JSON.stringify(arr);
  }

  static deserialize(raw: string | null | undefined): Array<MusicItem> {
    const arr = JsonUtil.parseRecordArray(raw);
    if (arr === null) {
      return [];
    }
    const result: Array<MusicItem> = [];
    for (const rec of arr) {
      result.push(MusicItem.fromRecord(rec));
    }
    return result;
  }

  /** 从任意 JSON Object（如插件返回）解析 */
  static fromObject(v: Object | null | undefined): MusicItem | null {
    const rec = JsonUtil.objToRecord(v);
    if (rec === null) {
      return null;
    }
    return MusicItem.fromRecord(rec);
  }

  static fromArray(v: Object | null | undefined): Array<MusicItem> {
    const arr = JsonUtil.objToRecordArray(v);
    if (arr === null) {
      return [];
    }
    const result: Array<MusicItem> = [];
    for (const rec of arr) {
      result.push(MusicItem.fromRecord(rec));
    }
    return result;
  }
}
