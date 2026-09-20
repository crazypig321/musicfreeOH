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
   * @param resumeFrom 断点续传：磁盘上半成品的字节数，>0 时发送 Range 请求并从末尾追加写入；
   *   服务器不支持续传（返回非 206）或资源总大小与 expectedTotal 不符时自动清空从头下载
   * @param expectedTotal 上次已知的资源总字节数（校验续传内容一致性，<=0 不校验）
   */
  static async downloadToFile(url: string, toPath: string, headers?: Record<string, string>,
    onProgress?: (downloadedSize: number, totalSize: number) => void,
    resumeFrom?: number, expectedTotal?: number): Promise<boolean> {
    const target = toPath.startsWith('file://') ? toPath.substring('file://'.length) : toPath;
    const dir = target.lastIndexOf('/') === -1 ? target : target.substring(0, target.lastIndexOf('/'));
    let file: fs.File | null = null;
    // 续传基线：以磁盘上实际半成品大小为准（与 resumeFrom 取小，防止文件被外部改动）
    let base = 0;
    if (resumeFrom !== undefined && resumeFrom > 0) {
      try {
        if (fs.accessSync(target)) {
          base = Math.min(resumeFrom, fs.statSync(target).size);
        }
      } catch (e) {
        base = 0;
      }
    }
    let written = base;
    let total = 0;
    let failed = false;
    // 续传时需等状态码确认（206）后才能写盘；此前到达的数据先缓冲
    let headerChecked = base === 0;
    const pendingChunks: Array<ArrayBuffer> = [];
    const writeChunk = (data: ArrayBuffer): void => {
      if (file !== null) {
        fs.writeSync(file.fd, data, { offset: written });
      }
      written += data.byteLength;
      if (onProgress !== undefined) {
        onProgress(written, total);
      }
    };
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      file = base > 0 ? fs.openSync(target, fs.OpenMode.READ_WRITE) :
        fs.openSync(target, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      const reqHeaders: rcp.RequestHeaders = {};
      if (headers !== undefined) {
        for (const k of Object.keys(headers)) {
          reqHeaders[k] = headers[k];
        }
      }
      if (base > 0) {
        reqHeaders['Range'] = `bytes=${base}-`;
      }
      const events: rcp.HttpEventsHandler = {
        onStatusCodeReceive: (code: number): void => {
          if (base > 0 && code !== 206) {
            // 服务器忽略 Range：清空半成品从头下载
            base = 0;
            written = 0;
            try {
              fs.truncateSync(target, 0);
            } catch (e) {
            }
          }
          headerChecked = true;
          for (const chunk of pendingChunks) {
            writeChunk(chunk);
          }
          pendingChunks.length = 0;
        },
        onHeaderReceive: (respHeaders: rcp.ResponseHeaders): void => {
          if (base <= 0) {
            return;
          }
          // 206：从 Content-Range 解析资源总大小，与上次已知大小不符视为资源已变化，作废续传
          const contentRange = respHeaders['content-range'];
          const rangeText = typeof contentRange === 'string' ? contentRange : '';
          const slashIdx = rangeText.lastIndexOf('/');
          if (slashIdx !== -1) {
            const parsed = Number(rangeText.substring(slashIdx + 1).trim());
            if (Number.isFinite(parsed) && parsed > 0) {
              if (expectedTotal !== undefined && expectedTotal > 0 && parsed !== expectedTotal) {
                base = 0;
                written = 0;
                try {
                  fs.truncateSync(target, 0);
                } catch (e) {
                }
              } else {
                total = parsed;
                if (onProgress !== undefined) {
                  onProgress(written, total);
                }
              }
            }
          }
        },
        onDataReceive: (data: ArrayBuffer): void => {
          if (!headerChecked) {
            pendingChunks.push(data);
            return;
          }
          writeChunk(data);
        },
        onDataEnd: (): void => {
          // 始终未收到状态码的异常响应：半成品原样保留，视为失败
          if (!headerChecked) {
            failed = true;
          }
        },
        onDownloadProgress: (totalSize: number, _transferredSize: number): void => {
          if (total === 0 && totalSize > 0) {
            // 未取到 Content-Range 时按本次响应推算总大小（续传时需叠加基线）
            total = base + totalSize;
            if (onProgress !== undefined) {
              onProgress(written, total);
            }
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
        // 从头下载失败清理残留；续传失败保留半成品待下次重试
        if (base === 0) {
          fs.unlinkSync(target);
        }
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
