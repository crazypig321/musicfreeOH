import socket from '@ohos.net.socket';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PathConst } from '../common/PathConst';
import { JsonUtil, JsonRecord } from '../utils/JsonUtil';
import { FileUtils } from '../utils/FileUtils';
import { HttpClient } from '../infra/HttpClient';
import { Delay } from '../utils/Delay';
import { appConfig } from './AppConfig';

const DOMAIN = 0x0002;
const TAG = 'AudioCacheProxy';

/** 缓存条目索引记录（对齐 RN react-native-track-player SimpleCache 行为） */
interface CacheEntry {
  url: string;
  size: number;
  lastAccess: number;
  contentType: string;
}

/** 解析后的 HTTP 请求 */
interface ParsedRequest {
  method: string;
  path: string;
  rangeStart: number;
  rangeEnd: number;
  headers: Record<string, string>;
}

/** 路径解析结果 */
interface PathParts {
  cacheKey: string;
  headersB64: string;
}

/**
 * 本地 HTTP 代理缓存（对齐 RN react-native-track-player SimpleCache 行为）
 * 播放流经本地代理，边下边缓存到磁盘，受 basic.maxCacheSize 限制（LRU 淘汰）
 * 上游 HTTP 一律用 rcp（与 infra/HttpClient.ets 同栈）
 */
export class AudioCacheProxy {
  private static readonly FIRST_CHUNK_SIZE: number = 64 * 1024;
  private static readonly PROGRESSIVE_CHUNK_SIZE: number = 512 * 1024;
  private static readonly PROGRESSIVE_POLL_INTERVAL_MS: number = 30;
  private static readonly PROGRESSIVE_WAIT_TIMEOUT_MS: number = 15000;
  private static readonly SEEK_WAIT_TIMEOUT_MS: number = 2000;
  private static readonly SEEK_THRESHOLD: number = 256 * 1024;
  private static readonly DEFAULT_CONTENT_TYPE: string = 'audio/mpeg';
  private static readonly INDEX_FILE: string = 'index.json';
  private static readonly MAX_HEADER_SIZE: number = 64 * 1024;
  private static readonly SEND_CHUNK_SIZE: number = 256 * 1024;
  private static readonly INDEX_FLUSH_INTERVAL_MS: number = 5000;

  private server: socket.TCPSocketServer | null = null;
  private port: number = 0;
  private started: boolean = false;
  private startingPromise: Promise<void> | null = null;

  private entries: Map<string, CacheEntry> = new Map<string, CacheEntry>();
  private indexDirty: boolean = false;
  private indexSavePromise: Promise<void> = Promise.resolve();

  private downloadingTasks: Map<string, Promise<boolean>> = new Map<string, Promise<boolean>>();
  private metaFetchTasks: Map<string, Promise<void>> = new Map<string, Promise<void>>();
  private activeKeys: Set<string> = new Set<string>();

  private readonly textEncoder: util.TextEncoder = new util.TextEncoder();
  private indexFlushTimer: number = 0;

  // ==================== 公开 API ====================

  /**
   * 获取代理 URL（仅 http/https 且非 m3u8 时改写）
   * 启动失败降级返回原始 URL，不影响播放
   * @param mediaId 歌曲唯一标识（platform@id），传入时用 SHA1(mediaId) 作 cacheKey，
   *                 同一首歌无论 CDN 签名 URL 怎么变都命中同一缓存文件
   */
  async getProxyUrl(
    originalUrl: string,
    headers?: Record<string, string>,
    mediaId?: string
  ): Promise<string> {
    if (!originalUrl.startsWith('http://') && !originalUrl.startsWith('https://')) {
      return originalUrl;
    }
    const ext = AudioCacheProxy.getUrlExt(originalUrl);
    if (ext === '.m3u8' || ext === '.m3u') {
      return originalUrl;
    }

    const ok = await this.ensureStarted();
    if (!ok || this.port === 0) {
      return originalUrl;
    }

    // cacheKey 优先基于歌曲ID（稳定不变），回退到 URL hash
    const cacheKey = mediaId !== undefined && mediaId.length > 0
      ? await AudioCacheProxy.computeCacheKey(mediaId)
      : await AudioCacheProxy.computeCacheKey(originalUrl);

    // 预写索引（代理收到请求后据此查上游 URL；URL 变化时更新为最新）
    this.ensureEntry(cacheKey, originalUrl);

    let proxyUrl = `http://127.0.0.1:${this.port}/${cacheKey}`;
    if (headers !== undefined && Object.keys(headers).length > 0) {
      const json = JsonUtil.safeStringify(JsonUtil.fromStringMap(headers));
      const encoder = new util.TextEncoder();
      const u8 = encoder.encodeInto(json);
      const helper = new util.Base64Helper();
      const b64 = helper.encodeToStringSync(u8);
      proxyUrl += '?h=' + encodeURIComponent(b64);
    }
    return proxyUrl;
  }

