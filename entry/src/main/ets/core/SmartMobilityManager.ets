import { smartMobilityCommon } from '@kit.CarKit';
import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { appState } from '../entryability/AppState';

const DOMAIN = 0x0000;
const TAG = 'SmartMobility';

/**
 * 智慧出行感知（HiCar / 超级桌面 / 流转）
 * - 监听 Car Kit smartMobilityStatus 连接状态变化
 * - 通过 displayId 比对判断应用是否显示在车机屏（虚拟屏）上，
 *   命中时驱动 appState.onCarScreen → 驾驶模式 UI
 * - 设备不支持（返回 801）/无权限（201）时全部静默降级，功能优雅退化
 */
export class SmartMobilityManager {
  private static instance: SmartMobilityManager | null = null;
  private awareness: smartMobilityCommon.SmartMobilityAwareness | null = null;
  private context: common.UIAbilityContext | null = null;
  private listening: boolean = false;

  static getInstance(): SmartMobilityManager {
    if (SmartMobilityManager.instance === null) {
      SmartMobilityManager.instance = new SmartMobilityManager();
    }
    return SmartMobilityManager.instance;
  }

  /** 订阅类型：HiCar、超级桌面、流转 */
  private static types(): Array<smartMobilityCommon.SmartMobilityType> {
    return [
      smartMobilityCommon.SmartMobilityType.HICAR,
      smartMobilityCommon.SmartMobilityType.SUPER_LAUNCHER,
      smartMobilityCommon.SmartMobilityType.CAR_HOP
    ];
  }

  /** 注册监听（EntryAbility.onCreate 调用；重复调用幂等；失败时 refreshOnCarScreen 会重试） */
  setup(context: common.UIAbilityContext): void {
    this.context = context;
    this.registerAwareness();
    this.refreshOnCarScreen();
  }

  /** 注册 awareness 监听（幂等；Car Kit 服务就绪晚于应用启动等场景由 refresh 时重试） */
  private registerAwareness(): void {
    if (this.listening) {
      return;
    }
    try {
      this.awareness = smartMobilityCommon.getSmartMobilityAwareness();
      const callBack = (info: smartMobilityCommon.SmartMobilityInfo): void => {
        hilog.info(DOMAIN, TAG, 'smart mobility status: type=%{public}d, status=%{public}d',
          info.type, info.status);
        appState.smartMobilityConnected =
          info.status === smartMobilityCommon.SmartMobilityStatus.RUNNING;
        this.refreshOnCarScreen();
      };
      this.awareness.on('smartMobilityStatus', SmartMobilityManager.types(), callBack);
      this.listening = true;
    } catch (e) {
      // 801 设备不支持（PC/2in1 等）/ 201 无权限 / 服务未就绪：静默降级，下次 refresh 重试
      this.awareness = null;
      hilog.warn(DOMAIN, TAG, 'register smart mobility listener failed: %{public}s',
        JSON.stringify(e));
    }
  }
  /**
   * 重新判定应用是否显示在车机屏上：
   * 车机设备本体（deviceType 为 car，含接续/通知等任意启动方式）直接命中；
   * 否则对各业务类型查询连接状态，业务所在虚拟屏 DISPLAY_ID 与当前窗口 displayId 一致即命中。
   * onConfigurationUpdate（HiCar 投射引起 config 变化）与状态回调时调用。
   */
  refreshOnCarScreen(): void {
    if (this.context === null) {
      return;
    }
    // 注册失败（服务未就绪等）时重试，保证投流会话建立后仍能感知
    this.registerAwareness();
    const onCar = SmartMobilityManager.isCarDevice() || this.matchCarDisplay();
    hilog.info(DOMAIN, TAG,
      'refresh: deviceType=%{public}s, displayId=%{public}d, awareness=%{public}s, onCar=%{public}d',
      deviceInfo.deviceType, this.context.config.displayId ?? -1,
      this.awareness === null ? 'null' : 'ok', onCar ? 1 : 0);
    if (appState.onCarScreen !== onCar) {
      hilog.info(DOMAIN, TAG, 'onCarScreen -> %{public}d', onCar ? 1 : 0);
      appState.onCarScreen = onCar;
      appState.refreshCarMode();
    }
  }

  /** 是否运行在车机设备本体上（车机上任意方式启动均自动进入驾驶模式） */
  private static isCarDevice(): boolean {
    return deviceInfo.deviceType === 'car';
  }

  /** HiCar / 超级桌面 / 流转虚拟屏命中判定（能力不可用时返回 false） */
  private matchCarDisplay(): boolean {
    if (this.awareness === null) {
      return false;
    }
    let onCar = false;
    try {
      const currentDisplayId = this.context?.config.displayId;
      if (currentDisplayId !== undefined) {
        const types = SmartMobilityManager.types();
      for (const t of types) {
        const info = this.awareness.getSmartMobilityStatus(t);
        const rawDisplay = info.data['DISPLAY_ID'];
        hilog.info(DOMAIN, TAG, 'type=%{public}d status=%{public}d displayId=%{public}s',
          t, info.status, rawDisplay === undefined ? 'none' : JSON.stringify(rawDisplay));
        if (info.status !== smartMobilityCommon.SmartMobilityStatus.RUNNING) {
          continue;
        }
        if (rawDisplay === undefined || rawDisplay === null) {
          continue;
        }
          const deviceDisplayId = Number(rawDisplay);
          if (currentDisplayId === deviceDisplayId) {
            onCar = true;
            break;
          }
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'get smart mobility status failed: %{public}s',
        JSON.stringify(e));
      return false;
    }
    return onCar;
  }

  /** 取消监听（EntryAbility.onDestroy 调用） */
  teardown(): void {
    if (this.awareness === null || !this.listening) {
      return;
    }
    try {
      this.awareness.off('smartMobilityStatus', SmartMobilityManager.types());
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'unregister smart mobility listener failed: %{public}s',
        JSON.stringify(e));
    }
    this.listening = false;
  }
}
