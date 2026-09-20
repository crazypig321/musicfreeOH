import { EventEmitter, EventListenerFn } from '../common/EventBus';
import { INTERNAL_SERIALIZE_KEY, SUPPORT_LOCAL_MEDIA_TYPE } from '../common/Consts';
import { PathConst } from '../common/PathConst';
import { JsonUtil, JsonRecord } from '../common/JsonUtil';
import { MusicItem, MediaSource, QualityKey, qualityFromStr } from '../common/model/MediaTypes';
import { MediaUtils } from '../utils/MediaUtils';
import { FileUtils } from '../utils/FileUtils';
import { Qualities } from '../utils/Qualities';
import { Network, NetworkState } from '../infra/Network';
import { HttpClient } from '../infra/HttpClient';
import { KVStore } from '../infra/KVStore';
import { Log } from '../utils/Log';
import { Delay } from '../utils/Delay';
import { appConfig } from './AppConfig';
import { localMusicSheet, downloadedSheet } from './LocalMusicSheet';
import { musicSheet } from './MusicSheet';
import { LocalMusicExclusion } from './LocalMusicExclusion';
import { MediaExtra, MediaExtraProperties } from './MediaExtra';
import { pluginManager } from '../plugin/PluginManager';
import { BackgroundTask } from '../utils/BackgroundTask';
import { DownloadNotify } from '../utils/DownloadNotify';

/** 下载状态 */
export enum DownloadStatus {
  /** 等待下载 */
  Pending,
  /** 准备下载链接 */
  Preparing,
  /** 下载中 */
  Downloading,
  /** 下载完成 */
  Completed,
  /** 下载失败 */
  Error,
}

export class DownloaderEvent {
  static readonly DOWNLOAD_ERROR = 'download-error';
  static readonly DOWNLOAD_TASK_UPDATE = 'download-task-update';
  static readonly DOWNLOAD_TASK_ERROR = 'download-task-error';
  static readonly DOWNLOAD_QUEUE_COMPLETED = 'download-queue-completed';
}

export class DownloadFailReason {
  /** 无网络 */
  static readonly NETWORK_OFFLINE = 'network-offline';
  /** 设置-禁止在移动网络下下载 */
  static readonly NOT_ALLOW_TO_DOWNLOAD_IN_CELLULAR = 'not-allow-to-download-in-cellular';
  /** 无法获取到媒体源 */
  static readonly FAIL_TO_FETCH_SOURCE = 'no-valid-source';
  /** 没有文件写入的权限 */
  static readonly NO_WRITE_PERMISSION = 'no-write-permission';
  static readonly UNKNOWN = 'unknown';
}

/** 下载任务信息 */
export class DownloadTaskInfo {
  status: DownloadStatus = DownloadStatus.Pending;
  /** 目标文件名 */
  filename: string = '';
  /** 断点续传缓存文件名（downloadCachePath 下，platform@id.ext 固定命名） */
  cacheFilename: string = '';
  /** 下载音质 */
  quality?: QualityKey;
  /** 文件大小 */
  fileSize: number = 0;
  /** 已下载大小 */
  downloadedSize: number = 0;
  /** 音乐信息 */
  musicItem: MusicItem = new MusicItem();
  /** 下载发起时歌曲所在的用户歌单名（已下载「来源歌单」分组标签用） */
  originSheets: string = '';
  /** 下载目标子文件夹名（空 = 下载目录根） */
  folder: string = '';
  /** 下载失败的原因 */
  errorReason: string = '';
}

/** 下载行为出错事件 */
export class DownloadErrorEvent {
  reason: string = DownloadFailReason.UNKNOWN;
  message: string = '';
}

/** 下载单个音乐出错事件 */
export class DownloadTaskErrorEvent {
  reason: string = DownloadFailReason.UNKNOWN;
  musicItem: MusicItem = new MusicItem();
  message: string = '';
}

/** 下载任务更新事件 */
export class DownloadTaskUpdateEvent {
  task: DownloadTaskInfo = new DownloadTaskInfo();
}

/** 下载队列清空事件 */
export class DownloadQueueCompletedEvent {
}

/**
 * 下载管理（移植自 core/downloader.ts）
 * react-native-fs 的 downloadFile 由 HttpClient.downloadToFile 承担
 */
