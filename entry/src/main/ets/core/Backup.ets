import { JsonUtil, JsonRecord } from '../utils/JsonUtil';
import { ResumeMode } from '../common/Consts';
import { musicSheet, SheetBackupEntry, backupEntriesFromRecord } from './MusicSheet';
import { pluginManager } from '../plugin/PluginManager';
import { Plugin } from '../plugin/Plugin';
import { Subscriptions } from '../plugin/Subscriptions';
import { appConfig } from './AppConfig';
import { VersionCompare } from '../utils/VersionCompare';
import { LegacyBackup } from './LegacyBackup';
import { PathConst } from '../common/PathConst';
import { FileUtils } from '../utils/FileUtils';
import { Log } from '../utils/Log';

/**
 * 备份与恢复（移植自 core/backup.ts）
 * 结果：一份大的 json 文件 { musicSheets: [], plugins: [], appConfig: {}, subscriptions: {}, pluginFiles: {} }
 * - plugins：全部插件（含禁用）的 {srcUrl, version}
 * - pluginFiles：无 srcUrl 插件（本地导入）的源码内嵌（文件名 -> 源码），恢复时重新安装
 * - resume 自动识别原版 MusicFree 备份（format=musicfree-backup）并转换
 */
export class Backup {
  /** 生成备份 JSON 字符串 */
  static backup(): string {
    const musicSheets = musicSheet.backupSheets();
    const plugins = pluginManager.getPlugins();

    const sheetRecs: Array<JsonRecord> = [];
    for (const entry of musicSheets) {
      sheetRecs.push(entry.toRecord());
    }

    const pluginRecs: Array<JsonRecord> = [];
    for (const p of plugins) {
      const rec: JsonRecord = {};
      const info = p.instanceInfo;
      rec['srcUrl'] = info === null ? '' : info.srcUrl;
      rec['version'] = info === null ? '' : info.version;
      pluginRecs.push(rec);
    }

    const out: JsonRecord = {
      'musicSheets': sheetRecs,
      'plugins': pluginRecs,
      'appConfig': appConfig.exportSettings(),
      'subscriptions': Subscriptions.exportData(),
    };
    const pluginFiles = Backup.collectLocalPluginFiles(plugins);
    if (pluginFiles !== null) {
      out['pluginFiles'] = pluginFiles;
    }
    return JsonUtil.safeStringify(out);
  }

  /** 收集无 srcUrl 插件（含禁用）的源码：文件名 -> 源码；无可内嵌内容返回 null */
  private static collectLocalPluginFiles(plugins: Array<Plugin>): JsonRecord | null {
    const files: Record<string, string> = {};
    for (const p of plugins) {
      const info = p.instanceInfo;
      const srcUrl = info === null ? '' : info.srcUrl;
      if (srcUrl.length > 0) {
        continue;
      }
      if (p.path.length === 0 || !p.path.endsWith('.js')) {
        continue;
      }
      const fileName = FileUtils.getFileName(p.path);
      if (fileName.length === 0) {
        continue;
      }
      const content = FileUtils.readFileText(p.path);
      if (content === null || content.length === 0) {
        continue;
      }
      files[fileName] = content;
    }
    if (Object.keys(files).length === 0) {
      return null;
    }
    return JsonUtil.fromStringMap(files);
  }

  /**
   * 从备份数据恢复（自动识别 musicfreeOH 备份与原版 MusicFree 备份，原版备份自动转换）
   * - 插件：同源且本地版本更高则忽略；本地插件源码重新安装（同 hash 去重）
   * - 歌单：按 resumeMode 合并
   */
  static async resume(raw: string, resumeMode: ResumeMode = ResumeMode.Append): Promise<void> {
    let obj = JsonUtil.parseRecord(raw);
    if (obj === null) {
      throw new Error('备份文件格式无效');
    }
    if (LegacyBackup.isLegacyRecord(obj)) {
      const converted = LegacyBackup.convert(raw);
      if (converted === null) {
        throw new Error('原版备份转换失败');
      }
      obj = converted;
    }
    await Backup.resumeFromRecord(obj, resumeMode);
  }

