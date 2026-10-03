import audio from '@ohos.multimedia.audio';
import { Log } from '../utils/Log';

/**
 * 空间音频 / 输出设备状态快照（不可变）
 */
export class AudioEnhanceState {
  /** 系统是否具备空间音频能力（API 18+，个别设备可能不支持该 syscap） */
  readonly spatializationApiAvailable: boolean;
  /** 当前输出设备展示名 */
  readonly deviceName: string;
  /** 当前输出设备类型标签 */
  readonly deviceTypeLabel: string;
  /** 当前输出是否为耳机 */
  readonly headphoneConnected: boolean;
  /** 当前输出设备是否支持空间音频渲染 */
  readonly spatializationSupported: boolean;
  /** 当前设备空间音频渲染是否开启 */
  readonly spatializationEnabled: boolean;

  constructor(spatializationApiAvailable: boolean, deviceName: string, deviceTypeLabel: string,
    headphoneConnected: boolean, spatializationSupported: boolean, spatializationEnabled: boolean) {
    this.spatializationApiAvailable = spatializationApiAvailable;
    this.deviceName = deviceName;
    this.deviceTypeLabel = deviceTypeLabel;
    this.headphoneConnected = headphoneConnected;
    this.spatializationSupported = spatializationSupported;
    this.spatializationEnabled = spatializationEnabled;
  }
}

/**
 * 音频增强中心（独立模块：空间音频状态 + 输出设备监测）
 *
 * 说明：三方应用无法直接开关空间音频（setSpatializationEnabled 为系统接口），
 * 也无法控制耳机侧低延时模式（由耳机/系统侧协商）。
 * 本中心提供可用的能力：设备能力查询、空间音频开关状态查询与订阅、输出设备变化监听，
 * 供 UI 展示状态与引导用户到系统设置。
 */
export class AudioEnhanceManager {
  private static instance: AudioEnhanceManager | null = null;

  private audioManager: audio.AudioManager | null = null;
  private routingManager: audio.AudioRoutingManager | null = null;
  private spatializationManager: audio.AudioSpatializationManager | null = null;
  private listeners: Array<(state: AudioEnhanceState) => void> = [];
  private watching: boolean = false;
  /** 设备插拔防抖定时器 */
  private deviceChangeTimer: number = -1;

  static getInstance(): AudioEnhanceManager {
    if (AudioEnhanceManager.instance === null) {
      AudioEnhanceManager.instance = new AudioEnhanceManager();
    }
    return AudioEnhanceManager.instance;
  }

  private constructor() {
  }

  /** 设备类型 → 中文标签 */
  static deviceTypeLabel(type: audio.DeviceType): string {
    if (type === audio.DeviceType.SPEAKER) {
      return '扬声器';
    }
    if (type === audio.DeviceType.EARPIECE) {
      return '听筒';
    }
    if (type === audio.DeviceType.BLUETOOTH_A2DP) {
      return '蓝牙耳机';
    }
    if (type === audio.DeviceType.BLUETOOTH_SCO) {
      return '蓝牙通话设备';
    }
    if (type === audio.DeviceType.WIRED_HEADSET || type === audio.DeviceType.WIRED_HEADPHONES) {
      return '有线耳机';
    }
    if (type === audio.DeviceType.USB_HEADSET) {
      return 'USB 耳机';
    }
    if (type === audio.DeviceType.DISPLAY_PORT) {
      return '外接显示设备';
    }
    if (type === audio.DeviceType.REMOTE_CAST) {
      return '投播设备';
    }
    return '其他设备';
  }

  /** 是否为耳机类设备 */
  static isHeadphoneType(type: audio.DeviceType): boolean {
    return type === audio.DeviceType.BLUETOOTH_A2DP || type === audio.DeviceType.BLUETOOTH_SCO ||
      type === audio.DeviceType.WIRED_HEADSET || type === audio.DeviceType.WIRED_HEADPHONES ||
      type === audio.DeviceType.USB_HEADSET;
  }

  /** 空间音频 API 是否可用 */
  isSpatializationApiAvailable(): boolean {
    this.ensureManagers();
    return this.spatializationManager !== null;
  }

  /** 延迟初始化（避免模块加载期访问音频服务） */
  private ensureManagers(): void {
    if (this.audioManager === null) {
      this.audioManager = audio.getAudioManager();
    }
    if (this.routingManager === null) {
      this.routingManager = this.audioManager.getRoutingManager();
    }
    if (this.spatializationManager === null && canIUse('SystemCapability.Multimedia.Audio.Spatialization')) {
      this.spatializationManager = this.audioManager.getSpatializationManager();
    }
  }

