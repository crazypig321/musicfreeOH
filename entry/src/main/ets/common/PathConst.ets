import { ContextHolder } from './ContextHolder';
import { picker, fileUri, fileIo as fs } from '@kit.CoreFileKit';
import { Log } from '../utils/Log';

/**
 * 路径常量（移植自 MusicFree src/constants/pathConst.ts）
 * 应用数据目录基于 context.filesDir
 * 下载目录按用户要求映射到公共 Download/MusicFreeOH（RN 原版为应用沙箱，此处为有意偏差）
 * 公共目录通过 DOWNLOAD 模式选择器解析（免弹窗免权限），失败回落沙箱
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
    // 默认沙箱回落；启动后由 bootstrapPublicDownloadDir 异步解析公共目录刷新
    PathConst.downloadPath = PathConst.basePath + '/download/';
    PathConst.downloadMusicPath = PathConst.downloadPath;
  }

  /**
   * 通过 DOWNLOAD 模式选择器解析公共下载目录（免弹窗免权限），
   * 成功后将下载目录刷新为 <公共Download>/MusicFreeOH；失败保持沙箱回落。
   * 每个进程生命周期内只尝试一次，可安全重复调用。
   */
  static async bootstrapPublicDownloadDir(): Promise<void> {
    if (PathConst.publicDownloadDirResolved) {
      return;
    }
    PathConst.publicDownloadDirResolved = true;
    try {
      const ctx = ContextHolder.get();
      const documentPicker = new picker.DocumentViewPicker(ctx);
      const options = new picker.DocumentSaveOptions();
      options.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      const result = await documentPicker.save(options);
      if (result.length === 0) {
        Log.error('DOWNLOAD模式未返回公共下载目录，保持沙箱目录');
        return;
      }
      const dirPath = new fileUri.FileUri(result[0]).path;
      if (PathConst.probeWritable(dirPath)) {
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
