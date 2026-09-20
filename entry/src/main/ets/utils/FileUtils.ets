import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { Log } from './Log';

/**
 * 文件工具（替代 react-native-fs）
 * 路径约定与 MusicFree pathConst 保持一致
 */
export class FileUtils {
  /** 剥离 file:// 前缀（RNFS 语义兼容） */
  /** 剥离 file:// 前缀（RN 侧 $localPath 带协议头存储） */
  static normalizePath(path: string): string {
    if (path.startsWith('file://')) {
      return path.substring('file://'.length);
    }
    return path;
  }

  /** 检查并创建目录（递归） */
  static checkAndCreateDir(dirPath: string): void {
    try {
      const dir = FileUtils.normalizePath(dirPath);
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (e) {
      Log.error('无法初始化目录: ' + dirPath);
    }
  }

  static exists(path: string): boolean {
    try {
      return fs.accessSync(FileUtils.normalizePath(path));
    } catch (e) {
      return false;
    }
  }

  static readFileText(path: string): string | null {
    try {
      const p = FileUtils.normalizePath(path);
      if (!fs.accessSync(p)) {
        return null;
      }
      const stat = fs.statSync(p);
      const file = fs.openSync(p, fs.OpenMode.READ_ONLY);
      try {
        const buf = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buf);
        const u8 = new Uint8Array(buf);
        return FileUtils.u8ToText(u8);
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      return null;
    }
  }

  static writeFileText(path: string, content: string): boolean {
    try {
      const dir = FileUtils.getDirectory(path);
      FileUtils.checkAndCreateDir(dir);
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        const encoder = new util.TextEncoder();
        const u8 = encoder.encodeInto(content);
        fs.writeSync(file.fd, u8.buffer);
      } finally {
        fs.closeSync(file);
      }
      return true;
    } catch (e) {
      Log.error('写文件失败: ' + path);
      return false;
    }
  }

