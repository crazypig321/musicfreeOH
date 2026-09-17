import { EventEmitter, EventListenerFn } from '../common/EventBus';
import { JsonUtil, JsonRecord } from '../common/JsonUtil';
import {
  FAVORITE_SHEET_ID,
  FAVORITE_SHEET_TITLE,
  LOCAL_PLUGIN_PLATFORM,
  ResumeMode,
  SortType,
} from '../common/Consts';
import { SheetItem } from '../common/model/SheetTypes';
import { MusicItem } from '../common/model/MediaTypes';
import { SortedMusicList } from './SortedMusicList';
import { MusicSheetStorage } from './MusicSheetStorage';
import { appMeta } from './AppMeta';
import { appConfig } from './AppConfig';
import { CryptoUtil } from '../utils/CryptoUtil';
import { Log } from '../utils/Log';

/** 歌单曲目更新事件 */
export class MusicListUpdatedEvent {
  sheetId: string = '';
  /** 'length' | 'resort' */
  updateType: string = '';
}

/** 歌单基本信息更新事件 */
export class SheetBasicUpdatedEvent {
  sheetId: string = '';
}

/** 歌单基本信息补丁（对应 RN Partial<Pick<...>>） */
export class SheetBasePatch {
  title: string | null = null;
  artist: string | null = null;
  coverImg: string | null = null;
  artwork: string | null = null;
  description: string | null = null;
  worksNum: number = -1;
  createAt: number = -1;
}

/** 歌单备份条目 */
export class SheetBackupEntry {
  sheet: SheetItem = new SheetItem();
  musicList: Array<MusicItem> = [];

  static fromRecord(rec: JsonRecord): SheetBackupEntry {
    const entry = new SheetBackupEntry();
    const sheetRec = JsonUtil.objToRecord(rec['sheet']);
    if (sheetRec !== null) {
      entry.sheet = SheetItem.fromRecord(sheetRec);
    }
    const listRaw = JsonUtil.objToRecordArray(rec['musicList']);
    if (listRaw !== null) {
      for (const it of listRaw) {
        entry.musicList.push(MusicItem.fromRecord(it));
      }
    }
    return entry;
  }

  toRecord(): JsonRecord {
    const arr: Array<JsonRecord> = [];
    for (const it of this.musicList) {
      arr.push(it.toPersistRecord());
    }
    const rec: JsonRecord = {
      'sheet': this.sheet.toRecord(),
      'musicList': arr,
    };
    return rec;
  }
}

export function backupEntriesFromRecord(raw: Object | null): Array<SheetBackupEntry> {
  const result: Array<SheetBackupEntry> = [];
  const arr = JsonUtil.objToRecordArray(raw);
  if (arr !== null) {
    for (const rec of arr) {
      result.push(SheetBackupEntry.fromRecord(rec));
    }
  }
  return result;
}

/**
 * 歌单管理（移植自 musicSheet/index.ts）
 */
export class MusicSheet {
  /** 默认歌单（我喜欢） */
  readonly defaultSheet: SheetItem = MusicSheet.createDefaultSheet();

  /** 所有歌单 */
  sheets: Array<SheetItem> = [];

  /** 收藏的歌单 */
  starredSheets: Array<SheetItem> = [];

  private musicListMap: Map<string, SortedMusicList> = new Map();
  private ee: EventEmitter = new EventEmitter();

  private static createDefaultSheet(): SheetItem {
    const s = new SheetItem();
    s.id = FAVORITE_SHEET_ID;
    s.platform = LOCAL_PLUGIN_PLATFORM;
    s.title = FAVORITE_SHEET_TITLE;
    s.worksNum = 0;
    return s;
  }