  /** 关闭代理 server（EntryAbility onDestroy 兜底；进程亡 socket 自灭） */
  async close(): Promise<void> {
    const s = this.server;
    this.server = null;
    this.started = false;
    this.port = 0;
    if (this.indexFlushTimer !== 0) {
      clearTimeout(this.indexFlushTimer);
      this.indexFlushTimer = 0;
    }
    if (s !== null) {
      try {
        await s.close();
      } catch (e) {
        // 忽略关闭失败
      }
    }
    hilog.info(DOMAIN, TAG, '代理已关闭');
  }

  /** 启动时清扫 .tmp 拘留 + 索引一致性修正（Bootstrap 调用） */
  reconcileOnStartup(): void {
    this.cleanupTmpFiles();
    this.loadIndex();
    this.reconcileIndexWithDir();
  }

  /**
   * 查找歌曲已完整缓存的URL（断网时用）
   * @param mediaId 歌曲唯一标识（platform@id）
   * @return 已缓存的上游 URL（代理据此改写为本地代理URL，.media存在则本地回包），null 表示无完整缓存
   */
  async getCachedUrlForMediaId(mediaId: string): Promise<string | null> {
    const cacheKey = await AudioCacheProxy.computeCacheKey(mediaId);
    const entry = this.entries.get(cacheKey);
    if (entry === undefined) {
      return null;
    }
    const mediaPath = PathConst.musicCachePath + cacheKey + '.media';
    if (!FileUtils.exists(mediaPath)) {
      return null;
    }
    return entry.url;
  }

  // ==================== 启动 ====================

  private ensureStarted(): Promise<boolean> {
    if (this.started && this.port > 0) {
      return Promise.resolve(true);
    }
    if (this.startingPromise !== null) {
      return this.startingPromise.then((): boolean => this.started);
    }
    this.startingPromise = this.doStart();
    return this.startingPromise.then((): boolean => this.started);
  }

