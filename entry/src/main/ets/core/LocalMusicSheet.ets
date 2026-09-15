import { KVStore } from '../infra/KVStore';
import { JsonUtil, JsonRecord } from '../common/JsonUtil';
import { EventEmitter, EventListenerFn } from '../common/EventBus';
import { INTERNAL_SERIALIZE_KEY, LOCAL_PLUGIN_PLATFORM, SUPPORT_LOCAL_MEDIA_TYPE } from '../common/Consts';
import { MusicItem } from '../common/model/MediaTypes';
import { MediaUtils } from '../utils/MediaUtils';
import { FileUtils } from '../utils/FileUtils';
import { CryptoUtil } from '../utils/CryptoUtil';
import { MediaMetadata, MediaBasicMeta } from '../utils/MediaMetadata';

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
 */
export class LocalMusicSheet {
  private localSheetItems: Array<MusicItem> = [];
  private ee: EventEmitter = new EventEmitter();
  private importToken: string | null = null;

  private getStore(): KVStore {
    return KVStore.getOrCreate('storage');
  }

  get musicList(): Array<MusicItem> {
    return this.localSheetItems;
  }

  setup(): Promise<void> {
    const task = (): Promise<void> => {
      const raw = this.getStore().get('LocalMusicSheet');
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
      this.ee.emit('UpdateLocalSheet', new LocalSheetUpdatedEvent());
      return Promise.resolve();
    };
    return task();
  }

  private saveItems(items: Array<MusicItem>): void {
    const arr: Array<JsonRecord> = [];
    for (const it of items) {
      arr.push(it.toPersistRecord());
    }
    this.getStore().set('LocalMusicSheet', JSON.stringify(arr));
  }

  private notify(): void {
    this.ee.emit('UpdateLocalSheet', new LocalSheetUpdatedEvent());
  }

  /** 添加本地音乐（去重） */
  addMusic(musicItem: MusicItem | Array<MusicItem>): Promise<void> {
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
    this.saveItems(newSheet);
    this.localSheetItems = newSheet;
    this.notify();
    return Promise.resolve();
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
   * 遍历目录收集本地音频（保留 file:// 前缀）
   */
  private collectMusicStats(folderPaths: Array<string>, token: string): Array<string> {
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
        } else if (LocalMusicSheet.localMediaFilter(child)) {
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
   * 导入本地音乐
   */
  importLocal(_folderPaths: Array<string>): Promise<void> {
    const folderPaths: Array<string> = [];
    for (const it of _folderPaths) {
      folderPaths.push(FileUtils.addFileScheme(it));
    }
    const token = CryptoUtil.nanoid();
    this.importToken = token;
    const musicList = this.collectMusicStats(folderPaths, token);
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
        tasks.push(MediaMetadata.getBasicMeta(FileUtils.normalizePath(p)));
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
        buildTasks.push(LocalMusicSheet.buildMusicItem(musicList[index], metas[index]));
      }
      return Promise.all(buildTasks);
    }).then((musicItems: Array<MusicItem>) => {
      if (this.importToken !== token) {
        throw new Error('Import Broken');
      }
      this.addMusic(musicItems);
    });
  }

  private static buildMusicItem(musicPath: string, meta: MediaBasicMeta): Promise<MusicItem> {
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
        return LocalMusicSheet.assembleMusicItem(musicPath, platform, hash, title, artist, meta);
      });
    }
    return Promise.resolve(LocalMusicSheet.assembleMusicItem(musicPath, platform, id, title, artist, meta));
  }

  private static assembleMusicItem(musicPath: string, platform: string, id: string,
    parsedTitle: string, parsedArtist: string, meta: MediaBasicMeta): MusicItem {
    const item = new MusicItem();
    item.id = id;
    item.platform = platform;
    item.title = parsedTitle.length > 0 ? parsedTitle : (meta.title.length > 0 ? meta.title : FileUtils.getFileName(musicPath));
    item.artist = parsedArtist.length > 0 ? parsedArtist : (meta.artist.length > 0 ? meta.artist : '未知歌手');
    item.album = meta.album.length > 0 ? meta.album : '未知专辑';
    item.duration = meta.durationMs / 1000;
    item.artwork = '';
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
    this.ee.on('UpdateLocalSheet', wrapper);
  }
}

export const localMusicSheet = new LocalMusicSheet();
