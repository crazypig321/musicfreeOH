import { KVStore } from '../infra/KVStore';
import { JsonUtil, JsonRecord } from '../common/JsonUtil';
import { HttpClient } from '../infra/HttpClient';
import { appConfig } from '../core/AppConfig';
import { pluginManager } from './PluginManager';
import { InstallPluginResult } from './PluginTypes';
import { FileUtils } from '../utils/FileUtils';
import { PathConst } from '../common/PathConst';

/** 订阅源存储（storage KV，随备份清单自动备份） */
const SOURCE_STORE = 'storage';
const SOURCE_KEY = 'subscriptionSources';
/** 订阅源自定义名称存储（url -> 名称） */
const SOURCE_NAME_KEY = 'subscriptionSourceNames';

/** 订阅安装计数 */
export class InstallCount {
  success: number = 0;
  failed: number = 0;
}

/**
 * 订阅源管理（订阅源 = 聚合插件地址：.json 为插件列表，.js 为单个插件）
 * 供订阅源页面与插件页「同步订阅源」共用
 */
export class Subscriptions {
  /** 获取全部订阅源 */
  static getSources(): Array<string> {
    const raw = KVStore.getOrCreate(SOURCE_STORE).get(SOURCE_KEY);
    const parsed = JsonUtil.parseStringArray(raw);
    return parsed !== null ? parsed : [];
  }

  /** 校验订阅源地址：必须以 .js 或 .json 结尾 */
  static isValidSourceUrl(url: string): boolean {
    return url.endsWith('.js') || url.endsWith('.json');
  }

  /** 添加订阅源（新源置顶、去重），返回是否新增 */
  static addSource(url: string): boolean {
    const sources = Subscriptions.getSources();
    for (const s of sources) {
      if (s === url) {
        return false;
      }
    }
    const next = [url].concat(sources);
    KVStore.getOrCreate(SOURCE_STORE).set(SOURCE_KEY, JSON.stringify(next));
    return true;
  }

  /** 获取订阅源自定义名称（未设置返回空串） */
  static getSourceName(url: string): string {
    const rec = JsonUtil.parseRecord(KVStore.getOrCreate(SOURCE_STORE).get(SOURCE_NAME_KEY));
    return rec !== null ? JsonUtil.recStr(rec, url) : '';
  }

  /** 设置/清除订阅源自定义名称（空串清除） */
  static setSourceName(url: string, name: string): void {
    const store = KVStore.getOrCreate(SOURCE_STORE);
    const parsed = JsonUtil.parseRecord(store.get(SOURCE_NAME_KEY));
    const next: JsonRecord = {};
    if (parsed !== null) {
      for (const k of Object.keys(parsed)) {
        if (k !== url) {
          next[k] = parsed[k];
        }
      }
    }
    const trimmed = name.trim();
    if (trimmed.length > 0) {
      next[url] = trimmed;
    }
    store.set(SOURCE_NAME_KEY, JSON.stringify(next));
  }

  /** 更换订阅源地址（保留原位置并迁移自定义名称），新地址已存在时返回 false */
  static changeSourceUrl(oldUrl: string, newUrl: string): boolean {
    if (oldUrl === newUrl) {
      return true;
    }
    const sources = Subscriptions.getSources();
    for (const s of sources) {
      if (s === newUrl) {
        return false;
      }
    }
    const next: Array<string> = [];
    for (const s of sources) {
      next.push(s === oldUrl ? newUrl : s);
    }
    KVStore.getOrCreate(SOURCE_STORE).set(SOURCE_KEY, JSON.stringify(next));
    // 迁移自定义名称
    const name = Subscriptions.getSourceName(oldUrl);
    if (name.length > 0) {
      Subscriptions.setSourceName(oldUrl, '');
      Subscriptions.setSourceName(newUrl, name);
    }
    return true;
  }

  /** 删除订阅源（同时清理自定义名称） */
  static removeSource(url: string): void {
    const sources = Subscriptions.getSources();
    const next: Array<string> = [];
    for (const s of sources) {
      if (s !== url) {
        next.push(s);
      }
    }
    KVStore.getOrCreate(SOURCE_STORE).set(SOURCE_KEY, JSON.stringify(next));
    if (Subscriptions.getSourceName(url).length > 0) {
      Subscriptions.setSourceName(url, '');
    }
  }

  /** 备份导出：订阅源列表 + 自定义名称 + 本地导入源的沙箱文件内容 */
  static exportData(): JsonRecord {
    const rec: JsonRecord = {};
    const sources = Subscriptions.getSources();
    rec['sources'] = sources;
    const names = JsonUtil.parseRecord(KVStore.getOrCreate(SOURCE_STORE).get(SOURCE_NAME_KEY));
    if (names !== null) {
      rec['names'] = names;
    }
    // 本地导入的订阅源（file:// 沙箱路径）：嵌入文件内容，换设备恢复时重建
    const localFiles: Record<string, string> = {};
    for (const url of sources) {
      if (!url.startsWith('file://')) {
        continue;
      }
      const path = url.substring('file://'.length);
      const text = FileUtils.readFileText(path);
      if (text !== null && text.length > 0) {
        localFiles[FileUtils.getFileName(path)] = text;
      }
    }
    if (Object.keys(localFiles).length > 0) {
      rec['localFiles'] = localFiles;
    }
    return rec;
  }

