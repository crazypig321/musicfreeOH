import util from '@ohos.util';
import deviceInfo from '@ohos.deviceInfo';
import { HttpClient } from '../infra/HttpClient';
import { appConfig } from './AppConfig';
import { Backup } from './Backup';

/** WebDAV 恢复结果 */
export class WebDavRestoreResult {
  /** 请求成功且拿到备份内容 */
  ok: boolean = false;
  /** 远端不存在备份文件 */
  notFound: boolean = false;
  /** 备份 JSON 文本 */
  data: string = '';
}

/** WebDAV 远端备份条目 */
export class WebDavBackupEntry {
  /** 备份文件名 */
  fileName: string = '';
  /** 文件大小（字节，未知为 -1） */
  size: number = -1;
}

/**
 * WebDAV 备份与恢复
 * 服务器地址（如 https://dav.example.com/dav/）+ 备份路径（可选）+ 自动追加的 musicfreeOH 目录，
 * 每次备份生成独立文件 musicfree-backup_yyyyMMdd_HHmmss_设备名.json（互不覆盖，恢复时选择）；
 * 认证方式为 Basic Auth（用户名/密码可留空）
 * 恢复走 Backup.resume：musicfreeOH 备份与原版 MusicFree 备份均可（原版自动转换）
 */
export class WebDav {
  static readonly BACKUP_PREFIX: string = 'musicfree-backup_';
  /** 旧版固定备份文件名（列表与恢复仍兼容） */
  static readonly LEGACY_BACKUP_FILENAME: string = 'musicfree-backup.json';
  static readonly BACKUP_DIRNAME: string = 'musicfreeOH';
  /** 退出备份进行中标记（防重复触发） */
  private static exitBackupRunning: boolean = false;

  /** 是否已配置服务器地址 */
  static isConfigured(): boolean {
    return appConfig.getWebdavUrl().trim().length > 0;
  }

