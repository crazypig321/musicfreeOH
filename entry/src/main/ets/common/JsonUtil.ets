/**
 * JSON 工具（ArkTS 下集中管理 JSON.parse 的类型转换）
 * Record<string, Object | null> 是插件/JSON 数据的通用承载类型
 */

export type JsonRecord = Record<string, Object | null>;
export type JsonArray = Array<JsonRecord>;

export class JsonUtil {
  /** 解析任意 JSON 值（对象/数组/标量），失败返回 null */
  static parseAny(raw: string | null | undefined): Object | null {
    if (raw === null || raw === undefined || raw.length === 0) {
      return null;
    }
    try {
      const v: Object | null = JSON.parse(raw);
      return v;
    } catch (e) {
      return null;
    }
  }

  /** 解析为对象 Record，失败返回 null */
  static parseRecord(raw: string | null | undefined): JsonRecord | null {
    if (raw === null || raw === undefined || raw.length === 0) {
      return null;
    }
    try {
      const v: Object | null = JSON.parse(raw);
      if (typeof v === 'object' && v !== null && !Array.isArray(v)) {
        return v as JsonRecord;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /** 解析为 Record 数组，失败返回 null */
  static parseRecordArray(raw: string | null | undefined): JsonArray | null {
    if (raw === null || raw === undefined || raw.length === 0) {
      return null;
    }
    try {
      const v: Object | null = JSON.parse(raw);
      if (typeof v === 'object' && v !== null && Array.isArray(v)) {
        return v as JsonArray;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /** 解析为字符串，失败返回 null */
  static parseString(raw: string | null | undefined): string | null {
    if (raw === null || raw === undefined || raw.length === 0) {
      return null;
    }
    try {
      const v: Object | null = JSON.parse(raw);
      if (typeof v === 'string') {
        return v;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /** 解析为数字，失败返回 null */
  static parseNumber(raw: string | null | undefined): number | null {
    if (raw === null || raw === undefined || raw.length === 0) {
      return null;
    }
    try {
      const v: Object | null = JSON.parse(raw);
      if (typeof v === 'number') {
        return v;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /** 解析为布尔值，失败返回 null */
  static parseBoolean(raw: string | null | undefined): boolean | null {
    if (raw === null || raw === undefined || raw.length === 0) {
      return null;
    }
    try {
      const v: Object | null = JSON.parse(raw);
      if (typeof v === 'boolean') {
        return v;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static safeStringify(v: Object | null): string {
    try {
      return JSON.stringify(v);
    } catch (e) {
      return '';
    }
  }

  // ---------- Record 字段提取 ----------

  static recStr(rec: JsonRecord, key: string, def: string = ''): string {
    const v: Object | null = rec[key];
    if (typeof v === 'string') {
      return v;
    }
    if (typeof v === 'number' || typeof v === 'boolean') {
      return String(v);
    }
    return def;
  }

  static recNum(rec: JsonRecord, key: string, def: number = 0): number {
    const v: Object | null = rec[key];
    if (typeof v === 'number') {
      return v;
    }
    if (typeof v === 'string') {
      const n = Number(v);
      if (!Number.isNaN(n)) {
        return n;
      }
    }
    return def;
  }

  static recBool(rec: JsonRecord, key: string, def: boolean = false): boolean {
    const v: Object | null = rec[key];
    if (typeof v === 'boolean') {
      return v;
    }
    if (typeof v === 'string') {
      return v === 'true';
    }
    return def;
  }

  /** 取嵌套 Record */
  static recRecord(rec: JsonRecord, key: string): JsonRecord | null {
    const v: Object | null = rec[key];
    return JsonUtil.objToRecord(v);
  }

  /** 取嵌套数组（元素为 Object） */
  static recArray(rec: JsonRecord, key: string): Array<Object> | null {
    const v: Object | null = rec[key];
    if (typeof v === 'object' && v !== null && Array.isArray(v)) {
      return v as Array<Object>;
    }
    return null;
  }

  static objToRecord(v: Object | null | undefined): JsonRecord | null {
    if (typeof v === 'object' && v !== null && !Array.isArray(v)) {
      return v as JsonRecord;
    }
    return null;
  }

  static objToRecordArray(v: Object | null | undefined): JsonArray | null {
    if (typeof v === 'object' && v !== null && Array.isArray(v)) {
      return v as JsonArray;
    }
    return null;
  }

  /** 过滤掉已知字段，返回剩余字段组成的 Record */
  static filterOutKnown(rec: JsonRecord, known: Array<string>): JsonRecord {
    const knownSet: Set<string> = new Set<string>(known);
    const extras: JsonRecord = {};
    for (const k of Object.keys(rec)) {
      if (!knownSet.has(k)) {
        extras[k] = rec[k];
      }
    }
    return extras;
  }

  /** 浅拷贝 Record */
  static cloneRecord(rec: JsonRecord): JsonRecord {
    const out: JsonRecord = {};
    for (const k of Object.keys(rec)) {
      out[k] = rec[k];
    }
    return out;
  }

  /** 过滤掉指定字段后重建 Record（ArkTS 无 delete，用重建实现） */
  static omitKeys(rec: JsonRecord, keys: Array<string>): JsonRecord {
    const omitSet: Set<string> = new Set<string>(keys);
    const out: JsonRecord = {};
    for (const k of Object.keys(rec)) {
      if (!omitSet.has(k)) {
        out[k] = rec[k];
      }
    }
    return out;
  }

  /** Record<string, string> 转 JsonRecord */
  static fromStringMap(map: Record<string, string>): JsonRecord {
    const out: JsonRecord = {};
    for (const k of Object.keys(map)) {
      out[k] = map[k];
    }
    return out;
  }

  /** JsonRecord 转 Record<string, string>（仅保留字符串值） */
  static toStringMap(rec: JsonRecord | null): Record<string, string> {
    const out: Record<string, string> = {};
    if (rec === null) {
      return out;
    }
    for (const k of Object.keys(rec)) {
      const v = rec[k];
      if (typeof v === 'string') {
        out[k] = v;
      }
    }
    return out;
  }
}
