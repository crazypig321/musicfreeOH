import util from '@ohos.util';
import { JsonUtil, JsonRecord } from '../common/JsonUtil';
import { MusicItem, MediaSource, LyricSource, QualityKey } from '../common/model/MediaTypes';
import {
  SupportMediaType, SearchResult, AlbumItem, ArtistItem, SheetItem, MediaTag, SheetGroupItem,
  PageResult, AlbumInfoResult, SheetInfoResult, TopListInfoResult, RecommendSheetTagsResult,
  CommentsResult,
} from '../common/model/SheetTypes';
import { MediaUtils } from '../utils/MediaUtils';
import { MediaCache } from '../core/MediaCache';
import { MediaExtra, MediaExtraProperties } from '../core/MediaExtra';
import { AppMeta } from '../core/AppMeta';
import { PathConst } from '../common/PathConst';
import { CacheControl, LOCAL_PLUGIN_PLATFORM } from '../common/Consts';
import { FileUtils } from '../utils/FileUtils';
import { CryptoUtil } from '../utils/CryptoUtil';
import { Network } from '../infra/Network';
import { HttpClient } from '../infra/HttpClient';
import { VersionCompare } from '../utils/VersionCompare';
import { Delay } from '../utils/Delay';
import { Log, devLog } from '../utils/Log';
import { IPluginExecutor, PluginState, PluginErrorReason, PluginInstanceInfo, LazyProps } from './PluginTypes';
import { LocalPluginExecutor } from './LocalPluginExecutor';

/**
 * 带鉴权信息解析后的 url
 */
class AuthUrlResult {
  url: string = '';
  auth: string = '';
}

/**
 * 解析 url 中的 userinfo（user:pass@host）生成 Basic 鉴权
 * @ohos.url.URL 不支持 password 属性，手工解析
 */
function formatAuthUrl(url: string): AuthUrlResult {
  const result = new AuthUrlResult();
  result.url = url;
  const schemeIdx = url.indexOf('://');
  if (schemeIdx <= 0) {
    return result;
  }
  const afterScheme = url.substring(schemeIdx + 3);
  let authorityEnd = afterScheme.length;
  for (let i = 0; i < afterScheme.length; ++i) {
    const ch = afterScheme.charAt(i);
    if (ch === '/' || ch === '?' || ch === '#') {
      authorityEnd = i;
      break;
    }
  }
  const authority = afterScheme.substring(0, authorityEnd);
  const rest = afterScheme.substring(authorityEnd);
  const atIdx = authority.lastIndexOf('@');
  if (atIdx === -1) {
    return result;
  }
  const userinfo = authority.substring(0, atIdx);
  const hostPart = authority.substring(atIdx + 1);
  const colonIdx = userinfo.indexOf(':');
  if (colonIdx === -1) {
    return result;
  }
  const usernameEnc = userinfo.substring(0, colonIdx);
  const passwordEnc = userinfo.substring(colonIdx + 1);
  if (usernameEnc.length === 0 || passwordEnc.length === 0) {
    return result;
  }
  try {
    const username = decodeURIComponent(usernameEnc);
    const password = decodeURIComponent(passwordEnc);
    const encoder = new util.TextEncoder();
    const cred = encoder.encodeInto(username + ':' + password);
    const helper = new util.Base64Helper();
    result.auth = 'Basic ' + helper.encodeToStringSync(cred);
    result.url = url.substring(0, schemeIdx + 3) + hostPart + rest;
  } catch (e) {
    // decode 失败时保持原 url
  }
  return result;
}

/**
 * Plugin 依赖的 PluginManager 子集（避免循环依赖，由 PluginManager 注入）
 */
export interface IPluginManagerLike {
  getByName(name: string): Plugin | null;
  getByMedia(item: MusicItem): Plugin | null;
  getAlternativePlugin(plugin: Plugin): Plugin | null;
}

/**
 * 插件方法包装（对应 RN PluginMethodsWrapper）
 */
class PluginMethods {
  private plugin: Plugin;
  private ensurePluginIsMounted: () => Promise<void>;

  constructor(plugin: Plugin, ensurePluginIsMounted: () => Promise<void>) {
    this.plugin = plugin;
    this.ensurePluginIsMounted = ensurePluginIsMounted;
  }