  setup(): Promise<void> {
    try {
      const allSheets = MusicSheetStorage.getSheets();
      if (allSheets === null) {
        throw new Error('sheets not exist');
      }
      let needRestore = false;
      if (allSheets.length === 0) {
        allSheets.push(MusicSheet.createDefaultSheet());
        needRestore = true;
      }
      if (allSheets[0].id !== this.defaultSheet.id) {
        let defaultSheetIndex = -1;
        for (let i = 0; i < allSheets.length; ++i) {
          if (allSheets[i].id === this.defaultSheet.id) {
            defaultSheetIndex = i;
            break;
          }
        }
        if (defaultSheetIndex === -1) {
          allSheets.unshift(MusicSheet.createDefaultSheet());
        } else {
          const removed = allSheets.splice(defaultSheetIndex, 1);
          allSheets.unshift(removed[0]);
        }
        needRestore = true;
      }
      if (needRestore) {
        MusicSheetStorage.setSheets(allSheets);
      }

      const needMigrate = appMeta.musicSheetVersion < 2;
      let worksNumChanged = false;
      for (const sheet of allSheets) {
        const musicItems = MusicSheetStorage.getMusicList(sheet.id);
        const sortType = MusicSheetStorage.getSheetSortType(sheet.id);
        if (needMigrate && this.migrateItems(musicItems)) {
          MusicSheetStorage.setMusicList(sheet.id, musicItems);
        }
        this.musicListMap.set(sheet.id, new SortedMusicList(musicItems, sortType));
        if (sheet.worksNum !== musicItems.length) {
          sheet.worksNum = musicItems.length;
          worksNumChanged = true;
        }
      }
      if (needMigrate) {
        appMeta.setMusicSheetVersion(2);
      }
      if (worksNumChanged) {
        MusicSheetStorage.setSheets(allSheets);
      }
      this.sheets = allSheets;

      const starred = MusicSheetStorage.getStarredSheets();
      this.starredSheets = starred === null ? [] : starred;
    } catch (e) {
      // 首次初始化
      const fresh: Array<SheetItem> = [MusicSheet.createDefaultSheet()];
      MusicSheetStorage.setSheets(fresh);
      MusicSheetStorage.setMusicList(this.defaultSheet.id, []);
      this.sheets = fresh;
      this.musicListMap.set(this.defaultSheet.id, new SortedMusicList([], SortType.None));
      this.starredSheets = [];
      Log.info('MusicSheet: 初始化默认歌单');
    }
    return Promise.resolve();
  }

  /**
   * migrateV2：补齐缺失的 $timestamp/$sortIndex
   */
  private migrateItems(musicItems: Array<MusicItem>): boolean {
    let dirty = false;
    const now = Date.now();
    for (let index = 0; index < musicItems.length; ++index) {
      const it = musicItems[index];
      if (it.timeStamp === 0) {
        it.timeStamp = now;
        it.sortIndex = index;
        dirty = true;
      }
    }
    return dirty;
  }

  /** 新建歌单，返回歌单 id */
  addSheet(title: string): Promise<string> {
    const newSheetId = CryptoUtil.nanoid();
    const newSheet = new SheetItem();
    newSheet.id = newSheetId;
    newSheet.title = title;
    newSheet.platform = LOCAL_PLUGIN_PLATFORM;
    newSheet.createAt = Date.now();
    const newSheets: Array<SheetItem> = [this.sheets[0], newSheet].concat(this.sheets.slice(1));
    this.sheets = newSheets;
    MusicSheetStorage.setSheets(newSheets);
    MusicSheetStorage.setMusicList(newSheetId, []);

    const defaultSortType = MusicSheetStorage.sortTypeFromStr(appConfig.getMusicOrderInLocalSheet());
    if (defaultSortType !== SortType.None) {
      MusicSheetStorage.setSheetMeta(newSheetId, 'sort', defaultSortType);
    }
    this.musicListMap.set(newSheetId, new SortedMusicList([], defaultSortType));
    this.emitSheetBasicUpdated(newSheetId);
    return Promise.resolve(newSheetId);
  }

