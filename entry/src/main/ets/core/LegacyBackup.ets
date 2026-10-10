import { JsonUtil, JsonRecord, JsonArray } from '../utils/JsonUtil';
import { LOCAL_PLUGIN_PLATFORM, FAVORITE_SHEET_ID, FAVORITE_SHEET_TITLE } from '../common/Consts';

/**
 * 原版 MusicFree 备份识别与转换
 * 原版结构（format=musicfree-backup，version 2）：
 *   { format, version, createdAt, origin, sections: { musicSheets, plugins, settings, ... } }
 * 转换目标为 musicfreeOH 备份结构：
 *   { musicSheets, plugins, appConfig, subscriptions }
 */
export class LegacyBackup {
  static readonly FORMAT: string = 'musicfree-backup';

  /** 是否为原版备份 Record */
  static isLegacyRecord(obj: JsonRecord | null): boolean {
    return obj !== null && JsonUtil.recStr(obj, 'format') === LegacyBackup.FORMAT;
  }

  /** 转换为 musicfreeOH 备份 Record；非原版备份或缺 sections 返回 null */
  static convert(raw: string): JsonRecord | null {
    const obj = JsonUtil.parseRecord(raw);
    if (obj === null || !LegacyBackup.isLegacyRecord(obj)) {
      return null;
    }
    const sections = JsonUtil.recRecord(obj, 'sections');
    if (sections === null) {
      return null;
    }
    const out: JsonRecord = {};
    out['musicSheets'] = LegacyBackup.convertSheets(sections);
    LegacyBackup.convertPlugins(sections, out);
    LegacyBackup.convertSettings(sections, out);
    return out;
  }

  /**
   * musicSheets: {id,title,createdAt,sortMode,musicList[]} -> [{sheet:{},musicList:[]}]
   * 默认歌单（favorite）标题为空时映射为「我的收藏」，恢复时按标题合并进本地默认歌单
   */
  private static convertSheets(sections: JsonRecord): JsonArray {
    const result: JsonArray = [];
    const sheets = JsonUtil.recArray(sections, 'musicSheets');
    if (sheets === null) {
      return result;
    }
    for (const o of sheets) {
      const rec = JsonUtil.objToRecord(o);
      if (rec === null) {
        continue;
      }
      const id = JsonUtil.recStr(rec, 'id');
      let title = JsonUtil.recStr(rec, 'title');
      if (id === FAVORITE_SHEET_ID && title.length === 0) {
        title = FAVORITE_SHEET_TITLE;
      }
      const sheetRec: JsonRecord = {
        'id': id,
        'platform': LOCAL_PLUGIN_PLATFORM,
        'title': title,
      };
      const createdAt = JsonUtil.recNum(rec, 'createdAt');
      if (createdAt > 0) {
        sheetRec['createAt'] = createdAt;
      }
      const musicList: JsonArray = [];
      const listRaw = JsonUtil.recArray(rec, 'musicList');
      if (listRaw !== null) {
        for (const m of listRaw) {
          const mRec = JsonUtil.objToRecord(m);
          if (mRec !== null) {
            // 曲目字段原样保留：已知字段强类型解析，songmid/strMediaMid 等插件字段自动收入 extras
            musicList.push(JsonUtil.cloneRecord(mRec));
          }
        }
      }
      const entry: JsonRecord = { 'sheet': sheetRec, 'musicList': musicList };
      result.push(entry);
    }
    return result;
  }

  /**
   * plugins: {installed:[{srcUrl,version}],subscriptions:[{name,url}]}
   * -> plugins:[{srcUrl,version}] + subscriptions:{sources:[],names:{}}
   */
  private static convertPlugins(sections: JsonRecord, out: JsonRecord): void {
    const plugins: JsonArray = [];
    const sources: Array<string> = [];
    const names: JsonRecord = {};
    const pluginsSec = JsonUtil.recRecord(sections, 'plugins');
    if (pluginsSec !== null) {
      const installed = JsonUtil.recArray(pluginsSec, 'installed');
      if (installed !== null) {
        for (const o of installed) {
          const rec = JsonUtil.objToRecord(o);
          if (rec === null) {
            continue;
          }
          let srcUrl = JsonUtil.recStr(rec, 'srcUrl');
          if (srcUrl.length === 0) {
            srcUrl = JsonUtil.recStr(rec, 'url');
          }
          if (srcUrl.length === 0) {
            continue;
          }
          const version = JsonUtil.recStr(rec, 'version', '0.0.1');
          const p: JsonRecord = { 'srcUrl': srcUrl, 'version': version };
          plugins.push(p);
        }
      }
      const subs = JsonUtil.recArray(pluginsSec, 'subscriptions');
      if (subs !== null) {
        for (const o of subs) {
          const rec = JsonUtil.objToRecord(o);
          if (rec === null) {
            continue;
          }
          const url = JsonUtil.recStr(rec, 'url');
          if (url.length === 0) {
            continue;
          }
          sources.push(url);
          const name = JsonUtil.recStr(rec, 'name');
          if (name.length > 0) {
            names[url] = name;
          }
        }
      }
    }
    out['plugins'] = plugins;
    const subscriptions: JsonRecord = { 'sources': sources };
    if (Object.keys(names).length > 0) {
      subscriptions['names'] = names;
    }
    out['subscriptions'] = subscriptions;
  }

  /** settings: {values:{k:v}} -> appConfig:{k:v}（布尔/数字转字符串，键名两端一致） */
  private static convertSettings(sections: JsonRecord, out: JsonRecord): void {
    const settingsSec = JsonUtil.recRecord(sections, 'settings');
    if (settingsSec === null) {
      return;
    }
    const values = JsonUtil.recRecord(settingsSec, 'values');
    if (values === null) {
      return;
    }
    const appConfigRec: JsonRecord = {};
    for (const key of Object.keys(values)) {
      const v: Object | null = values[key];
      if (typeof v === 'string') {
        appConfigRec[key] = v;
      } else if (typeof v === 'number' || typeof v === 'boolean') {
        appConfigRec[key] = String(v);
      }
    }
    out['appConfig'] = appConfigRec;
  }
}
