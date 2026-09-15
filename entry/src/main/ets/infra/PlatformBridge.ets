/**
 * 平台桥接：core 层对 UI 层的回调抽象
 * （解耦原工程 core→components/toast、core→dialogs 的反向依赖）
 */
export class PlatformBridge {
  private static impl: PlatformBridgeImpl | null = null;

  static setImpl(impl: PlatformBridgeImpl): void {
    PlatformBridge.impl = impl;
  }

  static showToast(message: string): void {
    if (PlatformBridge.impl !== null) {
      PlatformBridge.impl.showToast(message);
    }
  }

  /** 弹确认框，返回用户选择 */
  static confirm(title: string, content: string): Promise<boolean> {
    if (PlatformBridge.impl !== null) {
      return PlatformBridge.impl.confirm(title, content);
    }
    return Promise.resolve(true);
  }
}

export interface PlatformBridgeImpl {
  showToast(message: string): void;

  confirm(title: string, content: string): Promise<boolean>;
}
