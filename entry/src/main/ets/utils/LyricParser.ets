import { MusicItem, LyricSource } from '../common/model/MediaTypes';
import { JsonRecord } from '../common/JsonUtil';

/** 逐字歌词项 */
export class LyricWord {
  /** 字文本 */
  text: string = '';
  /** 开始时间 s */
  startTime: number = 0;
  /** 结束时间 s */
  endTime: number = 0;
}

/** 解析后的歌词项 */
export class ParsedLrcItem {
  /** 时间 s */
  time: number = 0;
  /** 行结束时间 s（下一行 time，末行取 time+5） */
  endTime: number = 0;
  /** 歌词 */
  lrc: string = '';
  /** 翻译 */
  translation: string = '';
  /** 位置 */
  index: number = 0;
  /** 逐字信息（按行时长均分） */
  words: Array<LyricWord> = [];
}

/** 歌词解析配置 */
export interface LyricParserOptions {
  musicItem?: MusicItem;
  lyricSource?: LyricSource;
  translation?: string;
  extra?: Record<string, number>;
}

class LyricParseResult {
  lrcItems: Array<ParsedLrcItem> = [];
  meta: JsonRecord = {};
}

/**
 * 歌词解析器（移植自 utils/lrcParser.ts）
 */
export class LyricParser {
  private _musicItem: MusicItem | null = null;
  private meta: JsonRecord = {};
  private lrcItems: Array<ParsedLrcItem> = [];
  private extra: Record<string, number> = {};
  private offsetValue: number = 0;
  private lastSearchIndex: number = 0;

  hasTranslation: boolean = false;
  lyricSource: LyricSource | null = null;

  get musicItem(): MusicItem | null {
    return this._musicItem;
  }

  /** 歌词时间偏移（秒），定位时从播放进度中扣除 */
  get offset(): number {
    return this.offsetValue;
  }

  constructor(raw: string, options?: LyricParserOptions) {
    if (options !== undefined) {
      this._musicItem = options.musicItem === undefined ? null : options.musicItem;
      this.lyricSource = options.lyricSource === undefined ? null : options.lyricSource;
      if (options.extra !== undefined) {
        this.extra = options.extra;
      }
    }

    let rawText = raw;
    let translation = options === undefined || options.translation === undefined ? '' : options.translation;
    if (rawText.length === 0 && translation.length > 0) {
      rawText = translation;
      translation = '';
    }

    const parsed = LyricParser.parseLyricImpl(rawText);
    const extraOffset = this.extra['offset'];
    const metaOffsetRaw = parsed.meta['offset'];
    const metaOffset = typeof metaOffsetRaw === 'number' ? metaOffsetRaw : 0;
    if (extraOffset !== undefined) {
      parsed.meta['offset'] = metaOffset + extraOffset;
    }
    this.meta = parsed.meta;
    this.lrcItems = parsed.lrcItems;
    const finalOffsetRaw = this.meta['offset'];
    this.offsetValue = typeof finalOffsetRaw === 'number' ? finalOffsetRaw : 0;

    if (translation.length > 0) {
      this.hasTranslation = true;
      const transLrcItems = LyricParser.parseLyricImpl(translation).lrcItems;
      if (transLrcItems.length > 0) {
        let p1 = 0;
        let p2 = 0;
        while (p1 < this.lrcItems.length) {
          const lrcItem = this.lrcItems[p1];
          while (transLrcItems[p2].time < lrcItem.time && p2 < transLrcItems.length - 1) {
            ++p2;
          }
          if (transLrcItems[p2].time === lrcItem.time) {
            lrcItem.translation = transLrcItems[p2].lrc;
          } else {
            lrcItem.translation = '';
          }
          ++p1;
        }
      }
    }
  }

