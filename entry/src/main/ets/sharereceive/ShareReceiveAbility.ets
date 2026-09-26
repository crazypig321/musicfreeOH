import { ShareExtensionAbility, UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { ShareReceiveStore } from './ShareReceiveStore';

/**
 * 系统分享接收扩展（分享面板「分享详情页」）：
 * 接收文本/链接/插件/订阅源/音频，确认后暂存进沙箱并拉起主应用完成导入
 */
export default class ShareReceiveAbility extends ShareExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    systemShare.getSharedData(want)
      .then((data: systemShare.SharedData): void => {
        ShareReceiveStore.open(this.context, session, data.getRecords());
        if (!ShareReceiveStore.hasItems()) {
          session.terminateSelf();
          return;
        }
        session.loadContent('view/ShareReceivePage');
      })
      .catch((_e: Object): void => {
        session.terminateSelf();
      });
  }

  onSessionDestroy(): void {
    ShareReceiveStore.clear();
  }
}
