import { FileUtils } from '../utils/FileUtils';
import { PathConst } from '../common/PathConst';
import { Log } from '../utils/Log';
import { KVStore } from '../infra/KVStore';
import { PersistStatus } from './PersistStatus';
import { appConfig } from './AppConfig';
import { musicSheet } from './MusicSheet';
import { musicHistory } from './MusicHistory';
import { localMusicSheet, downloadedSheet } from './LocalMusicSheet';
import { LocalMusicExclusion } from './LocalMusicExclusion';
import { LOCAL_PLUGIN_PLATFORM } from '../common/Consts';
import { trackPlayer } from './TrackPlayer';
import { mediaSession } from './MediaSession';
import { lyricManager } from './LyricManager';
import { ScheduleClose } from '../utils/ScheduleClose';
import { pluginManager } from '../plugin/PluginManager';

/**
 * 应用启动编排（移植自 src/entry/bootstrap/bootstrap.ts，仅后端部分）
 * 顺序：目录 -> 配置/歌单/历史 -> 插件 -> 播放器/媒体会话 -> 本地音乐 -> 非阻塞收尾
 */
export class Bootstrap {
  private static readonly PLUGIN_UPDATE_INTERVAL_MS = 86400000;

  private static inited: boolean = false;

  static isInited(): boolean {
    return Bootstrap.inited;
  }

  /** 执行完整初始化（幂等；失败时 Promise 拒绝，与 RN Fatal 态一致不自动重试） */
  static async setup(): Promise<void> {
    if (Bootstrap.inited) {
      // 进程未死、Ability 重建：媒体会话可能已随旧 Ability 销毁被释放，需补建
      await mediaSession.setup();
      return;
    }
    Bootstrap.inited = true;

    // 1. 数据目录（EntryAbility 已建，此处幂等兜底）
    Bootstrap.setupFolder();

    // 2. 配置 + 数据域
    await Promise.all([
      appConfig.setup(),
      musicSheet.setup(),
      musicHistory.setup()
    ]);

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

    // 5.1 下载目录自动扫描（非阻塞）：导入本地音乐（含下载产生的文件）；
    // 已下载列表不扫描目录，仅在下载完成时写入；
    // 被「移出本地音乐」的文件在排除名单中，跳过不导入
    PathConst.bootstrapPublicDownloadDir().then(() => {
      const dirs: Array<string> = [PathConst.downloadPath];
      const legacyDir = PathConst.basePath + '/download/';
      if (dirs.indexOf(legacyDir) === -1) {
        dirs.push(legacyDir);
      }
      const excluded = LocalMusicExclusion.getExcludedFiles();
      return localMusicSheet.importLocal(dirs, (filename: string): boolean => !excluded.has(filename));
    }).catch(() => {
      // 静默失败，不影响启动
    });

    // 6. 非阻塞收尾
    Bootstrap.extraMakeup().catch(() => {
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

    // 启动后自动播放
    try {
      if (appConfig.getAutoPlayWhenAppStart()) {
        trackPlayer.play().catch((reason: Object) => {
          Log.warn('自动播放失败: ' + (reason instanceof Error ? reason.message : ''));
        });
      }
    } catch (e) {
      // 静默失败
    }
  }
}
