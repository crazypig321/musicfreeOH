import { formBindingData, formProvider } from '@kit.FormKit';
import fs from '@ohos.file.fs';
import { trackPlayer } from './TrackPlayer';
import { mediaSession } from './MediaSession';
import { Bootstrap } from './Bootstrap';
import { PlayState } from './PlayerEngine';
import { MusicItem } from '../common/model/MediaTypes';
import { ArtworkCache } from '../utils/ArtworkCache';
import { CoverColorUtils } from '../utils/CoverColorUtils';
import { FileUtils } from '../utils/FileUtils';
import { Log } from '../utils/Log';
import { CARD_BG_ALPHA_HEX, MusicCardData } from '../widget/MusicCardData';

/** 桌面音乐卡片控制命令（与卡片页 MusicCard.ets postCommand 参数一致） */
export class MusicWidgetCommand {
  static readonly PLAY_PAUSE = 'playPause';
  static readonly PREVIOUS = 'previous';
  static readonly NEXT = 'next';
  static readonly FAVORITE = 'favorite';
}

/**
 * 桌面音乐卡片管理器（主应用进程侧）
 * - 监听播放器/收藏状态变化，把最新歌曲状态推送到所有已加桌的 MusicCard
 * - 接收卡片 call 事件命令（播放/暂停/上下曲/收藏），后台执行后回推状态
 */
export class MusicWidgetManager {
  /** 卡片配置名（与 form_config.json name 一致，用于过滤本应用卡片） */
  private static readonly CARD_NAME = 'MusicCard';
  /** 状态推送防抖间隔（切歌/播放态变化在短时间内可能连续触发） */
  private static readonly REFRESH_DEBOUNCE_MS = 300;

  private static inited: boolean = false;
  private static refreshTimer: number = -1;
  private static refreshing: boolean = false;
  private static refreshQueued: boolean = false;
  /** 封面缓存（同一歌曲重复刷新播放态时免重复解析/下载） */
  private static coverArtworkUrl: string = '';
  private static coverFilePath: string = '';
  /** 当前封面的 memory key（封面变化时递增换 key，同名 key 图片更新不触发卡片重载） */
  private static coverKeySeq: number = 0;
  private static coverKey: string = 'cover';

  /** 注册播放状态监听（幂等；EntryAbility onCreate 时调用） */
  static setup(): void {
    if (MusicWidgetManager.inited) {
      return;
    }
    MusicWidgetManager.inited = true;
    trackPlayer.onCurrentMusicChanged((_music: MusicItem | null): void => {
      MusicWidgetManager.scheduleRefresh();
    });
    trackPlayer.onPlayStateChanged((_state: PlayState): void => {
      MusicWidgetManager.scheduleRefresh();
    });
    mediaSession.onFavoriteChanged((): void => {
      MusicWidgetManager.scheduleRefresh();
    });
  }

  /** 卡片控制命令入口（EntryAbility callee 'mediaControl' 调用） */
  static async handleCommand(command: string): Promise<void> {
    MusicWidgetManager.setup();
    // 卡片冷启动拉起应用时需要先完成初始化（播放列表恢复等），Bootstrap.setup 幂等
    try {
      await Bootstrap.setup();
    } catch (e) {
      Log.error('桌面卡片控制：应用初始化失败');
      return;
    }
    try {
      if (command === MusicWidgetCommand.PLAY_PAUSE) {
        if (trackPlayer.playState === PlayState.Playing) {
          await trackPlayer.pause();
        } else {
          await trackPlayer.play();
        }
      } else if (command === MusicWidgetCommand.PREVIOUS) {
        await trackPlayer.skipToPrevious();
      } else if (command === MusicWidgetCommand.NEXT) {
        await trackPlayer.skipToNext();
      } else if (command === MusicWidgetCommand.FAVORITE) {
        mediaSession.toggleFavorite();
      }
    } catch (e) {
      Log.warn('桌面卡片控制命令执行失败: ' + command);
    }
    // 事件本身会触发刷新，此处兜底立即安排一次（如收藏切换无播放事件时）
    MusicWidgetManager.scheduleRefresh();
  }

  /** 防抖刷新全部已加桌卡片 */
  static refresh(): void {
    MusicWidgetManager.scheduleRefresh();
  }

  private static scheduleRefresh(): void {
    if (MusicWidgetManager.refreshTimer >= 0) {
      clearTimeout(MusicWidgetManager.refreshTimer);
    }
    MusicWidgetManager.refreshTimer = setTimeout((): void => {
      MusicWidgetManager.refreshTimer = -1;
      MusicWidgetManager.refreshAll();
    }, MusicWidgetManager.REFRESH_DEBOUNCE_MS);
  }