  /** 更新歌单基本信息 */
  updateMusicSheetBase(sheetId: string, patch: SheetBasePatch): void {
    const sheetIndex = this.findSheetIndex(sheetId);
    if (sheetIndex === -1) {
      return;
    }
    const target = this.sheets[sheetIndex];
    if (patch.title !== null) {
      target.title = patch.title;
    }
    if (patch.artist !== null) {
      target.artist = patch.artist;
    }
    if (patch.coverImg !== null) {
      target.coverImg = patch.coverImg;
    }
    if (patch.artwork !== null) {
      target.artwork = patch.artwork;
    }
    if (patch.description !== null) {
      target.description = patch.description;
    }
    if (patch.worksNum >= 0) {
      target.worksNum = patch.worksNum;
    }
    if (patch.createAt >= 0) {
      target.createAt = patch.createAt;
    }
    MusicSheetStorage.setSheets(this.sheets);
    this.emitSheetBasicUpdated(sheetId);
  }

  /** 删除歌单（不能删除默认歌单） */
  removeSheet(sheetId: string): Promise<void> {
    if (sheetId === this.defaultSheet.id) {
      return Promise.resolve();
    }
    const sheetIndex = this.findSheetIndex(sheetId);
    if (sheetIndex === -1) {
      return Promise.resolve();
    }
    this.sheets.splice(sheetIndex, 1);
    this.musicListMap.delete(sheetId);
    MusicSheetStorage.setSheets(this.sheets);
    MusicSheetStorage.removeMusicList(sheetId);
    this.emitMusicListUpdated(sheetId, 'length');
    this.emitSheetBasicUpdated(sheetId);
    return Promise.resolve();
  }

  /** 添加音乐到歌单 */
  addMusic(sheetId: string, musicItem: MusicItem | Array<MusicItem>): Promise<void> {
    const musicList = this.musicListMap.get(sheetId);
    if (musicList === undefined) {
      return Promise.resolve();
    }
    const now = Date.now();
    const rawItems: Array<MusicItem> = Array.isArray(musicItem) ? musicItem : [musicItem];
    const taggedItems: Array<MusicItem> = [];
    for (let index = 0; index < rawItems.length; ++index) {
      const it = rawItems[index].clone();
      it.timeStamp = now;
      it.sortIndex = rawItems.length - index;
      taggedItems.push(it);
    }
    const addedCount = musicList.add(taggedItems);
    if (addedCount === 0) {
      return Promise.resolve();
    }

    // 更新封面
    const sheet = this.findSheet(sheetId);
    if (sheet !== null && !sheet.coverImg.startsWith('file://')) {
      const first = musicList.at(0);
      const coverPatch = new SheetBasePatch();
      coverPatch.coverImg = first !== null ? first.artwork : '';
      this.updateMusicSheetBase(sheetId, coverPatch);
    }
    // 更新歌曲数
    if (sheet !== null && sheet.worksNum !== musicList.length) {
      const numPatch = new SheetBasePatch();
      numPatch.worksNum = musicList.length;
      this.updateMusicSheetBase(sheetId, numPatch);
    }

    MusicSheetStorage.setMusicList(sheetId, musicList.musicList);
    this.emitMusicListUpdated(sheetId, 'length');
    return Promise.resolve();
  }

  /** 按下标移除歌单内歌曲 */
  removeMusicByIndex(sheetId: string, indices: Array<number>): Promise<void> {
    const musicList = this.musicListMap.get(sheetId);
    if (musicList === undefined) {
      return Promise.resolve();
    }
    musicList.removeByIndex(indices);
    MusicSheetStorage.setMusicList(sheetId, musicList.musicList);
    this.emitMusicListUpdated(sheetId, 'length');
    const patch = new SheetBasePatch();
    patch.worksNum = musicList.length;
    this.applyCoverFollowPatch(sheetId, musicList, patch);
    this.updateMusicSheetBase(sheetId, patch);
    return Promise.resolve();
  }

  /** 移除歌单内歌曲 */
  removeMusic(sheetId: string, musicItems: Array<MusicItem>): Promise<void> {
    const musicList = this.musicListMap.get(sheetId);
    if (musicList === undefined) {
      return Promise.resolve();
    }
    musicList.remove(musicItems);
    MusicSheetStorage.setMusicList(sheetId, musicList.musicList);
    this.emitMusicListUpdated(sheetId, 'length');
    const patch = new SheetBasePatch();
    patch.worksNum = musicList.length;
    this.applyCoverFollowPatch(sheetId, musicList, patch);
    this.updateMusicSheetBase(sheetId, patch);
    return Promise.resolve();
  }

