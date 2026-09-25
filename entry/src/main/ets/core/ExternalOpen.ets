import { Want } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { JsonUtil, JsonRecord } from '../common/JsonUtil';
import { PathConst } from '../common/PathConst';
import { FileUtils } from '../utils/FileUtils';
import { Delay } from '../utils/Delay';
import { CryptoUtil } from '../utils/CryptoUtil';
import { ContextHolder } from '../common/ContextHolder';
import { MUSICFREE_SONG_MARK } from '../utils/ShareUtils';
import { PluginImport } from '../plugin/PluginImport';
import { pluginManager } from '../plugin/PluginManager';
import { appConfig } from './AppConfig';
import { Subscriptions } from '../plugin/Subscriptions';
import { Backup } from './Backup';
import { Bootstrap } from './Bootstrap';
import { trackPlayer } from './TrackPlayer';
import { localMusicSheet } from './LocalMusicSheet';
import { musicSheet, backupEntriesFromRecord } from './MusicSheet';
import { LocalMusicExclusion } from './LocalMusicExclusion';
import { MusicItem } from '../common/model/MediaTypes';
import { ResumeMode, LOCAL_PLUGIN_PLATFORM, INTERNAL_SERIALIZE_KEY, SUPPORT_LOCAL_MEDIA_TYPE } from '../common/Consts';

/**
 * 外部内容打开/接收处理（统一串行入口）
 * 1. 文件关联打开（文件管理器/QQ/微信 → 打开方式 → 本应用）：
 *    .js → 安装为单个插件；.json → 备份恢复或订阅源导入（按内容区分）；音频 → 复制到下载目录并立即播放
 * 2. 系统分享接收（ShareReceiveAbility 暂存后拉起）：歌曲标记文本 → 播放；
 *    URL → 安装插件/订阅源；其余文本 → 复制到剪贴板；文件走 1 相同分发
 */
export class ExternalOpen {
  private static pendingUri: string | null = null;
  private static handling: boolean = false;
  private static readonly READY_TIMEOUT_MS = 20000;

