import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { ContextHolder } from '../common/ContextHolder';
import { Log } from './Log';

/**
 * 后台长时任务（音频播放）
 *
 * module.json5 中已声明 backgroundModes: audioPlayback 与 KEEP_BACKGROUND_RUNNING 权限，
 * 但那只完成"声明"；运行时必须在开始播放后调用 startBackgroundRunning 申请长时任务，
 * 否则应用退到后台数分钟后会被系统挂起，音乐随之中断、进程可能被回收。
 * （参考 ting_read SXPlayer 的 startContinuousTask/stopContinuousTask）
 */
export class BackgroundTask {
  /** 期望状态：业务层最近一次请求（start=true / stop=false） */
  private static desired: boolean = false;
  /** 长时任务当前是否生效 */
  private static running: boolean = false;

  /** 开始播放时申请长时任务（幂等；启停竞态下自动收敛到期望状态） */
  static start(): void {
    BackgroundTask.desired = true;
    if (BackgroundTask.running) {
      return;
    }
    const context = ContextHolder.get();
    // 点击系统长时任务通知回到应用主界面
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
    wantAgent.getWantAgent(wantAgentInfo).then((agent: WantAgent) => {
      return backgroundTaskManager.startBackgroundRunning(context,
        backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, agent);
    }).then((): void => {
      BackgroundTask.running = true;
      Log.debug('BackgroundTask: 长时任务已开启');
      // 等待期间业务层已请求停止，立即收敛
      if (!BackgroundTask.desired) {
        BackgroundTask.stop();
      }
    }).catch((e: Object): void => {
      Log.warn('BackgroundTask: 开启失败 ' + JSON.stringify(e));
    });
  }

  /** 暂停/停止/出错时取消长时任务（持有音频长时任务却不播音频会被系统判定违规） */
  static stop(): void {
    BackgroundTask.desired = false;
    if (!BackgroundTask.running) {
      return;
    }
    const context = ContextHolder.get();
    backgroundTaskManager.stopBackgroundRunning(context).then((): void => {
      BackgroundTask.running = false;
      Log.debug('BackgroundTask: 长时任务已取消');
      // 取消期间业务层又请求开启，重新申请
      if (BackgroundTask.desired) {
        BackgroundTask.start();
      }
    }).catch((e: Object): void => {
      Log.warn('BackgroundTask: 取消失败 ' + JSON.stringify(e));
    });
  }
}