  /** 删除歌曲后让封面跟随剩余第一首（用户本地封面 file:// 不覆盖；清空时置空封面） */
  private applyCoverFollowPatch(sheetId: string, musicList: SortedMusicList, patch: SheetBasePatch): void {
    const sheet = this.findSheet(sheetId);
    if (sheet === null || sheet.coverImg.startsWith('file://')) {
      return;
    }
    const first = musicList.at(0);
    const nextCover = first !== null ? first.artwork : '';
    if (sheet.coverImg !== nextCover) {
      patch.coverImg = nextCover;
    }
  }

  /** 备份所有歌单 */
  backupSheets(): Array<SheetBackupEntry> {
    const result: Array<SheetBackupEntry> = [];
    for (const sheet of this.sheets) {
      const entry = new SheetBackupEntry();
      entry.sheet = sheet;
      const ml = this.musicListMap.get(sheet.id);
      entry.musicList = ml !== undefined ? ml.musicList.slice() : [];
      result.push(entry);
    }
    return result;
  }

  /** 恢复歌单 */
  resumeSheets(sheets: Array<SheetBackupEntry>, resumeMode: ResumeMode): Promise<void> {
    const task = (): Promise<void> => {
      if (resumeMode === ResumeMode.Append) {
        let chain: Promise<void> = Promise.resolve();
        for (let i = sheets.length - 1; i >= 0; --i) {
          const idx = i;
          chain = chain.then((): Promise<void> => {
            return this.addSheet(sheets[idx].sheet.title).then((newSheetId: string): Promise<void> => {
              return this.addMusic(newSheetId, sheets[idx].musicList);
            });
          });
        }
        return chain;
      }
      // 分离默认歌单
      let defaultSheetIndex = -1;
      for (let i = 0; i < sheets.length; ++i) {
        if (sheets[i].sheet.id === this.defaultSheet.id) {
          defaultSheetIndex = i;
          break;
        }
      }
      let exportedDefaultSheet: SheetBackupEntry | null = null;
      if (defaultSheetIndex !== -1) {
        const removed = sheets.splice(defaultSheetIndex, 1);
        exportedDefaultSheet = removed[0];
      }
      const defaultMusic: Array<MusicItem> =
        exportedDefaultSheet !== null ? exportedDefaultSheet.musicList : [];
      let chain: Promise<void> = this.addMusic(this.defaultSheet.id, defaultMusic);
      if (resumeMode === ResumeMode.OverwriteDefault) {
        for (let i = sheets.length - 1; i >= 0; --i) {
          const idx = i;
          chain = chain.then((): Promise<void> => {
            return this.addSheet(sheets[idx].sheet.title).then((newSheetId: string): Promise<void> => {
              return this.addMusic(newSheetId, sheets[idx].musicList);
            });
          });
        }
      } else {
        const existsSheetIdMap: Map<string, string> = new Map();
        for (const it of this.sheets) {
          existsSheetIdMap.set(it.title, it.id);
        }
        for (let i = sheets.length - 1; i >= 0; --i) {
          const idx = i;
          chain = chain.then((): Promise<void> => {
            const existingId = existsSheetIdMap.get(sheets[idx].sheet.title);
            if (existingId !== undefined) {
              return this.addMusic(existingId, sheets[idx].musicList);
            }
            return this.addSheet(sheets[idx].sheet.title).then((newSheetId: string): Promise<void> => {
              return this.addMusic(newSheetId, sheets[idx].musicList);
            });
          });
        }
      }
      return chain;
    };
    return task();
  }

  /** 收藏歌单 */
  starMusicSheet(musicSheet: SheetItem): void {
    this.starredSheets = [musicSheet].concat(this.starredSheets);
    MusicSheetStorage.setStarredSheets(this.starredSheets);
    this.emitSheetBasicUpdated(musicSheet.id);
  }

