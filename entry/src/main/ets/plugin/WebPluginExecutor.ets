import web_webview from '@ohos.web.webview';
import { rcp } from '@kit.RemoteCommunicationKit';
import util from '@ohos.util';
import { JsonUtil, JsonRecord } from '../common/JsonUtil';
import { HttpClient } from '../infra/HttpClient';
import { IPluginExecutor, PluginInstanceInfo } from './PluginTypes';
import { PluginMeta } from './PluginMeta';
import { Log } from '../utils/Log';

/**
 * 沙箱宿主桥（通过 javaScriptProxy 注入为 window.mfNative）
 */
export class SandboxNativeBridge {
  onPluginResult(callId: string, ok: boolean, json: string): void {
    WebPluginExecutor.getInstance().handlePluginResult(callId, ok, json);
  }

  /** 沙箱页面加载完成信号 */
  markReady(): void {
    WebPluginExecutor.getInstance().markReady();
  }

  /** 取插件用户变量（JSON 字符串） */
  getUserVariables(pluginName: string): string {
    return WebPluginExecutor.getInstance().getUserVariablesJson(pluginName);
  }

  /** HTTP 桥：沙箱内网络请求转发到原生 */
  httpRequest(callId: string, url: string, method: string, headersJson: string,
    bodyBase64: string, timeoutMs: number): void {
    WebPluginExecutor.getInstance().handleHttp(callId, url, method, headersJson, bodyBase64, timeoutMs);
  }

  /** 沙箱 console */
  log(level: string, message: string): void {
    if (level === 'error') {
      Log.error('[plugin] ' + message);
    } else if (level === 'warn') {
      Log.warn('[plugin] ' + message);
    } else {
      Log.info('[plugin] ' + message);
    }
  }
}

class PendingCall {
  resolve: (value: string) => void = (_value: string): void => {
  };
  reject: (reason: Error) => void = (_reason: Error): void => {
  };
  timer: number = -1;
}

/**
 * WebView 沙箱插件执行器
 * - 沙箱页面：resources/rawfile/plugin_host.html
 * - 宿主协议：__mf.load / __mf.call → mfNative.onPluginResult
 * - HTTP 桥：mfNative.httpRequest → 原生 rcp → __mf.onHttpResult
 */
export class WebPluginExecutor implements IPluginExecutor {
  private static inst: WebPluginExecutor | null = null;

  static getInstance(): WebPluginExecutor {
    if (WebPluginExecutor.inst === null) {
      WebPluginExecutor.inst = new WebPluginExecutor();
    }
    return WebPluginExecutor.inst;
  }

  /** 暴露给 javaScriptProxy 的桥对象 */
  readonly bridge: SandboxNativeBridge = new SandboxNativeBridge();

  private controller: web_webview.WebviewController | null = null;
  private ready: boolean = false;
  private readyResolvers: Array<() => void> = [];
  private mounted: Set<string> = new Set<string>();
  private pending: Map<string, PendingCall> = new Map();
  private callSeq: number = 0;

  private constructor() {
  }

  /** Index 页面在 Web 组件创建后绑定 controller */
  attachController(controller: web_webview.WebviewController): void {
    this.controller = controller;
  }

  markReady(): void {
    if (this.ready) {
      return;
    }
    this.ready = true;
    const resolvers = this.readyResolvers.slice();
    this.readyResolvers = [];
    for (const r of resolvers) {
      r();
    }
  }

