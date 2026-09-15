import { JsonRecord } from '../common/JsonUtil';
import { MusicItem } from '../common/model/MediaTypes';

interface LyricParserOptions {
  musicItem?: MusicItem;
  translation?: string;
  offset?: number;
}

/** 解析后的歌词行 */
export class ParsedLrcItem {
  /** 时间 s */
  time: number = 0;
  /** 歌词 */
  lrc: string = '';
  /** 翻译 */
  translation: string = '';
  /** 下标 */
  index: number = 0;
}

/**
 * LRC 歌词解析器（移植自 lrcParser.ts）
 */
export class LyricParser {
  private static readonly timeReg = /\[[0-9:.]+\]/g;
  private static readonly metaReg = /\[(.+):(.+)\]/g;

  private meta: JsonRecord = {};
  private lrcItems: Array<ParsedLrcItem> = [];
  private offset: number = 0;
  private lastSearchIndex: number = 0;

  public hasTranslation: boolean = false;

  getLyricItems(): Array<ParsedLrcItem> {
    return this.lrcItems;
  }

  constructor(raw: string, options?: LyricParserOptions) {
    let text = raw;
    let translation: string | undefined = undefined;
    if (options !== undefined) {
      translation = options.translation;
      if (options.offset !== undefined) {
        this.offset = options.offset;
      }
    }
    if ((text === undefined || text.length === 0) && translation !== undefined) {
      text = translation;
      translation = undefined;
    }

    this.parseLyricImpl(text);
    if (this.offset !== 0) {
      this.applyOffset();
    }

    if (translation !== undefined && translation.length > 0) {
      this.hasTranslation = true;
      this.mergeTranslation(translation);
    }
  }

  private applyOffset(): void {
    // 与原实现一致：将额外偏移累加到 meta.offset，getPosition 时统一扣除
    this.setMetaOffset(this.getMetaOffset() + this.offset);
  }

  private getMetaOffset(): number {
    const v = this.meta['offset'];
    if (typeof v === 'number') {
      return v;
    }
    return 0;
  }

  private setMetaOffset(v: number): void {
    this.meta['offset'] = v;
  }

  private mergeTranslation(translation: string): void {
    const transItems = this.parseItems(translation);
    let p2 = 0;
    let p1 = 0;
    while (p1 < this.lrcItems.length) {
      const lrcItem = this.lrcItems[p1];
      while (p2 < transItems.length - 1 && transItems[p2].time < lrcItem.time) {
        ++p2;
      }
      if (p2 < transItems.length && transItems[p2].time === lrcItem.time) {
        lrcItem.translation = transItems[p2].lrc;
      } else {
        lrcItem.translation = '';
      }
      ++p1;
    }
  }

  getPosition(position: number): ParsedLrcItem | null {
    let pos = position - this.getMetaOffset();
    if (this.lrcItems.length === 0 || pos < this.lrcItems[0].time) {
      this.lastSearchIndex = 0;
      return null;
    }
    let index = 0;
    for (index = this.lastSearchIndex; index < this.lrcItems.length - 1; ++index) {
      if (pos >= this.lrcItems[index].time && pos < this.lrcItems[index + 1].time) {
        this.lastSearchIndex = index;
        return this.lrcItems[index];
      }
    }
    for (index = 0; index < this.lastSearchIndex; ++index) {
      if (pos >= this.lrcItems[index].time && pos < this.lrcItems[index + 1].time) {
        this.lastSearchIndex = index;
        return this.lrcItems[index];
      }
    }
    index = this.lrcItems.length - 1;
    this.lastSearchIndex = index;
    return this.lrcItems[index];
  }

  toString(withTimestamp: boolean = true, useTranslation: boolean = false): string {
    const lines: Array<string> = [];
    for (const item of this.lrcItems) {
      const text = useTranslation ? item.translation : item.lrc;
      if (withTimestamp) {
        lines.push(this.timeToLrcTime(item.time) + ' ' + text);
      } else {
        lines.push(text);
      }
    }
    return lines.join('\r\n');
  }

