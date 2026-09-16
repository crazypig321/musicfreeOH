import { fileIo as fs } from '@kit.CoreFileKit';
import { PathConst } from '../common/PathConst';
import { FileUtils } from '../utils/FileUtils';
import { appConfig } from '../core/AppConfig';
import { pluginManager } from './PluginManager';

/** 本地批量导入结果 */
export class LocalImportSummary {
  success: number = 0;
  failed: number = 0;
  lastMessage: string = '';
}

/**
 * 本地插件文件导入工具（插件页与订阅源页共用）
 */
export class PluginImport {
  /** 批量安装本地 .js 插件文件：逐个复制到缓存后安装，返回汇总结果 */
  static async installLocalJsFiles(uris: Array<string>): Promise<LocalImportSummary> {
    const summary = new LocalImportSummary();
    for (const uri of uris) {
      const destPath = PathConst.cachePath + 'plugin_import_' + Date.now().toString() + '.js';
      try {
        const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        const dst = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        fs.copyFileSync(src.fd, dst.fd);
        fs.closeSync(src);
        fs.closeSync(dst);
      } catch (error) {
        summary.failed++;
        continue;
      }
      try {
        const r = await pluginManager.installPluginFromLocalFile(destPath, appConfig.getNotCheckPluginVersion());
        if (r.success) {
          summary.success++;
        } else {
          summary.failed++;
          summary.lastMessage = r.message;
        }
      } catch (e) {
        summary.failed++;
      }
    }
    return summary;
  }

  /** 读取选择器 URI 文件文本（经缓存中转，读取后删除缓存）；失败返回 null */
  static readUriText(uri: string, ext: string): string | null {
    const destPath = PathConst.cachePath + 'uri_read_' + Date.now().toString() + '.' + ext;
    try {
      const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const dst = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.copyFileSync(src.fd, dst.fd);
      fs.closeSync(src);
      fs.closeSync(dst);
    } catch (error) {
      return null;
    }
    const text = FileUtils.readFileText(destPath);
    FileUtils.unlink(destPath);
    return text;
  }
}
