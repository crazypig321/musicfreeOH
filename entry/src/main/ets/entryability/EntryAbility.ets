import { AbilityConstant, application, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { rpc } from '@kit.IPCKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ContextHolder } from '../common/ContextHolder';
import { PathConst } from '../common/PathConst';
import { Network } from '../infra/Network';
import { FileUtils } from '../utils/FileUtils';
import { mediaSession } from '../core/MediaSession';
import { trackPlayer } from '../core/TrackPlayer';
import { PlayState } from '../core/PlayerEngine';
import { MusicWidgetManager, MusicWidgetCommand } from '../core/MusicWidgetManager';
import { screenInfo } from '../utils/ScreenInfo';
import { themeUtils } from '../utils/ThemeUtils';
import { WebDav } from '../core/WebDav';
import { downloader } from '../core/Downloader';
import { ExternalOpen } from '../core/ExternalOpen';
import { HarmonyShareRecv } from '../sharereceive/HarmonyShareRecv';
import { JsonUtil } from '../utils/JsonUtil';
import { Continuation, ContinuationData } from '../core/Continuation';
import { SmartMobilityManager } from '../core/SmartMobilityManager';
import { Bootstrap } from '../core/Bootstrap';
import { WebPluginExecutor } from '../plugin/WebPluginExecutor';

const DOMAIN = 0x0000;
/** 桌面音乐卡片 call 事件方法名（与卡片页 MusicCard.ets postCardAction method 一致） */
const MUSIC_WIDGET_CALL_METHOD = 'mediaControl';

/** call 事件回调返回值（CalleeCallback 要求返回 Parcelable，本场景无回传数据） */
class WidgetCallResult implements rpc.Parcelable {
  marshalling(_sequence: rpc.MessageSequence): boolean {
    return true;
  }

  unmarshalling(_sequence: rpc.MessageSequence): boolean {
    return true;
  }
}

export default class EntryAbility extends UIAbility {
  /** 本次 Ability 实例是否已获得 WindowStage（正常前台启动时先于 onForeground） */
  private windowStageReady: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');

    // 全局上下文与路径初始化
    ContextHolder.init(this.context);

    PathConst.init();
    FileUtils.checkAndCreateDir(PathConst.pluginPath);
    FileUtils.checkAndCreateDir(PathConst.dataPath);
    FileUtils.checkAndCreateDir(PathConst.localLrcPath);
    FileUtils.checkAndCreateDir(PathConst.lrcCachePath);
    FileUtils.checkAndCreateDir(PathConst.logPath);
    // 网络状态监听
    Network.getInstance().setup();
    // 恢复上次未完成/失败的下载任务：失败任务原样恢复，中断任务网络可用时自动断点续传
    downloader.restorePersistedTasks();
    // 外部文件关联打开（文件管理器/QQ/微信 → .js 插件 / .json 备份或订阅源 / 音频播放）
    ExternalOpen.offer(want);
    // 应用接续（车机流转）目标端冷启动：接续数据覆写本地持久化，
    // 后续 Bootstrap.setup 的既有恢复链即可按源端播放现场恢复
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      this.handleContinuationColdStart(want);
    } else if (Continuation.pendingRepair !== null) {
      // 上次接续拉起被系统窗口缺陷破坏后经修复/手动重开：热应用暂存的播放现场
      this.applyPendingRepairContinuation();
    }
    // 智慧出行（HiCar/超级桌面/流转）状态感知：车机屏检测与驾驶模式切换
    SmartMobilityManager.getInstance().setup(this.context);
    // 桌面音乐卡片：监听播放状态用于推送卡片 + 注册 call 事件命令处理
    MusicWidgetManager.setup();
    this.registerMusicWidgetCaller();
  }

  /** 应用接续目标端冷启动：解析 want 数据并覆写本地持久化（须早于 Bootstrap.setup） */
  private handleContinuationColdStart(want: Want): void {
    const data = Continuation.parseFromWant(want);
    if (data === null || data.current === null) {
      hilog.warn(DOMAIN, 'testTag', 'continuation data invalid, fallback to local restore');
      return;
    }
    hilog.info(DOMAIN, 'testTag', 'continuation cold start: %{public}s', Continuation.describe(data));
    // 进程级暂存：若本次拉起遭遇窗口缺陷（WindowStage 不创建），修复路径据此热应用
    Continuation.pendingRepair = data;
    Continuation.writeToPersistStatus(data);
    // 源端在播时恢复后强制续播（不受「启动自动续播」设置限制）
    trackPlayer.markContinuationResume(data.playing);
  }

  /** 热应用暂存的接续播放现场（进程已初始化时直接重建，否则留给冷恢复链） */
  private applyPendingRepairContinuation(): void {
    const data = Continuation.pendingRepair;
    if (data === null) {
      return;
    }
    Continuation.pendingRepair = null;
    if (data.current === null || !Bootstrap.isInited()) {
      // Bootstrap 未初始化：onCreate 已写入 PersistStatus，冷恢复链自然生效
      return;
    }
    hilog.info(DOMAIN, 'testTag', 'apply pending continuation after repair: %{public}s', Continuation.describe(data));
    trackPlayer.applyContinuation(
      data.queue,
      data.current,
      data.progress,
      data.playing,
      data.repeatMode
    ).catch((_e: Object): void => {
    });
  }

  /** 应用接续源端：打包播放现场写入 wantParam，同意迁移 */
  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    const payload = Continuation.buildPayload();
    if (payload === null) {
      hilog.info(DOMAIN, 'testTag', 'onContinue: nothing to continue, reject');
      return AbilityConstant.OnContinueResult.REJECT;
    }
    try {
      const keys = Object.keys(payload);
      for (const key of keys) {
        wantParam[key] = payload[key];
      }
      hilog.info(DOMAIN, 'testTag', 'onContinue: agree with %{public}d keys', keys.length);
      return AbilityConstant.OnContinueResult.AGREE;
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'onContinue failed. Cause: %{public}s', JSON.stringify(err));
      return AbilityConstant.OnContinueResult.REJECT;
    }
  }

  /** 注册桌面音乐卡片 call 事件（卡片控制按钮 → 后台执行播放命令） */
  private registerMusicWidgetCaller(): void {
    try {
      this.callee.on(MUSIC_WIDGET_CALL_METHOD, (data: rpc.MessageSequence): rpc.Parcelable => {
        // call 事件冷启动：无 WindowStage 的后台拉起，标记无窗口模式
        // （插件沙箱不可用，挂载立即失败而非等待 30 秒超时）
        if (!this.windowStageReady) {
          WebPluginExecutor.getInstance().markHeadless();
        }
        // call 事件参数以 JSON 字符串送达（卡片 postCardAction params）
        const rec = JsonUtil.parseRecord(data.readString());
        const command = rec !== null ? JsonUtil.recStr(rec, 'command') : '';
        const index = rec !== null ? JsonUtil.recNum(rec, 'index', -1) : -1;
        if (command.length > 0) {
          MusicWidgetManager.handleCommand(command, index).catch((_e: Object): void => {
          });
        }
        return new WidgetCallResult();
      });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to register widget callee. Cause: %{public}s', JSON.stringify(err));
    }
  }

  /** 应用已启动时再次被外部文件打开拉起（冷启动走 onCreate 的 want）；
   *  应用接续（车机流转）目标端热启动也走此回调：直接重建播放现场 */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    ExternalOpen.offer(want);
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      const data = Continuation.parseFromWant(want);
      if (data !== null && data.current !== null) {
        hilog.info(DOMAIN, 'testTag', 'continuation hot start: %{public}s', Continuation.describe(data));
        trackPlayer.applyContinuation(
          data.queue,
          data.current,
          data.progress,
          data.playing,
          data.repeatMode
        ).catch((_e: Object): void => {
        });
      }
    }
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // 深浅模式切换：刷新 HDS 标题栏等组件的系统色
    if (newConfig.colorMode !== undefined) {
      themeUtils.colorModeChange(newConfig.colorMode);
    }
    // HiCar 投射等场景 displayId 随 config 变化：重新判定是否在车机屏上
    SmartMobilityManager.getInstance().refreshOnCarScreen();
    hilog.info(DOMAIN, 'testTag', 'onConfigurationUpdate colorMode: %{public}s', JSON.stringify(newConfig.colorMode));
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    // 销毁前落盘播放进度，保证下次启动可续播到上次位置
    trackPlayer.saveProgress();
    // 彻底退出前自动备份 WebDAV（开关开启且服务器可达时执行，静默失败）；
    // onDestroy 是退出（划走任务 / 定时退出 / 关闭窗口）前最后一个可靠回调
    WebDav.backupOnExit().catch(() => {
    });
    // 播放中（长时任务续跑、进程存活）不销毁媒体会话，
    // 否则系统播控中心/锁屏播控会随 Ability 销毁一起消失
    if (trackPlayer.playState !== PlayState.Playing) {
      mediaSession.destroy().catch(() => {
      });
    }
    // 注销智慧出行状态监听
    SmartMobilityManager.getInstance().teardown();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    if (this.windowStageReady) {
      // 修复路径已手动完成窗口初始化
      return;
    }
    this.windowStageReady = true;
    // 正常窗口创建：接续现场交由冷恢复链从持久化读取，清除修复暂存避免残留误应用
    Continuation.pendingRepair = null;
    this.setupMainWindow(windowStage);
  }

  /** 主窗口内容加载与全局 UI 上下文初始化（正常创建与缺陷修复共用） */
  private setupMainWindow(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', '%{public}s', 'Succeeded in loading the content.');
      try {
        // 全局上下文与路径初始化
        ContextHolder.initUiContext(windowStage.getMainWindowSync().getUIContext(), application.getApplicationContext())
        // 获取顶部 和底部避让以及断点
        screenInfo.info(windowStage)
        // 华为分享跨设备沙箱接收（碰一碰轻贴直达；设备不支持时内部静默失败）
        windowStage.getMainWindowSync().getProperties().then((props: window.WindowProperties): void => {
          HarmonyShareRecv.register(props.id);
        }).catch((_e: Object): void => {
        });
      } catch (e) {

      }
      // 确保公共下载目录存在（缺失时通过 DOWNLOAD 模式免弹窗重建，不回落沙箱）
      PathConst.bootstrapPublicDownloadDir();
    });
  }

  /**
   * 系统缺陷兜底：接续拉起存活进程中被销毁的 Ability 时，WindowStage 可能不创建
   * （表现为卡启动页 logo；onForeground 先于 onWindowStageCreate 即为异常态）。
   * 主动取回进程内 WindowStage 手动加载主页，并热应用暂存的接续现场。
   */
  private repairMissingWindowStage(): void {
    hilog.warn(DOMAIN, 'testTag', '%{public}s', 'window stage missing on foreground, try manual recovery');
    this.context.getApplicationContext().getAllWindowStages().then((stages: Array<window.WindowStage>): void => {
      if (stages.length === 0) {
        hilog.error(DOMAIN, 'testTag', '%{public}s', 'no window stage to recover, terminate broken ability');
        this.context.terminateSelf().catch((): void => {
        });
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'recover with window stage, count: %{public}d', stages.length);
      this.windowStageReady = true;
      this.setupMainWindow(stages[stages.length - 1]);
      this.applyPendingRepairContinuation();
    }).catch((error: BusinessError): void => {
      hilog.error(DOMAIN, 'testTag', 'getAllWindowStages failed: %{public}s', JSON.stringify(error));
      this.context.terminateSelf().catch((): void => {
      });
    });
  }

  onWindowStageDestroy(): void {
    // Window stage is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
    this.windowStageReady = false;
    HarmonyShareRecv.unregister();
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    // 正常前台启动 onWindowStageCreate 必先于 onForeground；缺失即为接续拉起存活进程的
    // 系统窗口缺陷（卡启动页 logo），主动修复
    if (!this.windowStageReady) {
      this.repairMissingWindowStage();
    }
    // 超级桌面/HiCar 投流可能在后台期间建立会话，回前台时重判是否在车机屏上
    SmartMobilityManager.getInstance().refreshOnCarScreen();
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    // 退后台时落盘播放进度（应用可能随时被系统回收）
    trackPlayer.saveProgress();
  }
}