export class Downloader {
  private ee: EventEmitter = new EventEmitter();
  private downloadQueue: Array<MusicItem> = [];
  private downloadTasks: Map<string, DownloadTaskInfo> = new Map();
  private downloadingCount: number = 0;
  /** 本批次统计（通知栏摘要用）：批次 = 队列从空转运行到再次清空 */
  private batchActive: boolean = false;
  private batchDone: number = 0;
  private batchFailed: number = 0;

  /** 队列全部结束：释放数据传输长时任务并弹出结果摘要通知 */
  private finishBatch(): void {
    this.batchActive = false;
    BackgroundTask.stopTransfer();
    DownloadNotify.showSummary(this.batchDone, this.batchFailed);
  }

  // ---------- 任务持久化（KVStore 'Downloader'：重启后恢复失败/未完成任务并断点续传） ----------

  private static readonly STORE_NAME = 'Downloader';
  private static readonly QUEUE_KEY = 'queue';
  private static readonly TASK_KEY_PREFIX = 'task.';
  /** 进度落盘节流定时器（进度高频变化，节流避免频繁写 preferences） */
  private persistProgressTimer: number = -1;

  private taskStore(): KVStore {
    return KVStore.getOrCreate(Downloader.STORE_NAME);
  }

  private taskRecordKey(key: string): string {
    return Downloader.TASK_KEY_PREFIX + key;
  }

  /** 落盘单个任务记录 */
  private saveTaskRecord(task: DownloadTaskInfo): void {
    const rec: JsonRecord = {
      'status': task.status,
      'filename': task.filename,
      'cacheFilename': task.cacheFilename,
      'fileSize': task.fileSize,
      'downloadedSize': task.downloadedSize,
      'errorReason': task.errorReason,
      'originSheets': task.originSheets,
      'folder': task.folder,
      'musicItem': task.musicItem.toPersistRecord()
    };
    if (task.quality !== undefined) {
      rec['quality'] = task.quality;
    }
    this.taskStore().set(this.taskRecordKey(MediaUtils.getMediaUniqueKey(task.musicItem)),
      JsonUtil.safeStringify(rec));
  }

  /** 删除任务记录 */
  private deleteTaskRecord(key: string): void {
    this.taskStore().delete(this.taskRecordKey(key));
  }

  /** 落盘队列顺序（恢复时保持原有排序） */
  private saveQueueOrder(): void {
    const keys: Array<string> = [];
    for (const item of this.downloadQueue) {
      keys.push(MediaUtils.getMediaUniqueKey(item));
    }
    this.taskStore().set(Downloader.QUEUE_KEY, JsonUtil.safeStringify(keys));
  }

  /** 节流落盘进行中任务的进度（重启后 UI 可显示上次进度；续传基线以实际文件大小为准） */
  private schedulePersistProgress(): void {
    if (this.persistProgressTimer !== -1) {
      return;
    }
    this.persistProgressTimer = setTimeout(() => {
      this.persistProgressTimer = -1;
      for (const task of this.downloadTasks.values()) {
        if (task.status === DownloadStatus.Pending || task.status === DownloadStatus.Preparing ||
          task.status === DownloadStatus.Downloading) {
          this.saveTaskRecord(task);
        }
      }
    }, 1000);
  }

  /** 解析任务记录 */
  private static parseTaskRecord(raw: string): DownloadTaskInfo | null {
    const rec = JsonUtil.parseRecord(raw);
    if (rec === null) {
      return null;
    }
    const itemRec = JsonUtil.recRecord(rec, 'musicItem');
    if (itemRec === null) {
      return null;
    }
    const musicItem = MusicItem.fromRecord(itemRec);
    if (musicItem.platform.length === 0 || musicItem.id.length === 0) {
      return null;
    }
    const task = new DownloadTaskInfo();
    task.musicItem = musicItem;
    const status = JsonUtil.recNum(rec, 'status', -1);
    if (status === DownloadStatus.Pending || status === DownloadStatus.Preparing ||
      status === DownloadStatus.Downloading || status === DownloadStatus.Error) {
      task.status = status;
    } else {
      return null;
    }
    task.filename = JsonUtil.recStr(rec, 'filename');
    task.cacheFilename = JsonUtil.recStr(rec, 'cacheFilename');
    task.fileSize = JsonUtil.recNum(rec, 'fileSize');
    task.downloadedSize = JsonUtil.recNum(rec, 'downloadedSize');
    task.errorReason = JsonUtil.recStr(rec, 'errorReason');
    task.originSheets = JsonUtil.recStr(rec, 'originSheets');
    task.folder = JsonUtil.recStr(rec, 'folder');
    const quality = JsonUtil.recStr(rec, 'quality');
    if (quality.length > 0) {
      task.quality = qualityFromStr(quality, 'high');
    }
    return task;
  }