  /** 从备份恢复：订阅源合并去重（保留本地顺序，新源追加），自定义名称覆盖写入，
   * 本地导入源的沙箱文件缺失时按备份内容重建 */
  static importData(rec: JsonRecord): void {
    const sources = JsonUtil.parseStringArray(JsonUtil.safeStringify(rec['sources']));
    if (sources !== null && sources.length > 0) {
      const existing = Subscriptions.getSources();
      const seen: Set<string> = new Set<string>(existing);
      const next: Array<string> = existing.slice();
      for (const url of sources) {
        if (!seen.has(url)) {
          seen.add(url);
          next.push(url);
        }
      }
      if (next.length !== existing.length) {
        KVStore.getOrCreate(SOURCE_STORE).set(SOURCE_KEY, JSON.stringify(next));
      }
    }
    const names = JsonUtil.objToRecord(rec['names']);
    if (names !== null) {
      for (const k of Object.keys(names)) {
        const n = JsonUtil.recStr(names, k);
        if (n.length > 0) {
          Subscriptions.setSourceName(k, n);
        }
      }
    }
    const localFiles = JsonUtil.objToRecord(rec['localFiles']);
    if (localFiles !== null) {
      FileUtils.checkAndCreateDir(PathConst.dataPath + 'subscriptions');
      for (const name of Object.keys(localFiles)) {
        const destPath = PathConst.dataPath + 'subscriptions/' + name;
        if (!FileUtils.exists(destPath)) {
          FileUtils.writeFileText(destPath, JsonUtil.recStr(localFiles, name));
        }
      }
    }
  }

  /** 解析订阅源为插件 URL 列表：.json 为插件列表，.js 为单插件；失败返回 null
   * file:// 前缀为本地导入的订阅源文件（沙箱路径），直接读文件内容 */
  static async resolveUrls(url: string): Promise<Array<string> | null> {
    let body: string | null = null;
    if (url.startsWith('file://')) {
      if (!url.endsWith('.json')) {
        return [url];
      }
      body = FileUtils.readFileText(url.substring('file://'.length));
      if (body === null) {
        return null;
      }
    } else if (url.endsWith('.json')) {
      const resp = await HttpClient.get(url, {
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
        'Expires': '0',
      });
      if (resp === null) {
        return null;
      }
      body = resp.body;
    } else {
      return [url];
    }
    const rec = JsonUtil.parseRecord(body);
    const plugins = rec !== null ? JsonUtil.recArray(rec, 'plugins') : null;
    if (plugins === null) {
      return null;
    }
    const urls: Array<string> = [];
    for (const item of plugins) {
      const itemRec = JsonUtil.objToRecord(item);
      const u = itemRec !== null ? JsonUtil.recStr(itemRec, 'url') : '';
      if (u.length > 0) {
        urls.push(u);
      }
    }
    return urls.length > 0 ? urls : null;
  }

  /** 安装一组插件 URL，返回成功/失败计数 */
  static async installUrls(urls: Array<string>): Promise<InstallCount> {
    const count = new InstallCount();
    for (const u of urls) {
      try {
        const r: InstallPluginResult =
          await pluginManager.installPluginFromUrl(u, appConfig.getNotCheckPluginVersion());
        if (r.success) {
          count.success++;
        } else {
          count.failed++;
        }
      } catch (e) {
        count.failed++;
      }
    }
    return count;
  }

  /** 同步单个订阅源（安装/更新其中的插件），返回状态文本 */
  static async syncSource(url: string): Promise<string> {
    const urls = await Subscriptions.resolveUrls(url);
    if (urls === null) {
      return '订阅源获取失败或格式不正确';
    }
    const count = await Subscriptions.installUrls(urls);
    return '更新完成：' + count.success.toString() + ' 个插件成功' +
      (count.failed > 0 ? '，' + count.failed.toString() + ' 个失败' : '');
  }

  /** 同步全部订阅源，返回状态文本；onProgress 回调当前进度（done 从 0 开始） */
  static async syncAll(onProgress?: (done: number, total: number) => void): Promise<string> {
    const sources = Subscriptions.getSources();
    if (sources.length === 0) {
      return '暂无订阅源';
    }
    const total = new InstallCount();
    for (let i = 0; i < sources.length; ++i) {
      if (onProgress !== undefined) {
        onProgress(i, sources.length);
      }
      const urls = await Subscriptions.resolveUrls(sources[i]);
      if (urls !== null) {
        const count = await Subscriptions.installUrls(urls);
        total.success += count.success;
        total.failed += count.failed;
      } else {
        total.failed++;
      }
    }
    if (onProgress !== undefined) {
      onProgress(sources.length, sources.length);
    }
    return '订阅同步完成：' + total.success.toString() + ' 个插件成功' +
      (total.failed > 0 ? '，' + total.failed.toString() + ' 个失败' : '');
  }
}
