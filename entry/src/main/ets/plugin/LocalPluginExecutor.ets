import { JsonUtil, JsonRecord } from '../common/JsonUtil';
import { MusicItem, MediaSource, LyricSource } from '../model/MediaTypes';
import { MediaUtils } from '../utils/MediaUtils';
import { MediaMetadata } from '../utils/MediaMetadata';
import { FileUtils } from '../utils/FileUtils';
import { CryptoUtil } from '../utils/CryptoUtil';
import { LOCAL_PLUGIN_PLATFORM } from '../common/Consts';
import { IPluginExecutor, PluginInstanceInfo } from './PluginTypes';

/**
 * 本地文件插件执行器（对应 RN localFilePluginDefine）
 * 原生实现，不走 WebView 沙箱；平台固定为「本地」
 */
export class LocalPluginExecutor implements IPluginExecutor {
  private static inst: LocalPluginExecutor | null = null;

  static get instance(): LocalPluginExecutor {
    if (LocalPluginExecutor.inst === null) {
      LocalPluginExecutor.inst = new LocalPluginExecutor();
    }
    return LocalPluginExecutor.inst;
  }

  mount(pluginKey: string, funcCode: string, appVersion: string): Promise<PluginInstanceInfo> {
    const info = new PluginInstanceInfo();
    info.platform = LOCAL_PLUGIN_PLATFORM;
    info.version = '0.0.0';
    info.cacheControl = 'no-cache';
    info.supportedMethods = ['getMediaSource', 'getMusicInfo', 'getLyric', 'importMusicItem'];
    return Promise.resolve(info);
  }

  async callMethod(pluginKey: string, method: string, argsJson: string): Promise<string> {
    const args = LocalPluginExecutor.parseArgs(argsJson);
    if (method === 'getMediaSource') {
      const item = LocalPluginExecutor.argMusicItem(args, 0);
      const qv: Object | null = args.length > 1 ? args[1] : null;
      let quality = 'standard';
      if (typeof qv === 'string') {
        quality = qv;
      }
      const src = LocalPluginExecutor.getMediaSource(item, quality);
      return src === null ? 'null' : JsonUtil.safeStringify(src.toRecord());
    }
    if (method === 'getMusicInfo') {
      return 'null';
    }
    if (method === 'getLyric') {
      const item = LocalPluginExecutor.argMusicItem(args, 0);
      const lrc = await LocalPluginExecutor.getLyricRaw(item);
      return lrc === null ? 'null' : JsonUtil.safeStringify(lrc.toRecord());
    }
    if (method === 'importMusicItem') {
      const uv: Object | null = args.length > 0 ? args[0] : null;
      let urlLike = '';
      if (typeof uv === 'string') {
        urlLike = uv;
      }
      if (urlLike.length === 0) {
        throw new Error('empty url');
      }
      const rec = await LocalPluginExecutor.importMusicItem(urlLike);
      return JsonUtil.safeStringify(rec);
    }
    throw new Error('method not found: ' + method);
  }

  /** 本地歌词（sidecar .lrc；内嵌 USLT 暂不支持） */
  static async getLyricRaw(item: MusicItem): Promise<LyricSource | null> {
    const localPath = MediaUtils.getLocalPath(item);
    if (localPath === null || localPath.length === 0) {
      return null;
    }
    const lastDot = localPath.lastIndexOf('.');
    const lrcPath = lastDot === -1 ? localPath + '.lrc' : localPath.substring(0, lastDot) + '.lrc';
    const raw = FileUtils.readFileText(lrcPath);
    if (raw !== null && raw.length > 0) {
      const lrc = new LyricSource();
      lrc.rawLrc = raw;
      return lrc;
    }
    return null;
  }

  private static getMediaSource(item: MusicItem, quality: string): MediaSource | null {
    if (quality !== 'standard') {
      return null;
    }
    const localPath = MediaUtils.getLocalPath(item);
    const url = localPath !== null ? localPath : item.url;
    if (url.length === 0) {
      return null;
    }
    const src = new MediaSource();
    src.url = FileUtils.addFileScheme(url);
    src.quality = 'standard';
    return src;
  }

  private static async importMusicItem(urlLike: string): Promise<JsonRecord> {
    let id = '';
    try {
      id = await CryptoUtil.md5(urlLike);
    } catch (e) {
      id = '';
    }
    if (id.length === 0) {
      id = CryptoUtil.nanoid();
    }
    const meta = await MediaMetadata.getBasicMeta(urlLike);
    const internal: JsonRecord = { 'localPath': urlLike };
    const rec: JsonRecord = {
      'id': id,
      'platform': LOCAL_PLUGIN_PLATFORM,
      'title': meta.title.length > 0 ? meta.title : FileUtils.getFileName(urlLike),
      'artist': meta.artist.length > 0 ? meta.artist : '未知歌手',
      'duration': meta.durationMs / 1000,
      'album': meta.album.length > 0 ? meta.album : '未知专辑',
      'artwork': '',
      'url': urlLike,
      '$': internal,
    };
    return rec;
  }

  private static argMusicItem(args: Array<Object | null>, idx: number): MusicItem {
    if (idx < args.length) {
      const rec = JsonUtil.objToRecord(args[idx]);
      if (rec !== null) {
        return MusicItem.fromRecord(rec);
      }
    }
    return new MusicItem();
  }

  private static parseArgs(argsJson: string): Array<Object | null> {
    const result: Array<Object | null> = [];
    const parsed = JsonUtil.parseAny(argsJson);
    if (typeof parsed === 'object' && parsed !== null && Array.isArray(parsed)) {
      const arr = parsed as Array<Object>;
      for (const it of arr) {
        result.push(it);
      }
    }
    return result;
  }
}
