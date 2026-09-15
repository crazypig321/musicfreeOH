import media from '@ohos.multimedia.media';
import fs from '@ohos.file.fs';
import { Log } from './Log';

/**
 * 媒体元信息提取（替代 RN 的 Mp3Util，基于 AVMetadataExtractor）
 */
export class MediaBasicMeta {
  title: string = '';
  artist: string = '';
  album: string = '';
  /** 时长（毫秒） */
  durationMs: number = 0;
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
}
