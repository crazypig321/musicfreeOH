import { AbilityConstant, application, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ContextHolder } from '../common/ContextHolder';
import { PathConst } from '../common/PathConst';
import { Network } from '../infra/Network';
import { FileUtils } from '../utils/FileUtils';
import { mediaSession } from '../core/MediaSession';
import { screenInfo } from '../utils/ScreenInfo';

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

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    mediaSession.destroy().catch(() => {
    });
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
        // 初始化屏幕信息
        screenInfo.init(windowStage)
        // 获取顶部 和底部避让以及断点
        screenInfo.info()
      }catch (e) {

      }
      // 解析公共下载目录（DOWNLOAD 模式免弹窗，失败自动回落沙箱）
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