  private async waitReady(timeoutMs: number): Promise<void> {
    if (this.ready) {
      return;
    }
    return new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        reject(new Error('插件沙箱未就绪'));
      }, timeoutMs);
      this.readyResolvers.push(() => {
        clearTimeout(timer);
        resolve();
      });
    });
  }

  async mount(pluginKey: string, funcCode: string, appVersion: string): Promise<PluginInstanceInfo> {
    await this.waitReady(30000);
    const funcCodeJson = JSON.stringify(funcCode);
    const envJson = JSON.stringify({ 'appVersion': appVersion, 'os': 'harmony', 'lang': 'zh-CN' });
    const raw = await this.runCall((callId: string): string => {
      return 'window.__mf.load(' + JSON.stringify(pluginKey) + ', ' + funcCodeJson + ', ' + envJson +
        ', ' + JSON.stringify(callId) + ')';
    }, 30000);
    const rec = JsonUtil.parseRecord(raw);
    if (rec === null) {
      throw new Error('插件挂载结果解析失败');
    }
    const infoRec = JsonUtil.recRecord(rec, 'info');
    if (infoRec === null) {
      let message = '';
      const msgRec = JsonUtil.recRecord(rec, 'error');
      if (msgRec !== null) {
        message = JsonUtil.recStr(msgRec, 'message');
      }
      if (message.length === 0) {
        message = '插件无法解析';
      }
      throw new Error(message);
    }
    const info = PluginInstanceInfo.fromRecord(infoRec);
    this.mounted.add(pluginKey);
    return info;
  }

  async callMethod(pluginKey: string, method: string, argsJson: string): Promise<string> {
    if (!this.mounted.has(pluginKey)) {
      throw new Error('插件未挂载: ' + pluginKey);
    }
    return this.runCall((callId: string): string => {
      return 'window.__mf.call(' + JSON.stringify(pluginKey) + ', ' + JSON.stringify(method) + ', ' +
        argsJson + ', ' + JSON.stringify(callId) + ')';
    }, 60000);
  }

  getUserVariablesJson(pluginName: string): string {
    const vars = PluginMeta.getUserVariables(pluginName);
    return JSON.stringify(JsonUtil.fromStringMap(vars));
  }

  handlePluginResult(callId: string, ok: boolean, json: string): void {
    const p = this.pending.get(callId);
    if (p === undefined) {
      return;
    }
    this.pending.delete(callId);
    if (p.timer >= 0) {
      clearTimeout(p.timer);
    }
    if (ok) {
      p.resolve(json);
    } else {
      let message = '';
      const rec = JsonUtil.parseRecord(json);
      if (rec !== null) {
        message = JsonUtil.recStr(rec, 'message');
      }
      if (message.length === 0) {
        message = '插件调用失败';
      }
      p.reject(new Error(message));
    }
  }

  handleHttp(callId: string, url: string, method: string, headersJson: string,
    bodyBase64: string, timeoutMs: number): void {
    this.doHttp(callId, url, method, headersJson, bodyBase64, timeoutMs);
  }

  private async doHttp(callId: string, url: string, method: string, headersJson: string,
    bodyBase64: string, timeoutMs: number): Promise<void> {
    let status = 0;
    let headersJsonOut = '{}';
    let bodyB64 = '';
    try {
      const headers: rcp.RequestHeaders = {};
      const rec = JsonUtil.parseRecord(headersJson);
      if (rec !== null) {
        for (const k of Object.keys(rec)) {
          const v = rec[k];
          if (typeof v === 'string') {
            headers[k] = v;
          }
        }
      }
      let content: rcp.RequestContent | undefined = undefined;
      if (bodyBase64.length > 0) {
        const helper = new util.Base64Helper();
        const decoded = helper.decodeSync(bodyBase64);
        const buf = new ArrayBuffer(decoded.length);
        const view = new Uint8Array(buf);
        for (let i = 0; i < decoded.length; ++i) {
          view[i] = decoded[i];
        }
        content = buf;
      }
      const config: rcp.Configuration = {
        transfer: { timeout: { connectMs: timeoutMs, transferMs: timeoutMs } }
      };
      const req = new rcp.Request(url, method, headers, content, undefined, undefined, config);
      const resp = await HttpClient.getSession().fetch(req);
      status = resp.statusCode;
      headersJsonOut = WebPluginExecutor.normalizeHeaders(resp.headers);
      if (resp.body !== undefined) {
        const helper = new util.Base64Helper();
        bodyB64 = helper.encodeToStringSync(new Uint8Array(resp.body));
      }
    } catch (e) {
      status = 0;
      headersJsonOut = '{}';
      bodyB64 = '';
    }
    this.respondHttp(callId, status, headersJsonOut, bodyB64);
  }

  private respondHttp(callId: string, status: number, headersJson: string, bodyB64: string): void {
    const controller = this.controller;
    if (controller === null) {
      return;
    }
    const script = 'window.__mf.onHttpResult(' + JSON.stringify(callId) + ', ' + status.toString() + ', ' +
      headersJson + ', ' + JSON.stringify(bodyB64) + ')';
    controller.runJavaScript(script).catch(() => {
    });
  }

  /** 响应头归一化：key 小写；set-cookie 归一为数组；其余多值头以 ", " 连接 */
  private static normalizeHeaders(header: rcp.ResponseHeaders): string {
    const out: JsonRecord = {};
    for (const k of Object.keys(header)) {
      const lower = k.toLowerCase();
      const v = header[k];
      if (lower === 'set-cookie') {
        if (Array.isArray(v)) {
          const arr = v as Array<Object>;
          const parts: Array<string> = [];
          for (const it of arr) {
            if (typeof it === 'string') {
              parts.push(it);
            }
          }
          out[lower] = parts;
        } else if (typeof v === 'string') {
          const wrapped: Array<string> = [v];
          out[lower] = wrapped;
        }
      } else if (typeof v === 'string') {
        out[lower] = v;
      } else if (Array.isArray(v)) {
        const arr = v as Array<Object>;
        const parts: Array<string> = [];
        for (const it of arr) {
          if (typeof it === 'string') {
            parts.push(it);
          }
        }
        if (parts.length > 0) {
          out[lower] = parts.join(', ');
        }
      }
    }
    return JsonUtil.safeStringify(out);
  }

  private async runCall(scriptFactory: (callId: string) => string, timeoutMs: number): Promise<string> {
    const controller = this.controller;
    if (controller === null) {
      throw new Error('插件沙箱未初始化');
    }
    this.callSeq += 1;
    const callId = 'c' + Date.now().toString() + '-' + this.callSeq.toString();
    const pendingCall = new PendingCall();
    const promise = new Promise<string>((resolve, reject) => {
      pendingCall.resolve = resolve;
      pendingCall.reject = reject;
    });
    this.pending.set(callId, pendingCall);
    const timer = setTimeout(() => {
      const p = this.pending.get(callId);
      if (p !== undefined) {
        this.pending.delete(callId);
        p.reject(new Error('插件调用超时'));
      }
    }, timeoutMs);
    pendingCall.timer = timer;
    try {
      await controller.runJavaScript(scriptFactory(callId));
    } catch (e) {
      clearTimeout(timer);
      this.pending.delete(callId);
      throw new Error('插件沙箱脚本执行失败');
    }
    return promise;
  }
}