  private static refreshAll(): void {
    MusicWidgetManager.doRefreshAll().catch((_e: Object): void => {
      Log.warn('桌面卡片刷新异常');
    });
  }

  private static async doRefreshAll(): Promise<void> {
    if (MusicWidgetManager.refreshing) {
      MusicWidgetManager.refreshQueued = true;
      return;
    }
    MusicWidgetManager.refreshing = true;
    try {
      const formIds = await MusicWidgetManager.queryCardFormIds();
      for (const formId of formIds) {
        await MusicWidgetManager.pushToForm(formId);
      }
    } finally {
      MusicWidgetManager.refreshing = false;
      if (MusicWidgetManager.refreshQueued) {
        MusicWidgetManager.refreshQueued = false;
        MusicWidgetManager.scheduleRefresh();
      }
    }
  }

  /** 枚举本应用已加桌的 MusicCard 卡片 id */
  private static async queryCardFormIds(): Promise<Array<string>> {
    try {
      const infos = await formProvider.getPublishedRunningFormInfos();
      const ids: Array<string> = [];
      for (const info of infos) {
        if (info.formName === MusicWidgetManager.CARD_NAME) {
          ids.push(info.formId);
        }
      }
      return ids;
    } catch (e) {
      // 无已加桌卡片（错误码 16500100）等场景静默处理
      return [];
    }
  }

  /** 构造当前播放状态并推送单张卡片 */
  private static async pushToForm(formId: string): Promise<void> {
    const music = trackPlayer.currentMusic;
    const data = new MusicCardData();
    data.formId = formId;
    data.title = music !== null ? music.title : '';
    data.artist = music !== null ? music.artist : '';
    data.isPlaying = trackPlayer.playState === PlayState.Playing;
    data.isFavorite = mediaSession.currentFavorite;

    const coverPath = await MusicWidgetManager.resolveCoverPath(music);
    let fd = -1;
    if (coverPath !== null && FileUtils.exists(coverPath)) {
      try {
        fd = fs.openSync(coverPath, fs.OpenMode.READ_ONLY).fd;
      } catch (e) {
        fd = -1;
      }
    }
    if (fd >= 0 && coverPath !== null) {
      data.hasCover = true;
      data.coverKey = MusicWidgetManager.coverKey;
      data.formImages[MusicWidgetManager.coverKey] = fd;
      const color = await CoverColorUtils.extract(coverPath);
      if (color !== null) {
        data.bgColor = CoverColorUtils.toHexWithAlpha(color, CARD_BG_ALPHA_HEX);
      }
    }
    try {
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
    } catch (e) {
      Log.warn('桌面卡片推送失败: ' + formId);
    } finally {
      if (fd >= 0) {
        try {
          fs.closeSync(fd);
        } catch (e) {
          // 关闭失败忽略
        }
      }
    }
  }

  /** 解析当前歌曲封面的本地文件路径（http 走封面缓存，file:// 直接使用；失败返回 null） */
  private static async resolveCoverPath(music: MusicItem | null): Promise<string | null> {
    const artwork = music !== null ? music.artwork : '';
    if (artwork.length === 0) {
      MusicWidgetManager.coverArtworkUrl = '';
      MusicWidgetManager.coverFilePath = '';
      return null;
    }
    if (artwork === MusicWidgetManager.coverArtworkUrl && MusicWidgetManager.coverFilePath.length > 0) {
      return MusicWidgetManager.coverFilePath;
    }
    MusicWidgetManager.coverArtworkUrl = '';
    MusicWidgetManager.coverFilePath = '';
    if (artwork.startsWith('file://')) {
      const path = artwork.substring('file://'.length);
      MusicWidgetManager.commitCover(artwork, path);
      return path;
    }
    if (artwork.startsWith('http://') || artwork.startsWith('https://')) {
      try {
        const path = await ArtworkCache.downloadToFile(artwork);
        if (path !== null) {
          MusicWidgetManager.commitCover(artwork, path);
        }
        return path;
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  /** 封面解析成功：记录缓存并换新 memory key（强制卡片 Image 重载新封面） */
  private static commitCover(artwork: string, path: string): void {
    MusicWidgetManager.coverArtworkUrl = artwork;
    MusicWidgetManager.coverFilePath = path;
    MusicWidgetManager.coverKeySeq += 1;
    MusicWidgetManager.coverKey = 'cover_' + MusicWidgetManager.coverKeySeq.toString();
  }
}
