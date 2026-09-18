import { KVStore } from '../infra/KVStore';
import { JsonUtil, JsonRecord } from '../common/JsonUtil';
import { QualityKey, qualityFromStr } from '../common/model/MediaTypes';
import { PathConst } from '../common/PathConst';

/**
 * 配置键定义（对应 IAppConfigProperties）
 */
export class ConfigKeys {
  static readonly SCHEMA = '$schema';
  static readonly AUTO_PLAY_WHEN_APP_START = 'basic.autoPlayWhenAppStart';
  static readonly USE_CELLULAR_NETWORK_PLAY = 'basic.useCelluarNetworkPlay';
  static readonly USE_CELLULAR_NETWORK_DOWNLOAD = 'basic.useCelluarNetworkDownload';
  static readonly MAX_DOWNLOAD = 'basic.maxDownload';
  static readonly CLICK_MUSIC_IN_SEARCH = 'basic.clickMusicInSearch';
  static readonly DOWNLOAD_PATH = 'basic.downloadPath';
  static readonly NOT_INTERRUPT = 'basic.notInterrupt';
  static readonly TEMP_REMOTE_DUCK = 'basic.tempRemoteDuck';
  static readonly TEMP_REMOTE_DUCK_VOLUME = 'basic.tempRemoteDuckVolume';
  static readonly AUTO_STOP_WHEN_ERROR = 'basic.autoStopWhenError';
  static readonly MAX_CACHE_SIZE = 'basic.maxCacheSize';
  static readonly DEFAULT_PLAY_QUALITY = 'basic.defaultPlayQuality';
  static readonly PLAY_QUALITY_ORDER = 'basic.playQualityOrder';
  static readonly DEFAULT_DOWNLOAD_QUALITY = 'basic.defaultDownloadQuality';
  static readonly DOWNLOAD_QUALITY_ORDER = 'basic.downloadQualityOrder';
  static readonly DOWNLOAD_TASK_INTERVAL = 'basic.downloadTaskInterval';
  static readonly MAX_HISTORY_LEN = 'basic.maxHistoryLen';
  static readonly MUSIC_ORDER_IN_LOCAL_SHEET = 'basic.musicOrderInLocalSheet';
  static readonly AUTO_UPDATE_PLUGIN = 'basic.autoUpdatePlugin';
  static readonly NOT_CHECK_PLUGIN_VERSION = 'basic.notCheckPluginVersion';
  static readonly IGNORE_PLUGIN_APP_VERSION = 'basic.ignorePluginAppVersion';
  static readonly LAZY_LOAD_PLUGIN = 'basic.lazyLoadPlugin';
  static readonly TRY_CHANGE_SOURCE_WHEN_PLAY_FAIL = 'basic.tryChangeSourceWhenPlayFail';
  static readonly LYRIC_AUTO_SEARCH_LYRIC = 'lyric.autoSearchLyric';
  static readonly LOCAL_MUSIC_AUTO_MATCH_COVER = 'localMusic.autoMatchCover';
  static readonly BACKUP_RESUME_MODE = 'backup.resumeMode';
  static readonly APPEARANCE_THEME_COLOR = 'appearance.themeColor';
  static readonly APPEARANCE_COLOR_MODE = 'appearance.colorMode';
  static readonly APPEARANCE_MATERIAL_TYPE = 'appearance.materialType';
  static readonly APPEARANCE_BAR_LAYOUT_MODE = 'appearance.barLayoutMode';
  static readonly APPEARANCE_PLAYER_EXPAND_ANIM = 'appearance.playerExpandAnim';
  static readonly APPEARANCE_TAB_SWITCH_ANIM = 'appearance.tabSwitchAnim';
  static readonly APPEARANCE_SMART_REACH = 'appearance.smartReach';
  static readonly APPEARANCE_ORIENTATION = 'appearance.orientation';
  static readonly PLUGIN_SUBSCRIBE_URL = 'plugin.subscribeUrl';
  static readonly WEBDAV_URL = 'webdav.url';
  static readonly WEBDAV_PATH = 'webdav.path';
  static readonly WEBDAV_USERNAME = 'webdav.username';
  static readonly WEBDAV_PASSWORD = 'webdav.password';
  static readonly DEBUG_ERROR_LOG = 'debug.errorLog';
  static readonly DEBUG_TRACE_LOG = 'debug.traceLog';
  static readonly DEBUG_DEV_LOG = 'debug.devLog';
}

/**
 * 应用配置中心（移植自 appConfig.ts，去掉 AsyncStorage 迁移逻辑）
 */