  /** 清理任务的续传缓存半成品 */
  private removeTaskCache(task: DownloadTaskInfo): void {
    if (task.cacheFilename.length > 0) {
      FileUtils.unlink(this.getCacheDownloadPath(task.cacheFilename));
    }
  }

  /**
   * 启动时恢复持久化的下载任务（EntryAbility onCreate 调用）：
   * 失败任务原样恢复（可批量换源/重新下载），中断/等待中的任务恢复为待下载，
   * 网络可用时自动续跑（断点续传），流量受限时待网络恢复后续跑
   */
  restorePersistedTasks(): void {
    const store = this.taskStore();
    // 任务记录
    const records: Map<string, DownloadTaskInfo> = new Map();
    for (const k of store.getAllKeys()) {
      if (k.indexOf(Downloader.TASK_KEY_PREFIX) !== 0) {
        continue;
      }
      const task = Downloader.parseTaskRecord(store.get(k));
      if (task !== null) {
        records.set(k.substring(Downloader.TASK_KEY_PREFIX.length), task);
      }
    }
    if (records.size === 0) {
      return;
    }
    // 按持久化的队列顺序恢复，顺序之外的残留记录追加在末尾
    const ordered: Array<string> = [];
    const orderRaw = JsonUtil.parseStringArray(store.get(Downloader.QUEUE_KEY));
    if (orderRaw !== null) {
      for (const key of orderRaw) {
        if (records.has(key)) {
          ordered.push(key);
          records.delete(key);
        }
      }
    }
    const restKeys: Array<string> = [];
    records.forEach((_task: DownloadTaskInfo, key: string) => {
      restKeys.push(key);
    });
    for (const key of restKeys) {
      ordered.push(key);
      records.delete(key);
    }
    let resumable = 0;
    for (const key of ordered) {
      const task = this.downloadTasks.has(key) ? null : Downloader.parseTaskRecord(store.get(this.taskRecordKey(key)));
      if (task === null || this.downloadTasks.has(key)) {
        continue;
      }
      if (task.status !== DownloadStatus.Error) {
        // 中断/等待中的任务恢复为待下载（半成品缓存保留，下载时断点续传）
        task.status = DownloadStatus.Pending;
        resumable++;
      }
      this.downloadTasks.set(key, task);
      this.downloadQueue.push(task.musicItem);
    }
    Log.info('恢复下载任务: ' + this.downloadQueue.length.toString() + ' 个（可续跑 ' + resumable.toString() + '）');
    this.saveQueueOrder();
    if (resumable > 0) {
      // 网络可用立即续跑；受限时等网络状态变化（如连上 Wi-Fi）自动续跑
      Network.getInstance().onStateChanged((_state: NetworkState) => {
        this.tryResumeQueue();
      });
      this.tryResumeQueue();
    }
  }

  /** 网络可用时自动续跑待下载任务（离线/流量受限不动，等下次网络变化） */
  private tryResumeQueue(): void {
    if (this.downloadingCount > 0) {
      return;
    }
    let hasPending = false;
    for (const task of this.downloadTasks.values()) {
      if (task.status === DownloadStatus.Pending) {
        hasPending = true;
        break;
      }
    }
    if (!hasPending) {
      return;
    }
    const net = Network.getInstance();
    if (net.isOffline) {
      return;
    }
    if (net.isCellular && !appConfig.getUseCellularNetworkDownload()) {
      return;
    }
    if (!this.batchActive) {
      this.batchActive = true;
      this.batchDone = 0;
      this.batchFailed = 0;
      DownloadNotify.resetProgress();
    }
    DownloadNotify.ensureEnabled();
    BackgroundTask.startTransfer((notificationId: number): void => {
      DownloadNotify.setSystemNotificationId(notificationId);
    });
    Downloader.ensureDownloadDirResolved().then(() => {
      this.downloadNextPendingTask();
    });
  }

