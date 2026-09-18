import { rcp } from '@kit.RemoteCommunicationKit';
import fs from '@ohos.file.fs';
import util from '@ohos.util';

/**
 * HTTP 客户端（应用侧最小封装，基于 rcp）
 * @ohos.net.http 的 RequestMethod 无 PATCH，故整体替换为 rcp
 * 插件内部的网络请求由 WebView 中的 axios 完成，不走这里
 */
export class HttpResult {
  statusCode: number = 0;
  headers: Record<string, string> = {};
  body: string = '';
}

export class HttpClient {
  /** 全局共享会话（rcp 会话数量有限制，禁止按请求新建） */
  private static session: rcp.Session | null = null;

  static getSession(): rcp.Session {
    if (HttpClient.session === null) {
      HttpClient.session = rcp.createSession();
    }
    return HttpClient.session;
  }

  /** GET 文本 */
  static async get(url: string, headers?: Record<string, string>, timeoutMs: number = 8000): Promise<HttpResult | null> {
    return HttpClient.request(url, 'GET', headers, timeoutMs);
  }

  /** 任意 method（含 PATCH），method 原样透传给 rcp */
  static async request(url: string, method: string, headers?: Record<string, string>,
    timeoutMs: number = 8000): Promise<HttpResult | null> {
    try {
      const reqHeaders: rcp.RequestHeaders = {};
      if (headers !== undefined) {
        for (const k of Object.keys(headers)) {
          reqHeaders[k] = headers[k];
        }
      }
      const config: rcp.Configuration = {
        transfer: { timeout: { connectMs: timeoutMs, transferMs: timeoutMs } }
      };
      const req = new rcp.Request(url, method, reqHeaders, undefined, undefined, undefined, config);
      const resp = await HttpClient.getSession().fetch(req);
      const result = new HttpResult();
      result.statusCode = resp.statusCode;
      result.body = HttpClient.decodeBody(resp.body);
      result.headers = HttpClient.flattenHeaders(resp.headers);
      return result;
    } catch (e) {
      return null;
    }
  }

  /** 下载二进制到内存（小文件：插件源码/封面） */
  static async downloadBuffer(url: string, headers?: Record<string, string>,
    timeoutMs: number = 15000): Promise<Uint8Array | null> {
    try {
      const reqHeaders: rcp.RequestHeaders = {};
      if (headers !== undefined) {
        for (const k of Object.keys(headers)) {
          reqHeaders[k] = headers[k];
        }
      }
      const config: rcp.Configuration = {
        transfer: { timeout: { connectMs: timeoutMs, transferMs: timeoutMs } }
      };
      const req = new rcp.Request(url, 'GET', reqHeaders, undefined, undefined, undefined, config);
      const resp = await HttpClient.getSession().fetch(req);
      if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body !== undefined) {
        return new Uint8Array(resp.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /** 任意 method + 请求体（WebDAV PUT 等） */
  static async requestWithBody(url: string, method: string, headers: Record<string, string> | undefined,
    body: string, timeoutMs: number = 15000): Promise<HttpResult | null> {
    try {
      const reqHeaders: rcp.RequestHeaders = {};
      if (headers !== undefined) {
        for (const k of Object.keys(headers)) {
          reqHeaders[k] = headers[k];
        }
      }
      const config: rcp.Configuration = {
        transfer: { timeout: { connectMs: timeoutMs, transferMs: timeoutMs } }
      };
      const req = new rcp.Request(url, method, reqHeaders, body, undefined, undefined, config);
      const resp = await HttpClient.getSession().fetch(req);
      const result = new HttpResult();
      result.statusCode = resp.statusCode;
      result.body = HttpClient.decodeBody(resp.body);
      return result;
    } catch (e) {
      return null;
    }
  }

  /** 下载文本 */
  static async downloadText(url: string, headers?: Record<string, string>): Promise<string | null> {
    const buf = await HttpClient.downloadBuffer(url, headers);
    if (buf === null) {
      return null;
    }
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(buf);
  }

  /**
   * 流式下载到文件（大文件：音乐下载）
   * @param onProgress (已下载字节数, 总字节数)；总字节数在响应头到达前为 0
   */
  static async downloadToFile(url: string, toPath: string, headers?: Record<string, string>,
    onProgress?: (downloadedSize: number, totalSize: number) => void): Promise<boolean> {
    let file: fs.File | null = null;
    let downloaded = 0;
    let total = 0;
    let failed = false;
    try {
      const target = toPath.startsWith('file://') ? toPath.substring('file://'.length) : toPath;
      const dir = target.lastIndexOf('/') === -1 ? target : target.substring(0, target.lastIndexOf('/'));
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      file = fs.openSync(target, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      const reqHeaders: rcp.RequestHeaders = {};
      if (headers !== undefined) {
        for (const k of Object.keys(headers)) {
          reqHeaders[k] = headers[k];
        }
      }
      const events: rcp.HttpEventsHandler = {
        onDataReceive: (data: ArrayBuffer): void => {
          downloaded += data.byteLength;
          if (file !== null) {
            fs.writeSync(file.fd, data);
          }
          if (onProgress !== undefined) {
            onProgress(downloaded, total);
          }
        },
        onDownloadProgress: (totalSize: number, transferredSize: number): void => {
          total = totalSize;
          if (onProgress !== undefined) {
            onProgress(transferredSize, totalSize);
          }
        }
      };
      const config: rcp.Configuration = { tracing: { httpEventsHandler: events } };
      const req = new rcp.Request(url, 'GET', reqHeaders, undefined, undefined, undefined, config);
      const resp = await HttpClient.getSession().fetch(req);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        failed = true;
      }
    } catch (e) {
      failed = true;
    } finally {
      if (file !== null) {
        fs.closeSync(file);
      }
    }
    if (failed) {
      try {
        fs.unlinkSync(toPath.startsWith('file://') ? toPath.substring('file://'.length) : toPath);
      } catch (e) {
        // 清理失败忽略
      }
      return false;
    }
    return true;
  }

  private static decodeBody(body: ArrayBuffer | undefined): string {
    if (body === undefined) {
      return '';
    }
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(new Uint8Array(body));
  }

  /** ResponseHeaders 值可能为 string | string[] | undefined，统一拍平为 Record<string, string> */
  private static flattenHeaders(header: rcp.ResponseHeaders): Record<string, string> {
    const out: Record<string, string> = {};
    for (const k of Object.keys(header)) {
      const v = header[k];
      if (typeof v === 'string') {
        out[k] = v;
      } else if (Array.isArray(v)) {
        const arr = v as Array<Object>;
        const parts: Array<string> = [];
        for (const it of arr) {
          if (typeof it === 'string') {
            parts.push(it);
          }
        }
        if (parts.length > 0) {
          out[k] = parts.join(', ');
        }
      }
    }
    return out;
  }
}
