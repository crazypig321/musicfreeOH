import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileUri } from '@kit.CoreFileKit';
import { ContextHolder } from '../common/ContextHolder';
import { PathConst } from '../common/PathConst';
import { FileUtils } from './FileUtils';
import { MediaUtils } from './MediaUtils';
import { MusicItem } from '../common/model/MediaTypes';
import { JsonRecord } from '../common/JsonUtil';
import { SheetItem } from '../common/model/SheetTypes';
import { musicSheet, SheetBackupEntry } from '../core/MusicSheet';

/** 分享歌曲的结构化标记：标记后为 JSON（platform/id/title/artist），接收端据此直接播放 */
export const MUSICFREE_SONG_MARK: string = '[MUSICFREE-SONG]';

/** 自定义 UTD（应用安装即注册到系统）：华为分享跨设备规则为“有可打开应用直接打开”，实现一步直达 */
export const SONG_UTD: string = 'com.crazypig321.musicfreeoh.song';
export const SHEETS_UTD: string = 'com.crazypig321.musicfreeoh.sheets';
export const PLUGIN_UTD: string = 'com.crazypig321.musicfreeoh.plugin';
export const SUB_UTD: string = 'com.crazypig321.musicfreeoh.sub';

/** 结构化歌曲数据（仅用于 JSON 序列化） */
class SharedSongPayload {
  platform: string = '';
  id: string = '';
  title: string = '';
  artist: string = '';
}

/** 歌曲跨设备分享数据（data 为发送数据；tempPath 为网络歌曲临时文件，发送后需清理） */
export class MusicShareData {
  data: systemShare.SharedData | null = null;
  tempPath: string = '';
}

/**
 * 鸿蒙系统分享工具（Share Kit）：拉起系统分享面板，将内容分享到其他应用/设备
 * 支持纯文本 / 链接 / 本地沙箱文件；面板拉起失败时回调 onFailure
 */
export class ShareUtils {
  /** 分享歌曲：有本地文件直接发文件（接收端导入后可播）；网络歌曲仅分享歌名文本
   * （接收端 MusicFreeOH 解析标记进入搜索页自动搜索，无需与发送方安装相同插件；其他应用可见歌名） */
  static shareMusic(item: MusicItem, onFailure: (message: string) => void): void {
    const localPath = MediaUtils.getLocalPath(item);
    if (localPath !== null && localPath.length > 0 && !localPath.startsWith('content://')) {
      ShareUtils.shareFile(item.title, localPath, onFailure);
      return;
    }
    const payload = new SharedSongPayload();
    payload.platform = item.platform;
    payload.id = item.id;
    payload.title = item.title;
    payload.artist = item.artist;
    const text = '「' + item.title + '」 - ' + item.artist + '（来自 ' + item.platform + '）' +
      '\n' + MUSICFREE_SONG_MARK + JSON.stringify(payload);
    ShareUtils.shareText(item.title, text, onFailure);
  }

  /** 批量分享本地沙箱文件：一个文件一条记录，BATCH 模式一次性分享 */
  static shareFiles(title: string, paths: Array<string>, onFailure: (message: string) => void): void {
    const valid: Array<string> = [];
    for (const p of paths) {
      const realPath = FileUtils.normalizePath(p);
      if (realPath.length > 0 && FileUtils.exists(realPath)) {
        valid.push(realPath);
      }
    }
    if (valid.length === 0) {
      onFailure('没有可分享的文件');
      return;
    }
    try {
      const data: systemShare.SharedData = new systemShare.SharedData(ShareUtils.fileRecord(title, valid[0]));
      for (let i = 1; i < valid.length; i++) {
        data.addRecord(ShareUtils.fileRecord(title, valid[i]));
      }
      ShareUtils.launch(data, valid.length > 1, onFailure);
    } catch (e) {
      onFailure('打开分享面板失败');
    }
  }

