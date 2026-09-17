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
  /** 读取本地音频的基础元信息（失败返回空 meta） */
  static async getBasicMeta(path: string): Promise<MediaBasicMeta> {
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
      // 内嵌专辑封面（失败不影响基础元信息）
      try {
        meta.artwork = await MediaMetadata.extractArtwork(path, extractor);
      } catch (e) {
        // 无封面或提取失败，保持为空
      }
    } catch (e) {
      Log.warn('读取媒体元信息失败: ' + path);
    } finally {
      if (extractor !== null) {
        extractor.release().catch(() => {
        });
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
   * 命中缓存直接返回缓存路径，避免重复解码。返回 file:// URI，无封面返回空串
   */
  private static async extractArtwork(path: string,
    extractor: media.AVMetadataExtractor): Promise<string> {
    const hash = await CryptoUtil.md5(path);
    const coverPath = PathConst.artworkCachePath + hash + '.jpg';
    const coverUri = FileUtils.addFileScheme(coverPath);
    if (FileUtils.exists(coverUri)) {
      return coverUri;
    }
    const pixelMap = await extractor.fetchAlbumCover();
    if (pixelMap === undefined || pixelMap === null) {
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