  static appendFileText(path: string, content: string): boolean {
    try {
      const dir = FileUtils.getDirectory(path);
      FileUtils.checkAndCreateDir(dir);
      const file = fs.openSync(path, fs.OpenMode.APPEND | fs.OpenMode.CREATE);
      try {
        const encoder = new util.TextEncoder();
        const u8 = encoder.encodeInto(content);
        fs.writeSync(file.fd, u8.buffer);
      } finally {
        fs.closeSync(file);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  static writeFileBytes(path: string, data: Uint8Array): boolean {
    try {
      const dir = FileUtils.getDirectory(path);
      FileUtils.checkAndCreateDir(dir);
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        // 视图非整块缓冲时先拷贝，避免 writeSync 写入底层缓冲之外的残留字节
        let bytes = data;
        if (data.byteOffset !== 0 || data.byteLength !== data.buffer.byteLength) {
          const copy = new Uint8Array(data.byteLength);
          copy.set(data);
          bytes = copy;
        }
        fs.writeSync(file.fd, bytes.buffer, { length: bytes.byteLength });
      } finally {
        fs.closeSync(file);
      }
      return true;
    } catch (e) {
      Log.error('写文件失败: ' + path);
      return false;
    }
  }

  static copyFile(from: string, to: string): boolean {
    try {
      const dir = FileUtils.getDirectory(to);
      FileUtils.checkAndCreateDir(dir);
      if (FileUtils.exists(to)) {
        fs.unlinkSync(FileUtils.normalizePath(to));
      }
      fs.copyFileSync(FileUtils.normalizePath(from), FileUtils.normalizePath(to));
      return true;
    } catch (e) {
      Log.error('复制文件失败: ' + from + ' -> ' + to);
      return false;
    }
  }

  static moveFile(from: string, to: string): boolean {
    try {
      const dir = FileUtils.getDirectory(to);
      FileUtils.checkAndCreateDir(dir);
      if (FileUtils.exists(to)) {
        fs.unlinkSync(to);
      }
      fs.moveFileSync(from, to);
      return true;
    } catch (e) {
      Log.error('移动文件失败: ' + from + ' -> ' + to);
      return false;
    }
  }

  /** 重命名目录（moveFileSync 不支持目录，需用 moveDirSync；目标路径必须不存在） */
  static renameDir(from: string, to: string): boolean {
    try {
      fs.moveDirSync(FileUtils.normalizePath(from), FileUtils.normalizePath(to));
      return true;
    } catch (e) {
      Log.error('重命名目录失败: ' + from + ' -> ' + to);
      return false;
    }
  }

  static unlink(path: string): boolean {
    try {
      const p = FileUtils.normalizePath(path);
      if (fs.accessSync(p)) {
        fs.unlinkSync(p);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 删除空目录（目录非空或不存在返回 false；不删除目录内的任何文件） */
  static removeDirIfEmpty(path: string): boolean {
    try {
      fs.rmdirSync(FileUtils.normalizePath(path));
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 列出目录下文件/文件夹名（不含路径前缀） */
  static listDir(dirPath: string): Array<string> {
    const result: Array<string> = [];
    try {
      const names = fs.listFileSync(dirPath);
      for (const n of names) {
        result.push(n);
      }
    } catch (e) {
      // 目录不存在
    }
    return result;
  }

  static isDirectory(path: string): boolean {
    try {
      const stat = fs.statSync(FileUtils.normalizePath(path));
      return stat.isDirectory();
    } catch (e) {
      return false;
    }
  }

  static isFile(path: string): boolean {
    try {
      const stat = fs.statSync(FileUtils.normalizePath(path));
      return stat.isFile();
    } catch (e) {
      return false;
    }
  }

  static fileSize(path: string): number {
    try {
      const stat = fs.statSync(FileUtils.normalizePath(path));
      return stat.size;
    } catch (e) {
      return 0;
    }
  }

  /** 递归获取目录大小 */
  static getFolderSize(dirPath: string): number {
    let size = 0;
    try {
      const names = fs.listFileSync(dirPath);
      for (const n of names) {
        const p = dirPath.endsWith('/') ? dirPath + n : dirPath + '/' + n;
        if (FileUtils.isDirectory(p)) {
          size += FileUtils.getFolderSize(p);
        } else {
          size += FileUtils.fileSize(p);
        }
      }
    } catch (e) {
      // ignore
    }
    return size;
  }

  /** 递归删除目录 */
  static removeDir(dirPath: string): void {
    try {
      if (!FileUtils.exists(dirPath)) {
        return;
      }
      const names = fs.listFileSync(dirPath);
      for (const n of names) {
        const p = dirPath.endsWith('/') ? dirPath + n : dirPath + '/' + n;
        if (FileUtils.isDirectory(p)) {
          FileUtils.removeDir(p);
        } else {
          fs.unlinkSync(p);
        }
      }
      fs.rmdirSync(dirPath);
    } catch (e) {
      Log.error('删除目录失败: ' + dirPath);
    }
  }

  static getDirectory(dirPath: string): string {
    const lastSlash = dirPath.lastIndexOf('/');
    if (lastSlash === -1) {
      return dirPath;
    }
    return dirPath.substring(0, lastSlash);
  }

  static getFileName(filePath: string, withoutExt?: boolean): string {
    const lastSlash = filePath.lastIndexOf('/');
    if (lastSlash === -1) {
      return filePath;
    }
    let fileName = filePath.substring(lastSlash + 1);
    if (withoutExt === true) {
      const lastDot = fileName.lastIndexOf('.');
      fileName = lastDot === -1 ? fileName : fileName.substring(0, lastDot);
    }
    try {
      return decodeURIComponent(fileName);
    } catch (e) {
      return fileName;
    }
  }

  static addFileScheme(fileName: string): string {
    if (fileName.startsWith('/')) {
      return 'file://' + fileName;
    }
    return fileName;
  }

  /** 文件名非法字符转义 */
  static escapeCharacter(str?: string): string {
    if (str === undefined || str === null) {
      return '';
    }
    return str.replace(/[/|\\?*"<>:]+/g, '_');
  }

  private static u8ToText(u8: Uint8Array): string {
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(u8);
  }
}
