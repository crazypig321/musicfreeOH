import { QualityKey, QUALITY_KEYS } from '../common/model/MediaTypes';

/** 音质顺序 */
export class Qualities {
  /**
   * 获取音质尝试顺序
   * @param qualityKey 目标音质
   * @param sort asc=优先高音质, desc=优先低音质
   */
  static getQualityOrder(qualityKey: QualityKey, sort: string): Array<QualityKey> {
    const idx = QUALITY_KEYS.indexOf(qualityKey);
    const left: Array<QualityKey> = QUALITY_KEYS.slice(0, idx);
    const right: Array<QualityKey> = QUALITY_KEYS.slice(idx + 1);
    const leftRev = left.slice().reverse();
    if (sort === 'asc') {
      const result: Array<QualityKey> = [qualityKey];
      return result.concat(right).concat(leftRev);
    } else {
      const result: Array<QualityKey> = [qualityKey];
      return result.concat(leftRev).concat(right);
    }
  }
}
