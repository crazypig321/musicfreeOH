import hilog from '@ohos.hilog';
import fs from '@ohos.file.fs';
import { PathConst } from '../common/PathConst';

/**
 * 日志（hilog + 可选文件日志）
 */
export class Log {
  private static readonly DOMAIN = 0x0001;
  private static readonly TAG = 'MusicFree';

  static info(msg: string, ...args: Array<Object>): void {
    hilog.info(Log.DOMAIN, Log.TAG, '%{public}s', Log.join(msg, args));
  }

  static warn(msg: string, ...args: Array<Object>): void {
    hilog.warn(Log.DOMAIN, Log.TAG, '%{public}s', Log.join(msg, args));
  }

  static error(msg: string, ...args: Array<Object>): void {
    hilog.error(Log.DOMAIN, Log.TAG, '%{public}s', Log.join(msg, args));
    Log.writeFile('error', Log.join(msg, args));
  }

  static debug(msg: string, ...args: Array<Object>): void {
    hilog.debug(Log.DOMAIN, Log.TAG, '%{public}s', Log.join(msg, args));
  }

  private static join(msg: string, args: Array<Object>): string {
    let result = msg;
    for (const a of args) {
      try {
        result += ' ' + JSON.stringify(a);
      } catch (e) {
        result += ' [unserializable]';
      }
    }
    return result;
  }

  /** 追加写入错误日志文件 */
  private static writeFile(level: string, content: string): void {
    try {
      const dir = PathConst.logPath;
      if (dir.length === 0 || !fs.accessSync(dir)) {
        return;
      }
      const now = new Date();
      const fileName = 'error-log-' + now.getDate() + '-' + (now.getMonth() + 1) + '-' + now.getFullYear() + '.log';
      const path = dir + fileName;
      const line = '[' + now.toISOString() + '][' + level + '] ' + content + '\n';
      const file = fs.openSync(path, fs.OpenMode.APPEND | fs.OpenMode.CREATE);
      fs.writeSync(file.fd, line);
      fs.closeSync(file);
    } catch (e) {
      // 文件日志失败不影响主流程
    }
  }
}

/** 错误日志（对应 errorLog） */
export function errorLog(desc: string, message?: Object): void {
  Log.error(desc, message === undefined ? '' : message);
}

export function traceLog(desc: string, message?: Object): void {
  Log.debug(desc, message === undefined ? '' : message);
}

export function devLog(method: string, content: string): void {
  Log.debug('[plugin:' + method + '] ' + content);
}
