import { HttpClient } from '../infra/HttpClient';
import { appConfig } from '../core/AppConfig';
import { AppMeta } from '../core/AppMeta';
import { appState } from '../entryability/AppState';

/** GitHub 最新 release 接口 */
const RELEASE_API_URL: string = 'https://api.github.com/repos/crazypig321/musicfreeOH/releases/latest';
/** 国内加速前缀型代理（拼接在目标 URL 前），检查更新与下载均依次回退尝试 */
const GH_PROXY_PREFIXES: Array<string> = ['https://gh-proxy.com/', 'https://ghfast.top/'];
/** 静默检查节流间隔（毫秒）：会话内最多每 10 分钟请求一次接口 */
const SILENT_CHECK_THROTTLE_MS: number = 10 * 60 * 1000;

/** GitHub latest release 接口返回体（仅声明所需字段） */
export interface ReleaseRaw {
  tag_name?: string;
  assets?: Array<ReleaseAssetRaw>;
}

/** release 资产原始字段 */
export interface ReleaseAssetRaw {
  name?: string;
  browser_download_url?: string;
}

/** 归一化后的 release 软件包资产 */
export class ReleaseAsset {
  name: string = '';
  url: string = '';
}

/**
 * 更新检查工具：拉取 GitHub 最新 release 并与本地版本比较
 * 静默检查结果写入 appState.latestVersion（设置页「关于」红点与关于页新版本标签共用）；
 * 下载流程（保存器、通知栏进度、代理回退）仍在关于页内
 */
export class UpdateChecker {
  /** 上次静默检查时间戳（0 = 本次会话尚未检查） */
  private static lastSilentCheckAt: number = 0;

  /** 从 release 资产中选取软件包：优先 .hap，其次第一个有效资产；无资产返回 null */
  static pickReleaseAsset(release: ReleaseRaw): ReleaseAsset | null {
    const assets = release.assets;
    if (assets === undefined) {
      return null;
    }
    let fallback: ReleaseAsset | null = null;
    for (const raw of assets) {
      const name = raw.name;
      const url = raw.browser_download_url;
      if (typeof name !== 'string' || name.length === 0 || typeof url !== 'string' || url.length === 0) {
        continue;
      }
      const asset = new ReleaseAsset();
      asset.name = name;
      asset.url = url;
      if (fallback === null) {
        fallback = asset;
      }
      if (name.toLowerCase().endsWith('.hap')) {
        return asset;
      }
    }
    return fallback;
  }

  /** 比较语义化版本号（忽略 v 前缀与非数字字符，逐段比较）：a 是否大于 b */
  static isNewerVersion(a: string, b: string): boolean {
    const parse = (v: string): Array<number> => {
      const parts: Array<number> = [];
      const segs = v.replace(/^[vV]/, '').split('.');
      for (const seg of segs) {
        const digits = seg.replace(/[^0-9]/g, '');
        const n = digits.length > 0 ? Number(digits) : 0;
        parts.push(Number.isFinite(n) ? n : 0);
      }
      return parts;
    };
    const pa = parse(a);
    const pb = parse(b);
    const len = Math.max(pa.length, pb.length);
    for (let i = 0; i < len; i++) {
      const x = i < pa.length ? pa[i] : 0;
      const y = i < pb.length ? pb[i] : 0;
      if (x !== y) {
        return x > y;
      }
    }
    return false;
  }

  /** 按代理开关排序候选地址（检查与下载共用）：
   *  开启 = 国内代理在前、直连兜底；关闭 = 直连在前、代理回退；均含全部来源，失败自动切换 */
  static orderedUrls(targetUrl: string, proxyFirst: boolean): Array<string> {
    const urls: Array<string> = [];
    if (!proxyFirst) {
      urls.push(targetUrl);
    }
    for (const prefix of GH_PROXY_PREFIXES) {
      urls.push(prefix + targetUrl);
    }
    if (proxyFirst) {
      urls.push(targetUrl);
    }
    return urls;
  }

  /** 拉取 GitHub 最新 release 信息：直连不通时依次走国内代理；全部失败返回 null */
  static async fetchLatestRelease(proxyFirst: boolean): Promise<ReleaseRaw | null> {
    const headers: Record<string, string> = {
      'User-Agent': 'musicfreeOH',
      'Accept': 'application/vnd.github+json'
    };
    const urls = UpdateChecker.orderedUrls(RELEASE_API_URL, proxyFirst);
    for (const url of urls) {
      const result = await HttpClient.get(url, headers, 6000);
      if (result === null || result.statusCode !== 200) {
        continue;
      }
      try {
        const raw = JSON.parse(result.body) as ReleaseRaw;
        const tag = raw.tag_name;
        if (typeof tag === 'string' && tag.length > 0) {
          return raw;
        }
      } catch (e) {
        // 当前源解析失败，尝试下一个
      }
    }
    return null;
  }

  /** 静默检查更新（会话内 10 分钟节流，设置页/关于页进入时共用）：
   *  最新版本高于本地时记录到 appState.latestVersion，否则清空（红点/标签随状态刷新）；
   *  请求失败不改动现有状态 */
  static async checkLatestSilently(): Promise<void> {
    const now = Date.now();
    if (now - UpdateChecker.lastSilentCheckAt < SILENT_CHECK_THROTTLE_MS) {
      return;
    }
    UpdateChecker.lastSilentCheckAt = now;
    const raw = await UpdateChecker.fetchLatestRelease(appConfig.getUpdateProxyDownload());
    if (raw === null) {
      return;
    }
    const tag = raw.tag_name;
    if (tag !== undefined && UpdateChecker.isNewerVersion(tag, AppMeta.appVersion)) {
      appState.latestVersion = tag;
    } else {
      appState.latestVersion = '';
    }
  }
}
