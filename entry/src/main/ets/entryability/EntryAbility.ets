import { AbilityConstant, application, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ContextHolder } from '../common/ContextHolder';
import { PathConst } from '../common/PathConst';
import { Network } from '../infra/Network';
import { FileUtils } from '../utils/FileUtils';
import { mediaSession } from '../core/MediaSession';
import { trackPlayer } from '../core/TrackPlayer';
import { PlayState } from '../core/PlayerEngine';
import { screenInfo } from '../utils/ScreenInfo';
import { themeUtils } from '../utils/ThemeUtils';
import { WebDav } from '../core/WebDav';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
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
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // 深浅模式切换：刷新 HDS 标题栏等组件的系统色
    if (newConfig.colorMode !== undefined) {
      themeUtils.colorModeChange(newConfig.colorMode);
    }
    hilog.info(DOMAIN, 'testTag', 'onConfigurationUpdate colorMode: %{public}s', JSON.stringify(newConfig.colorMode));
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
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
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', '%{public}s', 'Succeeded in loading the content.');
      try{
        // 全局上下文与路径初始化
        ContextHolder.initUiContext(windowStage.getMainWindowSync().getUIContext(), application.getApplicationContext())
        // 获取顶部 和底部避让以及断点
        screenInfo.info(windowStage)
      }catch (e) {

      }
      // 确保公共下载目录存在（缺失时通过 DOWNLOAD 模式免弹窗重建，不回落沙箱）
      PathConst.bootstrapPublicDownloadDir();
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}