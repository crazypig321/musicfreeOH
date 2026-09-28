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

  const v240: ChangelogEntry = new ChangelogEntry();
  v240.version = '2.4.0';
  v240.date = '2026-09-29';
  v240.markdown = '- 本地音乐扫描改为「先预检、确认后导入」：扫描 / 刷新文件夹先统计新增与已移出的文件，确认后一次性导入，启动时不再自动扫描\n' +
    '- 扫描确认弹窗支持一并恢复此前「移出本地音乐」的文件\n' +
    '- 扫描 / 导入全程显示全屏加载遮罩；导入与元数据提取全程串行化，修复多文件同时导入导致的标题 / 歌手 / 封面串读\n' +
    '- 修复封面缓存污染：导入时强制刷新内嵌封面，本地记录的异常封面自动修复\n' +
    '- 「搜索歌词」新增歌词音源选择弹窗（首位为「自动」，按原逻辑跨插件匹配）；插件不支持歌词类型搜索时自动回退音乐搜索，解决部分带歌词的插件搜不到的问题\n' +
    '- 歌词「更多」面板新增「下载歌词」：歌词保存为音频同目录同名 .lrc 文件并立即生效，本地音乐下次扫描导入时自动匹配';
  list.push(v240);

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
