/**
 * 公共 UI 工具：Toast 提示与时长格式化（收敛各页面重复实现）
 */

import { ArtistItem } from '../common/model/SheetTypes';

/** 歌手统计行：作品数 + 粉丝数 */
export function formatArtistStats(artist: ArtistItem): string {
  const parts: Array<string> = [];
  if (artist.worksNum > 0) {
    parts.push(artist.worksNum.toString() + '首歌曲');
  }
  if (artist.fans > 0) {
    parts.push(artist.fans >= 10000 ?
      (artist.fans / 10000).toFixed(1) + '万粉丝' : artist.fans.toString() + '粉丝');
  }
  return parts.join(' · ');
}

/** 页面内统一 Toast（1.5s）：传入 this.getUIContext() */
export function showUiToast(context: UIContext, message: string): void {
  try {
    context.getPromptAction().showToast({ message: message, duration: 1500 });
  } catch (error) {
    // UI 上下文不可用时忽略
  }
}

/** 秒 → mm:ss */
export function formatDuration(sec: number): string {
  const s = Math.max(0, Math.floor(sec));
  const m = Math.floor(s / 60);
  const r = s % 60;
  const mStr = m < 10 ? '0' + m.toString() : m.toString();
  const rStr = r < 10 ? '0' + r.toString() : r.toString();
  return mStr + ':' + rStr;
}
