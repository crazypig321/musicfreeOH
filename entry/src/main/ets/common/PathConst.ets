import { ContextHolder } from './ContextHolder';
import { bundleManager } from '@kit.AbilityKit';
import { fileUri, fileIo as fs, picker } from '@kit.CoreFileKit';
import { Log } from '../utils/Log';

/**
 * 路径常量（移植自 MusicFree src/constants/pathConst.ts）
 * 应用数据目录基于 context.filesDir
 * 下载目录固定映射到公共 Download/<bundleName>/（DOWNLOAD 模式授权目录，
 * 系统预置持久化权限，可直接构造 URI 访问，卸载重装后仍可访问）
 * 目录被手动删除后应用无法用 fs.mkdir 直接重建，需通过 DOWNLOAD 模式 save
 * 让系统自动重建；不做沙箱回落：目录不可用时下载任务以 NO_WRITE_PERMISSION
 * 失败（路径在下载设置页可见），不再静默落沙箱
 */
export class PathConst {
  static basePath: string = '';
  static pluginPath: string = '';
  static logPath: string = '';
  static dataPath: string = '';
  static cachePath: string = '';
  /** 在线音乐播放缓存目录（预留，对齐 RN 的 TrackPlayer 缓存） */
  static musicCachePath: string = '';
  static localLrcPath: string = '';
  static lrcCachePath: string = '';
  static downloadCachePath: string = '';
  /** 本地音乐内嵌封面缓存目录（沙箱 cache，可被系统清理后由下次扫描重建） */
  static artworkCachePath: string = '';
  static downloadPath: string = '';
  static downloadMusicPath: string = '';
  /** 公共下载目录可用性探测 Promise（成功后复用；失败置空，下次调用自动重试） */
  private static publicDownloadDirPromise: Promise<void> | null = null;

  static init(): void {
    const ctx = ContextHolder.get();
    PathConst.basePath = ctx.filesDir;
    PathConst.pluginPath = PathConst.basePath + '/plugins/';
    PathConst.logPath = PathConst.basePath + '/log/';
    PathConst.dataPath = PathConst.basePath + '/data/';
    PathConst.cachePath = ctx.cacheDir + '/';
    PathConst.musicCachePath = PathConst.cachePath + 'music/';
    PathConst.localLrcPath = PathConst.basePath + '/local_lrc/';
    PathConst.lrcCachePath = PathConst.cachePath + 'lrc/';
    PathConst.downloadCachePath = PathConst.cachePath + 'download/';
    PathConst.artworkCachePath = PathConst.cachePath + 'artwork/';
    // 下载目录固定使用公共 Download/<bundleName>/（同步构造，无沙箱回落；
    // 目录是否真实存在由 bootstrapPublicDownloadDir 异步保证）
    PathConst.downloadPath = PathConst.resolvePublicDownloadPath();
    PathConst.downloadMusicPath = PathConst.downloadPath;
  }

  /** 同步构造公共下载目录 Download/<bundleName>/ 路径（仅构造失败才回落沙箱，实际不会发生） */
  private static resolvePublicDownloadPath(): string {
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      const uri = 'file://docs/storage/Users/currentUser/Download/' + bundleInfo.name;
      const dirPath = new fileUri.FileUri(uri).path;
      if (dirPath.length > 0) {
        return dirPath;
      }
    } catch (e) {
      const detail = e instanceof Error ? e.message : '';
      Log.error('构造公共下载目录失败: ' + detail);
    }
    return PathConst.basePath + '/download/';
  }

  /**
   * 确保公共下载目录 Download/<bundleName>/ 存在可用：
   * 目录存在直接使用；目录缺失时先尝试 mkdir，被系统拒绝则通过 DOWNLOAD 模式
   * save（免弹窗）让系统自动重建 Download/包名/ 并授予持久化权限。
   * 失败不缓存结果，后续调用（如发起下载）自动重试；期间下载任务会以
   * NO_WRITE_PERMISSION 明确失败，不会静默写入沙箱。
   */
  static bootstrapPublicDownloadDir(): Promise<void> {
    if (PathConst.publicDownloadDirPromise === null) {
      PathConst.publicDownloadDirPromise = PathConst.ensurePublicDownloadDir();
    }
    return PathConst.publicDownloadDirPromise;
  }

  private static async ensurePublicDownloadDir(): Promise<void> {
    const dirPath = PathConst.downloadPath;
    if (PathConst.probeWritable(dirPath)) {
      Log.info('公共下载目录就绪: ' + dirPath);
      return;
    }
    // 目录缺失：应用直接在公共 Download 下 mkdir 通常被系统拒绝，
    // 改用 DOWNLOAD 模式 save 让系统重建（同时清理预置的占位空文件）
    const created = await PathConst.createPublicDirViaDownloadMode();
    if (created && PathConst.probeWritable(dirPath)) {
      Log.info('公共下载目录已重建: ' + dirPath);
      return;
    }
    Log.error('公共下载目录不可用，下载将失败直至目录恢复: ' + dirPath);
    // 失败不缓存，下次调用重试
    PathConst.publicDownloadDirPromise = null;
  }

  /** DOWNLOAD 模式保存：系统自动在 Download/包名/ 下创建目录并返回持久化授权 URI */
  private static async createPublicDirViaDownloadMode(): Promise<boolean> {
    try {
      const docPicker = new picker.DocumentViewPicker(ContextHolder.get());
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      const uris = await docPicker.save(saveOptions);
      for (const u of uris) {
        // DOWNLOAD 模式会在目录内预置空文件，清理占位文件
        try {
          const p = new fileUri.FileUri(u).path;
          if (fs.accessSync(p)) {
            fs.unlinkSync(p);
          }
        } catch (e) {
          // 占位文件清理失败不影响目录可用性
        }
      }
      return uris.length > 0;
    } catch (e) {
      const detail = e instanceof Error ? e.message : '';
      Log.error('DOWNLOAD 模式重建公共下载目录失败: ' + detail);
      return false;
    }
  }

  /** 探测目录可写性：尝试访问/创建包名子目录，失败时记录具体原因 */
  private static probeWritable(root: string): boolean {
    try {
      if (!fs.accessSync(root)) {
        fs.mkdirSync(root, true);
      }
      return true;
    } catch (e) {
      const detail = e instanceof Error ? e.message : '';
      Log.error('公共下载目录探测失败: ' + root + ' 原因: ' + detail);
      return false;
    }
  }
}
