/**
 * 版本比较（移植自 compare-versions 的 compare/satisfies 子集）
 * - compare(v1, v2): 返回 1 / 0 / -1
 * - compareWith(v1, v2, operator): 支持 > >= < <= = ==
 * - satisfies(version, range): 支持 || (OR)、空格/逗号 (AND)、> >= < <= = ^ ~ * x
 */

export class VersionCompare {
  /** 解析版本号为数字数组（每段取前导数字，无法解析按 0） */
  private static parseParts(v: string): Array<number> {
    const parts: Array<number> = [];
    const segs = v.split('.');
    for (const seg of segs) {
      let digits = '';
      for (let i = 0; i < seg.length; ++i) {
        const ch = seg.charAt(i);
        if (ch >= '0' && ch <= '9') {
          digits += ch;
        } else {
          break;
        }
      }
      parts.push(digits.length === 0 ? 0 : Number(digits));
    }
    if (parts.length === 0) {
      parts.push(0);
    }
    return parts;
  }

  /** 比较两个版本号：v1 > v2 返回 1，相等返回 0，否则 -1 */
  static compare(v1: string, v2: string): number {
    const a = VersionCompare.parseParts(v1);
    const b = VersionCompare.parseParts(v2);
    const len = Math.max(a.length, b.length);
    for (let i = 0; i < len; ++i) {
      const x = i < a.length ? a[i] : 0;
      const y = i < b.length ? b[i] : 0;
      if (x > y) {
        return 1;
      }
      if (x < y) {
        return -1;
      }
    }
    return 0;
  }

  /** 带操作符比较 */
  static compareWith(v1: string, v2: string, operator: string): boolean {
    const r = VersionCompare.compare(v1, v2);
    if (operator === '>') {
      return r > 0;
    }
    if (operator === '>=') {
      return r >= 0;
    }
    if (operator === '<') {
      return r < 0;
    }
    if (operator === '<=') {
      return r <= 0;
    }
    if (operator === '=' || operator === '==') {
      return r === 0;
    }
    return false;
  }

  /** v1 > v2 */
  static gt(v1: string, v2: string): boolean {
    return VersionCompare.compare(v1, v2) > 0;
  }

  /**
   * 判断版本是否满足范围表达式
   * 例：">=0.0.1"、"^1.2.3"、"~2.1"、"*"、">=1.0.0 <2.0.0 || >=3.0.0"
   */
  static satisfies(version: string, range: string): boolean {
    const groups = range.split('||');
    for (const group of groups) {
      if (VersionCompare.satisfiesGroup(version, group)) {
        return true;
      }
    }
    return false;
  }

  private static satisfiesGroup(version: string, group: string): boolean {
    const conditions = VersionCompare.splitConditions(group);
    if (conditions.length === 0) {
      // 空范围等同 *
      return true;
    }
    for (const cond of conditions) {
      if (!VersionCompare.satisfiesCondition(version, cond)) {
        return false;
      }
    }
    return true;
  }

  /** 按空格/逗号切分条件 */
  private static splitConditions(group: string): Array<string> {
    const result: Array<string> = [];
    let current = '';
    for (let i = 0; i < group.length; ++i) {
      const ch = group.charAt(i);
      if (ch === ' ' || ch === ',') {
        if (current.length > 0) {
          result.push(current);
          current = '';
        }
      } else {
        current += ch;
      }
    }
    if (current.length > 0) {
      result.push(current);
    }
    return result;
  }

  private static satisfiesCondition(version: string, cond: string): boolean {
    if (cond === '*' || cond === 'x' || cond === 'X') {
      return true;
    }
    if (cond.startsWith('>=')) {
      return VersionCompare.compareWith(version, cond.substring(2), '>=');
    }
    if (cond.startsWith('<=')) {
      return VersionCompare.compareWith(version, cond.substring(2), '<=');
    }
    if (cond.startsWith('>')) {
      return VersionCompare.compareWith(version, cond.substring(1), '>');
    }
    if (cond.startsWith('<')) {
      return VersionCompare.compareWith(version, cond.substring(1), '<');
    }
    if (cond.startsWith('^')) {
      return VersionCompare.satisfiesCaret(version, cond.substring(1));
    }
    if (cond.startsWith('~')) {
      return VersionCompare.satisfiesTilde(version, cond.substring(1));
    }
    return VersionCompare.compareWith(version, cond, '=');
  }

  /** ^：不修改最左侧非零数字的前提下允许变化 */
  private static satisfiesCaret(version: string, spec: string): boolean {
    const parts = VersionCompare.parseParts(spec);
    const major = parts[0];
    const minor = parts.length > 1 ? parts[1] : 0;
    if (!VersionCompare.compareWith(version, spec, '>=')) {
      return false;
    }
    if (major > 0) {
      return VersionCompare.ltMajor(version, major);
    }
    if (minor > 0) {
      return VersionCompare.ltMinor(version, minor);
    }
    // ^0.0.x
    const patch = parts.length > 2 ? parts[2] : 0;
    return VersionCompare.ltPatch(version, patch);
  }

  /** ~：只允许补丁位变化 */
  private static satisfiesTilde(version: string, spec: string): boolean {
    const parts = VersionCompare.parseParts(spec);
    if (!VersionCompare.compareWith(version, spec, '>=')) {
      return false;
    }
    if (parts.length === 1) {
      return VersionCompare.ltMajor(version, parts[0]);
    }
    if (parts.length === 2) {
      return VersionCompare.ltMinorOf(version, parts[0], parts[1]);
    }
    return VersionCompare.ltPatchOf(version, parts[0], parts[1], parts[2]);
  }

  private static part(v: Array<number>, idx: number): number {
    return idx < v.length ? v[idx] : 0;
  }

  private static ltMajor(version: string, major: number): boolean {
    const v = VersionCompare.parseParts(version);
    return VersionCompare.part(v, 0) < major;
  }

  private static ltMinor(version: string, minor: number): boolean {
    const v = VersionCompare.parseParts(version);
    if (VersionCompare.part(v, 0) > 0) {
      return false;
    }
    return VersionCompare.part(v, 1) < minor;
  }

  private static ltPatch(version: string, patch: number): boolean {
    const v = VersionCompare.parseParts(version);
    if (VersionCompare.part(v, 0) > 0 || VersionCompare.part(v, 1) > 0) {
      return false;
    }
    return VersionCompare.part(v, 2) < patch;
  }

  private static ltMinorOf(version: string, major: number, minor: number): boolean {
    const v = VersionCompare.parseParts(version);
    if (VersionCompare.part(v, 0) !== major) {
      return false;
    }
    return VersionCompare.part(v, 1) < minor;
  }

  private static ltPatchOf(version: string, major: number, minor: number, patch: number): boolean {
    const v = VersionCompare.parseParts(version);
    if (VersionCompare.part(v, 0) !== major) {
      return false;
    }
    if (VersionCompare.part(v, 1) !== minor) {
      return false;
    }
    return VersionCompare.part(v, 2) < patch;
  }
}
