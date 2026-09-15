import { EventEmitter, EventListenerFn } from '../common/EventBus';
import { INTERNAL_SERIALIZE_KEY, SUPPORT_LOCAL_MEDIA_TYPE } from '../common/Consts';
import { PathConst } from '../common/PathConst';
import { JsonUtil, JsonRecord } from '../common/JsonUtil';
import { MusicItem, MediaSource, QualityKey } from '../common/model/MediaTypes';
import { MediaUtils } from '../utils/MediaUtils';
import { FileUtils } from '../utils/FileUtils';
import { CryptoUtil } from '../utils/CryptoUtil';
import { Qualities } from '../utils/Qualities';
import { Network } from '../infra/Network';
import { HttpClient } from '../infra/HttpClient';
import { Log } from '../utils/Log';
import { appConfig } from './AppConfig';
import { localMusicSheet } from './LocalMusicSheet';
import { MediaExtra, MediaExtraProperties } from './MediaExtra';
import { pluginManager } from '../plugin/PluginManager';

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
  /** 下载音质 */
  quality?: QualityKey;
  /** 文件大小 */
  fileSize: number = 0;
  /** 已下载大小 */
  downloadedSize: number = 0;
  /** 音乐信息 */
  musicItem: MusicItem = new MusicItem();
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

  /** 确保公共下载目录解析完成后再启动下载队列（沙箱回落时下载功能不受影响） */
  private static async ensureDownloadDirResolved(): Promise<void> {
    await PathConst.bootstrapPublicDownloadDir();
  }

  private static generateFilename(musicItem: MusicItem): string {
    const name = `${FileUtils.escapeCharacter(musicItem.platform)}@${FileUtils.escapeCharacter(musicItem.id)}` +
      `@${FileUtils.escapeCharacter(musicItem.title)}@${FileUtils.escapeCharacter(musicItem.artist)}`;
    return name.slice(0, 200);
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
    this.updateTaskStatus(musicItem, DownloadStatus.Preparing);
  }

  private markTaskAsCompleted(musicItem: MusicItem): void {
    this.downloadingCount--;
    this.updateTaskStatus(musicItem, DownloadStatus.Completed);
  }

  private markTaskAsError(musicItem: MusicItem, reason: string, message: string): void {
    this.downloadingCount--;
    const key = MediaUtils.getMediaUniqueKey(musicItem);
    let task = this.downloadTasks.get(key);
    if (task === undefined) {
      task = new DownloadTaskInfo();
      task.musicItem = musicItem;
      this.downloadTasks.set(key, task);
    }
    task.status = DownloadStatus.Error;
    task.errorReason = reason;
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

  /** 获取下载路径 */
  private getDownloadPath(fileName: string): string {
    const dlPath = appConfig.getDownloadPath();
    if (!dlPath.endsWith('/')) {
      return `${dlPath}/${fileName}`;
    }
    return dlPath + fileName;
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
        this.ee.emit(DownloaderEvent.DOWNLOAD_QUEUE_COMPLETED, new DownloadQueueCompletedEvent());
      }
      return;
    }

    const musicItem = nextTask.musicItem;
    this.markTaskAsStarted(musicItem);

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
      return;
    }

    this.downloadNextPendingTask();

    let extension = this.getExtensionName(url);
    if (SUPPORT_LOCAL_MEDIA_TYPE.every((item: string): boolean => item !== '.' + extension)) {
      extension = 'mp3';
    }

    const cacheDownloadPath = FileUtils.addFileScheme(
      this.getCacheDownloadPath(`${CryptoUtil.nanoid()}.${extension}`)
    );
    const targetDownloadPath = FileUtils.addFileScheme(
      this.getDownloadPath(`${nextTask.filename}.${extension}`)
    );

    if (!FileUtils.exists(FileUtils.getDirectory(targetDownloadPath))) {
      FileUtils.checkAndCreateDir(FileUtils.getDirectory(targetDownloadPath));
      if (!FileUtils.exists(FileUtils.getDirectory(targetDownloadPath))) {
        this.markTaskAsError(musicItem, DownloadFailReason.NO_WRITE_PERMISSION, '');
        return;
      }
    }

    const ok = await HttpClient.downloadToFile(url, cacheDownloadPath, headers,
      (downloadedSize: number, totalSize: number): void => {
        this.updateDownloadTask(musicItem, DownloadStatus.Downloading, downloadedSize, totalSize);
      });

    if (ok) {
      const copied = FileUtils.copyFile(cacheDownloadPath, targetDownloadPath);
      if (!copied) {
        this.markTaskAsError(musicItem, DownloadFailReason.NO_WRITE_PERMISSION, '');
      } else {
        const localItem = musicItem.clone();
        const extras = JsonUtil.cloneRecord(musicItem.extras);
        const internalRec: JsonRecord = { 'localPath': targetDownloadPath };
        extras[INTERNAL_SERIALIZE_KEY] = internalRec;
        localItem.extras = extras;
        localMusicSheet.addMusic(localItem);

        const patch = new MediaExtraProperties();
        patch.downloaded = true;
        patch.localPath = targetDownloadPath;
        MediaExtra.patchMediaExtra(musicItem, patch);

        this.markTaskAsCompleted(musicItem);
      }
    } else {
      this.markTaskAsError(musicItem, DownloadFailReason.UNKNOWN, '');
    }

    FileUtils.unlink(cacheDownloadPath);
    this.downloadNextPendingTask();

    const key = MediaUtils.getMediaUniqueKey(musicItem);
    const task = this.downloadTasks.get(key);
    if (task !== undefined && task.status === DownloadStatus.Completed) {
      this.downloadTasks.delete(key);
      const newQueue: Array<MusicItem> = [];
      for (const item of this.downloadQueue) {
        if (!MediaUtils.isSameMediaItem(item, musicItem)) {
          newQueue.push(item);
        }
      }
      this.downloadQueue = newQueue;
    }
  }

  download(musicItems: MusicItem | Array<MusicItem>, quality?: QualityKey): void {
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

    const accepted: Array<MusicItem> = [];
    for (const m of items) {
      const key = MediaUtils.getMediaUniqueKey(m);
      if (this.downloadTasks.has(key)) {
        continue;
      }
      if (localMusicSheet.isLocalMusic(m) !== null) {
        continue;
      }
      const task = new DownloadTaskInfo();
      task.status = DownloadStatus.Pending;
      task.filename = Downloader.generateFilename(m);
      task.quality = quality;
      task.musicItem = m;
      this.downloadTasks.set(key, task);
      accepted.push(m);
    }

    if (accepted.length === 0) {
      return;
    }

    this.downloadQueue = this.downloadQueue.concat(accepted);
    Downloader.ensureDownloadDirResolved().then(() => {
      this.downloadNextPendingTask();
    });
  }

  remove(musicItem: MusicItem): boolean {
    const key = MediaUtils.getMediaUniqueKey(musicItem);
    const task = this.downloadTasks.get(key);
    if (task === undefined) {
      return false;
    }
    if (task.status === DownloadStatus.Pending || task.status === DownloadStatus.Error) {
      this.downloadTasks.delete(key);
      const newQueue: Array<MusicItem> = [];
      for (const item of this.downloadQueue) {
        if (!MediaUtils.isSameMediaItem(item, musicItem)) {
          newQueue.push(item);
        }
      }
      this.downloadQueue = newQueue;
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
