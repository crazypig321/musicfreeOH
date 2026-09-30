import { FileUtils } from '../utils/FileUtils';
import { PathConst } from '../common/PathConst';
import { KVStore } from '../infra/KVStore';
import { PersistStatus } from './PersistStatus';
import { appConfig } from './AppConfig';
import { musicSheet } from './MusicSheet';
import { musicHistory } from './MusicHistory';
import { localMusicSheet, downloadedSheet } from './LocalMusicSheet';
import { LOCAL_PLUGIN_PLATFORM } from '../common/Consts';
import { trackPlayer } from './TrackPlayer';
import { mediaSession } from './MediaSession';
import { lyricManager } from './LyricManager';
import { ScheduleClose } from '../utils/ScheduleClose';
import { pluginManager } from '../plugin/PluginManager';
import { SmartReach } from '../utils/SmartReach';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hdsMaterial } from '@kit.UIDesignKit';
import { window } from '@kit.ArkUI';
import { ContextHolder } from '../common/ContextHolder';
import { appState, themeColorOf } from '../entryability/AppState';

/**
 * 应用启动编排（移植自 src/entry/bootstrap/bootstrap.ts，仅后端部分）
 * 顺序：目录 -> 配置/歌单/历史 -> 插件 -> 播放器/媒体会话 -> 本地音乐 -> 非阻塞收尾
 */
export class Bootstrap {
  private static readonly PLUGIN_UPDATE_INTERVAL_MS = 86400000;

  private static inited: boolean = false;
  /** 首次完整初始化的 Promise（并发调用复用，避免重复初始化） */
  private static setupPromise: Promise<void> | null = null;

  static isInited(): boolean {
    return Bootstrap.inited;
  }

  /**
   * 执行完整初始化（幂等；失败时 Promise 拒绝，与 RN Fatal 态一致不自动重试）
   * 桌面卡片冷启动控制与应用页启动可能并发触发首次初始化，进行中的调用复用同一 Promise
   */
  static setup(): Promise<void> {
    if (Bootstrap.setupPromise !== null) {
      return Bootstrap.setupPromise;
    }
    if (Bootstrap.inited) {
      // 进程未死、Ability 重建：媒体会话可能已随旧 Ability 销毁被释放，需补建
      return mediaSession.setup();
    }
    Bootstrap.setupPromise = Bootstrap.doSetup();
    return Bootstrap.setupPromise;
  }

  private static async doSetup(): Promise<void> {
    Bootstrap.inited = true;
    try {
      await Bootstrap.runSetup();
    } finally {
      // 结束后清空：后续调用走 inited 分支（补建媒体会话），与原重复调用语义一致
      Bootstrap.setupPromise = null;
    }
  }

  private static async runSetup(): Promise<void> {
    // 1. 数据目录（EntryAbility 已建，此处幂等兜底）
    Bootstrap.setupFolder();

    // 2. 配置 + 数据域
    await Promise.all([
      appConfig.setup(),
      musicSheet.setup(),
      musicHistory.setup()
    ]);

    // 2.1 外观设置恢复（深浅模式/材质/底部栏布局/主题色/动画开关）
    Bootstrap.applyAppearance();

    // 3. 插件
    await pluginManager.setup();

    // 4. 播放器 + 媒体会话 + 歌词 + 定时关闭
    await trackPlayer.setupTrackPlayer();
    await mediaSession.setup();
    lyricManager.setup();
    ScheduleClose.setup();

    // 5. 本地音乐 + 已下载（两份独立数据，互不关联）
    await localMusicSheet.setup();
    await downloadedSheet.setup();
    // 历史数据拆分：旧版共享歌单中插件平台的条目属于已下载域
    Bootstrap.splitLegacyLocalSheet();

    // 5.1 下载目录不再启动时自动扫描导入：下载完成的文件由下载器直接入库，
    // 其余新文件（外部复制等）统一走本地音乐页手动扫描，预检后弹窗确认才导入

    // 6. 非阻塞收尾
    Bootstrap.extraMakeup().catch(() => {
    });
  }

