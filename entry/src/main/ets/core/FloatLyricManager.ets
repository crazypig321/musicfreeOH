import { appConfig, ConfigKeys } from './AppConfig';
import { mediaSession } from './MediaSession';
import { Log } from '../utils/Log';

/**
 * 悬浮歌词（桌面歌词）管理器 —— 系统桌面歌词方案
 * 通过 AVSession.enableDesktopLyric 启用系统桌面歌词，
 * 歌词内容由 MediaSession 的 singleLyricText 元数据驱动，无需自定义窗口。
 */
@ObservedV2
export class FloatLyricManager {
  /** 开关状态（持久化到 floatLyric.enabled） */
  @Trace enabled: boolean = false;
  /** 锁定状态（由系统桌面歌词 onDesktopLyricStateChanged 回调同步） */
  @Trace locked: boolean = false;

  /** 用户入口：切换开/关；返回是否成功开启 */
  async toggle(): Promise<boolean> {
    if (this.enabled) {
      await this.close();
      return false;
    }
    return this.open();
  }

  /** 开启系统桌面歌词；返回是否成功 */
  async open(): Promise<boolean> {
    if (this.enabled) {
      return true;
    }
    const ok = await mediaSession.setDesktopLyricVisible(true);
    if (ok) {
      this.enabled = true;
      appConfig.setConfig(ConfigKeys.FLOAT_LYRIC_ENABLED, true);
      return true;
    }
    Log.warn('系统桌面歌词开启失败');
    return false;
  }

  /** 关闭系统桌面歌词 */
  async close(): Promise<void> {
    await mediaSession.setDesktopLyricVisible(false);
    this.enabled = false;
    appConfig.setConfig(ConfigKeys.FLOAT_LYRIC_ENABLED, false);
  }

  /** 切换锁定状态 */
  async toggleLocked(): Promise<void> {
    const ok = await mediaSession.setDesktopLyricLocked(!this.locked);
    if (!ok) {
      Log.warn('设置桌面歌词锁定状态失败');
    }
  }

  /** 系统桌面歌词可见性变化（由 MediaSession 回调，仅更新状态） */
  onDesktopLyricVisibilityChanged(visible: boolean): void {
    this.enabled = visible;
    appConfig.setConfig(ConfigKeys.FLOAT_LYRIC_ENABLED, visible);
  }

  /** 系统桌面歌词锁定状态变化（由 MediaSession 回调，仅更新状态） */
  onLockStateChanged(locked: boolean): void {
    this.locked = locked;
  }
}

export const floatLyricManager = new FloatLyricManager();