  /** [xx:xx.xx] => x s */
  private parseTime(timeStr: string): number {
    let result = 0;
    const nums = timeStr.substring(1, timeStr.length - 1).split(':');
    for (const n of nums) {
      result = result * 60 + Number(n);
    }
    return result;
  }

  /** x s => [xx:xx.xx] */
  private timeToLrcTime(sec: number): string {
    const min = Math.floor(sec / 60);
    const secRest = sec - min * 60;
    const secInt = Math.floor(secRest);
    const secFloat = secRest - secInt;
    let secStr = secInt.toString();
    while (secStr.length < 2) {
      secStr = '0' + secStr;
    }
    let minStr = min.toString();
    while (minStr.length < 2) {
      minStr = '0' + minStr;
    }
    let frac = secFloat.toFixed(2).substring(2);
    return '[' + minStr + ':' + secStr + '.' + frac + ']';
  }

  /** 返回带时间戳的行（供合并翻译用） */
  private parseItems(raw: string): Array<ParsedLrcItem> {
    return this.parseRaw(raw).items;
  }

  private parseLyricImpl(raw: string): void {
    const parsed = this.parseRaw(raw);
    this.lrcItems = parsed.items;
    this.meta = parsed.meta;
  }

  private parseRaw(rawStr: string): ParsedLyricData {
    const raw = rawStr.trim();
    const data = new ParsedLyricData();
    const timeReg = new RegExp(LyricParser.timeReg.source, 'g');
    const rawTimes = raw.match(timeReg) ?? [];
    // split 并移除时间戳
    const rawLrcParts: Array<string> = raw.split(/\[[0-9:.]+\]/) ?? [];

    if (rawLrcParts.length > 0) {
      this.parseMetaInto(rawLrcParts[0].trim(), data);
    }
    const rawLrcs = rawLrcParts.slice(1);

    const len = rawTimes.length;
    let i = 0;
    while (i < len) {
      let counter = 0;
      while (rawLrcs.length > 0 && rawLrcs[0] === '') {
        ++counter;
        rawLrcs.shift();
      }
      const lrc = rawLrcs.length > 0 ? rawLrcs[0].trim() : '';
      // counter 个连续时间戳共用同一句歌词
      for (let j = i; j < i + counter && j < len; ++j) {
        data.items.push(this.makeItem(this.parseTime(rawTimes[j]), lrc, j));
      }
      i += counter;
      if (i < len) {
        data.items.push(this.makeItem(this.parseTime(rawTimes[i]), lrc, i));
      }
      if (rawLrcs.length > 0) {
        rawLrcs.shift();
      }
      ++i;
    }

    data.items.sort((a: ParsedLrcItem, b: ParsedLrcItem) => a.time - b.time);
    data.items.forEach((item: ParsedLrcItem, index: number) => {
      item.index = index;
    });
    if (data.items.length === 0 && raw.length > 0) {
      // 无时间戳歌词，每行 time=0
      const lines = raw.split('\n');
      for (let idx = 0; idx < lines.length; ++idx) {
        data.items.push(this.makeItem(0, lines[idx], idx));
      }
    }
    return data;
  }

  private parseMetaInto(metaStr: string, data: ParsedLyricData): void {
    if (metaStr.length === 0) {
      return;
    }
    const metaReg = new RegExp(LyricParser.metaReg.source, 'g');
    const matches = metaStr.match(metaReg);
    if (matches === null) {
      return;
    }
    for (const m of matches) {
      const colonIdx = m.indexOf(':');
      const k = m.substring(1, colonIdx);
      const v = m.substring(k.length + 2, m.length - 1);
      if (k === 'offset') {
        data.meta[k] = Number(v) / 1000;
      } else {
        data.meta[k] = v;
      }
    }
  }

  private makeItem(time: number, lrc: string, index: number): ParsedLrcItem {
    const item = new ParsedLrcItem();
    item.time = time;
    item.lrc = lrc;
    item.index = index;
    return item;
  }
}

class ParsedLyricData {
  items: Array<ParsedLrcItem> = [];
  meta: JsonRecord = {};
}
