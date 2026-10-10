import { KVStore } from '../infra/KVStore';
import { DataManifest } from '../common/DataManifest';
import { PathConst } from '../common/PathConst';
import { FileUtils } from '../utils/FileUtils';

/**
 * 清空所有应用数据（设置 → 缓存 → 清空所有数据）
 * 范围：全部 KV 存储（歌单/插件元数据/设置/订阅源/播放历史/本地音乐列表等缓存与持久数据）
 * + 插件脚本目录 + 数据目录（订阅源文件）+ 本地歌词 + 沙箱缓存子目录；
 * 不删除公共下载目录中已下载的音乐文件（属用户文件，由用户自行管理）
 * 清空后内存态与磁盘态不再一致，调用方应直接重启应用（ApplicationContext.restartApp，
 * 该路径不触发 onDestroy，避免清空后的空数据经退出自动备份覆盖云端 WebDAV 备份）
 */
export class DataReset {
  static clearAll(): void {
    // KV 存储：登记清单兜底 + 本进程已创建的全部实例（含 LocalSheet.* / MediaExtra.* 动态实例）
    const names: Set<string> = new Set<string>();
    for (const n of DataManifest.BACKUP_KV_STORES) {
      names.add(n);
    }
    for (const n of DataManifest.CACHE_KV_STORES) {
      names.add(n);
    }
    for (const n of KVStore.getRegisteredNames()) {
      names.add(n);
    }
    for (const n of names) {
      KVStore.getOrCreate(n).clearAll();
    }

    // 插件脚本目录（清空后重建，保持目录结构完整）
    FileUtils.removeDir(PathConst.pluginPath);
    FileUtils.checkAndCreateDir(PathConst.pluginPath);
    // 数据目录（本地导入的订阅源文件等）
    FileUtils.removeDir(PathConst.dataPath);
    FileUtils.checkAndCreateDir(PathConst.dataPath);
    // 本地歌词文件
    FileUtils.removeDir(PathConst.localLrcPath);
    // 沙箱缓存子目录（音乐缓存/歌词缓存/下载缓存/封面缓存）
    FileUtils.removeDir(PathConst.musicCachePath);
    FileUtils.removeDir(PathConst.lrcCachePath);
    FileUtils.removeDir(PathConst.downloadCachePath);
    FileUtils.removeDir(PathConst.artworkCachePath);
  }
}