  /** 拉取当前状态快照（当前输出设备 + 空间音频能力与开关状态） */
  refreshState(): AudioEnhanceState {
    this.ensureManagers();
    const apiAvailable = this.spatializationManager !== null;
    let deviceName = '';
    let typeLabel = '未知设备';
    let headphone = false;
    let supported = false;
    const routing = this.routingManager;
    if (routing !== null) {
      try {
        const rendererInfo: audio.AudioRendererInfo = {
          usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
          rendererFlags: 0
        };
        let descriptors = routing.getPreferredOutputDeviceForRendererInfoSync(rendererInfo);
        if (descriptors.length === 0) {
          descriptors = routing.getDevicesSync(audio.DeviceFlag.OUTPUT_DEVICES_FLAG);
        }
        if (descriptors.length > 0) {
          const desc = descriptors[0];
          typeLabel = AudioEnhanceManager.deviceTypeLabel(desc.deviceType);
          headphone = AudioEnhanceManager.isHeadphoneType(desc.deviceType);
          deviceName = desc.name.length > 0 ? desc.name : typeLabel;
          supported = desc.spatializationSupported === true;
        }
      } catch (e) {
        Log.error('AudioEnhance 查询输出设备失败: ' + (e as Error).message);
      }
    }
    let enabled = false;
    const spatial = this.spatializationManager;
    if (spatial !== null) {
      try {
        enabled = spatial.isSpatializationEnabledForCurrentDevice();
      } catch (e) {
        Log.error('AudioEnhance 查询空间音频状态失败: ' + (e as Error).message);
      }
    }
    return new AudioEnhanceState(apiAvailable, deviceName, typeLabel, headphone, supported, enabled);
  }

  /** 注册状态变化监听（首个监听注册时开始订阅系统事件，返回取消函数） */
  onChanged(listener: (state: AudioEnhanceState) => void): () => void {
    this.listeners.push(listener);
    this.startWatch();
    return (): void => {
      this.removeListener(listener);
    };
  }

  private removeListener(listener: (state: AudioEnhanceState) => void): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
    if (this.listeners.length === 0) {
      this.stopWatch();
    }
  }

  private startWatch(): void {
    this.ensureManagers();
    if (this.watching) {
      return;
    }
    this.watching = true;
    const spatial = this.spatializationManager;
    if (spatial !== null) {
      try {
        spatial.on('spatializationEnabledChangeForCurrentDevice', (_enabled: boolean): void => {
          this.notifyListeners();
        });
      } catch (e) {
        Log.error('AudioEnhance 订阅空间音频状态失败: ' + (e as Error).message);
      }
    }
    const routing = this.routingManager;
    if (routing !== null) {
      try {
        routing.on('deviceChange', audio.DeviceFlag.OUTPUT_DEVICES_FLAG,
          (_action: audio.DeviceChangeAction): void => {
            this.scheduleDeviceRefresh();
          });
      } catch (e) {
        Log.error('AudioEnhance 订阅设备变化失败: ' + (e as Error).message);
      }
    }
  }

  private stopWatch(): void {
    if (!this.watching) {
      return;
    }
    this.watching = false;
    if (this.deviceChangeTimer !== -1) {
      clearTimeout(this.deviceChangeTimer);
      this.deviceChangeTimer = -1;
    }
    const spatial = this.spatializationManager;
    if (spatial !== null) {
      try {
        spatial.off('spatializationEnabledChangeForCurrentDevice');
      } catch (e) {
        // 忽略取消订阅异常
      }
    }
    const routing = this.routingManager;
    if (routing !== null) {
      try {
        routing.off('deviceChange');
      } catch (e) {
        // 忽略取消订阅异常
      }
    }
  }

  /** 设备插拔/蓝牙连接会连续触发多次事件，做 300ms 防抖 */
  private scheduleDeviceRefresh(): void {
    if (this.deviceChangeTimer !== -1) {
      clearTimeout(this.deviceChangeTimer);
    }
    this.deviceChangeTimer = setTimeout((): void => {
      this.deviceChangeTimer = -1;
      this.notifyListeners();
    }, 300);
  }

  private notifyListeners(): void {
    const state = this.refreshState();
    for (const listener of this.listeners) {
      try {
        listener(state);
      } catch (e) {
        Log.error('AudioEnhance 状态回调异常: ' + (e as Error).message);
      }
    }
  }
}
