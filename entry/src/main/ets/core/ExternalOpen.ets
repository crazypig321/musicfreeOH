import { Want } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { JsonUtil, JsonRecord } from '../common/JsonUtil';
import { PathConst } from '../common/PathConst';
import { FileUtils } from '../utils/FileUtils';
import { Delay } from '../utils/Delay';
import { CryptoUtil } from '../utils/CryptoUtil';
import { ContextHolder } from '../common/ContextHolder';
import { PluginImport } from '../plugin/PluginImport';
import { Subscriptions } from '../plugin/Subscriptions';
import { Backup } from './Backup';
import { Bootstrap } from './Bootstrap';
import { trackPlayer } from './TrackPlayer';
import { localMusicSheet } from './LocalMusicSheet';
import { LocalMusicExclusion } from './LocalMusicExclusion';
import { MusicItem } from '../common/model/MediaTypes';
import { ResumeMode, LOCAL_PLUGIN_PLATFORM, INTERNAL_SERIALIZE_KEY, SUPPORT_LOCAL_MEDIA_TYPE } from '../common/Consts';

/**
 * 外部文件关联打开处理（文件管理器/QQ/微信 → 打开方式 → 本应用）
 * .js → 安装为单个插件；.json → 备份恢复或订阅源导入（按内容区分）；音频 → 复制到下载目录并立即播放
 */
export class ExternalOpen {
  private static pendingUri: string | null = null;
  private static handling: boolean = false;
  private static readonly READY_TIMEOUT_MS = 20000;

  /** Ability onCreate/onNewWant 入口：识别文件打开 Want 并排队处理 */
  static offer(want: Want | undefined): void {
    if (want === undefined || want.uri === undefined || want.uri === null) {
      return;
    }
    const uri = want.uri;
    if (uri.length === 0 || !uri.startsWith('file://')) {
      return;
    }
    ExternalOpen.pendingUri = uri;
    ExternalOpen.process();
  }

  /** 串行处理；冷启动时等待核心数据域初始化完成（Index.aboutToAppear → Bootstrap.setup） */
  private static process(): void {
    if (ExternalOpen.handling) {
      return;
    }
    ExternalOpen.handling = true;
    const run = async (): Promise<void> => {
      try {
        const deadline = Date.now() + ExternalOpen.READY_TIMEOUT_MS;
        while (!Bootstrap.isInited() && Date.now() < deadline) {
          await Delay.wait(200);
        }
        const uri = ExternalOpen.pendingUri;
        ExternalOpen.pendingUri = null;
        if (uri === null || !Bootstrap.isInited()) {
          return;
        }
        await ExternalOpen.dispatch(uri);
      } finally {
        ExternalOpen.handling = false;
      }
    };
    run().catch((_e: Object): void => {
    });
  }

  /** 按扩展名分发：.js 插件 / .json 备份或订阅源 / 音频 */
  private static async dispatch(uri: string): Promise<void> {
    const clean = uri.split('?')[0].toLowerCase();
    if (clean.endsWith('.js')) {
      await ExternalOpen.handlePlugin(uri);
      return;
    }
    if (clean.endsWith('.json')) {
      await ExternalOpen.handleJson(uri);
      return;
    }
    for (const ext of SUPPORT_LOCAL_MEDIA_TYPE) {
      if (clean.endsWith(ext)) {
        await ExternalOpen.handleAudio(uri);
        return;
      }
    }
    ExternalOpen.toast('暂不支持打开该类型文件');
  }

  /** .js → 安装为插件 */
  private static async handlePlugin(uri: string): Promise<void> {
    ExternalOpen.toast('正在导入插件…');
    const r = await PluginImport.installLocalJsFiles([uri]);
    if (r.success > 0) {
      ExternalOpen.toast('插件导入成功');
    } else {
      ExternalOpen.toast('插件导入失败' + (r.lastMessage.length > 0 ? '：' + r.lastMessage : ''));
    }
  }

  /** .json → 备份恢复 / 订阅源导入（按顶层字段区分） */
  private static async handleJson(uri: string): Promise<void> {
    const text = PluginImport.readUriText(uri, 'json');
    if (text === null || text.length === 0) {
      ExternalOpen.toast('读取文件失败');
      return;
    }
    const rec = JsonUtil.parseRecord(text);
    if (rec === null) {
      ExternalOpen.toast('JSON 文件格式无效');
      return;
    }
    // 备份文件：顶层含 musicSheets（备份固定包含 musicSheets/plugins/appConfig/subscriptions）
    if (JsonUtil.recArray(rec, 'musicSheets') !== null) {
      ExternalOpen.toast('正在恢复备份…');
      try {
        await Backup.resume(text, ResumeMode.Append);
        ExternalOpen.toast('备份恢复成功');
      } catch (e) {
        ExternalOpen.toast('备份恢复失败：' + (e instanceof Error ? e.message : '格式无效'));
      }
      return;
    }
    // 订阅源文件：{ plugins: [{ url }] }
    if (JsonUtil.recArray(rec, 'plugins') !== null) {
      ExternalOpen.importSubscription(uri, text);
      return;
    }
    ExternalOpen.toast('无法识别的 JSON 文件');
  }

