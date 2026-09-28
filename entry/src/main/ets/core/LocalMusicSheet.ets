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
        // 过滤失效文件 + 同一物理文件（localPath 相同）只保留一条记录：
        // 文件被简洁命名/外部改名后，文件名不再含 platform@id，扫描会按 md5(路径)
        // 生成 local 平台新条目，与原平台记录重复，这里按路径去重并优先保留平台记录
        const validSheet: Array<MusicItem> = [];
        const keptByPath: Record<string, MusicItem> = {};
        for (const musicItem of sheet) {
          const localPath = MediaUtils.getLocalPath(musicItem);
          if (localPath === null || !FileUtils.exists(localPath)) {
            continue;
          }
          if (localPath.length === 0) {
            validSheet.push(musicItem);
            continue;
          }
          const pathKey = FileUtils.normalizePath(localPath);
          const kept = keptByPath[pathKey];
          if (kept === undefined) {
            keptByPath[pathKey] = musicItem;
            validSheet.push(musicItem);
          } else {
            const winner = LocalMusicSheet.pickPathDuplicate(kept, musicItem);
            if (winner === musicItem) {
              const idx = validSheet.indexOf(kept);
              if (idx !== -1) {
                validSheet[idx] = musicItem;
              }
              keptByPath[pathKey] = musicItem;
            }
            // kept 胜出：丢弃当前重复项
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

  /** 同一物理文件的多条记录中优先保留平台来源记录（platform@id 可关联歌单/已下载/播放历史） */
  private static pickPathDuplicate(a: MusicItem, b: MusicItem): MusicItem {
    const aLocal = a.platform === LOCAL_PLUGIN_PLATFORM;
    const bLocal = b.platform === LOCAL_PLUGIN_PLATFORM;
    if (aLocal !== bLocal) {
      return aLocal ? b : a;
    }
    return a;
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
      const newPath = MediaUtils.getLocalPath(mi);
      const newPathKey = newPath === null ? '' : FileUtils.normalizePath(newPath);
      // 对 newSheet 去重（而非 localSheetItems）：同一批次的重复扫描项互相可见，
      // 否则同批次内两条相同记录会同时入库（表现为数量偶发 +1，重启后被 setup 清理）
      for (const it of newSheet) {
        const oldPath = MediaUtils.getLocalPath(it);
        const oldPathKey = oldPath === null ? '' : FileUtils.normalizePath(oldPath);
        // 同曲目（platform@id 相同），或同一物理文件（本地路径相同）均视为已存在：
        // 简洁命名/外部改名后的文件名不含 platform@id，扫描生成的 id 与原记录不同，
        // 仅按 id 去重会重复入库，需按路径兜底；路径统一剥掉 file:// 前缀后比较
        // （存量记录 url 为 file:// 时 getLocalPath 返回裸路径，扫描项 extras 带
        // file:// 前缀，格式不一致会导致比较失败）
        if (MediaUtils.isSameMediaItem(it, mi) ||
          (newPathKey.length > 0 && newPathKey === oldPathKey)) {
          exists = true;
          // 旧条目无封面或封面文件已失效（如重装后缓存被清）、重新扫描提取到封面时补上
          if (mi.artwork.length > 0 &&
            (it.artwork.length === 0 || LocalMusicSheet.isDeadFileArtwork(it.artwork))) {
            it.artwork = mi.artwork;
            changed = true;
          }
          // 文件被移动后重新扫描：同曲目出现在新路径 → 更新本地路径（两域同步，
          // 保证文件夹分组标签与播放路径随文件实际位置刷新）
          if (newPath !== null && newPath.length > 0 && newPathKey !== oldPathKey &&
            FileUtils.exists(newPath)) {
            LocalMusicSheet.setItemLocalPath(it, newPath);
            changed = true;
            if (this.peer !== null) {
              this.peer.patchLocalPath(it, newPath);
            }
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

  /** 更新同曲目记录的本地路径（文件被移动后同步另一域记录） */
  patchLocalPath(musicItem: MusicItem, newLocalPath: string): void {
    for (const it of this.localSheetItems) {
      if (MediaUtils.isSameMediaItem(it, musicItem)) {
        LocalMusicSheet.setItemLocalPath(it, newLocalPath);
        this.saveLocalSheet();
        this.notify();
        return;
      }
    }
  }

  /** 写入条目内部记录的本地路径（file:// 前缀格式与扫描入库一致） */
  private static setItemLocalPath(item: MusicItem, newLocalPath: string): void {
    const extras = JsonUtil.cloneRecord(item.extras);
    const rec = JsonUtil.objToRecord(extras[INTERNAL_SERIALIZE_KEY]);
    const target: JsonRecord = rec === null ? {} : rec;
    target['localPath'] = newLocalPath;
    extras[INTERNAL_SERIALIZE_KEY] = target;
    item.extras = extras;
  }

  /**
   * 移动本地音乐文件到目标目录（物理移动 + 同步本域与另一域记录）。
   * 返回：0 = 移动成功，1 = 已在目标位置，2 = 失败（目标已存在同名文件/无本地路径等）
   */
  moveLocalMusic(musicItem: MusicItem, destDir: string): number {
    let idx = -1;
    for (let i = 0; i < this.localSheetItems.length; ++i) {
      if (MediaUtils.isSameMediaItem(this.localSheetItems[i], musicItem)) {
        idx = i;
        break;
      }
    }
    if (idx === -1) {
      return 2;
    }
    const item = this.localSheetItems[idx];
    const localPath = MediaUtils.getLocalPath(item);
    if (localPath === null || localPath.length === 0) {
      return 2;
    }
    const srcPath = FileUtils.normalizePath(localPath);
    const fileName = FileUtils.getFileName(srcPath);
    const dir = destDir.endsWith('/') ? destDir : destDir + '/';
    const destPath = dir + fileName;
    if (srcPath === destPath) {
      return 1;
    }
    // 目标已存在同名文件：不覆盖，视为失败
    if (FileUtils.exists(destPath)) {
      return 2;
    }
    if (!FileUtils.moveFile(srcPath, destPath)) {
      return 2;
    }
    const destSchemePath = FileUtils.addFileScheme(destPath);
    LocalMusicSheet.setItemLocalPath(item, destSchemePath);
    this.saveLocalSheet();
    this.notify();
    if (this.peer !== null) {
      this.peer.patchLocalPath(item, destSchemePath);
    }
    return 0;
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

  /** 是否为本地音乐且本地文件仍存在（文件被外部删除时视为非本地，供下载拦截判断用） */
  isLocalMusicExisting(musicItem: MusicItem | null): MusicItem | null {
    const matched = this.isLocalMusic(musicItem);
    if (matched === null) {
      return null;
    }
    const localPath = MediaUtils.getLocalPath(matched);
    return localPath !== null && FileUtils.exists(localPath) ? matched : null;
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
    // 先清理本地路径已失效的记录（文件被移动/外部删除后，旧记录与新路径记录
    // 会以相同标题并存形成假重复，扫描时即时清理与启动时 setup 同口径）
    this.pruneDeadRecords();
    const musicList = this.collectMusicStats(folderPaths, token, filenameFilter);
    if (this.importToken !== token) {
      return Promise.reject(new Error('Import Broken'));
    }
    // 已入库且元信息已验证的文件跳过重新提取，重复扫描只遍历目录，速度接近瞬时；
    // 新文件与未验证的本地记录（历史并发串读产生的脏数据）仍需逐个串行提取：
    // AVMetadataExtractor 共享原生解析服务，并发多实例存在元数据串读
    // （A 文件读到 B 文件的标题/封面），必须串行提取保证条目与实际文件对应
    const knownByPath: Record<string, MusicItem> = {};
    for (const it of this.localSheetItems) {
      const lp = MediaUtils.getLocalPath(it);
      if (lp !== null && lp.length > 0) {
        knownByPath[FileUtils.normalizePath(lp)] = it;
      }
    }
    const metas: Array<MediaBasicMeta> = [];
    /** 该文件是否真实执行了元信息提取（false = 已入库跳过，meta 为空占位） */
    const extractedFlags: Array<boolean> = [];
    const needMeta = (index: number): boolean => {
      const existing = knownByPath[FileUtils.normalizePath(musicList[index])];
      if (existing === undefined) {
        return true;
      }
      // 本地记录未经修复后的流程验证过：需提取一次以刷新可能串读脏数据
      if (existing.platform === LOCAL_PLUGIN_PLATFORM && !LocalMusicSheet.metaVerified(existing)) {
        return true;
      }
      // 封面缺失/失效且开启自动匹配：需提取内嵌封面回填
      if (autoMatchCover &&
        (existing.artwork.length === 0 || LocalMusicSheet.isDeadFileArtwork(existing.artwork))) {
        return true;
      }
      return false;
    };
    const collectMetas = (index: number): Promise<void> => {
      if (index >= musicList.length) {
        if (this.importToken !== token) {
          return Promise.reject(new Error('Import Broken'));
        }
        return Promise.resolve();
      }
      if (this.importToken !== token) {
        return Promise.reject(new Error('Import Broken'));
      }
      const onMeta = (m: MediaBasicMeta, extracted: boolean): Promise<void> => {
        metas.push(m);
        extractedFlags.push(extracted);
        return collectMetas(index + 1);
      };
      if (!needMeta(index)) {
        return onMeta(new MediaBasicMeta(), false);
      }
      return MediaMetadata.getBasicMeta(FileUtils.normalizePath(musicList[index]), autoMatchCover)
        .then((m: MediaBasicMeta): Promise<void> => onMeta(m, true));
    };
    return collectMetas(0).then((): Promise<void> => {
      if (this.importToken !== token) {
        throw new Error('Import Broken');
      }
      // 修复历史脏数据：本地记录用重新提取的真实标签刷新标题/歌手/专辑/时长
      const healed = this.healLocalRecords(knownByPath, musicList, metas, extractedFlags);
      // 仅新文件与重新提取过元信息的文件需要构建条目入库；
      // 已入库且无需提取的文件直接跳过，避免无谓的 md5/封面回查
      const buildTasks: Array<Promise<MusicItem>> = [];
      for (let index = 0; index < musicList.length; ++index) {
        if (extractedFlags[index] ||
          knownByPath[FileUtils.normalizePath(musicList[index])] === undefined) {
          buildTasks.push(LocalMusicSheet.buildMusicItem(musicList[index], metas[index], autoMatchCover));
        }
      }
      return Promise.all(buildTasks).then((musicItems: Array<MusicItem>): Promise<void> => {
        if (this.importToken !== token) {
          throw new Error('Import Broken');
        }
        return this.addMusic(musicItems).then((): void => {
          // addMusic 未变更时，修复的历史记录需单独落盘并通知刷新
          if (healed) {
            this.saveLocalSheet();
            this.notify();
          }
        });
      });
    });
  }

  /** 清理本地路径已失效的记录（content:// 等外部 URI 不清理） */
  private pruneDeadRecords(): void {
    if (this.localSheetItems.length === 0) {
      return;
    }
    const kept: Array<MusicItem> = [];
    let changed = false;
    for (const it of this.localSheetItems) {
      const lp = MediaUtils.getLocalPath(it);
      if (lp !== null && lp.length > 0 && !lp.startsWith('content://') && !FileUtils.exists(lp)) {
        changed = true;
        continue;
      }
      kept.push(it);
    }
    if (changed) {
      this.saveItems(kept);
      this.localSheetItems = kept;
      this.notify();
    }
  }

  /**
   * 用重新提取的真实标签刷新本地平台记录（修复历史并发串读持久化的脏数据：
   * 条目标题/歌手与实际文件不符、列表出现假重复歌名）；返回是否有修改。
   * 仅刷新本地平台记录（platform@id 记录的标题来自在线元数据，不覆盖）；
   * 标签为空的字段保持原值，标题为空时回退文件名（与入库规则一致）
   */
  private healLocalRecords(knownByPath: Record<string, MusicItem>, musicList: Array<string>,
    metas: Array<MediaBasicMeta>, extractedFlags: Array<boolean>): boolean {
    let changed = false;
    for (let index = 0; index < musicList.length; ++index) {
      if (!extractedFlags[index]) {
        continue;
      }
      const existing = knownByPath[FileUtils.normalizePath(musicList[index])];
      if (existing === undefined || existing.platform !== LOCAL_PLUGIN_PLATFORM) {
        continue;
      }
      const meta = metas[index];
      if (meta.title.length > 0) {
        if (existing.title !== meta.title) {
          existing.title = meta.title;
          changed = true;
        }
      } else {
        // 无标签：标题按入库规则回退为文件名（去扩展名）
        const fallbackTitle = FileUtils.getFileName(musicList[index], true);
        if (existing.title !== fallbackTitle) {
          existing.title = fallbackTitle;
          changed = true;
        }
      }
      if (meta.artist.length > 0 && existing.artist !== meta.artist) {
        existing.artist = meta.artist;
        changed = true;
      }
      if (meta.album.length > 0 && existing.album !== meta.album) {
        existing.album = meta.album;
        changed = true;
      }
      if (meta.durationMs > 0 && Math.abs(existing.duration - meta.durationMs / 1000) > 1) {
        existing.duration = meta.durationMs / 1000;
        changed = true;
      }
      if (!LocalMusicSheet.metaVerified(existing)) {
        LocalMusicSheet.markMetaVerified(existing);
        changed = true;
      }
    }
    return changed;
  }

  /** 记录是否已经过修复后提取流程的元信息验证 */
  private static metaVerified(item: MusicItem): boolean {
    const rec = JsonUtil.objToRecord(item.extras[INTERNAL_SERIALIZE_KEY]);
    return rec !== null && JsonUtil.recNum(rec, 'metaVerified') === 1;
  }

  /** 标记记录元信息已验证（后续扫描跳过重新提取） */
  private static markMetaVerified(item: MusicItem): void {
    const extras = JsonUtil.cloneRecord(item.extras);
    const rec = JsonUtil.objToRecord(extras[INTERNAL_SERIALIZE_KEY]);
    const target: JsonRecord = rec === null ? {} : rec;
    target['metaVerified'] = 1;
    extras[INTERNAL_SERIALIZE_KEY] = target;
    item.extras = extras;
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
    item.title = parsedTitle.length > 0 ? parsedTitle : (meta.title.length > 0 ? meta.title : FileUtils.getFileName(musicPath, true));
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
      // 元信息已经过串行提取流程验证（历史并发串读脏数据修复标记）
      'metaVerified': 1,
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