  /** 确保公共下载目录就绪后再启动下载队列（目录缺失时由 bootstrap 自动重建） */
  private static async ensureDownloadDirResolved(): Promise<void> {
    await PathConst.bootstrapPublicDownloadDir();
  }

  private static generateFilename(musicItem: MusicItem): string {
    const name = `${FileUtils.escapeCharacter(musicItem.platform)}@${FileUtils.escapeCharacter(musicItem.id)}` +
      `@${FileUtils.escapeCharacter(musicItem.title)}@${FileUtils.escapeCharacter(musicItem.artist)}`;
    return name.slice(0, 200);
  }

  /** 记录下载发起时歌曲所在的用户歌单（已下载「来源歌单」分组标签用） */
  private static collectOriginSheets(item: MusicItem): string {
    try {
      for (const sheet of musicSheet.sheets) {
        const list = musicSheet.getMusicList(sheet.id);
        for (const it of list) {
          if (MediaUtils.isSameMediaItem(it, item)) {
            return sheet.title;
          }
        }
      }
    } catch (e) {
    }
    return '';
  }

  getDownloadQueue(): Array<MusicItem> {
    return this.downloadQueue;
  }

  getDownloadTask(musicItem: MusicItem): DownloadTaskInfo | null {
    return this.downloadTasks.get(MediaUtils.getMediaUniqueKey(musicItem)) ?? null;
  }

  private updateTaskStatus(musicItem: MusicItem, status: DownloadStatus): DownloadTaskInfo {
    return this.updateDownloadTask(musicItem, status, -1, -1);
  }

  private updateDownloadTask(musicItem: MusicItem, status: DownloadStatus,
    downloadedSize: number, fileSize: number): DownloadTaskInfo {
    const key = MediaUtils.getMediaUniqueKey(musicItem);
    let task = this.downloadTasks.get(key);
    if (task === undefined) {
      task = new DownloadTaskInfo();
      task.musicItem = musicItem;
      this.downloadTasks.set(key, task);
    }
    task.status = status;
    if (downloadedSize >= 0) {
      task.downloadedSize = downloadedSize;
    }
    if (fileSize >= 0) {
      task.fileSize = fileSize;
    }
    if (status === DownloadStatus.Downloading && task.fileSize > 0) {
      // 通知栏进度（节流由 DownloadNotify 控制）
      const percent = Math.min(100, Math.floor(task.downloadedSize / task.fileSize * 100));
      const songText = `${task.musicItem.title} - ${task.musicItem.artist}`;
      DownloadNotify.updateProgress(songText, percent, this.downloadQueue.length);
      // 进度节流落盘（重启后可见上次进度）
      this.schedulePersistProgress();
    }
    this.emitTaskUpdate(task);
    return task;
  }

  private emitTaskUpdate(task: DownloadTaskInfo): void {
    const ev = new DownloadTaskUpdateEvent();
    ev.task = task;
    this.ee.emit(DownloaderEvent.DOWNLOAD_TASK_UPDATE, ev);
  }

  private markTaskAsStarted(musicItem: MusicItem): void {
    this.downloadingCount++;
    const task = this.updateTaskStatus(musicItem, DownloadStatus.Preparing);
    this.saveTaskRecord(task);
  }

  /** 上一个任务的实际启动时刻（任务间隔节流用） */
  private lastTaskStartAt: number = 0;

  /** 任务间隔节流：先预留下一个启动时刻（并发调用依次错开），再等待到点；间隔 0 直接返回 */
  private async waitTaskInterval(): Promise<void> {
    const intervalMs = Math.max(0, appConfig.getDownloadTaskInterval()) * 1000;
    if (intervalMs === 0) {
      return;
    }
    const now = Date.now();
    const startAt = Math.max(now, this.lastTaskStartAt + intervalMs);
    this.lastTaskStartAt = startAt;
    const waitMs = startAt - now;
    if (waitMs > 0) {
      await Delay.wait(waitMs);
    }
  }