  private static async resumeFromRecord(obj: JsonRecord, resumeMode: ResumeMode): Promise<void> {
    const validPlugins = pluginManager.getPlugins();

    const resumePluginTasks: Array<Promise<void>> = [];
    let stageDir = '';

    // 本地插件源码：写入缓存暂存后逐个安装（串行避免并发注册丢失；同 hash 静默去重，
    // 本地版本更高时不降级），单个失败不影响其余数据恢复
    const pluginFilesRec = JsonUtil.objToRecord(obj['pluginFiles']);
    if (pluginFilesRec !== null) {
      stageDir = PathConst.cachePath + 'plugin_restore_' + Date.now().toString() + '/';
      let fileInstallChain: Promise<void> = Promise.resolve();
      for (const name of Object.keys(pluginFilesRec)) {
        const content = JsonUtil.recStr(pluginFilesRec, name);
        if (content.length === 0) {
          continue;
        }
        const safeName = name.endsWith('.js') ? name : name + '.js';
        const stagePath = stageDir + safeName;
        if (!FileUtils.writeFileText(stagePath, content)) {
          continue;
        }
        fileInstallChain = fileInstallChain.then((): Promise<void> => {
          return pluginManager.installPluginFromLocalFile(stagePath).then((): void => {
          }).catch((e: Object): void => {
            Log.error('恢复本地插件失败: ' + (e instanceof Error ? e.message : ''));
          });
        });
      }
      resumePluginTasks.push(fileInstallChain);
    }

    // URL 插件：同源且本地版本更高则忽略；单个下载失败不影响其余数据恢复
    const pluginArr = JsonUtil.recArray(obj, 'plugins');
    if (pluginArr !== null) {
      for (const o of pluginArr) {
        const rec = JsonUtil.objToRecord(o);
        if (rec === null) {
          continue;
        }
        const srcUrl = JsonUtil.recStr(rec, 'srcUrl');
        const version = JsonUtil.recStr(rec, 'version', '0.0.1');
        if (srcUrl.length === 0) {
          continue;
        }
        let skip = false;
        for (const vp of validPlugins) {
          const info = vp.instanceInfo;
          if (info === null) {
            continue;
          }
          const localVersion = info.version.length > 0 ? info.version : '0.0.0';
          if (info.srcUrl === srcUrl && VersionCompare.compare(localVersion, version) >= 0) {
            skip = true;
            break;
          }
        }
        if (skip) {
          continue;
        }
        resumePluginTasks.push(
          pluginManager.installPluginFromUrl(srcUrl).then((): void => {
          }).catch((e: Object): void => {
            Log.error('从备份恢复插件失败: ' + srcUrl + ' 原因: ' + (e instanceof Error ? e.message : ''));
          })
        );
      }
    }

    const entries: Array<SheetBackupEntry> = backupEntriesFromRecord(obj['musicSheets']);
    const resumeMusicSheets: Promise<void> = musicSheet.resumeSheets(entries, resumeMode);

    // 设置参数（旧备份无此字段时跳过；不覆盖 WebDAV 账密）
    const settingsRec = JsonUtil.objToRecord(obj['appConfig']);
    if (settingsRec !== null) {
      const settings: Record<string, string> = {};
      for (const key of Object.keys(settingsRec)) {
        settings[key] = JsonUtil.recStr(settingsRec, key);
      }
      appConfig.importSettings(settings);
    }

    // 订阅源（旧备份无此字段时跳过；合并去重）
    const subsRec = JsonUtil.objToRecord(obj['subscriptions']);
    if (subsRec !== null) {
      Subscriptions.importData(subsRec);
    }

    await Promise.all(resumePluginTasks.concat([resumeMusicSheets]));
    if (stageDir.length > 0) {
      FileUtils.removeDir(stageDir);
    }
  }
}