  /** 批量分享纯文本：一条文本一条记录（接收端 MusicFreeOH 逐条处理，可批量安装插件/订阅源） */
  static shareTexts(title: string, texts: Array<string>, onFailure: (message: string) => void): void {
    if (texts.length === 0) {
      onFailure('没有可分享的内容');
      return;
    }
    try {
      const first: systemShare.SharedRecord = {
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: texts[0],
        title: title,
        label: '文本'
      };
      const data: systemShare.SharedData = new systemShare.SharedData(first);
      for (let i = 1; i < texts.length; i++) {
        const record: systemShare.SharedRecord = {
          utd: utd.UniformDataType.PLAIN_TEXT,
          content: texts[i],
          title: title,
          label: '文本'
        };
        data.addRecord(record);
      }
      ShareUtils.launch(data, texts.length > 1, onFailure);
    } catch (e) {
      onFailure('打开分享面板失败');
    }
  }

  /** 分享单条纯文本（分享到目标应用为一段文字，分享到设备保存为 txt 文件） */
  static shareText(title: string, content: string, onFailure: (message: string) => void): void {
    const record: systemShare.SharedRecord = {
      utd: utd.UniformDataType.PLAIN_TEXT,
      content: content,
      title: title,
      label: '文本'
    };
    ShareUtils.launch(new systemShare.SharedData(record), false, onFailure);
  }

  /** 分享单条链接（HYPERLINK 类型可精确匹配能打开链接的目标应用） */
  static shareLink(title: string, url: string, onFailure: (message: string) => void): void {
    const record: systemShare.SharedRecord = {
      utd: utd.UniformDataType.HYPERLINK,
      content: url,
      title: title,
      label: '链接'
    };
    ShareUtils.launch(new systemShare.SharedData(record), false, onFailure);
  }

  /** 批量分享链接：一条链接一条记录，BATCH 模式下全部一次性分享给同一目标应用 */
  static shareLinks(title: string, urls: Array<string>, onFailure: (message: string) => void): void {
    if (urls.length === 0) {
      onFailure('没有可分享的内容');
      return;
    }
    const first: systemShare.SharedRecord = {
      utd: utd.UniformDataType.HYPERLINK,
      content: urls[0],
      title: title,
      label: '链接'
    };
    const data: systemShare.SharedData = new systemShare.SharedData(first);
    for (let i = 1; i < urls.length; i++) {
      const record: systemShare.SharedRecord = {
        utd: utd.UniformDataType.HYPERLINK,
        content: urls[i],
        title: title,
        label: '链接'
      };
      data.addRecord(record);
    }
    ShareUtils.launch(data, urls.length > 1, onFailure);
  }

  /** 分享本地沙箱文件（path 可带 file:// 前缀；自动转文件 URI，utd 优先用显式指定值，否则按扩展名匹配） */
  static shareFile(title: string, path: string, onFailure: (message: string) => void,
    utdId: string = ''): void {
    try {
      const realPath: string = FileUtils.normalizePath(path);
      if (realPath.length === 0) {
        onFailure('文件路径无效');
        return;
      }
      const record: systemShare.SharedRecord = ShareUtils.fileRecord(title, realPath, utdId);
      ShareUtils.launch(new systemShare.SharedData(record), false, onFailure);
    } catch (e) {
      onFailure('打开分享面板失败');
    }
  }

