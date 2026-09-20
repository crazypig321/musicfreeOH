import fs from '@ohos.file.fs';
import { HttpClient } from '../infra/HttpClient';
import { PathConst } from '../common/PathConst';
import { FileUtils } from './FileUtils';
import { CryptoUtil } from './CryptoUtil';
import { JsonUtil } from '../common/JsonUtil';

/** URL → 缓存文件名 索引持久化文件名（位于封面缓存目录内，随目录清空一起删除） */
const INDEX_FILE = 'index.json';
/** 索引写盘防抖间隔 */
const PERSIST_DELAY_MS = 500;

/**
 * 网络封面磁盘缓存（内容寻址去重：按封面字节 MD5 命名，相同内容只保留一份）
 * resolve() 同步返回：命中缓存返回本地 file:// 路径，未命中返回原地址并后台下载（下次渲染命中）
 * URL → 文件名映射持久化到 index.json；旧版按 URL 哈希命名的缓存文件命中后直接纳入索引
 */
export class ArtworkCache {
  /** 下载中的地址集合（去重，避免同一封面并发下载） */
  private static inflight: Set<string> = new Set<string>();
  /** URL → 缓存文件名（含扩展名）索引 */
  private static urlIndex: Map<string, string> = new Map<string, string>();
  private static indexLoaded: boolean = false;
  /** 索引写盘防抖定时器 */
  private static persistTimer: number = -1;

  /** 渲染入口：http 地址尝试走本地缓存，其余（file://、data:、空串）原样返回 */
  static resolve(url: string): string {
    if (!ArtworkCache.isHttpUrl(url)) {
      return url;
    }
    ArtworkCache.ensureIndexLoaded();
    const hit = ArtworkCache.lookup(url);
    if (hit !== null) {
      return hit;
    }
    // 兼容旧版 URL 哈希命名缓存：命中则直接纳入索引，避免升级后重复下载
    const legacyName = ArtworkCache.hashOf(url) + '.' + ArtworkCache.extOf(url);
    if (FileUtils.exists(PathConst.artworkCachePath + legacyName)) {
      ArtworkCache.putIndex(url, legacyName);
      return FileUtils.addFileScheme(PathConst.artworkCachePath + legacyName);
    }
    ArtworkCache.prefetch(url);
    return url;
  }

  /** 下载封面字节：命中缓存读本地，否则下载并写入缓存（供 AVSession 等内存消费方使用） */
  static async downloadBuffer(url: string): Promise<Uint8Array | null> {
    if (!ArtworkCache.isHttpUrl(url)) {
      return null;
    }
    ArtworkCache.ensureIndexLoaded();
    const fileName = ArtworkCache.lookupName(url);
    if (fileName !== null) {
      const cached = ArtworkCache.readFileBytes(PathConst.artworkCachePath + fileName);
      if (cached !== null) {
        return cached;
      }
    }
    return ArtworkCache.fetchAndStore(url);
  }

  /** 缓存目录被清空后调用：重置内存索引 */
  static reset(): void {
    ArtworkCache.urlIndex.clear();
    ArtworkCache.indexLoaded = false;
    if (ArtworkCache.persistTimer >= 0) {
      clearTimeout(ArtworkCache.persistTimer);
      ArtworkCache.persistTimer = -1;
    }
  }

  /** 后台预取（失败静默，下次渲染重试） */
  private static prefetch(url: string): void {
    if (ArtworkCache.inflight.has(url)) {
      return;
    }
    ArtworkCache.inflight.add(url);
    ArtworkCache.fetchAndStore(url).finally((): void => {
      ArtworkCache.inflight.delete(url);
    });
  }

  /** 下载字节 → 校验图片魔数 → 按内容 MD5 命名落盘（重复内容不重复写）→ 更新 URL 索引 */
  private static async fetchAndStore(url: string): Promise<Uint8Array | null> {
    const buf = await HttpClient.downloadBuffer(url);
    if (buf === null) {
      return null;
    }
    // 校验字节确为图片（服务端偶发返回错误页/占位图时拒绝入缓存，
    // 避免「封面与歌曲不匹配」被内容寻址缓存固化）
    const ext = ArtworkCache.sniffExt(buf);
    if (ext === null) {
      return null;
    }
    const hash = await CryptoUtil.md5Bytes(buf);
    const fileName = hash + '.' + ext;
    const path = PathConst.artworkCachePath + fileName;
    if (!FileUtils.exists(path)) {
      FileUtils.writeFileBytes(path, buf);
    }
    ArtworkCache.putIndex(url, fileName);
    return buf;
  }