  /** 取消收藏歌单 */
  unstarMusicSheet(musicSheet: SheetItem): void {
    const next: Array<SheetItem> = [];
    for (const it of this.starredSheets) {
      if (it.id === musicSheet.id && it.platform === musicSheet.platform) {
        continue;
      }
      next.push(it);
    }
    this.starredSheets = next;
    MusicSheetStorage.setStarredSheets(this.starredSheets);
    this.emitSheetBasicUpdated(musicSheet.id);
  }

  /** 获取歌单的排序歌曲列表 */
  getSortedMusicListBySheetId(sheetId: string): SortedMusicList {
    const ml = this.musicListMap.get(sheetId);
    if (ml !== undefined) {
      return ml;
    }
    return new SortedMusicList([], SortType.None);
  }

  /** 获取歌单曲目 */
  getMusicList(sheetId: string): Array<MusicItem> {
    return this.getSortedMusicListBySheetId(sheetId).musicList;
  }

  /** 设置歌单排序类型 */
  setSortType(sheetId: string, sortType: SortType): void {
    const musicList = this.musicListMap.get(sheetId);
    if (musicList === undefined) {
      return;
    }
    if (musicList.currentSortType === sortType) {
      return;
    }
    musicList.setSortType(sortType);
    MusicSheetStorage.setSheetMeta(sheetId, 'sort', sortType);
    this.emitMusicListUpdated(sheetId, 'resort');
  }

  /** 手动排序 */
  manualSort(sheetId: string, newMusicItems: Array<MusicItem>): void {
    const musicList = this.musicListMap.get(sheetId);
    if (musicList === undefined) {
      return;
    }
    musicList.manualSort(newMusicItems);
    MusicSheetStorage.setMusicList(sheetId, musicList.musicList);
    MusicSheetStorage.setSheetMeta(sheetId, 'sort', SortType.None);
    this.emitMusicListUpdated(sheetId, 'resort');
  }

  /** 读取歌单元信息 */
  getSheetMeta(sheetId: string, key: string): string | null {
    return MusicSheetStorage.getSheetMeta(sheetId, key);
  }

  onMusicListUpdated(cb: (sheetId: string, updateType: string) => void): void {
    const wrapper: EventListenerFn = (payload?: Object) => {
      if (payload instanceof MusicListUpdatedEvent) {
        cb(payload.sheetId, payload.updateType);
      }
    };
    this.ee.on('UpdateMusicList', wrapper);
  }

  onSheetBasicUpdated(cb: (sheetId: string) => void): void {
    const wrapper: EventListenerFn = (payload?: Object) => {
      if (payload instanceof SheetBasicUpdatedEvent) {
        cb(payload.sheetId);
      }
    };
    this.ee.on('UpdateSheetBasic', wrapper);
  }

  private findSheetIndex(sheetId: string): number {
    for (let i = 0; i < this.sheets.length; ++i) {
      if (this.sheets[i].id === sheetId) {
        return i;
      }
    }
    return -1;
  }

  private findSheet(sheetId: string): SheetItem | null {
    const idx = this.findSheetIndex(sheetId);
    return idx === -1 ? null : this.sheets[idx];
  }

  private emitMusicListUpdated(sheetId: string, updateType: string): void {
    const ev = new MusicListUpdatedEvent();
    ev.sheetId = sheetId;
    ev.updateType = updateType;
    this.ee.emit('UpdateMusicList', ev);
  }

  private emitSheetBasicUpdated(sheetId: string): void {
    const ev = new SheetBasicUpdatedEvent();
    ev.sheetId = sheetId;
    this.ee.emit('UpdateSheetBasic', ev);
  }
}

export const musicSheet = new MusicSheet();

/** 从备份数据解析歌单列表（备份恢复入口用） */
export function parseSheetBackup(raw: string | null | undefined): Array<SheetBackupEntry> {
  if (raw === null || raw === undefined || raw.length === 0) {
    return [];
  }
  return backupEntriesFromRecord(JsonUtil.parseAny(raw));
}
