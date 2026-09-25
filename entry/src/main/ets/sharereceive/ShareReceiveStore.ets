import common from '@ohos.app.ability.common';
import { UIExtensionContentSession, Want, bundleManager } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { PathConst } from '../common/PathConst';
import { FileUtils } from '../utils/FileUtils';

/** 分享详情页预览条目（文件或文本） */
export class SharedPreviewItem {
  isFile: boolean = false;
  name: string = '';
  /** 文件记录的临时 URI（仅 isFile 时有效） */
  uri: string = '';
  /** 文本记录内容（仅非文件时有效） */
  content: string = '';
}

/**
 * 分享接收暂存（运行在分享扩展进程中，与主应用同 bundle 共享同一沙箱）：
 * 确认导入后把收到的文件/文本复制进 filesDir 暂存目录，再拉起主应用 EntryAbility 完成导入
 */
export class ShareReceiveStore {
  private static context: common.UIExtensionContext | null = null;
  private static session: UIExtensionContentSession | null = null;
  private static items: Array<SharedPreviewItem> = [];

  /** 扩展 onSessionCreate：解析分享记录生成预览条目 */
  static open(context: common.UIExtensionContext, session: UIExtensionContentSession,
    records: Array<systemShare.SharedRecord>): void {
    ShareReceiveStore.context = context;
    ShareReceiveStore.session = session;
    ShareReceiveStore.items = [];
    for (const record of records) {
      const item = new SharedPreviewItem();
      if (record.uri !== undefined && record.uri.length > 0) {
        item.isFile = true;
        item.uri = record.uri;
        item.name = ShareReceiveStore.nameOfUri(record.uri, record.title);
      } else if (record.content !== undefined && record.content.length > 0) {
        item.isFile = false;
        item.content = record.content;
        item.name = ShareReceiveStore.nameOfText(record.content);
      } else {
        continue;
      }
      ShareReceiveStore.items.push(item);
    }
  }

  static hasItems(): boolean {
    return ShareReceiveStore.items.length > 0;
  }

  static getItems(): Array<SharedPreviewItem> {
    return ShareReceiveStore.items;
  }

  /** 确认导入：文件复制进暂存目录、文本写入 .mftxt，成功后拉起主应用并关闭面板 */
  static confirm(onDone: (ok: boolean, message: string) => void): void {
    const context = ShareReceiveStore.context;
    const session = ShareReceiveStore.session;
    if (context === null || session === null) {
      onDone(false, '会话已失效');
      return;
    }
    const pendingDir = context.filesDir + PathConst.SHARE_RECEIVED_REL;
    FileUtils.checkAndCreateDir(pendingDir);
    let successCount = 0;
    let index = 0;
    for (const item of ShareReceiveStore.items) {
      if (item.isFile) {
        const dest = pendingDir + ShareReceiveStore.uniqueName(pendingDir, item.name, index);
        if (ShareReceiveStore.copyTo(item.uri, dest)) {
          successCount++;
        }
      } else {
        const dest = pendingDir + 'text_' + Date.now().toString() + '_' + index.toString() + '.mftxt';
        if (FileUtils.writeFileText(dest, item.content)) {
          successCount++;
        }
      }
      index++;
    }
    if (successCount === 0) {
      onDone(false, '接收内容失败，请重试');
      return;
    }
    ShareReceiveStore.startMainApp(context).then((): void => {
      session.terminateSelf();
    }).catch((_e: Object): void => {
      // 主应用拉起失败：内容已暂存，下次打开应用时仍会自动导入
      onDone(true, '已接收，打开 MusicFreeOH 后自动导入');
    });
  }

  /** 取消导入（未写入暂存，直接关闭） */
  static cancel(): void {
    const session = ShareReceiveStore.session;
    if (session !== null) {
      session.terminateSelf();
    }
  }

  static clear(): void {
    ShareReceiveStore.context = null;
    ShareReceiveStore.session = null;
    ShareReceiveStore.items = [];
  }

  private static startMainApp(context: common.UIExtensionContext): Promise<void> {
    const bundleName = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).name;
    const params: Record<string, Object> = { 'mfShareImport': 'true' };
    const want: Want = {
      deviceId: '',
      bundleName: bundleName,
      abilityName: 'EntryAbility',
      parameters: params
    };
    return context.startAbility(want);
  }

  /** 复制分享 URI 到暂存路径（面板会话存活期间拥有临时读权限） */
  private static copyTo(uri: string, dest: string): boolean {
    try {
      const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const dst = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.copyFileSync(src.fd, dst.fd);
      } finally {
        fs.closeSync(dst);
        fs.closeSync(src);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 从 URI 提取展示名（去 query 取最后一段；空则用标题或兜底名） */
  private static nameOfUri(uri: string, title?: string): string {
    const clean = uri.split('?')[0];
    const idx = clean.lastIndexOf('/');
    const name = idx === -1 ? clean : clean.substring(idx + 1);
    if (name.length > 0) {
      return name;
    }
    if (title !== undefined && title.length > 0) {
      return title;
    }
    return '未命名文件';
  }

  /** 文本记录展示名：取首行并截断 */
  private static nameOfText(content: string): string {
    const firstLine = content.trim().split('\n')[0].trim();
    if (firstLine.length === 0) {
      return '文本';
    }
    return firstLine.length > 30 ? firstLine.substring(0, 30) + '…' : firstLine;
  }

  /** 暂存文件重名时追加序号 */
  private static uniqueName(pendingDir: string, name: string, index: number): string {
    const escaped = FileUtils.escapeCharacter(name);
    const finalName = escaped.length > 0 ? escaped : 'file_' + index.toString();
    if (!FileUtils.exists(pendingDir + finalName)) {
      return finalName;
    }
    const dot = finalName.lastIndexOf('.');
    if (dot > 0 && dot < finalName.length - 1) {
      return finalName.substring(0, dot) + '_' + index.toString() + finalName.substring(dot);
    }
    return finalName + '_' + index.toString();
  }
}
