import connection from '@ohos.net.connection';

/**
 * 网络状态（替代 @react-native-community/netinfo）
 */
export enum NetworkState {
  Offline = 'Offline',
  Wifi = 'Wifi',
  Cellular = 'Cellular',
}

/** 网络状态变化监听 */
export type NetworkStateListener = (state: NetworkState) => void;

export class Network {
  private static instance: Network | null = null;

  private _state: NetworkState = NetworkState.Offline;
  private conn: connection.NetConnection | null = null;
  /** 状态变化监听（下载队列自动续跑等） */
  private listeners: Array<NetworkStateListener> = [];

  static getInstance(): Network {
    if (Network.instance === null) {
      Network.instance = new Network();
    }
    return Network.instance;
  }

  /** 注册网络状态变化监听 */
  onStateChanged(cb: NetworkStateListener): void {
    this.listeners.push(cb);
  }

  private setState(state: NetworkState): void {
    if (this._state === state) {
      return;
    }
    this._state = state;
    const snapshot = this.listeners.slice();
    for (const cb of snapshot) {
      try {
        cb(state);
      } catch (e) {
        // 单个监听异常不影响其余
      }
    }
  }

  /** 初始化并监听网络变化（Bootstrap 调用） */
  setup(): void {
    if (this.conn !== null) {
      return;
    }
    this.conn = connection.createNetConnection();
    this.conn.on('netAvailable', () => {
      this.refreshState();
    });
    this.conn.on('netUnavailable', () => {
      this.setState(NetworkState.Offline);
    });
    this.conn.on('netCapabilitiesChange', (data: connection.NetCapabilityInfo) => {
      this.setState(this.mapCapabilities(data.netCap.bearerTypes));
    });
    try {
      this.conn.register(() => {
      });
    } catch (e) {
      // 忽略注册失败
    }
    this.refreshState();
  }

  private refreshState(): void {
    connection.getDefaultNet().then((netHandle: connection.NetHandle) => {
      connection.getNetCapabilities(netHandle).then((caps: connection.NetCapabilities) => {
        this.setState(this.mapCapabilities(caps.bearerTypes));
      }).catch(() => {
      });
    }).catch(() => {
      this.setState(NetworkState.Offline);
    });
  }

  private mapCapabilities(bearerTypes: Array<connection.NetBearType>): NetworkState {
    for (const t of bearerTypes) {
      if (t === connection.NetBearType.BEARER_CELLULAR) {
        return NetworkState.Cellular;
      }
    }
    for (const t of bearerTypes) {
      if (t === connection.NetBearType.BEARER_WIFI || t === connection.NetBearType.BEARER_ETHERNET) {
        return NetworkState.Wifi;
      }
    }
    return NetworkState.Cellular;
  }

  get state(): NetworkState {
    return this._state;
  }

  get isOffline(): boolean {
    return this._state === NetworkState.Offline;
  }

  get isWifi(): boolean {
    return this._state === NetworkState.Wifi;
  }

  get isCellular(): boolean {
    return this._state === NetworkState.Cellular;
  }

  get isConnected(): boolean {
    return this._state !== NetworkState.Offline;
  }
}

export const network: Network = Network.getInstance();