  private markTaskAsCompleted(musicItem: MusicItem): void {
    this.downloadingCount--;
    this.batchDone++;
    this.updateTaskStatus(musicItem, DownloadStatus.Completed);
  }

  private markTaskAsError(musicItem: MusicItem, reason: string, message: string): void {
    this.downloadingCount--;
    this.batchFailed++;
    const key = MediaUtils.getMediaUniqueKey(musicItem);
    let task = this.downloadTasks.get(key);
    if (task === undefined) {
      task = new DownloadTaskInfo();
      task.musicItem = musicItem;
      this.downloadTasks.set(key, task);
    }
    task.status = DownloadStatus.Error;
    task.errorReason = reason;
    this.saveTaskRecord(task);
    this.emitTaskUpdate(task);
    const ev = new DownloadTaskErrorEvent();
    ev.reason = reason;
    ev.musicItem = musicItem;
    ev.message = message;
    this.ee.emit(DownloaderEvent.DOWNLOAD_TASK_ERROR, ev);
  }

  /** 匹配文件后缀 */
  private getExtensionName(url: string): string {
    const regResult = url.match(/^https?\:\/\/.+\.([^\?\.]+?$)|(?:([^\.]+?)\?.+$)/);
    if (regResult !== null) {
      const g1 = regResult[1];
      if (typeof g1 === 'string' && g1.length > 0) {
        return g1;
      }
      const g2 = regResult[2];
      if (typeof g2 === 'string' && g2.length > 0) {
        return g2;
      }
      return 'mp3';
    }
    return 'mp3';
  }

  /** 获取下载路径（folder 为下载目录下的子文件夹名，空 = 根） */
  private getDownloadPath(fileName: string, folder: string): string {
    const dlPath = appConfig.getDownloadPath();
    const base = dlPath.endsWith('/') ? dlPath : dlPath + '/';
    if (folder.length > 0) {
      return `${base}${folder}/${fileName}`;
    }
    return base + fileName;
  }

  /** 获取缓存的下载路径 */
  private getCacheDownloadPath(fileName: string): string {
    const cachePath = PathConst.downloadCachePath;
    if (!cachePath.endsWith('/')) {
      return `${cachePath}/${fileName}`;
    }
    return cachePath + fileName;
  }

  /** 从 item extras 中收集下载请求头 */
  private static collectHeaders(track: MusicItem): Record<string, string> {
    const headers: Record<string, string> = {};
    const headersRec = JsonUtil.objToRecord(track.extras['headers']);
    if (headersRec !== null) {
      for (const k of Object.keys(headersRec)) {
        const v = headersRec[k];
        if (typeof v === 'string' && v.length > 0) {
          headers[k] = v;
        }
      }
    }
    return headers;
  }

