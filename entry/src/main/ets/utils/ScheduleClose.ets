import { ContextHolder } from '../common/ContextHolder';
import { trackPlayer } from '../core/TrackPlayer';

/**
 * 定时关闭（移植自 utils/scheduleClose.ts）
 * BackgroundTimer 由 setTimeout 承担；退出应用由 terminateSelf 承担
 * RN 通过 on/off PlayEnd 注册/注销 exitApp，这里用 armed 标记等价实现并修正了
 * setScheduleClose(null) 不注销等待播完退出的边界问题
 */
export class ScheduleClose {
  private static deadline: number | null = null;
  private static closeAfterPlayEnd: boolean = false;
  private static armed: boolean = false;
  private static timerId: number = -1;
  private static setupDone: boolean = false;

  /** 注册播完退出监听（Bootstrap 中调用一次） */
  static setup(): void {
    if (ScheduleClose.setupDone) {
      return;
    }
    ScheduleClose.setupDone = true;
    trackPlayer.onPlayEnd(() => {
      if (ScheduleClose.armed) {
        ScheduleClose.armed = false;
        if (ScheduleClose.closeAfterPlayEnd) {
          ScheduleClose.exitApp();
        }
      }
    });
  }

  static getDeadline(): number | null {
    return ScheduleClose.deadline;
  }

  static isCloseAfterPlayEnd(): boolean {
    return ScheduleClose.closeAfterPlayEnd;
  }

  static setScheduleClose(deadline: number | null): void {
    ScheduleClose.deadline = deadline;
    if (ScheduleClose.timerId !== -1) {
      clearTimeout(ScheduleClose.timerId);
      ScheduleClose.timerId = -1;
    }
    if (deadline !== null && deadline > Date.now()) {
      ScheduleClose.timerId = setTimeout(() => {
        ScheduleClose.timerId = -1;
        if (ScheduleClose.closeAfterPlayEnd) {
          ScheduleClose.armed = true;
        } else {
          ScheduleClose.exitApp();
        }
      }, deadline - Date.now());
    } else {
      ScheduleClose.armed = false;
    }
  }

  static setCloseAfterPlayEnd(closeAfterPlayEnd: boolean): void {
    if (!closeAfterPlayEnd) {
      ScheduleClose.armed = false;
    }
    ScheduleClose.closeAfterPlayEnd = closeAfterPlayEnd;
  }

  private static exitApp(): void {
    trackPlayer.reset().catch(() => {
    });
    ContextHolder.get().terminateSelf().catch(() => {
    });
  }
}
