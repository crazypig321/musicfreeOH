import util from '@ohos.util';
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

/**
 * WebDAV 备份与恢复
 * 服务器地址（如 https://dav.example.com/dav/）+ 备份路径（可选）+ 自动追加的 musicfreeOH 目录，
 * 备份文件固定为 musicfree-backup.json；认证方式为 Basic Auth（用户名/密码可留空）
 */
export class WebDav {
  static readonly BACKUP_FILENAME: string = 'musicfree-backup.json';
  static readonly BACKUP_DIRNAME: string = 'musicfreeOH';
  /** 退出备份进行中标记（防重复触发） */
  private static exitBackupRunning: boolean = false;

  /** 是否已配置服务器地址 */
  static isConfigured(): boolean {
    return appConfig.getWebdavUrl().trim().length > 0;
  }

  /** 生成备份 JSON 并 PUT 到 WebDAV */
  static async backup(): Promise<boolean> {
    const headers = WebDav.authHeaders();
    headers['Content-Type'] = 'application/json';
    // 逐级创建远端目录（已存在时返回 405，忽略即可）
    await WebDav.ensureRemoteFolders();
    const text = Backup.backup();
    const resp = await HttpClient.requestWithBody(WebDav.backupFileUrl(), 'PUT', headers, text, 30000);
    return resp !== null && resp.statusCode >= 200 && resp.statusCode < 300;
  }

  /** 从 WebDAV 拉取备份 JSON */
  static async restore(): Promise<WebDavRestoreResult> {
    const result = new WebDavRestoreResult();
    const resp = await HttpClient.request(WebDav.backupFileUrl(), 'GET', WebDav.authHeaders(), 30000);
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

  /** 备份文件完整地址 */
  static backupFileUrl(): string {
    return WebDav.folderUrl() + WebDav.BACKUP_FILENAME;
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