  /** 搜索 */
  async search(query: string, page: number, type: SupportMediaType): Promise<SearchResult> {
    await this.ensurePluginIsMounted();
    if (!this.plugin.hasMethod('search')) {
      const empty = new SearchResult();
      empty.isEnd = true;
      return empty;
    }
    const result = await this.plugin.callMethod('search', [query, page, type]);
    return PluginMethods.parseSearchResult(result, type, this.plugin.name);
  }

  private static parseSearchResult(v: Object | null, type: SupportMediaType, pluginName: string): SearchResult {
    const result = new SearchResult();
    const rec = JsonUtil.objToRecord(v);
    if (rec === null) {
      result.isEnd = true;
      return result;
    }
    const arr = JsonUtil.recArray(rec, 'data');
    if (arr === null) {
      result.isEnd = true;
      return result;
    }
    result.isEnd = JsonUtil.recBool(rec, 'isEnd', true);
    for (const o of arr) {
      const r = JsonUtil.objToRecord(o);
      if (r === null) {
        continue;
      }
      const reset = MediaUtils.resetRecord(r, pluginName);
      if (type === SupportMediaType.Music) {
        result.musicData.push(MusicItem.fromRecord(reset));
      } else if (type === SupportMediaType.Album) {
        result.albumData.push(AlbumItem.fromRecord(reset));
      } else if (type === SupportMediaType.Artist) {
        result.artistData.push(ArtistItem.fromRecord(reset));
      } else if (type === SupportMediaType.Sheet) {
        result.sheetData.push(SheetItem.fromRecord(reset));
      } else {
        result.lyricData.push(MusicItem.fromRecord(reset));
      }
    }
    return result;
  }