  private async downloadNextPendingTask(): Promise<void> {
    const maxDownloadCount = Math.max(1, Math.min(appConfig.getMaxDownload(), 10));
    if (this.downloadingCount >= maxDownloadCount || this.downloadingCount >= this.downloadQueue.length) {
      return;
    }

    let nextTask: DownloadTaskInfo | null = null;
    for (let i = 0; i < this.downloadQueue.length; i++) {
      const musicItem = this.downloadQueue[i];
      const key = MediaUtils.getMediaUniqueKey(musicItem);
      const task = this.downloadTasks.get(key);
      if (task !== undefined && task.status === DownloadStatus.Pending) {
        nextTask = task;
        break;
      }
    }

    if (nextTask === null) {
      if (this.downloadingCount === 0) {
        this.finishBatch();
        this.ee.emit(DownloaderEvent.DOWNLOAD_QUEUE_COMPLETED, new DownloadQueueCompletedEvent());
      }
      return;
    }

    const musicItem = nextTask.musicItem;
    this.markTaskAsStarted(musicItem);
    // 任务间隔：错开各任务的启动时刻，避免集中请求音源接口
    await this.waitTaskInterval();

    let url = musicItem.url;
    let headers: Record<string, string> = Downloader.collectHeaders(musicItem);

    const plugin = pluginManager.getByName(musicItem.platform);

    try {
      if (plugin !== null) {
        const qualityOrder = Qualities.getQualityOrder(
          nextTask.quality ?? appConfig.getDefaultDownloadQuality(),
          appConfig.getDownloadQualityOrder()
        );
        let data: MediaSource | null = null;
        for (const quality of qualityOrder) {
          try {
            const src = await plugin.methods.getMediaSource(musicItem, quality, 1, true);
            if (src === null || src.url.length === 0) {
              continue;
            }
            data = src;
            break;
          } catch (e) {
          }
        }
        url = data === null ? url : data.url;
        if (data !== null && Object.keys(data.headers).length > 0) {
          headers = data.headers;
        }
      }
      if (url.length === 0) {
        throw new Error(DownloadFailReason.FAIL_TO_FETCH_SOURCE);
      }
    } catch (e) {
      Log.error('下载失败-无法获取下载链接: ' + musicItem.title);
      const message = e instanceof Error ? e.message : '';
      if (message === DownloadFailReason.FAIL_TO_FETCH_SOURCE) {
        this.markTaskAsError(musicItem, DownloadFailReason.FAIL_TO_FETCH_SOURCE, message);
      } else {
        this.markTaskAsError(musicItem, DownloadFailReason.UNKNOWN, message);
      }
      this.downloadNextPendingTask();
      return;
    }

    this.downloadNextPendingTask();

    let extension = this.getExtensionName(url);
    if (SUPPORT_LOCAL_MEDIA_TYPE.every((item: string): boolean => item !== '.' + extension)) {
      extension = 'mp3';
    }

    // 断点续传：缓存文件固定命名（platform@id.ext），重试/重启后继续同一半成品
    if (nextTask.cacheFilename.length === 0) {
      nextTask.cacheFilename =
        `${FileUtils.escapeCharacter(musicItem.platform)}@${FileUtils.escapeCharacter(musicItem.id)}.${extension}`;
      this.saveTaskRecord(nextTask);
    }
    const cacheDownloadPath = FileUtils.addFileScheme(
      this.getCacheDownloadPath(nextTask.cacheFilename)
    );
    const targetDownloadPath = FileUtils.addFileScheme(
      this.getDownloadPath(`${nextTask.filename}.${extension}`, nextTask.folder)
    );

    if (!FileUtils.exists(FileUtils.getDirectory(targetDownloadPath))) {
      FileUtils.checkAndCreateDir(FileUtils.getDirectory(targetDownloadPath));
      if (!FileUtils.exists(FileUtils.getDirectory(targetDownloadPath))) {
        this.markTaskAsError(musicItem, DownloadFailReason.NO_WRITE_PERMISSION, '');
        this.downloadNextPendingTask();
        return;
      }
    }

    // 半成品缓存有效时断点续传（带上次已知总大小校验内容一致性）
    let resumeFrom = 0;
    const partialSize = FileUtils.fileSize(FileUtils.normalizePath(cacheDownloadPath));
    if (partialSize > 0 && nextTask.fileSize > 0 && partialSize < nextTask.fileSize) {
      resumeFrom = partialSize;
      Log.info('断点续传: ' + musicItem.title + ' 从 ' + partialSize.toString() + ' 字节继续');
    }
    const ok = await HttpClient.downloadToFile(url, cacheDownloadPath, headers,
      (downloadedSize: number, totalSize: number): void => {
        this.updateDownloadTask(musicItem, DownloadStatus.Downloading, downloadedSize, totalSize);
      }, resumeFrom, nextTask.fileSize);

    if (ok) {
      const copied = FileUtils.copyFile(cacheDownloadPath, targetDownloadPath);
      // 下载完成清理半成品缓存（失败时保留待续传）
      FileUtils.unlink(cacheDownloadPath);
      if (!copied) {
        this.markTaskAsError(musicItem, DownloadFailReason.NO_WRITE_PERMISSION, '');
      } else {
        const localItem = musicItem.clone();
        const extras = JsonUtil.cloneRecord(musicItem.extras);
        // 内部记录：本地路径 + 下载完成时间 + 来源歌单（已下载分组标签用）
        const internalRec: JsonRecord = {
          'localPath': targetDownloadPath,
          'downloadedAt': Date.now(),
          'downloadOrigin': nextTask.originSheets
        };
        extras[INTERNAL_SERIALIZE_KEY] = internalRec;
        localItem.extras = extras;
        downloadedSheet.addMusic(localItem);
        // 下载完成即加入本地音乐列表（与手动刷新扫描口径一致：跳过被「移出本地音乐」排除的文件）
        const destFileName = FileUtils.getFileName(FileUtils.normalizePath(targetDownloadPath));
        if (destFileName.length > 0 && !LocalMusicExclusion.getExcludedFiles().has(destFileName)) {
          localMusicSheet.addMusic(localItem);
        }

        const patch = new MediaExtraProperties();
        patch.downloaded = true;
        patch.localPath = targetDownloadPath;
        MediaExtra.patchMediaExtra(musicItem, patch);

        this.markTaskAsCompleted(musicItem);
      }
    } else {
      this.markTaskAsError(musicItem, DownloadFailReason.UNKNOWN, '');
    }

    this.downloadNextPendingTask();

    const key = MediaUtils.getMediaUniqueKey(musicItem);
    const task = this.downloadTasks.get(key);
    if (task !== undefined && task.status === DownloadStatus.Completed) {
      this.downloadTasks.delete(key);
      this.deleteTaskRecord(key);
      const newQueue: Array<MusicItem> = [];
      for (const item of this.downloadQueue) {
        if (!MediaUtils.isSameMediaItem(item, musicItem)) {
          newQueue.push(item);
        }
      }
      this.downloadQueue = newQueue;
      this.saveQueueOrder();
    }
  }