  /** 备份文件名中的设备名：外部产品系列名（marketName），空时回退产品型号；剔除文件名非法字符 */
  private static deviceName(): string {
    let name = deviceInfo.marketName.trim();
    if (name.length === 0) {
      name = deviceInfo.productModel.trim();
    }
    return name.replace(/[\\/:*?"<>|\s]+/g, '_');
  }

  /** 生成备份文件名：musicfree-backup_yyyyMMdd_HHmmss_设备名.json */
  static backupFileName(): string {
    const d = new Date();
    const p = (n: number): string => n < 10 ? '0' + n.toString() : n.toString();
    const stamp = d.getFullYear().toString() + p(d.getMonth() + 1) + p(d.getDate()) + '_' +
      p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds());
    return WebDav.BACKUP_PREFIX + stamp + '_' + WebDav.deviceName() + '.json';
  }

  /** 备份文件条目显示文本：时间戳+设备名文件转为「yyyy-MM-dd HH:mm:ss · 设备名」，其余（旧版固定名等）原样展示 */
  static displayTitle(fileName: string): string {
    if (!fileName.startsWith(WebDav.BACKUP_PREFIX) || !fileName.endsWith('.json')) {
      return fileName;
    }
    const stem = fileName.substring(WebDav.BACKUP_PREFIX.length, fileName.length - '.json'.length);
    // stem 结构：yyyyMMdd_HHmmss_设备名
    if (stem.length <= 16 || stem.charAt(8) !== '_' || stem.charAt(15) !== '_') {
      return fileName;
    }
    const dateStr = stem.substring(0, 8);
    const timeStr = stem.substring(9, 15);
    if (!/^\d{8}$/.test(dateStr) || !/^\d{6}$/.test(timeStr)) {
      return fileName;
    }
    return dateStr.substring(0, 4) + '-' + dateStr.substring(4, 6) + '-' + dateStr.substring(6, 8) + ' ' +
      timeStr.substring(0, 2) + ':' + timeStr.substring(2, 4) + ':' + timeStr.substring(4, 6) +
      ' · ' + stem.substring(16);
  }

  /** 字节数格式化（备份列表展示用；未知大小返回空串） */
  static formatSize(bytes: number): string {
    if (bytes <= 0) {
      return '';
    }
    const k = 1024;
    const sizes: Array<string> = ['B', 'KB', 'MB', 'GB'];
    const i = Math.min(Math.floor(Math.log(bytes) / Math.log(k)), sizes.length - 1);
    return (bytes / Math.pow(k, i)).toFixed(1) + sizes[i];
  }

  /** 生成备份 JSON 并 PUT 到 WebDAV（每次生成新文件，不覆盖历史备份；完成后按保留数量清理最老备份） */
  static async backup(): Promise<boolean> {
    const headers = WebDav.authHeaders();
    headers['Content-Type'] = 'application/json';
    // 逐级创建远端目录（已存在时返回 405，忽略即可）
    await WebDav.ensureRemoteFolders();
    const text = Backup.backup();
    const resp = await HttpClient.requestWithBody(
      WebDav.folderUrl() + encodeURIComponent(WebDav.backupFileName()), 'PUT', headers, text, 30000);
    const ok = resp !== null && resp.statusCode >= 200 && resp.statusCode < 300;
    if (ok) {
      await WebDav.pruneBackups().catch((_e: Object): void => {
      });
    }
    return ok;
  }

  /**
   * 备份完成后清理超限旧备份：带时间戳的备份仅保留最新 maxBackupCount 个（默认 10），
   * 其余按从旧到新删除；旧版固定名 musicfree-backup.json 不参与清理；失败静默
   */
  private static async pruneBackups(): Promise<void> {
    const limit = appConfig.getWebdavMaxBackupCount();
    const entries = await WebDav.listBackups();
    if (entries === null) {
      return;
    }
    // 列表按文件名倒序（新→旧），仅收集带时间戳前缀的备份
    const timestamped: Array<string> = [];
    for (const e of entries) {
      if (e.fileName.startsWith(WebDav.BACKUP_PREFIX)) {
        timestamped.push(e.fileName);
      }
    }
    for (let i = limit; i < timestamped.length; ++i) {
      await HttpClient.request(
        WebDav.folderUrl() + encodeURIComponent(timestamped[i]), 'DELETE', WebDav.authHeaders(), 15000);
    }
  }

  /**
   * 列出远端备份条目（PROPFIND Depth:1，含文件大小）
   * 按文件名倒序（时间戳前缀字典序即时间序，新备份在前，旧版固定名排在最后）；请求失败返回 null
   */
  static async listBackups(): Promise<Array<WebDavBackupEntry> | null> {
    const headers = WebDav.authHeaders();
    headers['Depth'] = '1';
    headers['Content-Type'] = 'application/xml';
    const body = '<?xml version="1.0" encoding="utf-8"?>' +
      '<D:propfind xmlns:D="DAV:"><D:prop><D:displayname/><D:getcontentlength/></D:prop></D:propfind>';
    const resp = await HttpClient.requestWithBody(WebDav.folderUrl(), 'PROPFIND', headers, body, 15000);
    if (resp === null || resp.statusCode < 200 || resp.statusCode >= 300) {
      return null;
    }
    const entries: Array<WebDavBackupEntry> = [];
    // 按 response 块解析（href 与文件大小配对；命名空间前缀因服务器而异，按通配处理）
    const blocks = resp.body.split(/<(?:[A-Za-z0-9_.-]+:)?response>/);
    for (const block of blocks) {
      const hrefMatch = block.match(/<(?:[A-Za-z0-9_.-]+:)?href>([^<]+)<\/(?:[A-Za-z0-9_.-]+:)?href>/);
      if (hrefMatch === null) {
        continue;
      }
      const href = hrefMatch[1];
      const raw = href.substring(href.lastIndexOf('/') + 1);
      if (raw.length === 0 || !raw.endsWith('.json')) {
        continue;
      }
      let name = raw;
      try {
        name = decodeURIComponent(raw);
      } catch (e) {
        name = raw;
      }
      const isBackup = name.startsWith(WebDav.BACKUP_PREFIX) || name === WebDav.LEGACY_BACKUP_FILENAME;
      if (!isBackup || entries.some((e: WebDavBackupEntry): boolean => e.fileName === name)) {
        continue;
      }
      const entry = new WebDavBackupEntry();
      entry.fileName = name;
      const sizeMatch = block.match(/<(?:[A-Za-z0-9_.-]+:)?getcontentlength>(\d+)<\/(?:[A-Za-z0-9_.-]+:)?getcontentlength>/);
      if (sizeMatch !== null) {
        entry.size = parseInt(sizeMatch[1], 10);
      }
      entries.push(entry);
    }
    entries.sort((a: WebDavBackupEntry, b: WebDavBackupEntry): number => b.fileName.localeCompare(a.fileName));
    return entries;
  }

  /** 从 WebDAV 拉取指定备份文件 */
  static async restore(fileName: string): Promise<WebDavRestoreResult> {
    const result = new WebDavRestoreResult();
    const resp = await HttpClient.request(
      WebDav.folderUrl() + encodeURIComponent(fileName), 'GET', WebDav.authHeaders(), 30000);
    if (resp === null) {
      return result;
    }
    if (resp.statusCode === 404) {
      result.notFound = true;
      return result;
    }
    if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.length > 0) {
      result.ok = true;
      result.data = resp.body;
    }
    return result;
  }