  /** 获取真实源 */
  async getMediaSource(musicItem: MusicItem, quality: QualityKey = 'standard',
    retryCount: number = 1, notUpdateCache: boolean = false): Promise<MediaSource | null> {
    await this.ensurePluginIsMounted();
    // 1. 本地播放
    const localPathExtra = MediaExtra.getMediaExtraProperty(musicItem, 'localPath');
    const extraLocalPath = typeof localPathExtra === 'string' ? localPathExtra : '';
    const localPath = MediaUtils.getLocalPath(musicItem);
    if (localPath !== null && FileUtils.exists(localPath)) {
      if (extraLocalPath !== localPath) {
        const patch = new MediaExtraProperties();
        patch.localPath = localPath;
        MediaExtra.patchMediaExtra(musicItem, patch);
      }
      const src = new MediaSource();
      src.url = FileUtils.addFileScheme(localPath);
      src.quality = quality;
      return src;
    } else if (extraLocalPath.length > 0) {
      MediaExtra.removeMediaExtraProperty(musicItem, 'localPath');
    }

    if (musicItem.platform === LOCAL_PLUGIN_PLATFORM) {
      throw new Error('本地音乐不存在');
    }

    // 2. 缓存播放
    const mediaCache = MediaCache.getMediaCache(musicItem);
    const pluginCacheControl = this.plugin.cacheControl();
    if (mediaCache !== null) {
      const cachedSource = mediaCache.source[quality];
      if (cachedSource !== undefined && cachedSource.url.length > 0 &&
        (pluginCacheControl === CacheControl.Cache ||
          (pluginCacheControl === CacheControl.NoCache && Network.getInstance().isOffline))) {
        const headersRec = JsonUtil.objToRecord(mediaCache.extras['headers']);
        const headers = JsonUtil.toStringMap(headersRec);
        let userAgent = '';
        const uaVal = mediaCache.extras['userAgent'];
        if (typeof uaVal === 'string') {
          userAgent = uaVal;
        } else if (headersRec !== null) {
          userAgent = JsonUtil.recStr(headersRec, 'user-agent');
        }
        const src = new MediaSource();
        src.url = cachedSource.url;
        src.headers = headers;
        src.userAgent = userAgent;
        src.quality = cachedSource.quality;
        return src;
      }
    }

    // 3. 替代插件
    const pm = Plugin.pluginManager;
    const alternativePlugin = pm !== null ? pm.getAlternativePlugin(this.plugin) : null;
    const parserPlugin = alternativePlugin !== null && alternativePlugin.hasMethod('getMediaSource')
      ? alternativePlugin : this.plugin;
    if (parserPlugin !== this.plugin) {
      devLog('info', '设置了替代插件，实际使用的插件为 ' + parserPlugin.name);
    }

    // 4. 插件解析
    if (!parserPlugin.hasMethod('getMediaSource')) {
      const qualitiesRec = JsonUtil.recRecord(musicItem.qualities, quality);
      const fallbackUrl = qualitiesRec !== null ? JsonUtil.recStr(qualitiesRec, 'url') : '';
      const targetUrl = fallbackUrl.length > 0 ? fallbackUrl : musicItem.url;
      const authResult = formatAuthUrl(targetUrl);
      const src = new MediaSource();
      src.url = authResult.url;
      src.quality = quality;
      if (authResult.auth.length > 0) {
        src.headers = { 'Authorization': authResult.auth };
      }
      return src;
    }
    try {
      let url = '';
      let headers: Record<string, string> = {};
      const rawResult = await this.plugin.callMethodOn(parserPlugin, 'getMediaSource',
        [musicItem.toPluginRecord(), quality]);
      const resultRec = JsonUtil.objToRecord(rawResult);
      if (resultRec === null) {
        const qualitiesRec = JsonUtil.recRecord(musicItem.qualities, quality);
        url = qualitiesRec !== null ? JsonUtil.recStr(qualitiesRec, 'url') : '';
      } else {
        url = JsonUtil.recStr(resultRec, 'url');
        const headersRec = JsonUtil.recRecord(resultRec, 'headers');
        if (headersRec !== null) {
          headers = JsonUtil.toStringMap(headersRec);
        }
      }
      if (url.length === 0) {
        throw new Error('NOT RETRY');
      }
      const src = new MediaSource();
      src.url = url;
      src.headers = headers;
      src.quality = quality;
      const uaVal = headers['user-agent'];
      if (typeof uaVal === 'string') {
        src.userAgent = uaVal;
      }
      const authFormatted = formatAuthUrl(src.url);
      if (authFormatted.auth.length > 0) {
        src.url = authFormatted.url;
        const merged: Record<string, string> = {};
        for (const k of Object.keys(src.headers)) {
          merged[k] = src.headers[k];
        }
        merged['Authorization'] = authFormatted.auth;
        src.headers = merged;
      }

      if (pluginCacheControl !== CacheControl.NoStore && !notUpdateCache) {
        // 更新缓存
        const cacheSource = new MediaSource();
        cacheSource.url = url;
        cacheSource.headers = src.headers;
        cacheSource.userAgent = src.userAgent;
        cacheSource.quality = quality;
        let realItem: MusicItem;
        if (mediaCache !== null) {
          const base = musicItem.toPluginRecord();
          const over = mediaCache.toPluginRecord();
          for (const k of Object.keys(over)) {
            base[k] = over[k];
          }
          realItem = MusicItem.fromRecord(base);
        } else {
          realItem = musicItem.clone();
        }
        realItem.source[quality] = cacheSource;
        MediaCache.setMediaCache(realItem);
      }
      return src;
    } catch (e) {
      const message = e instanceof Error ? e.message : '';
      if (retryCount > 0 && message !== 'NOT RETRY') {
        await Delay.wait(150);
        return this.getMediaSource(musicItem, quality, retryCount - 1, notUpdateCache);
      }
      Log.error('获取真实源失败: ' + message);
      return null;
    }
  }

  /** 获取音乐详情 */
  async getMusicInfo(musicItem: MusicItem): Promise<JsonRecord | null> {
    await this.ensurePluginIsMounted();
    if (!this.plugin.hasMethod('getMusicInfo')) {
      return null;
    }
    try {
      const resetItem = MediaUtils.resetMediaItem(musicItem, undefined, true);
      const result = await this.plugin.callMethod('getMusicInfo', [resetItem.toPluginRecord()]);
      return JsonUtil.objToRecord(result);
    } catch (e) {
      Log.error('获取音乐详情失败');
      return null;
    }
  }