  download(musicItems: MusicItem | Array<MusicItem>, quality?: QualityKey, folder?: string): void {
    const network = Network.getInstance();
    if (network.isOffline) {
      const ev = new DownloadErrorEvent();
      ev.reason = DownloadFailReason.NETWORK_OFFLINE;
      this.ee.emit(DownloaderEvent.DOWNLOAD_ERROR, ev);
      return;
    }

    if (network.isCellular && !appConfig.getUseCellularNetworkDownload()) {
      const ev = new DownloadErrorEvent();
      ev.reason = DownloadFailReason.NOT_ALLOW_TO_DOWNLOAD_IN_CELLULAR;
      this.ee.emit(DownloaderEvent.DOWNLOAD_ERROR, ev);
      return;
    }

    const items: Array<MusicItem> = Array.isArray(musicItems) ? musicItems : [musicItems];
    // 目标子文件夹（非法字符转义，与文件名同一套规则；不允许越出下载目录）
    const targetFolder = folder === undefined ? '' : FileUtils.escapeCharacter(folder.trim());

    const accepted: Array<MusicItem> = [];
    for (const m of items) {
      const key = MediaUtils.getMediaUniqueKey(m);
      if (this.downloadTasks.has(key)) {
        continue;
      }
      if (localMusicSheet.isLocalMusic(m) !== null || downloadedSheet.isLocalMusic(m) !== null) {
        continue;
      }
      const task = new DownloadTaskInfo();
      task.status = DownloadStatus.Pending;
      task.filename = Downloader.generateFilename(m);
      task.quality = quality;
      task.originSheets = Downloader.collectOriginSheets(m);
      task.folder = targetFolder;
      task.musicItem = m;
      this.downloadTasks.set(key, task);
      this.saveTaskRecord(task);
      accepted.push(m);
    }

    if (accepted.length === 0) {
      return;
    }

    if (!this.batchActive) {
      this.batchActive = true;
      this.batchDone = 0;
      this.batchFailed = 0;
      DownloadNotify.resetProgress();
    }
    // 息屏/后台继续下载：申请数据传输长时任务（幂等），并请求通知授权（首次）
    DownloadNotify.ensureEnabled();
    BackgroundTask.startTransfer((notificationId: number): void => {
      DownloadNotify.setSystemNotificationId(notificationId);
    });

    this.downloadQueue = this.downloadQueue.concat(accepted);
    this.saveQueueOrder();
    Downloader.ensureDownloadDirResolved().then(() => {
      this.downloadNextPendingTask();
    });
  }

