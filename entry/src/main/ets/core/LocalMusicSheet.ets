import { KVStore } from '../infra/KVStore';
import { JsonUtil, JsonRecord } from '../common/JsonUtil';
import { EventEmitter, EventListenerFn } from '../common/EventBus';
import { INTERNAL_SERIALIZE_KEY, LOCAL_PLUGIN_PLATFORM, SUPPORT_LOCAL_MEDIA_TYPE } from '../common/Consts';
import { MusicItem } from '../common/model/MediaTypes';
import { MediaUtils } from '../utils/MediaUtils';
import { FileUtils } from '../utils/FileUtils';
import { CryptoUtil } from '../utils/CryptoUtil';
import { MediaMetadata, MediaBasicMeta } from '../utils/MediaMetadata';
import { appConfig } from './AppConfig';
import { musicSheet } from './MusicSheet';

/** 本地歌单更新事件 */
export class LocalSheetUpdatedEvent {
}

/** 文件名解析结果（platform@id@title@artist） */
class ParsedFilename {
  platform: string = '';
  id: string = '';
  title: string = '';
  artist: string = '';
}

/**
 * 本地音乐歌单（移植自 localMusicSheet.ts）
 * 存储格式与 RN 一致：$localPath 带 file:// 前缀
 * 同一实现派生两个独立实例：localMusicSheet（本地音乐）与 downloadedSheet（已下载），
 * 两者数据与操作互不关联
 */
export class LocalMusicSheet {
  private readonly storeKey: string;
  private readonly eventName: string;
  private localSheetItems: Array<MusicItem> = [];
  private ee: EventEmitter = new EventEmitter();
  private importToken: string | null = null;
  /** 关联的另一域实例（本地音乐 ↔ 已下载）：删除源文件时同步移除两边记录 */
  peer: LocalMusicSheet | null = null;

  constructor(storeKey: string, eventName: string) {
    this.storeKey = storeKey;
    this.eventName = eventName;
  }

  private getStore(): KVStore {
    return KVStore.getOrCreate('storage');
  }

  get musicList(): Array<MusicItem> {
    return this.localSheetItems;
  }

  setup(): Promise<void> {
    const task = (): Promise<void> => {
      const raw = this.getStore().get(this.storeKey);
      if (raw.length > 0) {
        const arr = JsonUtil.parseRecordArray(raw);
        const sheet: Array<MusicItem> = [];
        if (arr !== null) {
          for (const rec of arr) {
            sheet.push(MusicItem.fromRecord(rec));
          }
        }
        const validSheet: Array<MusicItem> = [];
        for (const musicItem of sheet) {
          const localPath = MediaUtils.getLocalPath(musicItem);
          if (localPath !== null && FileUtils.exists(localPath)) {
            validSheet.push(musicItem);
          }
        }
        if (validSheet.length !== sheet.length) {
          this.saveItems(validSheet);
        }
        this.localSheetItems = validSheet;
      } else {
        this.saveItems([]);
      }
      this.ee.emit(this.eventName, new LocalSheetUpdatedEvent());
      return Promise.resolve();
    };
    return task();
  }

  private saveItems(items: Array<MusicItem>): void {
    const arr: Array<JsonRecord> = [];
    for (const it of items) {
      arr.push(it.toPersistRecord());
    }
    this.getStore().set(this.storeKey, JSON.stringify(arr));
  }

  private notify(): void {
    this.ee.emit(this.eventName, new LocalSheetUpdatedEvent());
  }

  /** 添加本地音乐（去重；已存在条目封面为空时合并新提取的封面） */
  addMusic(musicItem: MusicItem | Array<MusicItem>): Promise<void> {
    const rawItems: Array<MusicItem> = Array.isArray(musicItem) ? musicItem : [musicItem];
    const newSheet: Array<MusicItem> = this.localSheetItems.slice();
    let changed = false;
    for (const mi of rawItems) {
      let exists = false;
      for (const it of this.localSheetItems) {
        if (MediaUtils.isSameMediaItem(it, mi)) {
          exists = true;
          // 旧条目无封面或封面文件已失效（如重装后缓存被清）、重新扫描提取到封面时补上
          if (mi.artwork.length > 0 &&
            (it.artwork.length === 0 || LocalMusicSheet.isDeadFileArtwork(it.artwork))) {
            it.artwork = mi.artwork;
            changed = true;
          }
          break;
        }
      }
      if (!exists) {
        newSheet.push(mi);
        changed = true;
      }
    }
    if (!changed) {
      return Promise.resolve();
    }
    this.saveItems(newSheet);
    this.localSheetItems = newSheet;
    this.notify();
    return Promise.resolve();
  }

