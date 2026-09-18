import fs from '@ohos.file.fs';
import { HttpClient } from '../infra/HttpClient';
import { PathConst } from '../common/PathConst';
import { FileUtils } from './FileUtils';

/**
 * 网络封面磁盘缓存（写入 artwork 目录，供缓存页统计/清理）
 * resolve() 同步返回：命中缓存返回本地 file:// 路径，未命中返回原地址并后台下载（下次渲染命中）
 */
export class ArtworkCache {
  /** 下载中的地址集合（去重，避免同一封面并发下载） */
  private static inflight: Set<string> = new Set<string>();

  /** 渲染入口：http 地址尝试走本地缓存，其余（file://、data:、空串）原样返回 */
  static resolve(url: string): string {
    if (!ArtworkCache.isHttpUrl(url)) {
      return url;
    }
    const path = ArtworkCache.cachePathOf(url);
    if (FileUtils.exists(path)) {
      return FileUtils.addFileScheme(path);
    }
    ArtworkCache.prefetch(url, path);
    return url;
  }

  /** 下载封面字节：命中缓存读本地，否则下载并写入缓存（供 AVSession 等内存消费方使用） */
  static async downloadBuffer(url: string): Promise<Uint8Array | null> {
    if (!ArtworkCache.isHttpUrl(url)) {
      return null;
    }
    const path = ArtworkCache.cachePathOf(url);
    if (FileUtils.exists(path)) {
      const cached = ArtworkCache.readFileBytes(path);
      if (cached !== null) {
        return cached;
      }
    }
    const buf = await HttpClient.downloadBuffer(url);
    if (buf !== null) {
      FileUtils.writeFileBytes(path, buf);
    }
    return buf;
  }

  /** 后台预取（失败静默，下次渲染重试） */
  private static prefetch(url: string, path: string): void {
    if (ArtworkCache.inflight.has(url)) {
      return;
    }
    ArtworkCache.inflight.add(url);
    HttpClient.downloadToFile(url, path).finally((): void => {
      ArtworkCache.inflight.delete(url);
    });
  }

  private static isHttpUrl(url: string): boolean {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  /** 缓存文件路径：双 32 位 FNV 哈希 + 按地址后缀猜测扩展名 */
  private static cachePathOf(url: string): string {
    return PathConst.artworkCachePath + ArtworkCache.hashOf(url) + '.' + ArtworkCache.extOf(url);
  }

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

  /** 从地址后缀猜测图片扩展名（去掉查询串），不识别时回退 jpg */
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