  /** 订阅源导入：内容复制进沙箱后作为本地订阅源（file://）添加并立即同步 */
  private static importSubscription(uri: string, text: string): void {
    const clean = uri.split('?')[0];
    const idx = clean.lastIndexOf('/');
    const rawName = idx === -1 ? clean : clean.substring(idx + 1);
    const name = rawName.length > 0 ? rawName : '订阅源.json';
    FileUtils.checkAndCreateDir(PathConst.dataPath + 'subscriptions');
    const destPath = PathConst.dataPath + 'subscriptions/' + FileUtils.escapeCharacter(name);
    if (!FileUtils.writeFileText(destPath, text)) {
      ExternalOpen.toast('订阅源导入失败');
      return;
    }
    const sourceUrl = 'file://' + destPath;
    if (!Subscriptions.addSource(sourceUrl)) {
      ExternalOpen.toast('该订阅源已存在');
      return;
    }
    ExternalOpen.toast('已添加订阅源，正在同步…');
    Subscriptions.syncSource(sourceUrl).then((msg: string): void => {
      ExternalOpen.toast(msg);
    }).catch((_e: Object): void => {
      ExternalOpen.toast('订阅源同步失败');
    });
  }

  /** 音频文件 → 复制到下载目录并立即播放（后台重新扫描补全元信息/封面） */
  private static async handleAudio(uri: string): Promise<void> {
    const normalized = FileUtils.normalizePath(uri);
    const name = FileUtils.getFileName(normalized);
    if (name.length === 0) {
      ExternalOpen.toast('无法读取文件名');
      return;
    }
    const base = PathConst.downloadPath.endsWith('/') ?
      PathConst.downloadPath.substring(0, PathConst.downloadPath.length - 1) : PathConst.downloadPath;
    // 文件已在下载目录内：原位置直接播放（仅清除排除名单）
    if (normalized.startsWith(base + '/') && normalized.length > base.length + 1) {
      LocalMusicExclusion.clearExclusion(name);
      await ExternalOpen.playLocalFile(normalized);
      return;
    }
    const destName = FileUtils.escapeCharacter(name);
    const dest = base + '/' + destName;
    if (!FileUtils.exists(dest)) {
      try {
        const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        const dst = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        try {
          fs.copyFileSync(src.fd, dst.fd);
        } finally {
          fs.closeSync(dst);
          fs.closeSync(src);
        }
      } catch (e) {
        ExternalOpen.toast('导入音频失败');
        return;
      }
    }
    LocalMusicExclusion.clearExclusion(destName);
    await ExternalOpen.playLocalFile(dest);
    // 后台重新扫描下载目录补全元数据/封面并入库（与正在播放条目按 platform@id 去重合并）
    localMusicSheet.importLocal([PathConst.downloadPath], (filename: string): boolean => {
      return !LocalMusicExclusion.getExcludedFiles().has(filename);
    }).catch((_e: Object): void => {
    });
  }

  /** 构造本地 MusicItem（与扫描入库同 id 规则：md5(file://路径)）并替换播放列表立即播放 */
  private static async playLocalFile(path: string): Promise<void> {
    const fileUrl = FileUtils.addFileScheme(path);
    let id = '';
    try {
      id = await CryptoUtil.md5(fileUrl);
    } catch (e) {
      id = fileUrl;
    }
    const item = new MusicItem();
    item.id = id;
    item.platform = LOCAL_PLUGIN_PLATFORM;
    item.title = FileUtils.getFileName(path, true);
    item.artist = '未知歌手';
    item.album = '未知专辑';
    const extraRec: JsonRecord = {
      'localPath': fileUrl
    };
    item.extras[INTERNAL_SERIALIZE_KEY] = extraRec;
    try {
      await trackPlayer.playWithReplacePlayList(item, [item]);
      ExternalOpen.toast('正在播放：' + item.title);
    } catch (e) {
      ExternalOpen.toast('播放失败');
    }
  }

  private static toast(message: string): void {
    try {
      ContextHolder.getUiContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (e) {
      // UI 未就绪时静默
    }
  }
}