  getPosition(position: number): ParsedLrcItem | null {
    const pos = position - this.offsetValue;
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

  getLyricItems(): Array<ParsedLrcItem> {
    return this.lrcItems;
  }

  getMeta(): JsonRecord {
    return this.meta;
  }

  toString(withTimestamp: boolean = true, type: string = 'raw'): string {
    const lines: Array<string> = [];
    for (const item of this.lrcItems) {
      const content = type === 'raw' ? item.lrc : item.translation;
      if (withTimestamp) {
        lines.push(`${LyricParser.timeToLrctime(item.time)} ${content}`);
      } else {
        lines.push(content);
      }
    }
    return lines.join('\r\n');
  }

  /** [xx:xx.xx] => x s */
  private static parseTime(timeStr: string): number {
    let result = 0;
    const nums = timeStr.slice(1, timeStr.length - 1).split(':');
    for (let i = 0; i < nums.length; ++i) {
      result = result * 60 + Number(nums[i]);
    }
    return result;
  }

  /** x s => [xx:xx.xx] */
  private static timeToLrctime(sec: number): string {
    const min = Math.floor(sec / 60);
    const secRest = sec - min * 60;
    const secInt = Math.floor(secRest);
    const secFloat = secRest - secInt;
    return `[${min.toFixed(0).padStart(2, '0')}:${secInt.toString().padStart(2, '0')}.${secFloat.toFixed(2).slice(2)}]`;
  }

  private static parseMetaImpl(metaStr: string): JsonRecord {
    const meta: JsonRecord = {};
    if (metaStr === '') {
      return meta;
    }
    const metaReg = new RegExp('\\[(.+):(.+)\\]', 'g');
    const metaArr = metaStr.match(metaReg);
    if (metaArr === null) {
      return meta;
    }
    for (const m of metaArr) {
      const k = m.substring(1, m.indexOf(':'));
      const v = m.substring(k.length + 2, m.length - 1);
      if (k === 'offset') {
        meta[k] = Number(v) / 1000;
      } else {
        meta[k] = v;
      }
    }
    return meta;
  }

  private static parseLyricImpl(raw: string): LyricParseResult {
    const result = new LyricParseResult();
    const rawText = raw.trim();
    const rawLrcItems: Array<ParsedLrcItem> = [];

    const timeReg = new RegExp('\\[[\\d:.]+\\]', 'g');
    const rawLrcs = rawText.split(timeReg);
    const rawTimes = rawText.match(timeReg);
    const len = rawTimes === null ? 0 : rawTimes.length;
    if (rawLrcs.length > 0) {
      const firstSeg = rawLrcs[0];
      result.meta = LyricParser.parseMetaImpl(firstSeg.trim());
      rawLrcs.shift();
    }

    let counter = 0;
    let j = 0;
    for (let i = 0; i < len; ++i) {
      counter = 0;
      while (rawLrcs.length > 0 && rawLrcs[0] === '') {
        ++counter;
        rawLrcs.shift();
      }
      const head: string = rawLrcs.length > 0 ? rawLrcs[0] : '';
      const lrc = head.trim();
      for (j = i; j < i + counter; ++j) {
        const item = new ParsedLrcItem();
        item.time = rawTimes !== null ? LyricParser.parseTime(rawTimes[j]) : 0;
        item.lrc = lrc;
        item.index = j;
        LyricParser.parseWordTags(item);
        rawLrcItems.push(item);
      }
      i += counter;
      if (i < len) {
        const item = new ParsedLrcItem();
        item.time = rawTimes !== null ? LyricParser.parseTime(rawTimes[i]) : 0;
        item.lrc = lrc;
        item.index = j;
        LyricParser.parseWordTags(item);
        rawLrcItems.push(item);
      }
      rawLrcs.shift();
    }
    const lrcItems = rawLrcItems.sort((a: ParsedLrcItem, b: ParsedLrcItem): number => a.time - b.time);
    for (let idx = 0; idx < lrcItems.length; ++idx) {
      lrcItems[idx].index = idx;
    }
    if (lrcItems.length === 0 && rawText.length > 0) {
      const plainLines = rawText.split('\n');
      for (let idx = 0; idx < plainLines.length; ++idx) {
        const item = new ParsedLrcItem();
        item.time = 0;
        item.lrc = plainLines[idx];
        item.index = idx;
        lrcItems.push(item);
      }
    }
    LyricParser.fillWords(lrcItems);
    result.lrcItems = lrcItems;
    return result;
  }

  /** <mm:ss.xx> => x s（非法格式返回 -1） */
  private static parseWordTime(tag: string): number {
    const validReg = new RegExp('^\\d{1,3}:\\d{1,2}(?:\\.\\d{1,3})?$');
    if (!validReg.test(tag)) {
      return -1;
    }
    const colonIdx = tag.indexOf(':');
    const min = Number(tag.substring(0, colonIdx));
    const rest = tag.substring(colonIdx + 1);
    const dotIdx = rest.indexOf('.');
    let sec = 0;
    let frac = 0;
    if (dotIdx === -1) {
      sec = Number(rest);
    } else {
      sec = Number(rest.substring(0, dotIdx));
      frac = Number(rest.substring(dotIdx + 1).padEnd(3, '0'));
    }
    return min * 60 + sec + frac / 1000;
  }

  /**
   * 解析增强 LRC（A2）逐字标记：[mm:ss.xx]<mm:ss.xx>字<mm:ss.xx>字...
   * 命中时用真实时间戳填充 item.words，并把标记从 item.lrc 中剥离；
   * 未命中时不做任何修改（保持原文本，逐字时间由 fillWords 均分兜底）。
   */
  private static parseWordTags(item: ParsedLrcItem): void {
    const text = item.lrc;
    if (text.indexOf('<') === -1) {
      return;
    }
    const words: Array<LyricWord> = [];
    let pendingText = '';
    let pendingTime = -1;
    let leadPrefix = '';
    let pos = 0;
    while (pos < text.length) {
      const lt = text.indexOf('<', pos);
      if (lt === -1) {
        pendingText += text.substring(pos);
        break;
      }
      pendingText += text.substring(pos, lt);
      const gt = text.indexOf('>', lt);
      if (gt === -1) {
        pendingText += text.substring(lt);
        break;
      }
      const time = LyricParser.parseWordTime(text.substring(lt + 1, gt));
      if (time < 0) {
        pendingText += text.substring(lt, gt + 1);
        pos = gt + 1;
        continue;
      }
      if (pendingTime >= 0) {
        const w = new LyricWord();
        w.text = words.length === 0 && leadPrefix.length > 0 ? leadPrefix + pendingText : pendingText;
        w.startTime = pendingTime;
        w.endTime = 0;
        words.push(w);
      } else {
        leadPrefix = pendingText;
      }
      pendingText = '';
      pendingTime = time;
      pos = gt + 1;
    }
    if (pendingTime >= 0) {
      const w = new LyricWord();
      w.text = leadPrefix + pendingText;
      w.startTime = pendingTime;
      w.endTime = 0;
      words.push(w);
    }
    if (words.length === 0) {
      return;
    }
    let merged = '';
    for (const w of words) {
      merged += w.text;
    }
    item.lrc = merged;
    item.words = words;
  }

  /** 计算每行 endTime；有真实逐字标记的行直接沿用其时间轴，否则按行时长均分 */
  private static fillWords(items: Array<ParsedLrcItem>): void {
    for (let i = 0; i < items.length; ++i) {
      const item = items[i];
      item.endTime = i < items.length - 1 ? items[i + 1].time : item.time + 5;
      if (item.words.length > 0) {
        for (let c = 0; c < item.words.length; ++c) {
          const w = item.words[c];
          if (c < item.words.length - 1) {
            w.endTime = item.words[c + 1].startTime;
          } else {
            w.endTime = item.endTime > w.startTime ? item.endTime : w.startTime + 0.05;
          }
        }
        continue;
      }
      const chars = Array.from(item.lrc);
      if (chars.length === 0) {
        continue;
      }
      const lineDuration = Math.max(item.endTime - item.time, 0.1);
      const perChar = lineDuration / chars.length;
      item.words = new Array<LyricWord>(chars.length);
      for (let c = 0; c < chars.length; ++c) {
        const w = new LyricWord();
        w.text = chars[c];
        w.startTime = item.time + c * perChar;
        w.endTime = item.time + (c + 1) * perChar;
        item.words[c] = w;
      }
    }
  }
}
