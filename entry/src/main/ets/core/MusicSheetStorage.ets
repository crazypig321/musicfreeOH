import { KVStore } from '../infra/KVStore';
import { JsonUtil, JsonRecord } from '../common/JsonUtil';
import { SortType } from '../common/Consts';
import { MusicItem } from '../model/MediaTypes';
import { SheetItem } from '../model/SheetTypes';

/**
 * 歌单存储层（移植自 musicSheet/storage.ts）
 * 每个数据域独立 KVStore：LocalSheet.<key>
 */
export class MusicSheetStorage {
  private static storeOf(key: string): KVStore {
    return KVStore.getOrCreate('LocalSheet.' + key);
  }

  private static getData(key: string): Object | null {
    return JsonUtil.parseAny(MusicSheetStorage.storeOf(key).get('data'));
  }

  private static setData(key: string, value: JsonRecord | Array<JsonRecord>): void {
    MusicSheetStorage.storeOf(key).set('data', JSON.stringify(value));
  }

  private static removeData(key: string): void {
    MusicSheetStorage.storeOf(key).clearAll();
  }

  /** 存储歌单基本信息 */
  static setSheets(sheets: Array<SheetItem>): void {
    const arr: Array<JsonRecord> = [];
    for (const s of sheets) {
      arr.push(s.toRecord());
    }
    MusicSheetStorage.setData('music-sheets', arr);
  }

  /** 获取歌单基本信息 */
  static getSheets(): Array<SheetItem> | null {
    const raw = MusicSheetStorage.getData('music-sheets');
    const arr = JsonUtil.objToRecordArray(raw);
    if (arr === null) {
      return null;
    }
    const result: Array<SheetItem> = [];
    for (const rec of arr) {
      result.push(SheetItem.fromRecord(rec));
    }
    return result;
  }

  /** 存储收藏的歌单 */
  static setStarredSheets(sheets: Array<SheetItem>): void {
    const arr: Array<JsonRecord> = [];
    for (const s of sheets) {
      arr.push(s.toRecord());
    }
    MusicSheetStorage.setData('starred-sheets', arr);
  }

  /** 获取收藏的歌单 */
  static getStarredSheets(): Array<SheetItem> | null {
    const raw = MusicSheetStorage.getData('starred-sheets');
    const arr = JsonUtil.objToRecordArray(raw);
    if (arr === null) {
      return null;
    }
    const result: Array<SheetItem> = [];
    for (const rec of arr) {
      result.push(SheetItem.fromRecord(rec));
    }
    return result;
  }

  /** 存储歌单内的歌曲 */
  static setMusicList(sheetId: string, musicList: Array<MusicItem>): void {
    const arr: Array<JsonRecord> = [];
    for (const it of musicList) {
      arr.push(it.toPersistRecord());
    }
    MusicSheetStorage.setData(sheetId, arr);
  }

  /** 获取歌单内的歌曲 */
  static getMusicList(sheetId: string): Array<MusicItem> {
    const raw = MusicSheetStorage.getData(sheetId);
    const arr = JsonUtil.objToRecordArray(raw);
    if (arr === null) {
      return [];
    }
    const result: Array<MusicItem> = [];
    for (const rec of arr) {
      result.push(MusicItem.fromRecord(rec));
    }
    return result;
  }

  /** 清空歌单内的歌曲/其他信息 */
  static removeMusicList(sheetId: string): void {
    MusicSheetStorage.removeData(sheetId);
  }

  /** 设置歌单元信息 */
  static setSheetMeta(sheetId: string, key: string, value: string): void {
    MusicSheetStorage.storeOf(sheetId).set('meta.' + key, value);
  }

  /** 读取歌单元信息 */
  static getSheetMeta(sheetId: string, key: string): string | null {
    const v = MusicSheetStorage.storeOf(sheetId).get('meta.' + key);
    return v.length > 0 ? v : null;
  }

  /** 读取歌单排序类型 */
  static getSheetSortType(sheetId: string): SortType {
    const v = MusicSheetStorage.getSheetMeta(sheetId, 'sort');
    return MusicSheetStorage.sortTypeFromStr(v);
  }

  static sortTypeFromStr(s: string | null): SortType {
    if (s === null) {
      return SortType.None;
    }
    if (s === SortType.Title) {
      return SortType.Title;
    }
    if (s === SortType.Artist) {
      return SortType.Artist;
    }
    if (s === SortType.Album) {
      return SortType.Album;
    }
    if (s === SortType.Newest) {
      return SortType.Newest;
    }
    if (s === SortType.Oldest) {
      return SortType.Oldest;
    }
    return SortType.None;
  }
}
