import { JsonUtil, JsonRecord } from '../common/JsonUtil';
import { ResumeMode } from '../common/Consts';
import { musicSheet, SheetBackupEntry, backupEntriesFromRecord } from './MusicSheet';
import { pluginManager } from '../plugin/PluginManager';
import { VersionCompare } from '../utils/VersionCompare';

/**
 * 备份与恢复（移植自 core/backup.ts）
 * 结果：一份大的 json 文件 { musicSheets: [], plugins: [] }
 */
export class Backup {
  /** 生成备份 JSON 字符串 */
  static backup(): string {
    const musicSheets = musicSheet.backupSheets();
    const plugins = pluginManager.getEnabledPlugins();

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
    };
    return JsonUtil.safeStringify(out);
  }

  /**
   * 从备份数据恢复
   * - 插件：同源且本地版本更高则忽略
   * - 歌单：按 resumeMode 合并
   */
  static async resume(raw: string, resumeMode: ResumeMode = ResumeMode.Append): Promise<void> {
    const obj = JsonUtil.parseRecord(raw);
    if (obj === null) {
      throw new Error('备份文件格式无效');
    }

    const validPlugins = pluginManager.getEnabledPlugins();

    const resumePluginTasks: Array<Promise<void>> = [];
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
          })
        );
      }
    }

    const entries: Array<SheetBackupEntry> = backupEntriesFromRecord(obj['musicSheets']);
    const resumeMusicSheets: Promise<void> = musicSheet.resumeSheets(entries, resumeMode);

    await Promise.all(resumePluginTasks.concat([resumeMusicSheets]));
  }
}