  /** 获取歌词 */
  async getLyric(originalMusicItem: MusicItem): Promise<LyricSource | null> {
    await this.ensurePluginIsMounted();
    // 1. 额外存储的meta信息（关联歌词）
    const associatedLrcProp = MediaExtra.getMediaExtraProperty(originalMusicItem, 'associatedLrc');
    const associatedRec = JsonUtil.objToRecord(associatedLrcProp);
    let musicItem: MusicItem = originalMusicItem;
    if (associatedRec !== null) {
      musicItem = MusicItem.fromRecord(associatedRec);
    }

    const musicItemCacheInfo = MediaCache.getLyricCacheInfo(musicItem);

    /** 原始歌词文本 */
    let rawLrc: string = musicItem.rawLrc;
    let translation: string = '';

    // 2. 本地手动设置的歌词
    const platformHash = await CryptoUtil.md5(musicItem.platform);
    const idHash = await CryptoUtil.md5(musicItem.id);
    const manualLrcPath = PathConst.localLrcPath + platformHash + '/' + idHash + '.lrc';
    if (FileUtils.exists(manualLrcPath)) {
      const manualRaw = FileUtils.readFileText(manualLrcPath);
      if (manualRaw !== null) {
        rawLrc = manualRaw;
      }
      const manualTransPath = PathConst.localLrcPath + platformHash + '/' + idHash + '.tran.lrc';
      if (FileUtils.exists(manualTransPath)) {
        const manualTrans = FileUtils.readFileText(manualTransPath);
        if (manualTrans !== null) {
          translation = manualTrans;
        }
      }
      const source = new LyricSource();
      source.rawLrc = rawLrc;
      source.translation = translation;
      return source;
    }

    // 2.5 缓存歌词 / 对象上本身的歌词
    if (musicItemCacheInfo !== null && musicItemCacheInfo.hasLyricField) {
      // 优先用缓存的结果（远程）
      if (musicItemCacheInfo.cachedRawLrc.length > 0 || musicItemCacheInfo.cachedTrans.length > 0) {
        const cached = new LyricSource();
        cached.rawLrc = musicItemCacheInfo.cachedRawLrc;
        cached.translation = musicItemCacheInfo.cachedTrans;
        return cached;
      }

      // 本地其实是缓存的路径
      let needRefetch = false;
      if (musicItemCacheInfo.rawLrcPath.length > 0) {
        if (FileUtils.exists(musicItemCacheInfo.rawLrcPath)) {
          const content = FileUtils.readFileText(musicItemCacheInfo.rawLrcPath);
          if (content !== null) {
            rawLrc = content;
          }
        } else {
          needRefetch = true;
        }
      }
      if (musicItemCacheInfo.transPath.length > 0) {
        if (FileUtils.exists(musicItemCacheInfo.transPath)) {
          const content = FileUtils.readFileText(musicItemCacheInfo.transPath);
          if (content !== null) {
            translation = content;
          }
        } else {
          needRefetch = true;
        }
      }
      if (!needRefetch && (rawLrc.length > 0 || translation.length > 0)) {
        const source = new LyricSource();
        source.rawLrc = rawLrc;
        source.translation = translation;
        return source;
      }
    }

    // 3. 无缓存歌词/无自带歌词/无本地歌词
    let lrcSourceRec: JsonRecord | null = null;
    if (MediaUtils.isSameMediaItem(originalMusicItem, musicItem)) {
      if (this.plugin.hasMethod('getLyric')) {
        try {
          const resetItem = MediaUtils.resetMediaItem(musicItem, undefined, true);
          const result = await this.plugin.callMethod('getLyric', [resetItem.toPluginRecord()]);
          lrcSourceRec = JsonUtil.objToRecord(result);
        } catch (e) {
          lrcSourceRec = null;
        }
      }
    } else {
      const pm = Plugin.pluginManager;
      const targetPlugin = pm !== null ? pm.getByMedia(musicItem) : null;
      if (targetPlugin !== null && targetPlugin.hasMethod('getLyric')) {
        try {
          const resetItem = MediaUtils.resetMediaItem(musicItem, undefined, true);
          const result = await this.plugin.callMethodOn(targetPlugin, 'getLyric', [resetItem.toPluginRecord()]);
          lrcSourceRec = JsonUtil.objToRecord(result);
        } catch (e) {
          lrcSourceRec = null;
        }
      }
    }

    if (lrcSourceRec !== null) {
      const srcRawLrc = JsonUtil.recStr(lrcSourceRec, 'rawLrc');
      if (srcRawLrc.length > 0) {
        rawLrc = srcRawLrc;
      }
      translation = JsonUtil.recStr(lrcSourceRec, 'translation');

      const srcLrcUrl = JsonUtil.recStr(lrcSourceRec, 'lrc');
      const deprecatedLrcUrl = srcLrcUrl.length > 0 ? srcLrcUrl : musicItem.lrc;

      // 本地的文件名
      let filename = PathConst.lrcCachePath + CryptoUtil.nanoid() + '.lrc';
      let filenameTrans = PathConst.lrcCachePath + CryptoUtil.nanoid() + '.lrc';

      // 旧版本兼容
      if (rawLrc.length === 0 && translation.length === 0) {
        if (deprecatedLrcUrl.length > 0) {
          const resp = await HttpClient.get(deprecatedLrcUrl, undefined, 3000);
          if (resp !== null) {
            rawLrc = resp.body;
          }
        } else if (musicItem.rawLrc.length > 0) {
          rawLrc = musicItem.rawLrc;
        }
      }

      if (rawLrc.length > 0) {
        FileUtils.writeFileText(filename, rawLrc);
      } else {
        filename = '';
      }
      if (translation.length > 0) {
        FileUtils.writeFileText(filenameTrans, translation);
      } else {
        filenameTrans = '';
      }

      if (rawLrc.length > 0 || translation.length > 0) {
        MediaCache.setLyricCachePaths(musicItem, filename, filenameTrans);
        const source = new LyricSource();
        source.rawLrc = rawLrc;
        source.translation = translation;
        return source;
      }
    }

    // 6. 如果是本地文件
    const localFilePath = MediaUtils.getLocalPath(originalMusicItem);
    if (originalMusicItem.platform !== LOCAL_PLUGIN_PLATFORM && localFilePath !== null) {
      const res = await LocalPluginExecutor.getLyricRaw(originalMusicItem);
      if (res !== null) {
        return res;
      }
    }
    return null;
  }