  /** 替换失败任务的音源（换源用）：更新任务与队列中的条目，保留失败状态等待重新下载；
   *  音源已变化，作废旧半成品缓存（无法断点续传） */
  replaceTask(oldItem: MusicItem, newItem: MusicItem): boolean {
    const oldKey = MediaUtils.getMediaUniqueKey(oldItem);
    const task = this.downloadTasks.get(oldKey);
    if (task === undefined || task.status !== DownloadStatus.Error) {
      return false;
    }
    const newKey = MediaUtils.getMediaUniqueKey(newItem);
    if (newKey !== oldKey && this.downloadTasks.has(newKey)) {
      return false;
    }
    this.downloadTasks.delete(oldKey);
    this.deleteTaskRecord(oldKey);
    this.removeTaskCache(task);
    task.musicItem = newItem;
    task.filename = Downloader.generateFilename(newItem);
    task.cacheFilename = '';
    task.errorReason = '';
    task.downloadedSize = 0;
    task.fileSize = 0;
    this.downloadTasks.set(newKey, task);
    this.saveTaskRecord(task);
    const newQueue: Array<MusicItem> = [];
    for (const item of this.downloadQueue) {
      if (MediaUtils.isSameMediaItem(item, oldItem)) {
        newQueue.push(newItem);
      } else {
        newQueue.push(item);
      }
    }
    this.downloadQueue = newQueue;
    this.saveQueueOrder();
    this.emitTaskUpdate(task);
    return true;
  }

  /** 重新下载失败任务：保留半成品缓存断点续传，任务重置为待下载并尝试续跑 */
  retry(musicItem: MusicItem): boolean {
    const key = MediaUtils.getMediaUniqueKey(musicItem);
    const task = this.downloadTasks.get(key);
    if (task === undefined || task.status !== DownloadStatus.Error) {
      return false;
    }
    task.status = DownloadStatus.Pending;
    task.errorReason = '';
    this.saveTaskRecord(task);
    this.emitTaskUpdate(task);
    this.tryResumeQueue();
    return true;
  }

  remove(musicItem: MusicItem): boolean {
    const key = MediaUtils.getMediaUniqueKey(musicItem);
    const task = this.downloadTasks.get(key);
    if (task === undefined) {
      return false;
    }
    if (task.status === DownloadStatus.Pending || task.status === DownloadStatus.Error) {
      this.downloadTasks.delete(key);
      this.deleteTaskRecord(key);
      this.removeTaskCache(task);
      const newQueue: Array<MusicItem> = [];
      for (const item of this.downloadQueue) {
        if (!MediaUtils.isSameMediaItem(item, musicItem)) {
          newQueue.push(item);
        }
      }
      this.downloadQueue = newQueue;
      this.saveQueueOrder();
      if (this.downloadQueue.length === 0 && this.downloadingCount === 0) {
        this.finishBatch();
      }
      return true;
    }
    return false;
  }

  onDownloadError(cb: (reason: string, message: string) => void): void {
    const wrapper: EventListenerFn = (payload?: Object) => {
      if (payload instanceof DownloadErrorEvent) {
        cb(payload.reason, payload.message);
      }
    };
    this.ee.on(DownloaderEvent.DOWNLOAD_ERROR, wrapper);
  }

  onDownloadTaskError(cb: (reason: string, musicItem: MusicItem, message: string) => void): void {
    const wrapper: EventListenerFn = (payload?: Object) => {
      if (payload instanceof DownloadTaskErrorEvent) {
        cb(payload.reason, payload.musicItem, payload.message);
      }
    };
    this.ee.on(DownloaderEvent.DOWNLOAD_TASK_ERROR, wrapper);
  }

  onDownloadTaskUpdate(cb: (task: DownloadTaskInfo) => void): void {
    const wrapper: EventListenerFn = (payload?: Object) => {
      if (payload instanceof DownloadTaskUpdateEvent) {
        cb(payload.task);
      }
    };
    this.ee.on(DownloaderEvent.DOWNLOAD_TASK_UPDATE, wrapper);
  }

  onDownloadQueueCompleted(cb: () => void): void {
    const wrapper: EventListenerFn = (_payload?: Object) => {
      cb();
    };
    this.ee.on(DownloaderEvent.DOWNLOAD_QUEUE_COMPLETED, wrapper);
  }
}

export const downloader = new Downloader();
