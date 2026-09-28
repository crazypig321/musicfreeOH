/**
 * 更新日志数据（每次发版在此追加条目，新版本在前）：
 *  - version / date 用于分组标题展示
 *  - markdown 为该版本日志正文（MarkdownView 渲染）
 */
export class ChangelogEntry {
  public version: string = '';
  public date: string = '';
  public markdown: string = '';
}

function buildChangelogs(): Array<ChangelogEntry> {
  const list: Array<ChangelogEntry> = [];

  const v230: ChangelogEntry = new ChangelogEntry();
  v230.version = '2.3.0';
  v230.date = '2026-09-28';
  v230.markdown = '- 新增「更新日志」页面（关于 → 更新日志），版本升级后首次启动自动弹出\n' +
    '- 歌单 / 歌手 / 专辑详情页「一键导入歌单」增加确认弹窗，避免误触';
  list.push(v230);

  return list;
}

/** 全部版本更新日志（新版本在前） */
export const CHANGELOGS: Array<ChangelogEntry> = buildChangelogs();