  /** 服务器地址（补齐结尾斜杠，不含备份路径） */
  static serverUrl(): string {
    const base = appConfig.getWebdavUrl().trim();
    return base.endsWith('/') ? base : base + '/';
  }

  /** 备份路径段（去首尾斜杠，空配置为空数组） */
  private static pathSegments(): Array<string> {
    const path = appConfig.getWebdavPath().trim();
    if (path.length === 0) {
      return [];
    }
    const parts: Array<string> = [];
    for (const seg of path.split('/')) {
      if (seg.length > 0) {
        parts.push(seg);
      }
    }
    return parts;
  }

  /** 备份目录完整地址：服务器地址 + 备份路径 + musicfreeOH/（路径末尾已是 musicfreeOH 时不重复拼接） */
  static folderUrl(): string {
    const segs = WebDav.pathSegments();
    let url = WebDav.serverUrl();
    for (const seg of segs) {
      url = url + seg + '/';
    }
    if (segs.length === 0 || segs[segs.length - 1] !== WebDav.BACKUP_DIRNAME) {
      url = url + WebDav.BACKUP_DIRNAME + '/';
    }
    return url;
  }

  /** 逐级 MKCOL 创建备份路径与 musicfreeOH 目录（每级失败不中断，由 PUT 兜底报错） */
  private static async ensureRemoteFolders(): Promise<void> {
    const segs = WebDav.pathSegments();
    if (segs.length === 0 || segs[segs.length - 1] !== WebDav.BACKUP_DIRNAME) {
      segs.push(WebDav.BACKUP_DIRNAME);
    }
    let cur = WebDav.serverUrl();
    for (const seg of segs) {
      cur = cur + seg + '/';
      await HttpClient.request(cur, 'MKCOL', WebDav.authHeaders(), 15000);
    }
  }

  /** 服务器连通性探测（OPTIONS）：拿到 HTTP 响应且认证通过（非 401/403）视为可达 */
  private static async isReachable(): Promise<boolean> {
    const resp = await HttpClient.request(WebDav.serverUrl(), 'OPTIONS', WebDav.authHeaders(), 8000);
    if (resp === null) {
      return false;
    }
    return resp.statusCode !== 401 && resp.statusCode !== 403;
  }

  /** 彻底退出应用前自动备份（Ability onDestroy 触发）：开关开启 + 已配置服务器 + 服务器可达时执行，全程静默失败 */
  static async backupOnExit(): Promise<void> {
    if (WebDav.exitBackupRunning) {
      return;
    }
    if (!appConfig.getWebdavAutoBackupOnExit() || !WebDav.isConfigured()) {
      return;
    }
    WebDav.exitBackupRunning = true;
    try {
      if (await WebDav.isReachable()) {
        await WebDav.backup();
      }
    } catch (e) {
      // 退出路径不弹提示，静默失败
    } finally {
      WebDav.exitBackupRunning = false;
    }
  }

  /** Basic Auth 请求头 */
  private static authHeaders(): Record<string, string> {
    const headers: Record<string, string> = {};
    const user = appConfig.getWebdavUsername();
    const pass = appConfig.getWebdavPassword();
    if (user.length > 0 || pass.length > 0) {
      const encoder = new util.TextEncoder();
      const u8 = encoder.encodeInto(user + ':' + pass);
      const helper = new util.Base64Helper();
      headers['Authorization'] = 'Basic ' + helper.encodeToStringSync(u8);
    }
    return headers;
  }
}