  /** 获取专辑信息 */
  async getAlbumInfo(albumItem: AlbumItem, page: number = 1): Promise<AlbumInfoResult | null> {
    await this.ensurePluginIsMounted();
    if (!this.plugin.hasMethod('getAlbumInfo')) {
      const result = new AlbumInfoResult();
      result.albumItem = albumItem;
      const presetArr = JsonUtil.objToRecordArray(albumItem.extras['musicList']);
      if (presetArr !== null) {
        for (const rec of presetArr) {
          result.musicList.push(MusicItem.fromRecord(MediaUtils.resetRecord(rec, this.plugin.name)));
        }
      }
      result.isEnd = true;
      return result;
    }
    try {
      const argRec = MediaUtils.resetRecord(albumItem.toRecord());
      const raw = await this.plugin.callMethod('getAlbumInfo', [argRec, page]);
      const rec = JsonUtil.objToRecord(raw);
      if (rec === null) {
        throw new Error('empty');
      }
      const result = new AlbumInfoResult();
      result.isEnd = JsonUtil.recBool(rec, 'isEnd', true);
      const musicArr = JsonUtil.recArray(rec, 'musicList');
      if (musicArr !== null) {
        for (const o of musicArr) {
          const r = JsonUtil.objToRecord(o);
          if (r === null) {
            continue;
          }
          const reset = MediaUtils.resetRecord(r, this.plugin.name);
          reset['album'] = albumItem.title;
          result.musicList.push(MusicItem.fromRecord(reset));
        }
      }
      if (page <= 1) {
        // 合并信息
        const albumRec = JsonUtil.recRecord(rec, 'albumItem');
        const merged = JsonUtil.cloneRecord(albumItem.toRecord());
        if (albumRec !== null) {
          for (const k of Object.keys(albumRec)) {
            merged[k] = albumRec[k];
          }
        }
        result.albumItem = AlbumItem.fromRecord(merged);
      }
      return result;
    } catch (e) {
      Log.error('获取专辑信息失败');
      return null;
    }
  }

