import { KVStore } from '../infra/KVStore';
import bundleManager from '@ohos.bundle.bundleManager';

/**
 * 应用元信息（移植自 appMeta.ts）
 */
export class AppMeta {
  private static cachedVersion: string = '';

  /** 应用版本号（对应 DeviceInfo.getVersion()） */
  static get appVersion(): string {
    if (AppMeta.cachedVersion.length === 0) {
      let version = '';
      try {
        const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
        version = info.versionName;
      } catch (e) {
        version = '';
      }
      AppMeta.cachedVersion = version.length > 0 ? version : '1.0.0';
    }
    return AppMeta.cachedVersion;
  }

  private store(): KVStore {
    return KVStore.getOrCreate('App.meta');
  }

  get musicSheetVersion(): number {
    const v = this.store().get('MusicSheetVersion');
    if (v.length > 0) {
      return Number(v);
    }
    return 0;
  }

  setMusicSheetVersion(version: number): void {
    this.store().set('MusicSheetVersion', '' + version);
  }

  get historySheetVersion(): number {
    const v = this.store().get('HistorySheetVersion');
    if (v.length > 0) {
      return Number(v);
    }
    return 0;
  }

  setHistorySheetVersion(version: number): void {
    this.store().set('HistorySheetVersion', '' + version);
  }
}

export const appMeta = new AppMeta();