export class AppConfig {
  private store(): KVStore {
    return KVStore.getOrCreate('App.config');
  }

  setup(): Promise<void> {
    const store = this.store();
    if (!store.contains(ConfigKeys.SCHEMA)) {
      store.set(ConfigKeys.SCHEMA, '"2"');
    }
    return Promise.resolve();
  }

  /** 写入配置（value 为 JSON 可序列化值；null 表示删除） */
  setConfig(key: string, value: Object | null): void {
    const store = this.store();
    if (value === null) {
      store.delete(key);
    } else {
      store.set(key, JsonUtil.safeStringify(value));
    }
  }

  /** 读取原始 JSON Record */
  getConfigRecord(key: string): JsonRecord | null {
    return JsonUtil.parseRecord(this.store().get(key));
  }

  getString(key: string, def: string = ''): string {
    const v = JsonUtil.parseString(this.store().get(key));
    return v === null ? def : v;
  }

  getBoolean(key: string, def: boolean): boolean {
    const v = JsonUtil.parseBoolean(this.store().get(key));
    return v === null ? def : v;
  }

  getNumber(key: string, def: number): number {
    const v = JsonUtil.parseNumber(this.store().get(key));
    return v === null ? def : v;
  }

  // ---------- 业务化 getter（含默认值，与原版设置页默认值一致） ----------

  getWebdavUrl(): string {
    return this.getString(ConfigKeys.WEBDAV_URL, '');
  }

  getWebdavPath(): string {
    return this.getString(ConfigKeys.WEBDAV_PATH, '');
  }

  getWebdavUsername(): string {
    return this.getString(ConfigKeys.WEBDAV_USERNAME, '');
  }

  getWebdavPassword(): string {
    return this.getString(ConfigKeys.WEBDAV_PASSWORD, '');
  }

  /** 导出全部设置（备份用；排除 WebDAV 账密等敏感项） */
  exportSettings(): Record<string, string> {
    const out: Record<string, string> = {};
    const data = this.store().exportData();
    for (const key of Object.keys(data)) {
      if (key === ConfigKeys.WEBDAV_USERNAME || key === ConfigKeys.WEBDAV_PASSWORD ||
        key === ConfigKeys.SCHEMA) {
        continue;
      }
      out[key] = data[key];
    }
    return out;
  }

  /** 从备份导入设置（仅写入备份中存在的键，不覆盖 WebDAV 账密，不删除本地其余键） */
  importSettings(data: Record<string, string>): void {
    const store = this.store();
    for (const key of Object.keys(data)) {
      if (key === ConfigKeys.WEBDAV_USERNAME || key === ConfigKeys.WEBDAV_PASSWORD ||
        key === ConfigKeys.SCHEMA) {
        continue;
      }
      store.set(key, data[key]);
    }
  }

  getAutoPlayWhenAppStart(): boolean {
    return this.getBoolean(ConfigKeys.AUTO_PLAY_WHEN_APP_START, false);
  }

  getUseCellularNetworkPlay(): boolean {
    return this.getBoolean(ConfigKeys.USE_CELLULAR_NETWORK_PLAY, false);
  }

  getUseCellularNetworkDownload(): boolean {
    return this.getBoolean(ConfigKeys.USE_CELLULAR_NETWORK_DOWNLOAD, false);
  }

  getMaxDownload(): number {
    return this.getNumber(ConfigKeys.MAX_DOWNLOAD, 3);
  }

  /** 在线音乐缓存上限（字节，默认 512M，对齐 RN basic.maxCacheSize） */
  getMaxCacheSize(): number {
    return this.getNumber(ConfigKeys.MAX_CACHE_SIZE, 512 * 1024 * 1024);
  }

  getNotInterrupt(): boolean {
    return this.getBoolean(ConfigKeys.NOT_INTERRUPT, false);
  }

  getTempRemoteDuck(): string {
    return this.getString(ConfigKeys.TEMP_REMOTE_DUCK, 'pause');
  }

  getTempRemoteDuckVolume(): number {
    return this.getNumber(ConfigKeys.TEMP_REMOTE_DUCK_VOLUME, 0.3);
  }

  getAutoStopWhenError(): boolean {
    return this.getBoolean(ConfigKeys.AUTO_STOP_WHEN_ERROR, false);
  }

  getDefaultPlayQuality(): QualityKey {
    return qualityFromStr(this.getString(ConfigKeys.DEFAULT_PLAY_QUALITY, 'high'));
  }

  getPlayQualityOrder(): string {
    return this.getString(ConfigKeys.PLAY_QUALITY_ORDER, 'desc');
  }