  /** 获取歌单信息 */
  async getMusicSheetInfo(sheetItem: SheetItem, page: number = 1): Promise<SheetInfoResult | null> {
    await this.ensurePluginIsMounted();
    if (!this.plugin.hasMethod('getMusicSheetInfo')) {
      const result = new SheetInfoResult();
      result.sheetItem = sheetItem;
      const presetArr = JsonUtil.objToRecordArray(sheetItem.extras['musicList']);
      if (presetArr !== null) {
        for (const rec of presetArr) {
          result.musicList.push(MusicItem.fromRecord(MediaUtils.resetRecord(rec, this.plugin.name)));
        }
      }
      result.isEnd = true;
      return result;
    }
    try {
      const argRec = MediaUtils.resetRecord(sheetItem.toRecord());
      const raw = await this.plugin.callMethod('getMusicSheetInfo', [argRec, page]);
      const rec = JsonUtil.objToRecord(raw);
      if (rec === null) {
        throw new Error('empty');
      }
      const result = new SheetInfoResult();
      result.isEnd = JsonUtil.recBool(rec, 'isEnd', true);
      const musicArr = JsonUtil.recArray(rec, 'musicList');
      if (musicArr !== null) {
        for (const o of musicArr) {
          const r = JsonUtil.objToRecord(o);
          if (r === null) {
            continue;
          }
          result.musicList.push(MusicItem.fromRecord(MediaUtils.resetRecord(r, this.plugin.name)));
        }
      }
      if (page <= 1) {
        // 合并信息
        const sheetRec = JsonUtil.recRecord(rec, 'sheetItem');
        const merged = JsonUtil.cloneRecord(sheetItem.toRecord());
        if (sheetRec !== null) {
          for (const k of Object.keys(sheetRec)) {
            merged[k] = sheetRec[k];
          }
        }
        result.sheetItem = SheetItem.fromRecord(merged);
      }
      return result;
    } catch (e) {
      Log.error('获取歌单信息失败');
      return null;
    }
  }

  /** 查询作者信息 */
  async getArtistWorks(artistItem: ArtistItem, page: number,
    type: SupportMediaType): Promise<SearchResult> {
    await this.ensurePluginIsMounted();
    if (!this.plugin.hasMethod('getArtistWorks')) {
      const empty = new SearchResult();
      empty.isEnd = true;
      return empty;
    }
    try {
      const raw = await this.plugin.callMethod('getArtistWorks', [artistItem.toRecord(), page, type]);
      return PluginMethods.parseSearchResult(raw, type, this.plugin.name);
    } catch (e) {
      Log.error('查询作者信息失败');
      if (e instanceof Error) {
        throw e;
      }
      throw new Error('查询作者信息失败');
    }
  }

  /** 导入歌单 */
  async importMusicSheet(urlLike: string): Promise<Array<MusicItem>> {
    await this.ensurePluginIsMounted();
    try {
      const result: Array<MusicItem> = [];
      if (this.plugin.hasMethod('importMusicSheet')) {
        const raw = await this.plugin.callMethod('importMusicSheet', [urlLike]);
        const arr = JsonUtil.objToRecordArray(raw);
        if (arr !== null) {
          for (const rec of arr) {
            result.push(MusicItem.fromRecord(MediaUtils.resetRecord(rec, this.plugin.name)));
          }
        }
      }
      return result;
    } catch (e) {
      Log.error('导入歌单失败');
      return [];
    }
  }

  /** 导入单曲 */
  async importMusicItem(urlLike: string): Promise<MusicItem | null> {
    await this.ensurePluginIsMounted();
    try {
      if (!this.plugin.hasMethod('importMusicItem')) {
        return null;
      }
      const raw = await this.plugin.callMethod('importMusicItem', [urlLike]);
      const rec = JsonUtil.objToRecord(raw);
      if (rec === null) {
        throw new Error('empty');
      }
      return MusicItem.fromRecord(MediaUtils.resetRecord(rec, this.plugin.name));
    } catch (e) {
      Log.error('导入单曲失败');
      return null;
    }
  }

  /** 获取榜单 */
  async getTopLists(): Promise<Array<SheetGroupItem>> {
    await this.ensurePluginIsMounted();
    try {
      if (!this.plugin.hasMethod('getTopLists')) {
        throw new Error('empty');
      }
      const raw = await this.plugin.callMethod('getTopLists', []);
      const arr = JsonUtil.objToRecordArray(raw);
      if (arr === null) {
        throw new Error('empty');
      }
      const result: Array<SheetGroupItem> = [];
      for (const rec of arr) {
        result.push(SheetGroupItem.fromRecord(rec));
      }
      return result;
    } catch (e) {
      Log.error('获取榜单失败');
      return [];
    }
  }

