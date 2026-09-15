import connection from '@ohos.net.connection';

/**
 * 网络状态（替代 @react-native-community/netinfo）
 */
export enum NetworkState {
  Offline = 'Offline',
  Wifi = 'Wifi',
  Cellular = 'Cellular',
}

export class Network {
  private static instance: Network | null = null;

  private _state: NetworkState = NetworkState.Offline;
  private conn: connection.NetConnection | null = null;

  static getInstance(): Network {
    if (Network.instance === null) {
      Network.instance = new Network();
    }
    return Network.instance;
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
      this._state = NetworkState.Offline;
    });
    this.conn.on('netCapabilitiesChange', (data: connection.NetCapabilityInfo) => {
      this._state = this.mapCapabilities(data.netCap.bearerTypes);
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
        this._state = this.mapCapabilities(caps.bearerTypes);
      }).catch(() => {
      });
    }).catch(() => {
      this._state = NetworkState.Offline;
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
