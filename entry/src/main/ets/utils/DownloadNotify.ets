import { notificationManager } from '@kit.NotificationKit';
import { ContextHolder } from '../common/ContextHolder';
import { Log } from './Log';

/**
 * 下载通知（进度实况 + 完成摘要）
 *
 * 进度条通知复用 dataTransfer 长时任务返回的系统通知 Id（downloadTemplate
 * 实况通知，随长时任务取消由系统移除）；实况发布失败或 Id 不可用时，
 * 降级为普通文本通知（自有固定 Id，覆盖式更新）。
 * 应用通知需用户授权：首次下载时请求一次，被拒绝则静默跳过（不影响下载）。
 */
export class DownloadNotify {
  /** 摘要/降级通知的固定 Id */
  private static readonly NOTIFY_ID = 1001;
  /** 进度通知最小刷新间隔（毫秒） */
  private static readonly PROGRESS_THROTTLE_MS = 600;

  /** dataTransfer 长时任务系统通知 Id（<=0 表示不可用） */
  private static systemNotificationId: number = -1;
  private static lastPublishAt: number = 0;
  private static enabledChecked: boolean = false;

  static setSystemNotificationId(id: number): void {
    DownloadNotify.systemNotificationId = id;
  }

  /** 新批次开始：重置节流状态，首条进度立即发布 */
  static resetProgress(): void {
    DownloadNotify.lastPublishAt = 0;
  }

  /** 首次下载时确保通知授权（仅弹一次；用户拒绝过或应用不在前台时静默失败） */
  static ensureEnabled(): void {
    if (DownloadNotify.enabledChecked) {
      return;
    }
    DownloadNotify.enabledChecked = true;
    notificationManager.isNotificationEnabled().then((enabled: boolean): Promise<void> => {
      if (enabled) {
        return Promise.resolve();
      }
      return notificationManager.requestEnableNotification(ContextHolder.get());
    }).catch((_e: Object): void => {
    });
  }

  /** 更新下载进度通知（节流）：songText 形如 "歌名 - 歌手"，remaining 为剩余下载数 */
  static updateProgress(songText: string, percent: number, remaining: number): void {
    const now = Date.now();
    if (now - DownloadNotify.lastPublishAt < DownloadNotify.PROGRESS_THROTTLE_MS) {
      return;
    }
    DownloadNotify.lastPublishAt = now;
    if (DownloadNotify.systemNotificationId > 0) {
      DownloadNotify.publishLive(DownloadNotify.systemNotificationId, songText, percent, remaining)
        .catch((): void => {
          DownloadNotify.systemNotificationId = -1;
          DownloadNotify.publishBasic('正在下载', DownloadNotify.progressText(songText, remaining));
        });
    } else {
      DownloadNotify.publishBasic('正在下载', DownloadNotify.progressText(songText, remaining));
    }
  }

  /** 下载结束：显示完成/失败摘要（长时任务通知由系统随任务取消移除） */
  static showSummary(done: number, failed: number): void {
    DownloadNotify.systemNotificationId = -1;
    DownloadNotify.lastPublishAt = 0;
    let text: string;
    if (failed > 0) {
      text = `下载完成 ${done} 首，失败 ${failed} 首`;
    } else if (done > 0) {
      text = `已下载完成 ${done} 首`;
    } else {
      text = '下载已结束';
    }
    DownloadNotify.publishBasic('下载结束', text);
  }

  private static progressText(songText: string, remaining: number): string {
    const suffix = remaining > 1 ? `（剩余 ${remaining} 首）` : '';
    return songText + suffix;
  }

  /** 进度实况通知（downloadTemplate + 系统实况类型；Id 必须为长时任务返回的系统通知 Id） */
  private static publishLive(id: number, songText: string, percent: number, _remaining: number): Promise<void> {
    const data: Record<string, Object> = {
      'title': 'MusicFreeOH',
      'fileName': songText,
      'progressValue': percent
    };
    const template: notificationManager.NotificationTemplate = {
      name: 'downloadTemplate',
      data: data
    };
    const request: notificationManager.NotificationRequest = {
      id: id,
      notificationSlotType: notificationManager.SlotType.LIVE_VIEW,
      template: template,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
        systemLiveView: {
          typeCode: 8,
          title: 'MusicFreeOH',
          text: songText
        }
      }
    };
    return notificationManager.publish(request);
  }

  private static publishBasic(title: string, text: string): void {
    const request: notificationManager.NotificationRequest = {
      id: DownloadNotify.NOTIFY_ID,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: title,
          text: text,
          additionalText: 'MusicFreeOH'
        }
      }
    };
    notificationManager.publish(request).catch((_e: Object): void => {
      Log.warn('下载通知发布失败（可能未授权通知）');
    });
  }
}
