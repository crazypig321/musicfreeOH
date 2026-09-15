import { MusicItem } from '../common/model/MediaTypes';
import { LOCAL_PLUGIN_PLATFORM, INTERNAL_SERIALIZE_KEY } from '../common/Consts';
import { JsonUtil, JsonRecord } from '../common/JsonUtil';
import { MediaExtra } from '../core/MediaExtra';

/**
 * 媒体工具（移植自 mediaUtils.ts）
 */
export class MediaUtils {
  /** 媒体唯一key: platform@id */
  static getUniqueKey(platform: string, id: string): string {
    return platform + '@' + id;
  }

  static getMediaUniqueKey(media: MusicItem): string {
    return media.platform + '@' + media.id;
  }

  /** 判断两个媒体是否相同 */
  static isSameMediaItem(a: MusicItem | null | undefined, b: MusicItem | null | undefined): boolean {
    if (a === null || a === undefined || b === null || b === undefined) {
      return false;
    }
    return a.id === b.id && a.platform === b.platform;
  }

  /**
   * 复位媒体项：设置平台并剥离内部字段（$），对应 RN resetMediaItem
   * @param newObj 为 true 时返回新对象（不动原对象）
   */
  static resetMediaItem(mediaItem: MusicItem, platform?: string, newObj?: boolean): MusicItem {
    let item = mediaItem;
    if (mediaItem.platform === LOCAL_PLUGIN_PLATFORM || platform === LOCAL_PLUGIN_PLATFORM) {
      return item;
    }
    if (newObj === true) {
      item = mediaItem.clone();
    }
    if (platform !== undefined && platform.length > 0) {
      item.platform = platform;
    }
    MediaUtils.stripInternalFields(item);
    return item;
  }

  /**
   * 复位 JsonRecord（用于 sheet/album 等非 MusicItem 的记录）
   * 返回新对象，剥离 $ 字段
   */
  static resetRecord(rec: JsonRecord, platform?: string): JsonRecord {
    const ownPlatform = JsonUtil.recStr(rec, 'platform');
    if (ownPlatform === LOCAL_PLUGIN_PLATFORM || platform === LOCAL_PLUGIN_PLATFORM) {
      return JsonUtil.cloneRecord(rec);
    }
    const result = JsonUtil.omitKeys(rec, [INTERNAL_SERIALIZE_KEY]);
    if (platform !== undefined && platform.length > 0) {
      result['platform'] = platform;
    }
    return result;
  }

  /** 从 extras 中剥离内部字段（$） */
  private static stripInternalFields(mediaItem: MusicItem): void {
    if (mediaItem.extras[INTERNAL_SERIALIZE_KEY] === undefined) {
      return;
    }
    mediaItem.extras = JsonUtil.omitKeys(mediaItem.extras, [INTERNAL_SERIALIZE_KEY]);
  }

  /**
   * 获取媒体资源的本地路径（不存在返回 null）
   * - url 为 file:// 开头 → 剥掉 scheme 返回磁盘路径
   * - url 为 content:// → 原样返回
   * - extras['$'].localPath（遗留）
   * - MediaExtra.localPath
   */
  static getLocalPath(mediaItem: MusicItem): string | null {
    if (mediaItem.url.startsWith('file://')) {
      return mediaItem.url.substring('file://'.length);
    }
    if (mediaItem.url.startsWith('content://')) {
      return mediaItem.url;
    }
    const legacy = JsonUtil.objToRecord(mediaItem.extras[INTERNAL_SERIALIZE_KEY]);
    if (legacy !== null) {
      const lp = JsonUtil.recStr(legacy, 'localPath');
      if (lp.length > 0) {
        return lp;
      }
    }
    const localPathInMediaExtra = MediaExtra.getMediaExtraProperty(mediaItem, 'localPath');
    if (typeof localPathInMediaExtra === 'string' && localPathInMediaExtra.length > 0) {
      return localPathInMediaExtra;
    }
    return null;
  }

  /** 数组随机打乱 */
  static shuffle<T>(arr: Array<T>): Array<T> {
    const result = arr.slice();
    for (let i = result.length - 1; i > 0; --i) {
      const j = Math.floor(Math.random() * (i + 1));
      const tmp = result[i];
      result[i] = result[j];
      result[j] = tmp;
    }
    return result;
  }
}