  getDefaultDownloadQuality(): QualityKey {
    return qualityFromStr(this.getString(ConfigKeys.DEFAULT_DOWNLOAD_QUALITY, 'high'));
  }

  getDownloadQualityOrder(): string {
    return this.getString(ConfigKeys.DOWNLOAD_QUALITY_ORDER, 'desc');
  }

  /** 下载任务启动间隔（秒，0 表示不间隔） */
  getDownloadTaskInterval(): number {
    return this.getNumber(ConfigKeys.DOWNLOAD_TASK_INTERVAL, 0);
  }

  getMaxHistoryLen(): number {
    return this.getNumber(ConfigKeys.MAX_HISTORY_LEN, 50);
  }

  getMusicOrderInLocalSheet(): string {
    return this.getString(ConfigKeys.MUSIC_ORDER_IN_LOCAL_SHEET, '');
  }

  getAutoUpdatePlugin(): boolean {
    return this.getBoolean(ConfigKeys.AUTO_UPDATE_PLUGIN, false);
  }

  getNotCheckPluginVersion(): boolean {
    return this.getBoolean(ConfigKeys.NOT_CHECK_PLUGIN_VERSION, false);
  }

  /** 忽略插件声明的应用版本要求（实验性） */
  getIgnorePluginAppVersion(): boolean {
    return this.getBoolean(ConfigKeys.IGNORE_PLUGIN_APP_VERSION, false);
  }

  getLazyLoadPlugin(): boolean {
    return this.getBoolean(ConfigKeys.LAZY_LOAD_PLUGIN, false);
  }

  getTryChangeSourceWhenPlayFail(): boolean {
    return this.getBoolean(ConfigKeys.TRY_CHANGE_SOURCE_WHEN_PLAY_FAIL, true);
  }

  getLyricAutoSearchLyric(): boolean {
    return this.getBoolean(ConfigKeys.LYRIC_AUTO_SEARCH_LYRIC, true);
  }

  getDownloadPath(): string {
    const p = this.getString(ConfigKeys.DOWNLOAD_PATH, '');
    return p.length > 0 ? p : PathConst.downloadMusicPath;
  }

  getPluginSubscribeUrl(): string {
    return this.getString(ConfigKeys.PLUGIN_SUBSCRIBE_URL, '');
  }

  /** 主题色（空串 = 跟随系统） */
  getAppearanceThemeColor(): string {
    return this.getString(ConfigKeys.APPEARANCE_THEME_COLOR, '');
  }

  /** 深浅模式：system / light / dark */
  getAppearanceColorMode(): string {
    const v = this.getString(ConfigKeys.APPEARANCE_COLOR_MODE, 'system');
    return v === 'light' || v === 'dark' ? v : 'system';
  }

  /** 沉浸光感材质：immersive / adaptive / none */
  getAppearanceMaterialType(): string {
    const v = this.getString(ConfigKeys.APPEARANCE_MATERIAL_TYPE, 'immersive');
    return v === 'adaptive' || v === 'none' ? v : 'immersive';
  }

  /** 底部栏排列模式：1 上下两排 / 0 单排 */
  getAppearanceBarLayoutMode(): number {
    return this.getNumber(ConfigKeys.APPEARANCE_BAR_LAYOUT_MODE, 1) === 0 ? 0 : 1;
  }

  /** 播放页展开/收起一镜到底动画 */
  getPlayerExpandAnim(): boolean {
    return this.getBoolean(ConfigKeys.APPEARANCE_PLAYER_EXPAND_ANIM, true);
  }

  /** Tab 切换过渡动画 */
  getTabSwitchAnim(): boolean {
    return this.getBoolean(ConfigKeys.APPEARANCE_TAB_SWITCH_ANIM, true);
  }

  /** 智感握姿（适人握持） */
  getSmartReachEnabled(): boolean {
    return this.getBoolean(ConfigKeys.APPEARANCE_SMART_REACH, false);
  }

  /** 屏幕方向：portrait / landscape / system */
  getAppearanceOrientation(): string {
    const v = this.getString(ConfigKeys.APPEARANCE_ORIENTATION, 'system');
    return v === 'portrait' || v === 'landscape' ? v : 'system';
  }

  /** 本地音乐自动匹配音乐封面（导入时提取内嵌封面并回填网络封面） */
  getLocalMusicAutoMatchCover(): boolean {
    return this.getBoolean(ConfigKeys.LOCAL_MUSIC_AUTO_MATCH_COVER, true);
  }
}

export const appConfig = new AppConfig();
