import { notificationManager } from '@kit.NotificationKit';
import { ContextHolder } from '../common/ContextHolder';
import { Log } from './Log';

/**
 * 版本更新下载通知（进度实况 + 完成摘要），机制同歌曲下载 DownloadNotify
 *
 * 进度条通知复用 dataTransfer 长时任务返回的系统通知 Id（downloadTemplate
 * 实况通知，随长时任务取消由系统移除）；实况发布失败或 Id 不可用时，
 * 降级为普通文本通知（自有固定 Id，覆盖式更新）。
 * 应用通知需用户授权：首次下载时请求一次，被拒绝则静默跳过（不影响下载）。
 */
export class UpdateNotify {
  /** 摘要/降级通知的固定 Id */
  private static readonly NOTIFY_ID = 1002;
  /** 进度通知最小刷新间隔（毫秒） */
  private static readonly PROGRESS_THROTTLE_MS = 600;

  /** dataTransfer 长时任务系统通知 Id（<=0 表示不可用） */
  private static systemNotificationId: number = -1;
  private static lastPublishAt: number = 0;
  private static enabledChecked: boolean = false;

  static setSystemNotificationId(id: number): void {
    UpdateNotify.systemNotificationId = id;
  }

  /** 新下载开始：重置节流状态，首条进度立即发布 */
  static resetProgress(): void {
    UpdateNotify.lastPublishAt = 0;
  }

  /** 首次下载时确保通知授权（仅弹一次；用户拒绝过或应用不在前台时静默失败） */
  static ensureEnabled(): void {
    if (UpdateNotify.enabledChecked) {
      return;
    }
    UpdateNotify.enabledChecked = true;
    notificationManager.isNotificationEnabled().then((enabled: boolean): Promise<void> => {
      if (enabled) {
        return Promise.resolve();
      }
      return notificationManager.requestEnableNotification(ContextHolder.get());
    }).catch((_e: Object): void => {
    });
  }

  /** 更新下载进度通知（节流）：nameText 如「新版本 v1.2.3」，percent 0-100，sizeText 如「12.3MB/27.5MB」 */
  static updateProgress(nameText: string, percent: number, sizeText: string): void {
    const now = Date.now();
    if (now - UpdateNotify.lastPublishAt < UpdateNotify.PROGRESS_THROTTLE_MS) {
      return;
    }
    UpdateNotify.lastPublishAt = now;
    if (UpdateNotify.systemNotificationId > 0) {
      UpdateNotify.publishLive(UpdateNotify.systemNotificationId, nameText, percent)
        .catch((): void => {
          UpdateNotify.systemNotificationId = -1;
          UpdateNotify.publishBasic('正在下载新版本', nameText + ' ' + sizeText);
        });
    } else {
      UpdateNotify.publishBasic('正在下载新版本', nameText + ' ' + sizeText);
    }
  }

  /** 下载完成：显示保存摘要（长时任务通知由系统随任务取消移除） */
  static showDone(fileName: string): void {
    UpdateNotify.systemNotificationId = -1;
    UpdateNotify.lastPublishAt = 0;
    UpdateNotify.publishBasic('新版本下载完成', fileName + ' 已保存');
  }

  /** 下载失败提示 */
  static showFailed(): void {
    UpdateNotify.systemNotificationId = -1;
    UpdateNotify.lastPublishAt = 0;
    UpdateNotify.publishBasic('新版本下载失败', '请稍后重试');
  }

  /** 进度实况通知（downloadTemplate + 系统实况类型；Id 必须为长时任务返回的系统通知 Id） */
  private static publishLive(id: number, nameText: string, percent: number): Promise<void> {
    const data: Record<string, Object> = {
      'title': 'MusicFreeOH',
      'fileName': nameText,
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
          text: nameText
        }
      }
    };
    return notificationManager.publish(request);
  }

  private static publishBasic(title: string, text: string): void {
    const request: notificationManager.NotificationRequest = {
      id: UpdateNotify.NOTIFY_ID,
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
      Log.warn('更新通知发布失败（可能未授权通知）');
    });
  }
}