  private async doStart(): Promise<void> {
    try {
      FileUtils.checkAndCreateDir(PathConst.musicCachePath);
      this.loadIndex();

      const server = socket.constructTCPSocketServerInstance();
      this.server = server;

      const addr: socket.NetAddress = { address: '127.0.0.1', port: 0, family: 1 };
      await server.listen(addr);

      const localAddr = await server.getLocalAddress();
      this.port = localAddr.port !== undefined ? localAddr.port : 0;

      server.on('connect', (client: socket.TCPSocketConnection): void => {
        this.handleClient(client);
      });
      server.on('error', (err: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'server error: %{public}s', err.message);
      });

      this.started = true;
      hilog.info(DOMAIN, TAG, '代理已启动，端口 %{public}d', this.port);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, '代理启动失败: %{public}s', err.message);
      this.started = false;
      this.server = null;
      this.port = 0;
    } finally {
      this.startingPromise = null;
    }
  }

  // ==================== socket 客户端处理 ====================

  private handleClient(client: socket.TCPSocketConnection): void {
    const chunks: Array<ArrayBuffer> = [];
    let totalLen: number = 0;
    let headerParsed: boolean = false;
    let closed: boolean = false;

    const cleanup = (): void => {
      if (closed) {
        return;
      }
      closed = true;
      try {
        client.close().catch((): void => {
        });
      } catch (e) {
        // 忽略
      }
    };

    client.on('message', (info: socket.SocketMessageInfo): void => {
      if (headerParsed || closed) {
        return;
      }
      chunks.push(info.message);
      totalLen += info.message.byteLength;

      const merged = AudioCacheProxy.mergeBuffers(chunks, totalLen);
      const sep = AudioCacheProxy.findHeaderEnd(merged);
      if (sep === -1) {
        if (totalLen > AudioCacheProxy.MAX_HEADER_SIZE) {
          hilog.warn(DOMAIN, TAG, '请求头过大，关闭连接');
          cleanup();
        }
        return;
      }

      headerParsed = true;
      const headerText = AudioCacheProxy.bufferToString(merged, 0, sep);
      const req = AudioCacheProxy.parseHttpRequest(headerText);
      if (req === null) {
        this.sendSimpleResponse(client, 400, 'Bad Request', 0).then((): void => cleanup());
        return;
      }

      this.handleRequest(client, req).then((): void => {
        cleanup();
      }).catch((e: Object): void => {
        hilog.error(DOMAIN, TAG, '处理请求失败: %{public}s', e instanceof Error ? e.message : '');
        cleanup();
      });
    });

    client.on('close', (): void => {
      closed = true;
    });
    client.on('error', (err: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'client error: %{public}s', err.message);
      cleanup();
    });
  }

  private async handleRequest(client: socket.TCPSocketConnection, req: ParsedRequest): Promise<void> {
    const parts = AudioCacheProxy.splitPath(req.path);
    if (parts === null) {
      await this.sendSimpleResponse(client, 404, 'Not Found', 0);
      return;
    }
    const cacheKey = parts.cacheKey;
    const upstreamHeaders = AudioCacheProxy.decodeHeaders(parts.headersB64);

    this.activeKeys.add(cacheKey);
    try {
      const entry = this.entries.get(cacheKey);
      const mediaPath = PathConst.musicCachePath + cacheKey + '.media';
      const tmpPath = PathConst.musicCachePath + cacheKey + '.tmp';

      if (FileUtils.exists(mediaPath) && entry !== undefined) {
        this.touchEntry(cacheKey);
        await this.serveFromCache(client, mediaPath, entry, req);
        return;
      }

      if (entry === undefined) {
        hilog.warn(DOMAIN, TAG, '无索引条目: %{public}s', cacheKey);
        await this.sendSimpleResponse(client, 404, 'Not Found', 0);
        return;
      }

      const upstreamUrl = entry.url;
      this.startDownload(cacheKey, upstreamUrl, upstreamHeaders, tmpPath);
      await this.serveFromUpstream(client, cacheKey, tmpPath, mediaPath, entry, req);
    } finally {
      this.activeKeys.delete(cacheKey);
    }
  }

  // ==================== 缓存命中 ====================

  private async serveFromCache(
    client: socket.TCPSocketConnection,
    mediaPath: string,
    entry: CacheEntry,
    req: ParsedRequest
  ): Promise<void> {
    const fileSize = FileUtils.fileSize(mediaPath);
    if (fileSize <= 0) {
      await this.sendSimpleResponse(client, 404, 'Not Found', 0);
      return;
    }

    const totalSize = entry.size > 0 ? entry.size : fileSize;
    const rangeStart = req.rangeStart >= 0 ? req.rangeStart : 0;
    const rangeEnd = (req.rangeEnd >= 0 && req.rangeEnd < fileSize) ? req.rangeEnd : fileSize - 1;

    if (rangeStart > rangeEnd) {
      await this.sendSimpleResponse(client, 416, 'Range Not Satisfiable', 0);
      return;
    }

    const contentLength = rangeEnd - rangeStart + 1;
    const contentType = entry.contentType.length > 0 ? entry.contentType : AudioCacheProxy.DEFAULT_CONTENT_TYPE;
    const isPartial = rangeStart > 0 || rangeEnd < fileSize - 1 || req.rangeStart >= 0;

    let header: string;
    if (isPartial) {
      header = `HTTP/1.1 206 Partial Content\r\n` +
        `Content-Type: ${contentType}\r\n` +
        `Content-Length: ${contentLength}\r\n` +
        `Content-Range: bytes ${rangeStart}-${rangeEnd}/${totalSize}\r\n` +
        `Accept-Ranges: bytes\r\n` +
        `Connection: close\r\n` +
        `\r\n`;
    } else {
      header = `HTTP/1.1 200 OK\r\n` +
        `Content-Type: ${contentType}\r\n` +
        `Content-Length: ${contentLength}\r\n` +
        `Accept-Ranges: bytes\r\n` +
        `Connection: close\r\n` +
        `\r\n`;
    }

    await this.sendString(client, header);
    if (req.method === 'HEAD') {
      return;
    }
    await this.sendFileRange(client, mediaPath, rangeStart, contentLength);
  }

  // ==================== 缓存未命中（渐进回包） ====================

  private async serveFromUpstream(
    client: socket.TCPSocketConnection,
    cacheKey: string,
    tmpPath: string,
    mediaPath: string,
    entry: CacheEntry,
    req: ParsedRequest
  ): Promise<void> {
    // 下载可能已完成
    if (FileUtils.exists(mediaPath)) {
      await this.serveFromCache(client, mediaPath, entry, req);
      return;
    }

    const rangeStart = req.rangeStart >= 0 ? req.rangeStart : 0;
    let totalSize = entry.size > 0 ? entry.size : 0;

    const available = await this.waitForData(tmpPath, rangeStart, totalSize, cacheKey);
    if (available <= 0) {
      hilog.warn(DOMAIN, TAG, '等待数据超时且 0 字节，回 504: %{public}s', cacheKey);
      await this.sendSimpleResponse(client, 504, 'Gateway Timeout', 0);
      return;
    }

    // 下载完成后转走缓存路径
    if (FileUtils.exists(mediaPath)) {
      await this.serveFromCache(client, mediaPath, entry, req);
      return;
    }

    // totalSize 未知时等待 HEAD 元数据获取完成（最多 3s），避免 AVPlayer 误判总长
    if (totalSize <= 0) {
      const metaTask = this.metaFetchTasks.get(cacheKey);
      if (metaTask !== undefined) {
        await Promise.race<Array<Promise<void>>>([metaTask, Delay.wait(3000)]);
      }
      const refreshed = this.entries.get(cacheKey);
      if (refreshed !== undefined && refreshed.size > 0) {
        totalSize = refreshed.size;
      }
    }

    const currentSize = FileUtils.exists(tmpPath) ? FileUtils.fileSize(tmpPath) : 0;
    const end = Math.min(available, currentSize) - 1;
    if (end < rangeStart) {
      await this.sendSimpleResponse(client, 504, 'Gateway Timeout', 0);
      return;
    }

    const contentLength = end - rangeStart + 1;
    const contentType = entry.contentType.length > 0 ? entry.contentType : AudioCacheProxy.DEFAULT_CONTENT_TYPE;
    // totalSize 未知时用 *（RFC 7233），避免 AVPlayer 误判音频总长导致播一点就 completed
    const contentRange = totalSize > 0
      ? `bytes ${rangeStart}-${end}/${totalSize}`
      : `bytes ${rangeStart}-${end}/*`;

    const header = `HTTP/1.1 206 Partial Content\r\n` +
      `Content-Type: ${contentType}\r\n` +
      `Content-Length: ${contentLength}\r\n` +
      `Content-Range: ${contentRange}\r\n` +
      `Accept-Ranges: bytes\r\n` +
      `Connection: close\r\n` +
      `\r\n`;

    await this.sendString(client, header);
    if (req.method === 'HEAD') {
      return;
    }
    await this.sendFileRange(client, tmpPath, rangeStart, contentLength);
  }

  /**
   * 等待 .tmp 文件增长到 rangeStart + 64KB
   * seek 到未下载区（起点 > 当前末尾 + 阈值）等待至多 2s
   * 超时 15s 则按当前已有字节回，若 0 字节回 504
   */
  private async waitForData(
    tmpPath: string,
    rangeStart: number,
    totalSize: number,
    cacheKey: string
  ): Promise<number> {
    const deadline = Date.now() + AudioCacheProxy.PROGRESSIVE_WAIT_TIMEOUT_MS;
    const seekDeadline = Date.now() + AudioCacheProxy.SEEK_WAIT_TIMEOUT_MS;

    while (Date.now() < deadline) {
      // 下载完成
      const mediaPath = PathConst.musicCachePath + cacheKey + '.media';
      if (FileUtils.exists(mediaPath)) {
        return FileUtils.fileSize(mediaPath);
      }

      if (!FileUtils.exists(tmpPath)) {
        await Delay.wait(AudioCacheProxy.PROGRESSIVE_POLL_INTERVAL_MS);
        continue;
      }
      const currentSize = FileUtils.fileSize(tmpPath);
      if (currentSize <= 0) {
        await Delay.wait(AudioCacheProxy.PROGRESSIVE_POLL_INTERVAL_MS);
        continue;
      }

      // seek 到未下载区
      if (rangeStart > currentSize + AudioCacheProxy.SEEK_THRESHOLD) {
        if (Date.now() < seekDeadline) {
          await Delay.wait(AudioCacheProxy.PROGRESSIVE_POLL_INTERVAL_MS);
          continue;
        }
        // 超时，回当前末尾数据
        return currentSize;
      }

      // 正常渐进：首块用小粒度快速起播，后续用大粒度减少请求往返
      const chunkSize = rangeStart === 0
        ? AudioCacheProxy.FIRST_CHUNK_SIZE
        : AudioCacheProxy.PROGRESSIVE_CHUNK_SIZE;
      if (currentSize >= rangeStart + chunkSize) {
        return rangeStart + chunkSize;
      }

      // 下载完成（已知总大小且已达到）
      if (totalSize > 0 && currentSize >= totalSize) {
        return currentSize;
      }

      await Delay.wait(AudioCacheProxy.PROGRESSIVE_POLL_INTERVAL_MS);
    }

    // 超时，返回当前已有字节
    if (FileUtils.exists(tmpPath)) {
      return FileUtils.fileSize(tmpPath);
    }
    return 0;
  }

  // ==================== 下载 ====================

  private startDownload(
    cacheKey: string,
    url: string,
    headers: Record<string, string> | undefined,
    tmpPath: string
  ): Promise<boolean> {
    const existing = this.downloadingTasks.get(cacheKey);
    if (existing !== undefined) {
      return existing;
    }
    const task = this.doDownload(cacheKey, url, headers, tmpPath);
    this.downloadingTasks.set(cacheKey, task);
    return task;
  }

  private async doDownload(
    cacheKey: string,
    url: string,
    headers: Record<string, string> | undefined,
    tmpPath: string
  ): Promise<boolean> {
    // 并行获取 Content-Type/Length（HEAD 请求，不阻塞下载）
    const metaTask = this.fetchContentType(cacheKey, url, headers).catch((): void => {
    });
    this.metaFetchTasks.set(cacheKey, metaTask);

    const onProgress = (downloaded: number, total: number): void => {
      const entry = this.entries.get(cacheKey);
      if (entry !== undefined && total > 0) {
        entry.size = total;
      }
    };

    const ok = await HttpClient.downloadToFile(url, tmpPath, headers, onProgress);
    if (!ok) {
      hilog.warn(DOMAIN, TAG, '下载失败: %{public}s', cacheKey);
      FileUtils.unlink(tmpPath);
      this.downloadingTasks.delete(cacheKey);
      this.metaFetchTasks.delete(cacheKey);
      return false;
    }

    const mediaPath = PathConst.musicCachePath + cacheKey + '.media';
    const fileSize = FileUtils.fileSize(tmpPath);
    if (fileSize <= 0) {
      FileUtils.unlink(tmpPath);
      this.downloadingTasks.delete(cacheKey);
      return false;
    }

    // 原子 rename
    if (FileUtils.exists(mediaPath)) {
      FileUtils.unlink(mediaPath);
    }
    if (!FileUtils.renameFile(tmpPath, mediaPath)) {
      hilog.error(DOMAIN, TAG, 'rename 失败: %{public}s', cacheKey);
      FileUtils.unlink(tmpPath);
      this.downloadingTasks.delete(cacheKey);
      return false;
    }

    // 更新索引
    const entry = this.entries.get(cacheKey);
    if (entry !== undefined) {
      entry.size = fileSize;
      entry.lastAccess = Date.now();
    }
    this.markIndexDirty();
    this.evictIfNeeded();

    this.downloadingTasks.delete(cacheKey);
    this.metaFetchTasks.delete(cacheKey);
    hilog.info(DOMAIN, TAG, '下载完成: %{public}s 大小 %{public}d', cacheKey, fileSize);
    return true;
  }

  private async fetchContentType(
    cacheKey: string,
    url: string,
    headers: Record<string, string> | undefined
  ): Promise<void> {
    try {
      const resp = await HttpClient.request(url, 'HEAD', headers, 8000);
      if (resp !== null && resp.statusCode >= 200 && resp.statusCode < 300) {
        const ct = resp.headers['content-type'];
        if (ct !== undefined && ct.length > 0) {
          const entry = this.entries.get(cacheKey);
          if (entry !== undefined) {
            entry.contentType = ct;
            this.markIndexDirty();
          }
        }
        const cl = resp.headers['content-length'];
        if (cl !== undefined && cl.length > 0) {
          const parsed = Number(cl);
          if (Number.isFinite(parsed) && parsed > 0) {
            const entry = this.entries.get(cacheKey);
            if (entry !== undefined) {
              entry.size = parsed;
              this.markIndexDirty();
            }
          }
        }
      }
    } catch (e) {
      // HEAD 失败忽略，用默认 Content-Type
    }
  }

  // ==================== LRU 淘汰 ====================

  private evictIfNeeded(): void {
    const limit = appConfig.getMaxCacheSize();
    let total = 0;
    this.entries.forEach((e: CacheEntry): void => {
      total += e.size;
    });

    if (total <= limit) {
      return;
    }

    // 按 lastAccess 升序排列
    const sorted: Array<string> = [];
    this.entries.forEach((_e: CacheEntry, key: string): void => {
      sorted.push(key);
    });
    sorted.sort((a: string, b: string): number => {
      const ea = this.entries.get(a);
      const eb = this.entries.get(b);
      const ta = ea !== undefined ? ea.lastAccess : 0;
      const tb = eb !== undefined ? eb.lastAccess : 0;
      return ta - tb;
    });

    for (const key of sorted) {
      if (total <= limit) {
        break;
      }
      // 正在播放的条目不可淘汰
      if (this.activeKeys.has(key)) {
        continue;
      }
      const entry = this.entries.get(key);
      if (entry === undefined) {
        continue;
      }
      const mediaPath = PathConst.musicCachePath + key + '.media';
      if (FileUtils.exists(mediaPath)) {
        FileUtils.unlink(mediaPath);
      }
      total -= entry.size;
      this.entries.delete(key);
      hilog.info(DOMAIN, TAG, 'LRU 淘汰: %{public}s 大小 %{public}d', key, entry.size);
    }
    this.markIndexDirty();
  }

  // ==================== 索引管理 ====================

  private ensureEntry(cacheKey: string, url: string): void {
    const existing = this.entries.get(cacheKey);
    if (existing !== undefined) {
      existing.url = url;
      return;
    }
    const entry: CacheEntry = {
      url: url,
      size: 0,
      lastAccess: Date.now(),
      contentType: ''
    };
    this.entries.set(cacheKey, entry);
    this.markIndexDirty();
  }

  private touchEntry(cacheKey: string): void {
    const entry = this.entries.get(cacheKey);
    if (entry !== undefined) {
      entry.lastAccess = Date.now();
      this.scheduleIndexFlush();
    }
  }

  /** 防抖落盘：5s 内多次 touch 只触发一次写盘 */
  private scheduleIndexFlush(): void {
    if (this.indexFlushTimer !== 0) {
      return;
    }
    this.indexFlushTimer = setTimeout((): void => {
      this.indexFlushTimer = 0;
      this.markIndexDirty();
    }, AudioCacheProxy.INDEX_FLUSH_INTERVAL_MS);
  }

  private markIndexDirty(): void {
    this.indexDirty = true;
    this.indexSavePromise = this.indexSavePromise.then((): Promise<void> => this.flushIndexIfNeeded());
  }

  private async flushIndexIfNeeded(): Promise<void> {
    if (!this.indexDirty) {
      return;
    }
    this.indexDirty = false;
    try {
      this.saveIndex();
    } catch (e) {
      // 落盘失败下次重试
      this.indexDirty = true;
    }
  }

  private indexFilePath(): string {
    return PathConst.musicCachePath + AudioCacheProxy.INDEX_FILE;
  }

  private loadIndex(): void {
    const path = this.indexFilePath();
    const text = FileUtils.readFileText(path);
    if (text === null) {
      return;
    }
    const rec = JsonUtil.parseRecord(text);
    if (rec === null) {
      return;
    }
    const entriesRec = JsonUtil.recRecord(rec, 'entries');
    if (entriesRec === null) {
      return;
    }
    for (const key of Object.keys(entriesRec)) {
      const item = JsonUtil.objToRecord(entriesRec[key]);
      if (item === null) {
        continue;
      }
      const entry: CacheEntry = {
        url: JsonUtil.recStr(item, 'url'),
        size: JsonUtil.recNum(item, 'size', 0),
        lastAccess: JsonUtil.recNum(item, 'lastAccess', 0),
        contentType: JsonUtil.recStr(item, 'contentType')
      };
      if (entry.url.length > 0) {
        this.entries.set(key, entry);
      }
    }
    hilog.info(DOMAIN, TAG, '加载索引: %{public}d 条', this.entries.size);
  }

  private saveIndex(): void {
    const entriesRec: JsonRecord = {};
    this.entries.forEach((e: CacheEntry, key: string): void => {
      const item: JsonRecord = {
        'url': e.url,
        'size': e.size,
        'lastAccess': e.lastAccess,
        'contentType': e.contentType
      };
      entriesRec[key] = item;
    });
    const root: JsonRecord = { 'entries': entriesRec };
    const text = JsonUtil.safeStringify(root);
    FileUtils.writeFileText(this.indexFilePath(), text);
  }

  /** 启动时若 index 与目录不一致，以目录实际 .media 文件为准修正 */
  private reconcileIndexWithDir(): void {
    const names = FileUtils.listDir(PathConst.musicCachePath);
    const mediaKeys: Set<string> = new Set<string>();
    for (const n of names) {
      if (n.endsWith('.media')) {
        mediaKeys.add(n.substring(0, n.length - '.media'.length));
      }
    }

    // 目录有但索引无：补建索引
    for (const key of mediaKeys) {
      if (!this.entries.has(key)) {
        const mediaPath = PathConst.musicCachePath + key + '.media';
        const entry: CacheEntry = {
          url: '',
          size: FileUtils.fileSize(mediaPath),
          lastAccess: Date.now(),
          contentType: ''
        };
        this.entries.set(key, entry);
        this.markIndexDirty();
      }
    }

    // 索引有但目录无：删除索引条目
    const keysToRemove: Array<string> = [];
    this.entries.forEach((_e: CacheEntry, key: string): void => {
      if (!mediaKeys.has(key)) {
        keysToRemove.push(key);
      }
    });
    for (const key of keysToRemove) {
      this.entries.delete(key);
    }
    if (keysToRemove.length > 0) {
      this.markIndexDirty();
    }
  }

  /** 清扫所有 .tmp 拘留（Bootstrap 启动时调用） */
  private cleanupTmpFiles(): void {
    const names = FileUtils.listDir(PathConst.musicCachePath);
    for (const n of names) {
      if (n.endsWith('.tmp')) {
        const p = PathConst.musicCachePath + n;
        FileUtils.unlink(p);
        hilog.info(DOMAIN, TAG, '清扫拘留: %{public}s', n);
      }
    }
  }

  // ==================== socket 发送 ====================

  private async sendString(client: socket.TCPSocketConnection, text: string): Promise<void> {
    const u8 = this.textEncoder.encodeInto(text);
    const options: socket.TCPSendOptions = { data: u8.buffer };
    await client.send(options);
  }

  private async sendSimpleResponse(
    client: socket.TCPSocketConnection,
    code: number,
    reason: string,
    contentLength: number
  ): Promise<void> {
    const header = `HTTP/1.1 ${code} ${reason}\r\n` +
      `Content-Length: ${contentLength}\r\n` +
      `Connection: close\r\n` +
      `\r\n`;
    await this.sendString(client, header);
  }

  /** 分块读取文件区间并发送（避免大 Range 一次性占内存） */
  private async sendFileRange(
    client: socket.TCPSocketConnection,
    filePath: string,
    start: number,
    length: number
  ): Promise<void> {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      let remaining = length;
      let offset = start;
      const chunkSize = AudioCacheProxy.SEND_CHUNK_SIZE;
      while (remaining > 0) {
        const readLen = Math.min(remaining, chunkSize);
        const buf = new ArrayBuffer(readLen);
        const read = fs.readSync(file.fd, buf, { offset: offset });
        if (read <= 0) {
          break;
        }
        const sendBuf = read === readLen ? buf : buf.slice(0, read);
        const options: socket.TCPSendOptions = { data: sendBuf };
        await client.send(options);
        offset += read;
        remaining -= read;
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, '发送文件数据失败: %{public}s', err.message);
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (e) {
          // 忽略
        }
      }
    }
  }

  // ==================== HTTP 解析工具 ====================

  private static getUrlExt(url: string): string {
    let path = url;
    const qIdx = path.indexOf('?');
    if (qIdx !== -1) {
      path = path.substring(0, qIdx);
    }
    const hIdx = path.indexOf('#');
    if (hIdx !== -1) {
      path = path.substring(0, hIdx);
    }
    const lastSlash = path.lastIndexOf('/');
    const fileName = lastSlash === -1 ? path : path.substring(lastSlash + 1);
    const lastDot = fileName.lastIndexOf('.');
    if (lastDot === -1 || lastDot === 0) {
      return '';
    }
    return fileName.substring(lastDot).toLowerCase();
  }

  private static computeCacheKey(url: string): Promise<string> {
    return new Promise<string>((resolve: (v: string) => void, _reject: (r: Object) => void): void => {
      try {
        const md: cryptoFramework.Md = cryptoFramework.createMd('SHA1');
        const encoder = new util.TextEncoder();
        const u8 = encoder.encodeInto(url);
        md.update({ data: u8 });
        md.digest().then((digest: cryptoFramework.DataBlob): void => {
          resolve(AudioCacheProxy.u8ToHex(digest.data));
        }).catch((): void => {
          resolve(AudioCacheProxy.fallbackHash(url));
        });
      } catch (e) {
        resolve(AudioCacheProxy.fallbackHash(url));
      }
    });
  }

  private static u8ToHex(data: Uint8Array): string {
    let hex = '';
    for (let i = 0; i < data.length; ++i) {
      let h = data[i].toString(16);
      if (h.length < 2) {
        h = '0' + h;
      }
      hex += h;
    }
    return hex;
  }

  private static fallbackHash(text: string): string {
    let h = 5381;
    for (let i = 0; i < text.length; ++i) {
      h = ((h << 5) + h + text.charCodeAt(i)) & 0x7fffffff;
    }
    return 'fb' + h.toString(16) + text.length.toString(16);
  }

  private static mergeBuffers(chunks: Array<ArrayBuffer>, totalLen: number): ArrayBuffer {
    const merged = new ArrayBuffer(totalLen);
    const view = new Uint8Array(merged);
    let offset = 0;
    for (const chunk of chunks) {
      view.set(new Uint8Array(chunk), offset);
      offset += chunk.byteLength;
    }
    return merged;
  }

  private static findHeaderEnd(buf: ArrayBuffer): number {
    const view = new Uint8Array(buf);
    for (let i = 0; i < view.length - 3; ++i) {
      if (view[i] === 0x0d && view[i + 1] === 0x0a && view[i + 2] === 0x0d && view[i + 3] === 0x0a) {
        return i + 4;
      }
    }
    return -1;
  }

  private static bufferToString(buf: ArrayBuffer, start: number, end: number): string {
    const view = new Uint8Array(buf, start, end - start);
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(view);
  }

  private static parseHttpRequest(headerText: string): ParsedRequest | null {
    const lines = headerText.split('\r\n');
    if (lines.length === 0) {
      return null;
    }
    const firstLine = lines[0];
    const parts = firstLine.split(' ');
    if (parts.length < 2) {
      return null;
    }
    const method = parts[0].toUpperCase();
    const path = parts[1];

    const headers: Record<string, string> = {};
    for (let i = 1; i < lines.length; ++i) {
      const line = lines[i];
      const colon = line.indexOf(':');
      if (colon === -1) {
        continue;
      }
      const key = line.substring(0, colon).trim().toLowerCase();
      const value = line.substring(colon + 1).trim();
      headers[key] = value;
    }

    let rangeStart = -1;
    let rangeEnd = -1;
    const range = headers['range'];
    if (range !== undefined) {
      const m = range.match(/bytes=(\d*)-(\d*)/);
      if (m !== null) {
        const s = m[1];
        const e = m[2];
        if (s !== undefined && s.length > 0) {
          rangeStart = parseInt(s, 10);
        }
        if (e !== undefined && e.length > 0) {
          rangeEnd = parseInt(e, 10);
        }
        if (rangeStart < 0) {
          rangeStart = 0;
        }
      }
    }

    const req: ParsedRequest = {
      method: method,
      path: path,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      headers: headers
    };
    return req;
  }

  private static splitPath(path: string): PathParts | null {
    let p = path;
    const qIdx = p.indexOf('?');
    let query = '';
    if (qIdx !== -1) {
      query = p.substring(qIdx + 1);
      p = p.substring(0, qIdx);
    }
    if (p.startsWith('/')) {
      p = p.substring(1);
    }
    if (p.length === 0) {
      return null;
    }
    let headersB64 = '';
    if (query.length > 0) {
      const params = query.split('&');
      for (const param of params) {
        const eq = param.indexOf('=');
        if (eq === -1) {
          continue;
        }
        const k = param.substring(0, eq);
        const v = param.substring(eq + 1);
        if (k === 'h') {
          try {
            headersB64 = decodeURIComponent(v);
          } catch (e) {
            headersB64 = v;
          }
        }
      }
    }
    const parts: PathParts = { cacheKey: p, headersB64: headersB64 };
    return parts;
  }

  private static decodeHeaders(headersB64: string): Record<string, string> | undefined {
    if (headersB64.length === 0) {
      return undefined;
    }
    try {
      const helper = new util.Base64Helper();
      const encoder = new util.TextEncoder();
      const u8 = encoder.encodeInto(headersB64);
      const decoded = helper.decodeSync(u8);
      const decoder = util.TextDecoder.create('utf-8');
      const json = decoder.decodeToString(decoded);
      const rec = JsonUtil.parseRecord(json);
      if (rec === null) {
        return undefined;
      }
      return JsonUtil.toStringMap(rec);
    } catch (e) {
      return undefined;
    }
  }
}

export const audioCacheProxy = new AudioCacheProxy();