  /** 获取榜单详情 */
  async getTopListDetail(topListItem: SheetItem, page: number): Promise<TopListInfoResult> {
    await this.ensurePluginIsMounted();
    const raw = this.plugin.hasMethod('getTopListDetail')
      ? await this.plugin.callMethod('getTopListDetail', [topListItem.toRecord(), page])
      : null;
    const rec = JsonUtil.objToRecord(raw);
    if (rec === null) {
      throw new Error('empty');
    }
    const result = new TopListInfoResult();
    result.isEnd = JsonUtil.recBool(rec, 'isEnd', true);
    const sheetRec = JsonUtil.recRecord(rec, 'topListItem');
    if (sheetRec !== null) {
      result.topListItem = SheetItem.fromRecord(sheetRec);
    }
    const musicArr = JsonUtil.recArray(rec, 'musicList');
    if (musicArr !== null) {
      for (const o of musicArr) {
        const r = JsonUtil.objToRecord(o);
        if (r === null) {
          continue;
        }
        result.musicList.push(MusicItem.fromRecord(MediaUtils.resetRecord(r, this.plugin.name)));
      }
    }
    return result;
  }

  /** 获取推荐歌单的tag */
  async getRecommendSheetTags(): Promise<RecommendSheetTagsResult> {
    await this.ensurePluginIsMounted();
    try {
      if (!this.plugin.hasMethod('getRecommendSheetTags')) {
        throw new Error('empty');
      }
      const raw = await this.plugin.callMethod('getRecommendSheetTags', []);
      return RecommendSheetTagsResult.fromJson(raw);
    } catch (e) {
      Log.error('获取推荐歌单失败', e instanceof Error ? e.message : JSON.stringify(e));
      return new RecommendSheetTagsResult();
    }
  }

  /** 获取某个tag的推荐歌单 */
  async getRecommendSheetsByTag(tagItem: MediaTag, page: number = 1): Promise<PageResult<SheetItem>> {
    await this.ensurePluginIsMounted();
    try {
      if (!this.plugin.hasMethod('getRecommendSheetsByTag')) {
        throw new Error('empty');
      }
      const raw = await this.plugin.callMethod('getRecommendSheetsByTag', [tagItem.toRecord(), page]);
      const rec = JsonUtil.objToRecord(raw);
      if (rec === null) {
        throw new Error('empty');
      }
      const result = new PageResult<SheetItem>();
      result.isEnd = JsonUtil.recBool(rec, 'isEnd', true);
      const arr = JsonUtil.recArray(rec, 'data');
      if (arr !== null) {
        for (const o of arr) {
          const r = JsonUtil.objToRecord(o);
          if (r === null) {
            continue;
          }
          result.data.push(SheetItem.fromRecord(MediaUtils.resetRecord(r, this.plugin.name)));
        }
      }
      return result;
    } catch (e) {
      Log.error('获取推荐歌单详情失败');
      const result = new PageResult<SheetItem>();
      result.isEnd = true;
      return result;
    }
  }

  /** 获取音乐评论 */
  async getMusicComments(musicItem: MusicItem, page: number = 1): Promise<CommentsResult> {
    await this.ensurePluginIsMounted();
    const raw = this.plugin.hasMethod('getMusicComments')
      ? await this.plugin.callMethod('getMusicComments', [musicItem.toPluginRecord(), page])
      : null;
    const rec = JsonUtil.objToRecord(raw);
    if (rec === null) {
      throw new Error('empty');
    }
    return CommentsResult.fromJson(rec);
  }
}

/**
 * 插件类（对应 RN Plugin）
 */
export class Plugin {
  /** 插件名 */
  name: string = '';
  /** 插件的hash，作为唯一id */
  hash: string = '';
  /** 插件状态 */
  state: PluginState = PluginState.Initializing;
  /** 插件出错时的原因 */
  errorReason: PluginErrorReason | null = null;
  /** 挂载后的实例信息 */
  instanceInfo: PluginInstanceInfo | null = null;
  /** 插件路径 */
  path: string = '';
  /** 插件方法，内部进行标准化和校验 */
  methods: PluginMethods;
  /** 支持的方法名 */
  supportedMethods: Set<string> = new Set<string>();

  private lazyProps: LazyProps | null = null;
  private executor: IPluginExecutor;

  static pluginManager: IPluginManagerLike | null = null;

  static injectDependencies(pluginManager: IPluginManagerLike): void {
    Plugin.pluginManager = pluginManager;
  }

