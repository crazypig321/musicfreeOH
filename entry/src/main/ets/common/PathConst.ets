import { ContextHolder } from './ContextHolder';
import { bundleManager } from '@kit.AbilityKit';
import { fileUri, fileIo as fs } from '@kit.CoreFileKit';
import { Log } from '../utils/Log';

/**
 * 路径常量（移植自 MusicFree src/constants/pathConst.ts）
 * 应用数据目录基于 context.filesDir
 * 下载目录映射到公共 Download/<bundleName>/（RN 原版为应用沙箱，此处为有意偏差）
 * DOWNLOAD 模式授权目录可直接构造 URI 访问（免弹窗免权限、卸载重装后仍可访问），失败回落沙箱
 */
export class PathConst {
  static basePath: string = '';
  static pluginPath: string = '';
  static logPath: string = '';
  static dataPath: string = '';
  static cachePath: string = '';
  static localLrcPath: string = '';
  static lrcCachePath: string = '';
  static downloadCachePath: string = '';
  /** 本地音乐内嵌封面缓存目录（沙箱 cache，可被系统清理后由下次扫描重建） */
  static artworkCachePath: string = '';
  static downloadPath: string = '';
  static downloadMusicPath: string = '';
  /** 公共下载目录是否已解析过（每次进程生命周期内只尝试一次） */
  private static publicDownloadDirResolved: boolean = false;

  static init(): void {
    const ctx = ContextHolder.get();
    PathConst.basePath = ctx.filesDir;
    PathConst.pluginPath = PathConst.basePath + '/plugins/';
    PathConst.logPath = PathConst.basePath + '/log/';
    PathConst.dataPath = PathConst.basePath + '/data/';
    PathConst.cachePath = ctx.cacheDir + '/';
    PathConst.localLrcPath = PathConst.basePath + '/local_lrc/';
    PathConst.lrcCachePath = PathConst.cachePath + 'lrc/';
    PathConst.downloadCachePath = PathConst.cachePath + 'download/';
    PathConst.artworkCachePath = PathConst.cachePath + 'artwork/';
    // 默认沙箱回落；启动后由 bootstrapPublicDownloadDir 异步解析公共目录刷新
    PathConst.downloadPath = PathConst.basePath + '/download/';
    PathConst.downloadMusicPath = PathConst.downloadPath;
  }

  /**
   * 解析公共下载目录 Download/<bundleName>/（DOWNLOAD 模式授权目录，
   * 系统预置持久化权限，可直接构造 URI 访问，卸载重装后仍有效）；
   * 失败保持沙箱回落。每个进程生命周期内只尝试一次，可安全重复调用。
   */
  static async bootstrapPublicDownloadDir(): Promise<void> {
    if (PathConst.publicDownloadDirResolved) {
      return;
    }
    PathConst.publicDownloadDirResolved = true;
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      const uri = 'file://docs/storage/Users/currentUser/Download/' + bundleInfo.name;
      const dirPath = new fileUri.FileUri(uri).path;
      if (dirPath.length > 0 && PathConst.probeWritable(dirPath)) {
        PathConst.downloadPath = dirPath;
        PathConst.downloadMusicPath = PathConst.downloadPath;
        Log.info('公共下载目录已解析: ' + PathConst.downloadPath);
      } else {
        Log.error('公共下载目录不可写，保持沙箱目录');
      }
    } catch (e) {
      const detail = e instanceof Error ? e.message : '';
      Log.error('解析公共下载目录失败: ' + detail + '，保持沙箱目录');
    }
  }

  /** 探测目录可写性：尝试创建 MusicFreeOH 子目录 */
  private static probeWritable(root: string): boolean {
    try {
      if (!fs.accessSync(root)) {
        fs.mkdirSync(root, true);
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}