  /** file:// 封面路径是否已失效（文件不存在） */
  private static isDeadFileArtwork(artwork: string): boolean {
    if (!artwork.startsWith('file://')) {
      return false;
    }
    return !FileUtils.exists(artwork);
  }

  /** 添加本地音乐（仅内存，不落盘） */
  addMusicDraft(musicItem: MusicItem | Array<MusicItem>): void {
    const rawItems: Array<MusicItem> = Array.isArray(musicItem) ? musicItem : [musicItem];
    const newSheet: Array<MusicItem> = this.localSheetItems.slice();
    for (const mi of rawItems) {
      let exists = false;
      for (const it of this.localSheetItems) {
        if (MediaUtils.isSameMediaItem(it, mi)) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        newSheet.push(mi);
      }
    }
    this.localSheetItems = newSheet;
    this.notify();
  }

  /** 落盘当前本地歌单 */
  saveLocalSheet(): void {
    this.saveItems(this.localSheetItems);
  }

  /** 移除本地音乐；deleteOriginalFile 时删除源文件 */
  removeMusic(musicItem: MusicItem, deleteOriginalFile: boolean = false): Promise<void> {
    let idx = -1;
    for (let i = 0; i < this.localSheetItems.length; ++i) {
      if (MediaUtils.isSameMediaItem(this.localSheetItems[i], musicItem)) {
        idx = i;
        break;
      }
    }
    const newSheet = this.localSheetItems.slice();
    if (idx !== -1) {
      const localMusicItem = this.localSheetItems[idx];
      newSheet.splice(idx, 1);
      const legacyRec = JsonUtil.objToRecord(musicItem.extras[INTERNAL_SERIALIZE_KEY]);
      const localRec = JsonUtil.objToRecord(localMusicItem.extras[INTERNAL_SERIALIZE_KEY]);
      let localPath: string | null = null;
      if (legacyRec !== null) {
        localPath = JsonUtil.recStr(legacyRec, 'localPath');
      }
      if ((localPath === null || localPath.length === 0) && localRec !== null) {
        localPath = JsonUtil.recStr(localRec, 'localPath');
      }
      if (deleteOriginalFile && localPath !== null && localPath.length > 0) {
        FileUtils.unlink(localPath);
      }
    }
    this.localSheetItems = newSheet;
    this.notify();
    this.saveLocalSheet();
    // 删除了源文件：另一域中同一首歌的记录也一并移除（仅移除列表时不联动）
    if (deleteOriginalFile && idx !== -1 && this.peer !== null) {
      this.peer.removeMusic(musicItem, false);
    }
    return Promise.resolve();
  }

  /** 是否为本地音乐，返回匹配项 */
  isLocalMusic(musicItem: MusicItem | null): MusicItem | null {
    if (musicItem === null) {
      return null;
    }
    for (const it of this.localSheetItems) {
      if (MediaUtils.isSameMediaItem(it, musicItem)) {
        return it;
      }
    }
    return null;
  }

  /** 更新匹配条目的封面（搜索封面命中后写回；无匹配或封面为空不处理） */
  setArtwork(musicItem: MusicItem, artwork: string): void {
    if (artwork.length === 0) {
      return;
    }
    for (const it of this.localSheetItems) {
      if (MediaUtils.isSameMediaItem(it, musicItem)) {
        it.artwork = artwork;
        this.saveLocalSheet();
        this.notify();
        return;
      }
    }
  }

  getMusicList(): Array<MusicItem> {
    return this.localSheetItems;
  }

