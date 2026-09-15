/**
 * 全局常量（移植自 MusicFree src/constants/commonConst.ts + repeatModeConst.ts）
 */

/** 内部序列化字段前缀 */
export const INTERNAL_SERIALIZE_KEY = '$';

export const LOCAL_MUSIC_SHEET_ID = 'local-music-sheet';
export const MUSIC_HISTORY_SHEET_ID = 'history-music-sheet';

/** 内置本地插件的平台名与hash */
export const LOCAL_PLUGIN_PLATFORM = '本地';
export const LOCAL_PLUGIN_HASH = 'local-plugin-hash';

/** 歌单内默认歌单 */
export const FAVORITE_SHEET_ID = 'favorite';
export const FAVORITE_SHEET_TITLE = '我喜欢';

export enum SortType {
  None = 'None',
  Title = 'title',
  Artist = 'artist',
  Album = 'album',
  Newest = 'time',
  Oldest = 'time-rev',
}

export enum ResumeMode {
  Append = 'append',
  Overwrite = 'overwrite',
  OverwriteDefault = 'overwrite-default',
}

export enum MusicRepeatMode {
  SHUFFLE = 'SHUFFLE',
  QUEUE = 'QUEUE',
  SINGLE = 'SINGLE',
}

/** 插件缓存控制 */
export class CacheControl {
  static readonly Cache: string = 'cache';
  static readonly NoCache: string = 'no-cache';
  static readonly NoStore: string = 'no-store';
}

/** 播放列表上限 */
export const MAX_PLAYLIST_SIZE = 10000;

/** 支持的本地音频扩展名 */
export const SUPPORT_LOCAL_MEDIA_TYPE: Array<string> = [
  '.mp3', '.flac', '.wma', '.wav', '.m4a',
  '.ogg', '.acc', '.aac', '.ape', '.opus',
];

/** 媒体缓存最大条数与淘汰阈值（移植自 mediaCache） */
export const MEDIA_CACHE_MAX = 800;
export const MEDIA_CACHE_EVICT = 400;

/** 插件能力（用于 getPluginsWithAbility） */
export enum PluginAbility {
  Search = 'search',
  GetMediaSource = 'getMediaSource',
  GetMusicInfo = 'getMusicInfo',
  GetLyric = 'getLyric',
  GetAlbumInfo = 'getAlbumInfo',
  GetMusicSheetInfo = 'getMusicSheetInfo',
  GetArtistWorks = 'getArtistWorks',
  ImportMusicSheet = 'importMusicSheet',
  ImportMusicItem = 'importMusicItem',
  GetTopLists = 'getTopLists',
  GetTopListDetail = 'getTopListDetail',
  GetRecommendSheetTags = 'getRecommendSheetTags',
  GetRecommendSheetsByTag = 'getRecommendSheetsByTag',
  GetMusicComments = 'getMusicComments',
}
