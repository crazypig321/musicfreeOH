import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { ContextHolder } from '../common/ContextHolder';
import { Log } from './Log';

/**
 * 后台长时任务（多类型复用：音频播放 audioPlayback / 数据传输 dataTransfer）
 *
 * module.json5 中已声明 backgroundModes 与 KEEP_BACKGROUND_RUNNING 权限，
 * 但那只完成"声明"；运行时必须调用 startBackgroundRunning 申请长时任务，
 * 否则应用退后台/息屏数分钟后会被系统挂起，音乐中断、下载失败。
 *
 * 一个 UIAbility 同一时刻仅支持一个长时任务：播放与下载按需叠加类型
 * （startBackgroundRunning 传类型数组，updateBackgroundRunning 动态增删），
 * 全部业务释放后取消任务；持有 audioPlayback 任务却不播音频会被系统判定违规。
 */
export class BackgroundTask {
  private static readonly MODE_AUDIO: string = 'audioPlayback';
  private static readonly MODE_TRANSFER: string = 'dataTransfer';

  /** 业务期望：是否需要音频播放/数据传输保活 */
  private static audioDesired: boolean = false;
  private static transferDesired: boolean = false;
  /** 当前长时任务已生效的类型集合（空数组 = 未持有任务） */
  private static runningModes: Array<string> = [];
  /** 串行化异步启停操作，避免竞态 */
  private static chain: Promise<void> = Promise.resolve();
  /** dataTransfer 长时任务系统通知 Id 回调（用于下载进度实况通知） */
  private static transferIdListener: ((notificationId: number) => void) | null = null;

  /** 播放开始时申请（幂等；下载任务持有期间自动叠加类型） */
  static startAudio(): void {
    BackgroundTask.audioDesired = true;
    BackgroundTask.sync();
  }

  /** 暂停/停止/出错时释放 */
  static stopAudio(): void {
    BackgroundTask.audioDesired = false;
    BackgroundTask.sync();
  }

  /** 下载队列启动时申请；dataTransfer 系统通知 Id 通过 listener 回传（用于进度更新） */
  static startTransfer(listener: (notificationId: number) => void): void {
    BackgroundTask.transferIdListener = listener;
    BackgroundTask.transferDesired = true;
    BackgroundTask.sync();
  }

  /** 下载队列结束/清空时释放（若同时还在播放，长时任务降级为纯音频类型） */
  static stopTransfer(): void {
    BackgroundTask.transferDesired = false;
    BackgroundTask.transferIdListener = null;
    BackgroundTask.sync();
  }

  /** 同步长时任务状态到期望集合（串行执行） */
  private static sync(): void {
    BackgroundTask.chain = BackgroundTask.chain.then((): Promise<void> => BackgroundTask.apply());
  }

  private static async apply(): Promise<void> {
    const desired: Array<string> = [];
    if (BackgroundTask.audioDesired) {
      desired.push(BackgroundTask.MODE_AUDIO);
    }
    if (BackgroundTask.transferDesired) {
      desired.push(BackgroundTask.MODE_TRANSFER);
    }

    const running = BackgroundTask.runningModes;
    try {
      if (desired.length === 0) {
        if (running.length > 0) {
          await backgroundTaskManager.stopBackgroundRunning(ContextHolder.get());
          BackgroundTask.runningModes = [];
          Log.debug('BackgroundTask: 长时任务已取消');
        }
        return;
      }
      if (running.length === 0) {
        const res = await backgroundTaskManager.startBackgroundRunning(ContextHolder.get(), desired,
          await BackgroundTask.buildWantAgent());
        BackgroundTask.runningModes = desired;
        Log.debug('BackgroundTask: 长时任务已开启 ' + desired.join(','));
        BackgroundTask.notifyTransferId(res.notificationId);
        return;
      }
      if (desired.join(',') !== running.join(',')) {
        const res = await backgroundTaskManager.updateBackgroundRunning(ContextHolder.get(), desired);
        BackgroundTask.runningModes = desired;
        Log.debug('BackgroundTask: 长时任务已更新 ' + desired.join(','));
        BackgroundTask.notifyTransferId(res.notificationId);
      }
    } catch (e) {
      const detail = e instanceof Error ? e.message : JSON.stringify(e);
      Log.warn('BackgroundTask: 长时任务操作失败 ' + detail);
    }
  }

  private static notifyTransferId(notificationId: number): void {
    if (BackgroundTask.transferDesired && BackgroundTask.transferIdListener !== null) {
      BackgroundTask.transferIdListener(notificationId);
    }
  }

  /** 点击系统长时任务通知回到应用主界面 */
  private static async buildWantAgent(): Promise<WantAgent> {
    const context = ContextHolder.get();
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: context.abilityInfo.bundleName,
          abilityName: context.abilityInfo.name
        }
      ],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return wantAgent.getWantAgent(wantAgentInfo);
  }
}