  /** 覆盖本地歌单 */
  updateMusicList(newSheet: Array<MusicItem>): Promise<void> {
    const items = newSheet.slice();
    this.saveItems(items);
    this.localSheetItems = items;
    this.notify();
    return Promise.resolve();
  }

  /** 取消导入 */
  cancelImportLocal(): void {
    this.importToken = null;
  }

  /**
   * 遍历目录收集本地音频（保留 file:// 前缀）；filenameFilter 返回 false 的文件跳过
   */
  private collectMusicStats(folderPaths: Array<string>, token: string,
    filenameFilter?: (filename: string) => boolean): Array<string> {
    const musicList: Array<string> = [];
    const queued: Set<string> = new Set();
    for (const p of folderPaths) {
      queued.add(p);
    }
    while (folderPaths.length !== 0) {
      if (this.importToken !== token) {
        throw new Error('Import Broken');
      }
      const peek = folderPaths.shift();
      if (peek === undefined) {
        break;
      }
      const names = FileUtils.listDir(FileUtils.normalizePath(peek));
      for (const name of names) {
        const child = peek.endsWith('/') ? peek + name : peek + '/' + name;
        if (FileUtils.isDirectory(child)) {
          if (!queued.has(child)) {
            queued.add(child);
            folderPaths.push(child);
          }
        } else if (LocalMusicSheet.localMediaFilter(child) &&
          (filenameFilter === undefined || filenameFilter(name))) {
          musicList.push(child);
        }
      }
    }
    return musicList;
  }

  private static localMediaFilter(filename: string): boolean {
    const lower = filename.toLowerCase();
    for (const ext of SUPPORT_LOCAL_MEDIA_TYPE) {
      if (lower.endsWith(ext)) {
        return true;
      }
    }
    return false;
  }

  private static parseFilename(fn: string): ParsedFilename | null {
    const data = fn.slice(0, fn.lastIndexOf('.')).split('@');
    const parsed = new ParsedFilename();
    if (data.length > 0) {
      parsed.platform = data[0];
    }
    if (data.length > 1) {
      parsed.id = data[1];
    }
    if (data.length > 2) {
      parsed.title = data[2];
    }
    if (data.length > 3) {
      parsed.artist = data[3];
    }
    if (parsed.platform.length === 0 || parsed.id.length === 0) {
      return null;
    }
    return parsed;
  }

  /**
   * 导入本地音乐；filenameFilter 返回 false 的文件跳过（用于下载/本地两个域按文件名分流）
   */
  importLocal(_folderPaths: Array<string>, filenameFilter?: (filename: string) => boolean): Promise<void> {
    const folderPaths: Array<string> = [];
    for (const it of _folderPaths) {
      folderPaths.push(FileUtils.addFileScheme(it));
    }
    const token = CryptoUtil.nanoid();
    this.importToken = token;
    // 自动匹配封面开关：关闭时跳过内嵌封面提取与网络封面回填（导入更快）
    const autoMatchCover = appConfig.getLocalMusicAutoMatchCover();
    const musicList = this.collectMusicStats(folderPaths, token, filenameFilter);
    if (this.importToken !== token) {
      return Promise.reject(new Error('Import Broken'));
    }
    // 分组读取元信息（每组 25 个，避免并发 fd 过多）
    const groupNum = 25;
    const metas: Array<MediaBasicMeta> = [];
    const groups = Math.ceil(musicList.length / groupNum);
    const collectMetas = (groupIndex: number): Promise<void> => {
      if (groupIndex >= groups) {
        if (this.importToken !== token) {
          return Promise.reject(new Error('Import Broken'));
        }
        return Promise.resolve();
      }
      const chunk: Array<string> = musicList.slice(groupIndex * groupNum, (groupIndex + 1) * groupNum);
      const tasks: Array<Promise<MediaBasicMeta>> = [];
      for (const p of chunk) {
        tasks.push(MediaMetadata.getBasicMeta(FileUtils.normalizePath(p), autoMatchCover));
      }
      return Promise.all(tasks).then((chunkMetas: Array<MediaBasicMeta>) => {
        for (const m of chunkMetas) {
          metas.push(m);
        }
        return collectMetas(groupIndex + 1);
      });
    };
    return collectMetas(0).then((): Promise<Array<MusicItem>> => {
      if (this.importToken !== token) {
        throw new Error('Import Broken');
      }
      const buildTasks: Array<Promise<MusicItem>> = [];
      for (let index = 0; index < musicList.length; ++index) {
        buildTasks.push(LocalMusicSheet.buildMusicItem(musicList[index], metas[index], autoMatchCover));
      }
      return Promise.all(buildTasks);
    }).then((musicItems: Array<MusicItem>) => {
      if (this.importToken !== token) {
        throw new Error('Import Broken');
      }
      this.addMusic(musicItems);
    });
  }