  /** 构造当前歌曲的跨设备分享数据（碰一碰/隔空手势直达，不拉面板）：本地歌曲→音频文件记录；网络歌曲→歌曲标记临时 txt 文件（接收端解析标记直接播放）。utd 按扩展名推导具体类型（抽象父类型如 general.text 会校验失败） */
  static buildMusicShare(item: MusicItem): MusicShareData {
    const r = new MusicShareData();
    const localPath = MediaUtils.getLocalPath(item);
    if (localPath !== null && localPath.length > 0 && !localPath.startsWith('content://')) {
      try {
        const realPath: string = FileUtils.normalizePath(localPath);
        if (realPath.length > 0 && FileUtils.exists(realPath)) {
          r.data = new systemShare.SharedData(ShareUtils.fileRecord(item.title, realPath));
          return r;
        }
      } catch (e) {
        // 本地文件不可用，回落临时 txt
      }
    }
    try {
      const dir: string = PathConst.cachePath + 'songshare/';
      FileUtils.checkAndCreateDir(dir);
      const tempPath: string = dir + FileUtils.escapeCharacter(item.title) + '-' + Date.now() + '.mfsong';
      const payload = new SharedSongPayload();
      payload.platform = item.platform;
      payload.id = item.id;
      payload.title = item.title;
      payload.artist = item.artist;
      const text = '「' + item.title + '」 - ' + item.artist + '（来自 ' + item.platform + '）' +
        '\n' + MUSICFREE_SONG_MARK + JSON.stringify(payload);
      if (!FileUtils.writeFileText(tempPath, text)) {
        return r;
      }
      r.tempPath = tempPath;
      r.data = new systemShare.SharedData(ShareUtils.fileRecord(item.title, tempPath, SONG_UTD));
    } catch (e) {
      r.tempPath = '';
      r.data = null;
    }
    return r;
  }

  /** 构造歌单分享文件（歌单元数据+全曲目；多歌单合并为一个 json），返回临时文件路径（失败返回空串） */
  static buildSheetsShare(title: string, sheets: Array<SheetItem>): string {
    try {
      const arr: Array<JsonRecord> = [];
      for (const sheet of sheets) {
        const entry = new SheetBackupEntry();
        entry.sheet = sheet;
        entry.musicList = musicSheet.getMusicList(sheet.id);
        arr.push(entry.toRecord());
      }
      const rec: JsonRecord = {
        'musicfreeSheets': arr
      };
      const dir: string = PathConst.cachePath + 'sheetshare/';
      FileUtils.checkAndCreateDir(dir);
      const path: string = dir + FileUtils.escapeCharacter(title) + '-' + Date.now() + '.mfsheets';
      if (!FileUtils.writeFileText(path, JSON.stringify(rec))) {
        return '';
      }
      return path;
    } catch (e) {
      return '';
    }
  }

  /** 分享歌单：导出为可导入的 json 文件经系统分享面板发出（接收端 MusicFreeOH 打开后自动导入） */
  static shareSheets(title: string, sheets: Array<SheetItem>, onFailure: (message: string) => void): void {
    if (sheets.length === 0) {
      onFailure('没有可分享的歌单');
      return;
    }
    const path: string = ShareUtils.buildSheetsShare(title, sheets);
    if (path.length === 0) {
      onFailure('生成歌单分享文件失败');
      return;
    }
    ShareUtils.shareFile(title, path, onFailure, SHEETS_UTD);
  }

  /** 清理网络歌曲分享临时文件（发送完成/失败后调用） */
  static cleanupMusicShare(tempPath: string): void {
    if (tempPath.length > 0) {
      FileUtils.unlink(tempPath);
    }
  }

  /** 构造插件分享临时文件（复制插件 js 为 .mfplugin，接收端直达安装），失败返回空串 */
  static buildPluginShare(name: string, srcPath: string): string {
    try {
      const dir: string = PathConst.cachePath + 'pluginshare/';
      FileUtils.checkAndCreateDir(dir);
      const path: string = dir + FileUtils.escapeCharacter(name) + '-' + Date.now() + '.mfplugin';
      if (!FileUtils.copyFile(srcPath, path)) {
        return '';
      }
      return path;
    } catch (e) {
      return '';
    }
  }

  /** 构造插件源地址分享临时文件（本地文件缺失时回落：内容为插件 URL，接收端从 URL 安装），失败返回空串 */
  static buildPluginUrlShare(name: string, url: string): string {
    return ShareUtils.buildNamedTextShare('pluginshare/', name, url, '.mfplugin');
  }

  /** 构造订阅源分享临时文件（内容为订阅源 URL 或源 json 文本，接收端直达导入），失败返回空串 */
  static buildSubscriptionShare(title: string, content: string): string {
    return ShareUtils.buildNamedTextShare('subshare/', title, content, '.mfsub');
  }

