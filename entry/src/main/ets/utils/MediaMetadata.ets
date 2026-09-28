import media from '@ohos.multimedia.media';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import { Log } from './Log';
import { PathConst } from '../common/PathConst';
import { FileUtils } from './FileUtils';
import { CryptoUtil } from './CryptoUtil';

/**
 * 媒体元信息提取（替代 RN 的 Mp3Util，基于 AVMetadataExtractor）
 */
export class MediaBasicMeta {
  title: string = '';
  artist: string = '';
  album: string = '';
  /** 时长（毫秒） */
  durationMs: number = 0;
  /** 内嵌专辑封面缓存路径（file:// URI，无封面为空） */
  artwork: string = '';
}

export class MediaMetadata {
  /** 全局串行队列尾巴：AVMetadataExtractor 共享原生解析服务，并发多实例会元数据串读
   * （A 文件读到 B 文件的标题/封面）。所有调用方（扫描导入/本地插件导入等）
   * 统一在此排队，保证全应用同一时刻至多一个 extractor 实例在运行 */
  private static queueTail: Promise<void> = Promise.resolve();

  /** 读取本地音频的基础元信息（失败返回空 meta）；withArtwork=false 时跳过内嵌封面提取；
   * forceArtworkRefresh=true 时绕过封面缓存重新提取并覆盖缓存文件（修复历史串读污染）。
   * 内部经全局队列串行执行，调用方可安全并发调用 */
  static getBasicMeta(path: string, withArtwork: boolean = true,
    forceArtworkRefresh: boolean = false): Promise<MediaBasicMeta> {
    const task = (): Promise<MediaBasicMeta> =>
      MediaMetadata.extractBasicMeta(path, withArtwork, forceArtworkRefresh);
    const next = MediaMetadata.queueTail.then(task, task);
    // 队列尾巴吞掉结果与异常：不出未处理的 rejection，也不阻塞后续排队提取
    MediaMetadata.queueTail = next.then((_m: MediaBasicMeta): void => {
    }, (_e: Object): void => {
    });
    return next;
  }

  private static async extractBasicMeta(path: string, withArtwork: boolean,
    forceArtworkRefresh: boolean): Promise<MediaBasicMeta> {
    const meta = new MediaBasicMeta();
    let file: fs.File | null = null;
    let extractor: media.AVMetadataExtractor | null = null;
    try {
      const stat = fs.statSync(path);
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      extractor = await media.createAVMetadataExtractor();
      const fdSrc: media.AVFileDescriptor = {
        fd: file.fd,
        offset: 0,
        length: stat.size,
      };
      extractor.fdSrc = fdSrc;
      const avMeta: media.AVMetadata = await extractor.fetchMetadata();
      if (avMeta.title !== undefined) {
        meta.title = avMeta.title;
      }
      if (avMeta.artist !== undefined) {
        meta.artist = avMeta.artist;
      }
      if (avMeta.album !== undefined) {
        meta.album = avMeta.album;
      }
      // AVMetadata.duration 为字符串（毫秒）
      if (avMeta.duration !== undefined) {
        const d = Number(avMeta.duration);
        if (!Number.isNaN(d)) {
          meta.durationMs = d;
        }
      }
      // 内嵌专辑封面（失败不影响基础元信息）；自动匹配封面关闭时跳过提取
      if (withArtwork) {
        try {
          meta.artwork = await MediaMetadata.extractArtwork(path, extractor, forceArtworkRefresh);
        } catch (e) {
          // 无封面或提取失败，保持为空
        }
      }
    } catch (e) {
      Log.warn('读取媒体元信息失败: ' + path);
    } finally {
      if (extractor !== null) {
        // 等待原生解析器完全释放后再关闭 fd，避免释放中的实例继续读已关闭的 fd
        try {
          await extractor.release();
        } catch (e) {
          // 释放失败不影响结果返回
        }
      }
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (e) {
          // ignore
        }
      }
    }
    return meta;
  }

  /**
   * 提取内嵌专辑封面并缓存为 JPEG（沙箱 artwork 目录）；
   * 命中缓存直接返回缓存路径，避免重复解码。返回 file:// URI，无封面返回空串。
   * forceRefresh=true 时绕过缓存重新提取并覆盖：历史并发串读可能把其他文件的
   * 封面写进本路径的缓存且命中即返回，导致封面与歌曲不匹配且永不自愈
   */
  private static async extractArtwork(path: string,
    extractor: media.AVMetadataExtractor, forceRefresh: boolean): Promise<string> {
    const hash = await CryptoUtil.md5(path);
    const coverPath = PathConst.artworkCachePath + hash + '.jpg';
    const coverUri = FileUtils.addFileScheme(coverPath);
    if (!forceRefresh && FileUtils.exists(coverUri)) {
      return coverUri;
    }
    const pixelMap = await extractor.fetchAlbumCover();
    if (pixelMap === undefined || pixelMap === null) {
      if (forceRefresh) {
        // 本文件确实无内嵌封面：缓存中已存在的封面必为串读污染，清除
        FileUtils.unlink(coverPath);
      }
      return '';
    }
    const packer = image.createImagePacker();
    let coverFile: fs.File | null = null;
    try {
      const data: ArrayBuffer = await packer.packing(pixelMap, { format: 'image/jpeg', quality: 85 });
      coverFile = fs.openSync(coverPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(coverFile.fd, data);
      return coverUri;
    } finally {
      packer.release();
      pixelMap.release();
      if (coverFile !== null) {
        try {
          fs.closeSync(coverFile);
        } catch (e) {
          // ignore
        }
      }
    }
  }
}