  private static buildMusicItem(musicPath: string, meta: MediaBasicMeta,
    autoMatchCover: boolean): Promise<MusicItem> {
    const parsed = LocalMusicSheet.parseFilename(FileUtils.getFileName(musicPath));
    let platform: string;
    let id: string;
    let title: string;
    let artist: string;
    if (parsed !== null) {
      platform = parsed.platform;
      id = parsed.id;
      title = parsed.title;
      artist = parsed.artist;
    } else {
      platform = LOCAL_PLUGIN_PLATFORM;
      artist = '';
      title = '';
      return CryptoUtil.md5(musicPath).then((hash: string): MusicItem => {
        return LocalMusicSheet.assembleMusicItem(musicPath, platform, hash, title, artist, meta, autoMatchCover);
      });
    }
    return Promise.resolve(
      LocalMusicSheet.assembleMusicItem(musicPath, platform, id, title, artist, meta, autoMatchCover));
  }

  private static assembleMusicItem(musicPath: string, platform: string, id: string,
    parsedTitle: string, parsedArtist: string, meta: MediaBasicMeta, autoMatchCover: boolean): MusicItem {
    const item = new MusicItem();
    item.id = id;
    item.platform = platform;
    item.title = parsedTitle.length > 0 ? parsedTitle : (meta.title.length > 0 ? meta.title : FileUtils.getFileName(musicPath));
    item.artist = parsedArtist.length > 0 ? parsedArtist : (meta.artist.length > 0 ? meta.artist : '未知歌手');
    item.album = meta.album.length > 0 ? meta.album : '未知专辑';
    item.duration = meta.durationMs / 1000;
    // 封面：自动匹配开启时，优先文件内嵌封面；无内嵌封面时回退已下载记录/我的歌单中的平台封面
    // （下载文件名含 platform@id，可与 downloadedSheet 条目精确匹配；
    // 重装后已下载记录为空，再从恢复的歌单中找同曲目网络封面）
    let artwork = autoMatchCover ? meta.artwork : '';
    if (artwork.length === 0 && autoMatchCover) {
      const downloaded = downloadedSheet.isLocalMusic(item);
      if (downloaded !== null && downloaded.artwork.length > 0) {
        artwork = downloaded.artwork;
      }
    }
    if (artwork.length === 0 && autoMatchCover) {
      artwork = musicSheet.findArtworkEverywhere(item);
    }
    item.artwork = artwork;
    const extraRec: JsonRecord = {
      'localPath': musicPath,
    };
    item.extras[INTERNAL_SERIALIZE_KEY] = extraRec;
    return item;
  }

  onLocalSheetUpdated(cb: () => void): void {
    const wrapper: EventListenerFn = (_payload?: Object) => {
      cb();
    };
    this.ee.on(this.eventName, wrapper);
  }
}

/** 本地音乐（用户导入的音频） */
export const localMusicSheet = new LocalMusicSheet('LocalMusicSheet', 'UpdateLocalSheet');

/** 已下载（下载器产生 + 下载目录扫描），与本地音乐互不关联 */
export const downloadedSheet = new LocalMusicSheet('DownloadedSheet', 'UpdateDownloadedSheet');

// 两域互为 peer：删除源文件时同步移除两边记录
localMusicSheet.peer = downloadedSheet;
downloadedSheet.peer = localMusicSheet;