  /** 分享单个插件（优先本地 js 文件；本地文件缺失回落插件源地址），均失败回调 onFailure */
  static sharePlugin(name: string, srcPath: string, srcUrl: string,
    onFailure: (message: string) => void): void {
    if (srcPath.length > 0 && FileUtils.exists(srcPath)) {
      const path: string = ShareUtils.buildPluginShare(name, srcPath);
      if (path.length > 0) {
        ShareUtils.shareFile(name, path, onFailure, PLUGIN_UTD);
        return;
      }
    }
    if (srcUrl.startsWith('http://') || srcUrl.startsWith('https://')) {
      const path: string = ShareUtils.buildPluginUrlShare(name, srcUrl);
      if (path.length > 0) {
        ShareUtils.shareFile(name, path, onFailure, PLUGIN_UTD);
        return;
      }
    }
    onFailure('插件文件不存在');
  }

  /** 分享订阅源（内容为源 URL 或本地源 json 文本），失败回调 onFailure */
  static shareSubscription(title: string, content: string,
    onFailure: (message: string) => void): void {
    if (content.trim().length === 0) {
      onFailure('订阅源内容为空');
      return;
    }
    const path: string = ShareUtils.buildSubscriptionShare(title, content);
    if (path.length === 0) {
      onFailure('生成订阅源分享文件失败');
      return;
    }
    ShareUtils.shareFile(title, path, onFailure, SUB_UTD);
  }

  /** 写入命名的临时分享文本文件，失败返回空串 */
  private static buildNamedTextShare(dirRel: string, name: string, content: string,
    ext: string): string {
    try {
      const dir: string = PathConst.cachePath + dirRel;
      FileUtils.checkAndCreateDir(dir);
      const path: string = dir + FileUtils.escapeCharacter(name) + '-' + Date.now() + ext;
      if (!FileUtils.writeFileText(path, content)) {
        return '';
      }
      return path;
    } catch (e) {
      return '';
    }
  }

  /** 构造文件分享记录（utd 优先用显式指定值，否则按扩展名匹配精确 UTD，失败回落通用文件类型） */
  private static fileRecord(title: string, realPath: string, utdId: string = ''): systemShare.SharedRecord {
    const record: systemShare.SharedRecord = {
      utd: utdId.length > 0 ? utdId : ShareUtils.utdOfPath(realPath),
      uri: fileUri.getUriFromPath(realPath),
      title: title,
      label: '文件'
    };
    return record;
  }

  /** 按扩展名推断精确 UTD 类型（不限定归属类型，兼容带点/不带点两种写法；失败回落通用文件类型，不抛异常） */
  private static utdOfPath(path: string): string {
    const dot: number = path.lastIndexOf('.');
    const slash: number = path.lastIndexOf('/');
    if (dot > slash && dot < path.length - 1) {
      const ext: string = path.substring(dot + 1);
      const forms: Array<string> = ['.' + ext, ext];
      for (const form of forms) {
        try {
          const typeId: string = utd.getUniformDataTypeByFilenameExtension(form);
          if (typeId.length > 0) {
            return typeId;
          }
        } catch (e) {
          // 换下一种写法重试
        }
      }
    }
    return utd.UniformDataType.FILE;
  }

  /** 拉起系统分享面板（文本/链接推荐卡片预览模式）；构造或拉起异常统一走 onFailure，不崩溃 */
  private static launch(data: systemShare.SharedData, batch: boolean,
    onFailure: (message: string) => void): void {
    try {
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      const options: systemShare.ShareControllerOptions = {
        selectionMode: batch ? systemShare.SelectionMode.BATCH : systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT
      };
      controller.show(ContextHolder.get(), options).catch((_e: Object): void => {
        onFailure('打开分享面板失败');
      });
    } catch (e) {
      onFailure('打开分享面板失败');
    }
  }
}