  /** 索引命中且文件存在 → file:// 路径；否则 null */
  private static lookup(url: string): string | null {
    const fileName = ArtworkCache.lookupName(url);
    if (fileName === null) {
      return null;
    }
    const path = PathConst.artworkCachePath + fileName;
    if (FileUtils.exists(path)) {
      return FileUtils.addFileScheme(path);
    }
    return null;
  }

  private static lookupName(url: string): string | null {
    const fileName = ArtworkCache.urlIndex.get(url);
    return fileName !== undefined ? fileName : null;
  }

  /** 更新索引并防抖写盘 */
  private static putIndex(url: string, fileName: string): void {
    ArtworkCache.urlIndex.set(url, fileName);
    if (ArtworkCache.persistTimer >= 0) {
      clearTimeout(ArtworkCache.persistTimer);
    }
    ArtworkCache.persistTimer = setTimeout((): void => {
      ArtworkCache.persistTimer = -1;
      ArtworkCache.persistIndex();
    }, PERSIST_DELAY_MS);
  }

  private static persistIndex(): void {
    const map: Record<string, string> = {};
    ArtworkCache.urlIndex.forEach((fileName: string, url: string): void => {
      map[url] = fileName;
    });
    FileUtils.writeFileText(PathConst.artworkCachePath + INDEX_FILE,
      JsonUtil.safeStringify(JsonUtil.fromStringMap(map)));
  }

  /** 首次访问时从 index.json 恢复 URL 索引 */
  private static ensureIndexLoaded(): void {
    if (ArtworkCache.indexLoaded) {
      return;
    }
    ArtworkCache.indexLoaded = true;
    const raw = FileUtils.readFileText(PathConst.artworkCachePath + INDEX_FILE);
    if (raw === null) {
      return;
    }
    const rec = JsonUtil.parseRecord(raw);
    if (rec === null) {
      return;
    }
    const map = JsonUtil.toStringMap(rec);
    for (const k of Object.keys(map)) {
      ArtworkCache.urlIndex.set(k, map[k]);
    }
  }

  private static isHttpUrl(url: string): boolean {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  /** 旧版缓存文件名哈希（URL 双 32 位 FNV，仅用于兼容已存在的旧缓存） */
  private static hashOf(url: string): string {
    let h1 = 0x811c9dc5;
    let h2 = 0x9e3779b9;
    for (let i = 0; i < url.length; i++) {
      const c = url.charCodeAt(i);
      h1 = ((h1 ^ c) * 16777619) % 4294967296;
      h2 = ((h2 ^ c) * 2654435761) % 4294967296;
    }
    return h1.toString(16) + h2.toString(16);
  }

  /** 从地址后缀猜测图片扩展名（去掉查询串），不识别时回退 jpg（仅用于兼容旧缓存） */
  private static extOf(url: string): string {
    let end = url.length;
    const q = url.indexOf('?');
    if (q >= 0) {
      end = Math.min(end, q);
    }
    const h = url.indexOf('#');
    if (h >= 0) {
      end = Math.min(end, h);
    }
    const dot = url.lastIndexOf('.', end - 1);
    if (dot < 0) {
      return 'jpg';
    }
    const slash = url.lastIndexOf('/', end - 1);
    if (dot < slash) {
      return 'jpg';
    }
    const ext = url.substring(dot + 1, end).toLowerCase();
    if (ext === 'jpg' || ext === 'jpeg' || ext === 'png' || ext === 'webp' || ext === 'gif' || ext === 'bmp') {
      return ext;
    }
    return 'jpg';
  }

  /** 按文件头嗅探图片扩展名；非图片字节（错误页/占位内容）返回 null 拒绝入缓存 */
  private static sniffExt(buf: Uint8Array): string | null {
    if (buf.length >= 3) {
      // JPEG
      if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) {
        return 'jpg';
      }
    }
    if (buf.length >= 12) {
      if (buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47) {
        return 'png';
      }
      if (buf[0] === 0x47 && buf[1] === 0x49 && buf[2] === 0x46) {
        return 'gif';
      }
      if (buf[0] === 0x42 && buf[1] === 0x4d) {
        return 'bmp';
      }
      if (buf[0] === 0x52 && buf[1] === 0x49 && buf[2] === 0x46 && buf[3] === 0x46 &&
        buf[8] === 0x57 && buf[9] === 0x45 && buf[10] === 0x42 && buf[11] === 0x50) {
        return 'webp';
      }
    }
    return null;
  }

  private static readFileBytes(path: string): Uint8Array | null {
    try {
      const stat = fs.statSync(path);
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const buf = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buf);
        return new Uint8Array(buf);
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      return null;
    }
  }
}
