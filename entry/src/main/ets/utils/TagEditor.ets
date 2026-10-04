import { writeAudioMetadata, AudioMetadataWriter } from '@dabing/taglib_harmony';
import { image } from '@kit.ImageKit';
import { MusicItem } from '../common/model/MediaTypes';
import { MediaUtils } from './MediaUtils';
import { FileUtils } from './FileUtils';
import { Log } from './Log';
import { localMusicSheet, downloadedSheet } from '../core/LocalMusicSheet';
import { trackPlayer } from '../core/TrackPlayer';

/** 标签编辑结果 */
export class TagEditOutcome {
  /** 是否成功 */
  ok: boolean = false;
  /** 失败提示文案（成功为空） */
  message: string = '';
}

/** 待写入的标签字段（空串表示清空对应标签） */
export class TagEditFields {
  title: string = '';
  artist: string = '';
  album: string = '';
}

/**
 * 本地音频标签编辑（基于 @dabing/taglib_harmony / TagLib 2.3.1）
 * 写入为原位修改音频文件：仅支持本地路径条目（content:// 媒体库条目不可写）
 */
export class TagEditor {
  /** 全局串行队列尾巴：TagLib 要求同一文件不并发写入，所有写操作统一在此排队 */
  private static queueTail: Promise<void> = Promise.resolve();

  /** 条目是否可编辑标签（存在本地文件且非 content:// 媒体库条目） */
  static canEdit(item: MusicItem): boolean {
    if (trackPlayer.isCurrentMusic(item)) {
      return false;
    }
    const lp = MediaUtils.getLocalPath(item);
    if (lp === null || lp.length === 0 || lp.startsWith('content://')) {
      return false;
    }
    return FileUtils.exists(FileUtils.normalizePath(lp));
  }

  /**
   * 编辑本地音频标签：写入文件 → 同步本地音乐/已下载两域记录。
   * 写入成功后条目内容与文件内标签一致，后续扫描 heal 不会回退。
   */
  static editLocalMusic(item: MusicItem, fields: TagEditFields): Promise<TagEditOutcome> {
    const writer: AudioMetadataWriter = {
      title: fields.title,
      artist: fields.artist,
      album: fields.album,
    };
    return TagEditor.enqueue((): Promise<TagEditOutcome> => TagEditor.performWrite(item, writer, fields));
  }

  /** 写入内嵌封面到本地音频文件（不影响文字标签）：应用内封面记录由调用方负责更新 */
  static writeCover(item: MusicItem, cover: image.PixelMap): Promise<TagEditOutcome> {
    const writer: AudioMetadataWriter = {
      coverImage: cover,
    };
    return TagEditor.enqueue((): Promise<TagEditOutcome> => TagEditor.performWrite(item, writer, null));
  }

  /** 排队写入：TagLib 要求同一文件不并发写入，所有写操作统一在此排队 */
  private static enqueue(task: () => Promise<TagEditOutcome>): Promise<TagEditOutcome> {
    const next = TagEditor.queueTail.then(task, task);
    // 队列尾巴吞掉结果与异常：不出未处理的 rejection，也不阻塞后续排队写入
    TagEditor.queueTail = next.then((_r: TagEditOutcome): void => {
    }, (_e: Object): void => {
    });
    return next;
  }

  /** 执行写入：syncFields 非空表示文字标签编辑，写入成功后同步应用内两域记录 */
  private static performWrite(item: MusicItem, writer: AudioMetadataWriter,
    syncFields: TagEditFields | null): Promise<TagEditOutcome> {
    const outcome = new TagEditOutcome();
    const lp = MediaUtils.getLocalPath(item);
    if (lp === null || lp.length === 0 || lp.startsWith('content://')) {
      outcome.message = '媒体库歌曲不支持编辑';
      return Promise.resolve(outcome);
    }
    const path = FileUtils.normalizePath(lp);
    if (!FileUtils.exists(path)) {
      outcome.message = '本地文件不存在';
      return Promise.resolve(outcome);
    }
    return writeAudioMetadata(path, writer).then((ok: boolean): TagEditOutcome => {
      if (!ok) {
        outcome.message = '写入失败';
        return outcome;
      }
      if (syncFields !== null) {
        // 写入成功：同步应用内两域记录（两域可能持有同一文件的记录，均按路径/同曲目匹配）
        localMusicSheet.updateMusicMeta(item, syncFields.title, syncFields.artist, syncFields.album);
        downloadedSheet.updateMusicMeta(item, syncFields.title, syncFields.artist, syncFields.album);
      }
      outcome.ok = true;
      return outcome;
    }).catch((_e: Object): TagEditOutcome => {
      Log.warn('写入音频标签失败: ' + path);
      outcome.message = '写入失败';
      return outcome;
    });
  }
}