  private constructor(executor: IPluginExecutor, lazyProps: LazyProps | null) {
    this.executor = executor;
    this.lazyProps = lazyProps;
    this.methods = new PluginMethods(this, (): Promise<void> => this.ensureMounted());
    if (lazyProps !== null) {
      // 使用懒加载参数初始化
      this.name = lazyProps.name;
      this.hash = lazyProps.hash;
      this.path = lazyProps.path;
      if (lazyProps.instanceInfo !== null) {
        this.instanceInfo = lazyProps.instanceInfo;
      } else {
        const info = new PluginInstanceInfo();
        info.platform = lazyProps.name;
        this.instanceInfo = info;
      }
      for (const m of lazyProps.supportedMethods) {
        this.supportedMethods.add(m);
      }
    }
  }

  /** 立即挂载插件 */
  static async create(funcCode: string, pluginPath: string, executor: IPluginExecutor): Promise<Plugin> {
    const plugin = new Plugin(executor, null);
    await plugin.mountPlugin(funcCode, pluginPath);
    return plugin;
  }

  /** 本地插件（原生实现，hash 由外部指定） */
  static async createNative(executor: IPluginExecutor, pluginPath: string, hash: string): Promise<Plugin> {
    const plugin = new Plugin(executor, null);
    await plugin.mountPlugin('', pluginPath, hash);
    return plugin;
  }

  /** 懒加载插件 */
  static createLazy(lazyProps: LazyProps, executor: IPluginExecutor): Plugin {
    return new Plugin(executor, lazyProps);
  }

  /** 懒加载插件确保挂载 */
  async ensureMounted(): Promise<void> {
    if (this.state === PluginState.Initializing && this.lazyProps !== null) {
      this.state = PluginState.Loading;
      const loadFuncCode = this.lazyProps.loadFuncCode;
      try {
        const funcCode = await loadFuncCode();
        await this.mountPlugin(funcCode, this.lazyProps.path);
      } catch (e) {
        Log.error('懒加载插件挂载失败: ' + this.lazyProps.path + ' ' + (e instanceof Error ? e.message : ''));
        this.state = PluginState.Error;
        if (this.errorReason === null) {
          this.errorReason = PluginErrorReason.CannotParse;
        }
      }
    }
  }

  private async mountPlugin(funcCode: string, pluginPath: string, presetHash?: string): Promise<void> {
    this.state = PluginState.Loading;
    let hash = presetHash !== undefined ? presetHash : '';
    try {
      if (hash.length === 0) {
        hash = await CryptoUtil.sha256(funcCode);
      }
      this.hash = hash;
      const info = await this.executor.mount(hash, funcCode, AppMeta.appVersion);
      this.instanceInfo = info;
      this.path = pluginPath;
      this.name = info.platform;
      this.supportedMethods = new Set<string>();
      for (const m of info.supportedMethods) {
        this.supportedMethods.add(m);
      }
      if (this.name.length === 0) {
        Log.error('插件实例缺少 platform: ' + pluginPath + ' hash=' + hash);
        this.hash = '';
        this.state = PluginState.Error;
        if (this.errorReason === null) {
          this.errorReason = PluginErrorReason.CannotParse;
        }
        return;
      }
      // 版本号校验
      if (info.appVersion.length > 0 && !VersionCompare.satisfies(AppMeta.appVersion, info.appVersion)) {
        this.state = PluginState.Error;
        this.errorReason = PluginErrorReason.VersionNotMatch;
        return;
      }
      this.state = PluginState.Mounted;
    } catch (e) {
      this.state = PluginState.Error;
      this.errorReason = PluginErrorReason.CannotParse;
      const message = e instanceof Error ? e.message : '';
      Log.error('插件无法解析 ' + pluginPath + ' ' + message);
    }
  }

  hasMethod(method: string): boolean {
    return this.supportedMethods.has(method);
  }

  /** 缓存控制策略（默认 no-cache） */
  cacheControl(): string {
    if (this.instanceInfo !== null && this.instanceInfo.cacheControl.length > 0) {
      return this.instanceInfo.cacheControl;
    }
    return CacheControl.NoCache;
  }

  /** 调用插件方法 */
  async callMethod(method: string, args: Array<Object | null>): Promise<Object | null> {
    const json = await this.executor.callMethod(this.hash, method, JSON.stringify(args));
    return JsonUtil.parseAny(json);
  }

  /** 调用其他插件的方法 */
  async callMethodOn(target: Plugin, method: string, args: Array<Object | null>): Promise<Object | null> {
    await target.ensureMounted();
    if (!target.hasMethod(method)) {
      return null;
    }
    const json = await target.executor.callMethod(target.hash, method, JSON.stringify(args));
    return JsonUtil.parseAny(json);
  }
}
