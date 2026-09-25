import { harmonyShare } from '@kit.ShareKit';
import { window } from '@kit.ArkUI';
import { ContextHolder } from '../common/ContextHolder';
import { Log } from '../utils/Log';
import { ShareUtils, MusicShareData } from '../utils/ShareUtils';
import { MusicItem } from '../common/model/MediaTypes';

/**
 * 碰一碰 / 隔空手势（一抓一放）跨设备分享当前歌曲（Share Kit 发送端）
 * 播放页可见期间注册监听：设备轻贴/抓放手势触发后把当前歌曲构造为分享数据
 * 直接发送（本地歌曲→音频文件；网络歌曲→歌曲标记临时 txt 文件），
 * 接收端 MusicFreeOH 经沙箱接收自动导入/播放；无歌曲时拒绝本次分享。
 */
export class HarmonyShareSend {
  private static registry: harmonyShare.SendCapabilityRegistry | null = null;
  private static getSong: (() => MusicItem | null) | null = null;
  /** 注册代数：stop 后使在途的异步注册失效 */
  private static gen: number = 0;

  /** 进入可分享页面时调用：注册碰一碰与隔空手势监听（重复调用仅更新取歌回调） */
  static start(getSong: () => MusicItem | null): void {
    HarmonyShareSend.getSong = getSong;
    if (HarmonyShareSend.registry !== null) {
      return;
    }
    const gen = ++HarmonyShareSend.gen;
    window.getLastWindow(ContextHolder.get()).then((win: window.Window): Promise<void> => {
      return win.getProperties().then((props: window.WindowProperties): void => {
        if (gen !== HarmonyShareSend.gen) {
          return; // 等待窗口信息期间页面已退出
        }
        try {
          const registry: harmonyShare.SendCapabilityRegistry = {
            windowId: props.id
          };
          harmonyShare.on('knockShare', registry, (target: harmonyShare.SharableTarget): void => {
            HarmonyShareSend.onTarget(target);
          });
          harmonyShare.on('gesturesShare', registry, (target: harmonyShare.SharableTarget): void => {
            HarmonyShareSend.onTarget(target);
          });
          HarmonyShareSend.registry = registry;
          Log.info('碰一碰/隔空手势分享已注册 windowId=' + props.id);
        } catch (e) {
          const detail = e instanceof Error ? e.message : '';
          Log.error('碰一碰/隔空手势分享注册失败: ' + detail);
        }
      });
    }).catch((_e: Object): void => {
      Log.error('碰一碰/隔空手势分享注册失败：获取主窗口失败');
    });
  }

  /** 离开页面时注销监听 */
  static stop(): void {
    HarmonyShareSend.gen++;
    HarmonyShareSend.getSong = null;
    const registry = HarmonyShareSend.registry;
    if (registry === null) {
      return;
    }
    try {
      harmonyShare.off('knockShare', registry);
      harmonyShare.off('gesturesShare', registry);
    } catch (e) {
      const detail = e instanceof Error ? e.message : '';
      Log.error('碰一碰/隔空手势分享注销失败: ' + detail);
    }
    HarmonyShareSend.registry = null;
  }

  /** 手势/轻贴触发：构造当前歌曲分享数据直接发送（3 秒内必须调用 share），完成后清理临时文件 */
  private static onTarget(target: harmonyShare.SharableTarget): void {
    const getSong = HarmonyShareSend.getSong;
    const song = getSong === null ? null : getSong();
    if (song === null || song.id.length === 0) {
      Log.error('碰一碰/隔空分享：无正在播放的歌曲，拒绝本次分享');
      target.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR).catch((_e: Object): void => {
      });
      return;
    }
    const r: MusicShareData = ShareUtils.buildMusicShare(song);
    const data = r.data;
    if (data === null) {
      Log.error('碰一碰/隔空分享：构造分享数据失败「' + song.title + '」');
      target.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR).catch((_e: Object): void => {
      });
      return;
    }
    Log.info('碰一碰/隔空分享：发送「' + song.title + '」（platform=' + song.platform + '）');
    try {
      target.share(data).then((): void => {
        ShareUtils.cleanupMusicShare(r.tempPath);
        Log.info('碰一碰/隔空分享：发送成功「' + song.title + '」');
      }).catch((_e: Object): void => {
        ShareUtils.cleanupMusicShare(r.tempPath);
        Log.error('碰一碰/隔空手势分享发送失败: ' + song.title);
      });
    } catch (e) {
      const detail = e instanceof Error ? e.message : '';
      Log.error('碰一碰/隔空分享发送异常: ' + detail);
      ShareUtils.cleanupMusicShare(r.tempPath);
      target.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR).catch((_e: Object): void => {
      });
    }
  }
}