  /** 恢复外观相关设置到全局状态 */
  private static applyAppearance(): void {
    // 深浅模式
    try {
      const mode = appConfig.getAppearanceColorMode();
      let colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      if (mode === 'light') {
        colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      } else if (mode === 'dark') {
        colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      }
      ContextHolder.get().getApplicationContext().setColorMode(colorMode);
    } catch (e) {
      // 静默失败，跟随系统
    }
    // 沉浸光感材质
    const mt = appConfig.getAppearanceMaterialType();
    if (mt === 'adaptive') {
      appState.materialType = hdsMaterial.MaterialType.ADAPTIVE;
    } else if (mt === 'none') {
      appState.materialType = hdsMaterial.MaterialType.NONE;
    } else {
      appState.materialType = hdsMaterial.MaterialType.IMMERSIVE;
      // 沉浸光感生效时的效果等级（exquisite 精致 / gentle 轻柔 / smooth 顺滑）
      const ml = appConfig.getAppearanceMaterialLevel();
      if (ml === 'exquisite') {
        appState.materialLevel = hdsMaterial.MaterialLevel.EXQUISITE;
      } else if (ml === 'gentle') {
        appState.materialLevel = hdsMaterial.MaterialLevel.GENTLE;
      } else if (ml === 'smooth') {
        appState.materialLevel = hdsMaterial.MaterialLevel.SMOOTH;
      }
    }
    // 底部栏排列模式
    appState.hdsBarLayoutMode = appConfig.getAppearanceBarLayoutMode();
    // 主题色
    appState.accentColor = themeColorOf(appConfig.getAppearanceThemeColor());
    // Tab 切换动画
    appState.tabSwitchAnim = appConfig.getTabSwitchAnim();
    // 智感握姿订阅（先恢复开关状态，底部栏 handedness 适配据此渲染）
    appState.smartReachEnabled = appConfig.getSmartReachEnabled();
    SmartReach.setup();
    // 车载模式手动开关（驾驶界面 = 手动开关 || 车机屏检测）
    appState.carModeManual = appConfig.getCarModeEnabled();
    appState.refreshCarMode();
    // 屏幕方向
    Bootstrap.applyOrientation();
  }

  /** 屏幕方向（竖屏/横屏/跟随系统） */
  private static applyOrientation(): void {
    const o = appConfig.getAppearanceOrientation();
    window.getLastWindow(ContextHolder.get()).then((win: window.Window): Promise<void> => {
      let orientation = window.Orientation.AUTO_ROTATION_RESTRICTED;
      if (o === 'portrait') {
        orientation = window.Orientation.PORTRAIT;
      } else if (o === 'landscape') {
        orientation = window.Orientation.LANDSCAPE;
      }
      // AUTO_ROTATION_RESTRICTED：跟随传感器旋转，且受系统控制中心「自动旋转」开关控制
      return win.setPreferredOrientation(orientation);
    }).catch((): void => {
      // 静默失败
    });
  }

  /** 旧版共享歌单拆分（仅执行一次）：插件平台条目移入已下载，其余（本地导入）保留 */
  private static splitLegacyLocalSheet(): void {
    const store = KVStore.getOrCreate('storage');
    if (store.get('LocalDownloadSplitDone').length > 0) {
      return;
    }
    store.set('LocalDownloadSplitDone', '1');
    const legacy = localMusicSheet.getMusicList().slice();
    for (const it of legacy) {
      if (it.platform !== LOCAL_PLUGIN_PLATFORM) {
        downloadedSheet.addMusic(it);
        localMusicSheet.removeMusic(it, false);
      }
    }
  }

  /** 初始化数据目录 */
  private static setupFolder(): void {    FileUtils.checkAndCreateDir(PathConst.dataPath);
    FileUtils.checkAndCreateDir(PathConst.logPath);
    FileUtils.checkAndCreateDir(PathConst.cachePath);
    FileUtils.checkAndCreateDir(PathConst.musicCachePath);
    FileUtils.checkAndCreateDir(PathConst.pluginPath);
    FileUtils.checkAndCreateDir(PathConst.lrcCachePath);
    FileUtils.checkAndCreateDir(PathConst.downloadCachePath);
    FileUtils.checkAndCreateDir(PathConst.artworkCachePath);
    FileUtils.checkAndCreateDir(PathConst.localLrcPath);
    FileUtils.checkAndCreateDir(PathConst.downloadPath);
    FileUtils.checkAndCreateDir(PathConst.downloadMusicPath);
  }

  /** 不阻塞启动的收尾逻辑（对应 RN extraMakeup） */
  private static async extraMakeup(): Promise<void> {
    // 启动自动续播已在 setupTrackPlayer 的恢复链内完成（seek 到上次进度后再播放），
    // 此处不再调用 play()，避免与恢复链并发重新拉源导致进度被重置

    // 插件自动更新（每 24h 一次，静默失败）
    try {
      if (appConfig.getAutoUpdatePlugin()) {
        const lastUpdated = PersistStatus.getPluginUpdateTime();
        const now = Date.now();
        if (Math.abs(now - lastUpdated) > Bootstrap.PLUGIN_UPDATE_INTERVAL_MS) {
          PersistStatus.setPluginUpdateTime(now);
          const plugins = pluginManager.getEnabledPlugins();
          for (let i = 0; i < plugins.length; ++i) {
            const info = plugins[i].instanceInfo;
            if (info !== null && info.srcUrl.length > 0) {
              try {
                await pluginManager.installPluginFromUrl(
                  info.srcUrl,
                  appConfig.getNotCheckPluginVersion()
                );
              } catch (e) {
                // 静默失败
              }
            }
          }
        }
      }
    } catch (e) {
      // 静默失败
    }
  }
}
