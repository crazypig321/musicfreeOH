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

  const v260: ChangelogEntry = new ChangelogEntry();
  v260.version = '2.6.0';
  v260.date = '2026-10-02';
  v260.markdown = '- 新增车载模式：设置 → 外观设置可手动开启驾驶界面；连接 HiCar / 超级桌面等车机时自动进入（不受开关限制），大按钮控制排 + 歌词滚动，背景随封面主色染色\n' +
    '- 支持应用接续（流转）：当前歌曲、播放队列、进度、播放状态与循环模式随流转迁移到车机等设备，接续后自动重建播放现场并无缝续播\n' +
    '- 新增 10 段均衡器（设置 → 播放设置或播放页 EQ 按钮进入）：内置 9 种预设与自定义增益（31Hz ~ 16kHz，单段 ±12dB），拖动实时生效，频段下方按钮可弹窗输入精确数值\n' +
    '- 均衡器基于独立解码管线（@ospark/free-pcm）：开关切换时原位重载当前歌曲不打断聆听；个别不支持的音源自动回退系统播放器，不影响播放\n' +
    '- 播放页音质入口移至进度条时间行中间（纯文本胶囊），封面下方功能按钮排新增 EQ 按钮（开启时主题色高亮）\n' +
    '- 关于页「三方库」列表补充 @ospark/free-pcm\n' +
    '- 修复横屏播放页「投播」按钮与其它功能按钮大小不一致的问题';
  list.push(v260);

  const v250: ChangelogEntry = new ChangelogEntry();
  v250.version = '2.5.0';
  v250.date = '2026-09-30';
  v250.markdown = '- 新增 2*2 桌面音乐卡片\n' +
    '- 新增 4*4 桌面音乐卡片\n' +
    '- 桌面卡片在应用未运行时同样可控（自动后台拉起执行，不打开界面）；卡片初始状态从上次播放记录回填\n' +
    '- 修复桌面卡片切歌后封面不刷新的问题\n' +
    '- 导入歌单支持选择超时时长（1/3/5/10 分钟），避免大歌单因超时导入失败\n' +
    '- 首页与歌单详情页增加转场动画，首页加载样式优化';
  list.push(v250);

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