  /** Ability onCreate/onNewWant 入口：识别文件打开 Want 与分享导入 Want 并排队处理 */
  static offer(want: Want | undefined): void {
    if (want !== undefined) {
      const uri = want.uri;
      if (typeof uri === 'string' && uri.length > 0 && uri.startsWith('file://')) {
        ExternalOpen.pendingUri = uri;
      }
    }
    // 文件打开 / 分享导入 / 暂存目录残留清理，统一走串行处理
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
        if (!Bootstrap.isInited()) {
          return;
        }
        if (uri !== null) {
          await ExternalOpen.dispatch(uri);
        }
        await ExternalOpen.drainShareReceived();
      } finally {
        ExternalOpen.handling = false;
      }
    };
    run().catch((_e: Object): void => {
    });
  }

  /** 内部通道（碰一碰沙箱接收等）直接投递文件 URI：等待核心数据域就绪后统一分发 */
  static async deliverFile(uri: string): Promise<void> {
    const deadline = Date.now() + ExternalOpen.READY_TIMEOUT_MS;
    while (!Bootstrap.isInited() && Date.now() < deadline) {
      await Delay.wait(200);
    }
    if (!Bootstrap.isInited()) {
      return;
    }
    await ExternalOpen.dispatch(uri);
  }

  /** 按扩展名分发：.js 及 .mfplugin 插件 / .json 及 .mfsheets 歌单或备份 / .txt 及 .mfsong 分享文本 / .mfsub 订阅源 / 音频 */
  private static async dispatch(uri: string): Promise<void> {
    const clean = uri.split('?')[0].toLowerCase();
    if (clean.endsWith('.js') || clean.endsWith('.mfplugin')) {
      await ExternalOpen.handlePlugin(uri);
      return;
    }
    if (clean.endsWith('.json') || clean.endsWith('.mfsheets')) {
      await ExternalOpen.handleJson(uri);
      return;
    }
    if (clean.endsWith('.mfsub')) {
      await ExternalOpen.handleMfSub(uri);
      return;
    }
    if (clean.endsWith('.txt') || clean.endsWith('.mfsong')) {
      // 外部打开的 URI 为 file://docs/... 形式，normalizePath 会剥成相对路径导致读取失败，须经 openSync 按 URI 读取
      const text = PluginImport.readUriText(uri, 'txt');
      if (text !== null && text.length > 0) {
        await ExternalOpen.handleSharedText(text);
      } else {
        ExternalOpen.toast('读取文件失败');
      }
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

  /** .js / .mfplugin → 安装为插件（.mfplugin 内容为插件源地址时从 URL 安装） */
  private static async handlePlugin(uri: string): Promise<void> {
    // 回落格式：文件内容为插件源地址（本地插件文件缺失时生成），转 URL 安装；
    // file://docs URI 需经 openSync 读取，normalizePath 剥前缀后是相对路径
    const head = PluginImport.readUriText(uri, 'txt');
    if (head !== null) {
      const trimmedHead = head.trim();
      if (trimmedHead.startsWith('http://') || trimmedHead.startsWith('https://')) {
        await ExternalOpen.handleSharedUrl(trimmedHead.split('\n')[0].trim());
        return;
      }
    }
    ExternalOpen.toast('正在导入插件…');
    const r = await PluginImport.installLocalJsFiles([uri]);
    if (r.success > 0) {
      ExternalOpen.toast('插件导入成功');
    } else {
      ExternalOpen.toast('插件导入失败' + (r.lastMessage.length > 0 ? '：' + r.lastMessage : ''));
    }
  }

  /** .mfsub → 订阅源直达导入：内容为源 URL（逐行）直接添加；否则视为源 json 内容保存为本地订阅源 */
  private static async handleMfSub(uri: string): Promise<void> {
    // 外部打开的 URI 为 file://docs/... 形式，须经 openSync 按 URI 读取（normalizePath 剥前缀后是相对路径）
    const text = PluginImport.readUriText(uri, 'mfsub');
    if (text === null || text.trim().length === 0) {
      ExternalOpen.toast('读取订阅源失败');
      return;
    }
    const trimmed = text.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      const lines: Array<string> = [];
      for (const line of trimmed.split('\n')) {
        const url = line.trim();
        if (url.startsWith('http://') || url.startsWith('https://')) {
          lines.push(url);
        }
      }
      for (const url of lines) {
        await ExternalOpen.handleSharedUrl(url);
      }
      return;
    }
    // 源 json 内容：按来源文件名（换 .json 扩展名）保存为本地订阅源
    const clean = uri.split('?')[0];
    const idx = clean.lastIndexOf('/');
    const rawName = idx === -1 ? clean : clean.substring(idx + 1);
    const dot = rawName.lastIndexOf('.');
    const baseName = dot > 0 ? rawName.substring(0, dot) : rawName;
    ExternalOpen.importSubscriptionText(
      (baseName.length > 0 ? baseName : '订阅源') + '.json', trimmed);
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
    // 分享歌单文件：{ musicfreeSheets: [...] }（接收端导入为本地歌单，同名歌单合并曲目）
    if (JsonUtil.recArray(rec, 'musicfreeSheets') !== null) {
      await ExternalOpen.importSharedSheets(rec);
      return;
    }
    // 订阅源文件：{ plugins: [{ url }] }
    if (JsonUtil.recArray(rec, 'plugins') !== null) {
      ExternalOpen.importSubscription(uri, text);
      return;
    }
    ExternalOpen.toast('无法识别的 JSON 文件');
  }

  /** 分享歌单导入：逐个歌单导入（同名歌单合并曲目，否则新建歌单） */
  private static async importSharedSheets(rec: JsonRecord): Promise<void> {
    const entries = backupEntriesFromRecord(JsonUtil.recArray(rec, 'musicfreeSheets'));
    if (entries.length === 0) {
      ExternalOpen.toast('歌单文件为空');
      return;
    }
    ExternalOpen.toast('正在导入歌单…');
    try {
      await musicSheet.resumeSheets(entries, ResumeMode.Append);
      ExternalOpen.toast('已导入 ' + entries.length.toString() + ' 个歌单');
    } catch (e) {
      ExternalOpen.toast('歌单导入失败');
    }
  }

  /** 订阅源导入：内容复制进沙箱后作为本地订阅源（file://）添加并立即同步 */
  private static importSubscription(uri: string, text: string): void {
    const clean = uri.split('?')[0];
    const idx = clean.lastIndexOf('/');
    const rawName = idx === -1 ? clean : clean.substring(idx + 1);
    ExternalOpen.importSubscriptionText(rawName.length > 0 ? rawName : '订阅源.json', text);
  }

  /** 订阅源文本导入：写入沙箱 subscriptions 目录后作为本地订阅源添加并立即同步 */
  private static importSubscriptionText(name: string, text: string): void {
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

  /**
   * 处理系统分享暂存目录（ShareReceiveAbility 确认导入后写入，主应用与扩展共用沙箱）：
   * .mftxt 为文本记录，其余文件按扩展名走 dispatch；处理后清理暂存
   */
  private static async drainShareReceived(): Promise<void> {
    await ExternalOpen.drainDir(PathConst.dataPath + 'share_received/');
    // 碰一碰沙箱接收目录残留（传输完成但处理中断的文件）：下次启动补导入后清理
    await ExternalOpen.drainDir(PathConst.dataPath + 'harmonyshare_recv/');
  }

  /** 处理暂存目录内文件：.mftxt 文本记录，其余按扩展名分发；处理后删除文件避免占用沙箱 */
  private static async drainDir(dir: string): Promise<void> {
    if (!FileUtils.exists(dir)) {
      return;
    }
    let names: Array<string> = [];
    try {
      names = fs.listFileSync(dir);
    } catch (e) {
      return;
    }
    for (const name of names) {
      const path = dir + name;
      if (name.endsWith('.mftxt')) {
        const text = FileUtils.readFileText(path);
        FileUtils.unlink(path);
        if (text !== null && text.length > 0) {
          await ExternalOpen.handleSharedText(text);
        }
        continue;
      }
      try {
        await ExternalOpen.dispatch('file://' + path);
      } finally {
        FileUtils.unlink(path);
      }
    }
  }

  /** 分享文本：歌曲标记 → 播放；URL → 安装插件(.js)/导入订阅源；其余 → 复制到剪贴板 */
  private static async handleSharedText(text: string): Promise<void> {
    const trimmed = text.trim();
    const markIdx = trimmed.indexOf(MUSICFREE_SONG_MARK);
    if (markIdx !== -1) {
      const rec = JsonUtil.parseRecord(trimmed.substring(markIdx + MUSICFREE_SONG_MARK.length));
      if (rec !== null) {
        const platform = JsonUtil.recStr(rec, 'platform');
        const id = JsonUtil.recStr(rec, 'id');
        if (platform.length > 0 && id.length > 0) {
          await ExternalOpen.playSharedSong(platform, id,
            JsonUtil.recStr(rec, 'title'), JsonUtil.recStr(rec, 'artist'));
          return;
        }
      }
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      const url = trimmed.split('\n')[0].trim();
      await ExternalOpen.handleSharedUrl(url);
      return;
    }
    // 纯文本（如歌单列表）：复制到剪贴板
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data)
      .then((): void => {
        ExternalOpen.toast('文本已复制到剪贴板');
      })
      .catch((_e: Object): void => {
        ExternalOpen.toast('文本复制失败');
      });
  }

  /** 分享 URL：.js 结尾 → 安装插件；其余 → 导入订阅源（同步失败自动移除） */
  private static async handleSharedUrl(url: string): Promise<void> {
    if (url.toLowerCase().endsWith('.js')) {
      ExternalOpen.toast('正在安装插件…');
      try {
        const r = await pluginManager.installPluginFromUrl(url, appConfig.getNotCheckPluginVersion());
        ExternalOpen.toast(r.success ? '插件安装成功' :
          '插件安装失败' + (r.message.length > 0 ? '：' + r.message : ''));
      } catch (e) {
        ExternalOpen.toast('插件安装失败');
      }
      return;
    }
    ExternalOpen.toast('正在导入订阅源…');
    if (!Subscriptions.addSource(url)) {
      ExternalOpen.toast('该订阅源已存在');
      return;
    }
    Subscriptions.syncSource(url).then((msg: string): void => {
      ExternalOpen.toast(msg);
    }).catch((_e: Object): void => {
      Subscriptions.removeSource(url);
      ExternalOpen.toast('订阅源同步失败，已移除');
    });
  }

  /** 结构化歌曲（MusicFree 分享标记）：构造 MusicItem 直接播放（需接收端装有对应平台插件） */
  private static async playSharedSong(platform: string, id: string, title: string, artist: string): Promise<void> {
    const item = new MusicItem();
    item.id = id;
    item.platform = platform;
    item.title = title.length > 0 ? title : '未知歌曲';
    item.artist = artist.length > 0 ? artist : '未知歌手';
    try {
      await trackPlayer.playWithReplacePlayList(item, [item]);
      ExternalOpen.toast('正在播放：' + item.title);
    } catch (e) {
      ExternalOpen.toast('播放失败：请先安装「' + platform + '」插件');
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
