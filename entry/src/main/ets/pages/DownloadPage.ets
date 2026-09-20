import { downloader, DownloadTaskInfo, DownloadStatus, DownloadFailReason } from '../core/Downloader';
import { ArtworkCache } from '../utils/ArtworkCache';
import { downloadedSheet, localMusicSheet, LocalMusicSheet } from '../core/LocalMusicSheet';
import { LocalMusicExclusion } from '../core/LocalMusicExclusion';
import { musicSheet } from '../core/MusicSheet';
import { trackPlayer } from '../core/TrackPlayer';
import { appConfig } from '../core/AppConfig';
import { Network } from '../infra/Network';
import { CommonNav, titleBarOf } from '../view/CommonNav';
import { CommonBlur } from '../view/CommonCom';
import { MusicOptionsSheet } from '../view/MusicOptionsSheet';
import { appState } from '../entryability/AppState';
import { sheetTopAvoidVp } from '../utils/BreakpointUtils';
import { MusicItem, LyricSource } from '../common/model/MediaTypes';
import { SheetItem } from '../common/model/SheetTypes';
import { MusicDataSource } from '../common/model/MusicDataSource';
import { MediaUtils } from '../utils/MediaUtils';
import { CoverSearch } from '../utils/CoverSearch';
import { pluginManager } from '../plugin/PluginManager';
import { pasteboard } from '@kit.BasicServicesKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { SUPPORT_LOCAL_MEDIA_TYPE, INTERNAL_SERIALIZE_KEY } from '../common/Consts';
import { JsonUtil } from '../common/JsonUtil';
import { PathConst } from '../common/PathConst';
import { FileUtils } from '../utils/FileUtils';
import { ContextHolder } from '../common/ContextHolder';
import { DialogManager } from '../utils/DialogUtils';

/**
 * 下载页面：上半部分为下载任务（等待/准备中/下载中/失败，带进度条），
 * 下半部分为已下载列表（下载记录歌单），条目风格与搜索结果一致。
 * 两个分组各自独立批量操作：分组标题右侧进入对应分组的批量模式
 * （任务区底栏额外提供 换源/重新下载；已下载区操作不变），
 * 批量模式下滑动可连续勾选（参考系统相册多选）。
 * 已下载标题下方有横向分组标签（全部 + 下载日期 M月D日 + 来源歌单），
 * 选中标签后列表与批量操作均只作用于该分组。
 * isLocalMode 时为「本地音乐」页：数据源切换为扫描目录的本地音乐歌单，
 * 附加右上角 导入本地音频/刷新 菜单，移出语义为移出本地音乐（排除名单防复活）
 */
@ComponentV2
export struct DownloadPage {
  /** 本地音乐模式（本地音乐页复用本组件，保证两页 UI 永久一致） */
  @Param isLocalMode: boolean = false;
  scroller: Scroller = new Scroller();
  /** 下载任务行（队列快照，进度事件驱动刷新） */
  @Local taskRows: Array<DownloadTaskInfo> = [];
  /** 已下载歌曲数（分组标题与空态使用） */
  @Local downloadedCount: number = 0;
  @Local showOptions: boolean = false;
  /** 本地模式单项操作面板（与主页/搜索页共用的 MusicOptionsSheet） */
  @Local showLocalOptions: boolean = false;
  @Local optionsItem: MusicItem = new MusicItem();
  /** 批量模式下已勾选的歌曲键（platform_id） */
  @Local batchSelected: Array<string> = [];
  /** 批量操作范围：task=下载任务分组，downloaded=已下载分组 */
  @Local batchScope: string = '';
  /** 本地模式：正在导入/扫描 */
  @Local scanning: boolean = false;
  /** 批量「添加到歌单」歌单选择半模态 */
  @Local showBatchSheetPicker: boolean = false;
  /** 批量换源进行中（下载失败任务） */
  @Local batchChanging: boolean = false;
  /** 批量换源进度文案 */
  @Local batchChangeProgress: string = '';
  /** 已下载分组标签（全部 + 日期 M月D日 + 来源歌单） */
  @Local dateTags: Array<string> = ['全部'];
  /** 当前选中的分组标签 */
  @Local selectedTag: string = '全部';
  /** 滑动勾选：手势起点坐标（windowX/windowY，vp） */
  private slideStartX: number = 0;
  private slideStartY: number = 0;
  /** 滑动勾选已激活（移动超过阈值后连续勾选划过的行） */
  private slideSelectActive: boolean = false;
  /** 滑动勾选吞掉本次手势的行点击 */
  private suppressRowClick: boolean = false;
  /** 滑动勾选：已挂载行 key→组件 id（命中测试只遍历可见行） */
  private taskRowIds: Map<string, string> = new Map();
  private itemRowIds: Map<string, string> = new Map();

  /** 已下载/本地音乐列表懒加载数据源（复用搜索页的数据源） */
  dataSource: MusicDataSource = new MusicDataSource();

  /** 当前模式对应的数据域（已下载 / 本地音乐） */
  private get activeSheet(): LocalMusicSheet {
    return this.isLocalMode ? localMusicSheet : downloadedSheet;
  }

  aboutToAppear(): void {
    if (!this.isLocalMode) {
      this.refreshTasks();
      // 下载任务状态/进度变化 → 刷新任务行
      downloader.onDownloadTaskUpdate((_task: DownloadTaskInfo): void => {
        this.refreshTasks();
      });
      // 队列全部结束 → 刷新任务与已下载列表
      downloader.onDownloadQueueCompleted((): void => {
        this.refreshTasks();
        this.refreshDownloaded();
      });
    }
    // 歌单变化（下载完成/导入/删除） → 刷新列表
    this.activeSheet.onLocalSheetUpdated((): void => {
      this.refreshDownloaded();
    });
    this.refreshDownloaded();
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  /** 刷新下载任务行（队列快照，键含进度以驱动重建；跳过已完成任务） */
  private refreshTasks(): void {
    const rows: Array<DownloadTaskInfo> = [];
    for (const m of downloader.getDownloadQueue()) {
      const task = downloader.getDownloadTask(m);
      if (task !== null && task.status !== DownloadStatus.Completed) {
        rows.push(task);
      }
    }
    this.taskRows = rows;
  }

  /** 刷新已下载/本地音乐列表（下载模式按日期/来源歌单过滤，本地模式按所在文件夹过滤） */
  private refreshDownloaded(): void {
    const items = this.activeSheet.getMusicList();
    this.downloadedCount = items.length;
    if (this.isLocalMode) {
      // 本地音乐：按文件所在子文件夹分组（标签 = 下载目录下的相对目录名）
      const folders: Array<string> = [];
      for (const item of items) {
        const localPath = MediaUtils.getLocalPath(item);
        const folder = localPath === null ? '' : DownloadPage.itemLocalFolder(localPath);
        if (folder.length > 0 && folders.indexOf(folder) === -1) {
          folders.push(folder);
        }
      }
      this.dateTags = ['全部'].concat(folders);
      if (this.selectedTag !== '全部' && folders.indexOf(this.selectedTag) === -1) {
        this.selectedTag = '全部';
      }
      const filtered: Array<MusicItem> = [];
      for (const item of items) {
        if (this.itemMatchesTag(item)) {
          filtered.push(item);
        }
      }
      this.dataSource.clear();
      this.dataSource.appendData(filtered);
      return;
    }
    this.computeDateTags(items);
    const filtered: Array<MusicItem> = [];
    for (const item of items) {
      if (this.itemMatchesTag(item)) {
        filtered.push(item);
      }
    }
    this.dataSource.clear();
    this.dataSource.appendData(filtered);
  }

  /** 计算分组标签：全部 + 下载日期 M月D日（最近在前）+ 更早 + 来源歌单 */
  private computeDateTags(items: Array<MusicItem>): void {
    const dayTags: Array<string> = [];
    const dayTs: Array<number> = [];
    let hasOlder = false;
    const originTags: Array<string> = [];
    for (const item of items) {
      const ts = this.itemDownloadedAt(item);
      if (ts > 0) {
        const dayTag = DownloadPage.formatMonthDay(ts);
        const idx = dayTags.indexOf(dayTag);
        if (idx === -1) {
          dayTags.push(dayTag);
          dayTs.push(ts);
        } else if (ts > dayTs[idx]) {
          dayTs[idx] = ts;
        }
      } else {
        hasOlder = true;
      }
      const origin = this.itemDownloadOrigin(item);
      if (origin.length > 0 && originTags.indexOf(origin) === -1) {
        originTags.push(origin);
      }
    }
    // 日期标签按最近下载时间倒序
    const order: Array<number> = [];
    for (let i = 0; i < dayTags.length; ++i) {
      order.push(i);
    }
    order.sort((a: number, b: number): number => dayTs[b] - dayTs[a]);
    const tags: Array<string> = ['全部'];
    for (const i of order) {
      tags.push(dayTags[i]);
    }
    if (hasOlder) {
      tags.push('更早');
    }
    for (const t of originTags) {
      tags.push(t);
    }
    this.dateTags = tags;
    if (this.selectedTag !== '全部' && tags.indexOf(this.selectedTag) === -1) {
      this.selectedTag = '全部';
    }
  }

  /** 条目是否匹配当前选中的分组标签 */
  private itemMatchesTag(item: MusicItem): boolean {
    if (this.selectedTag === '全部') {
      return true;
    }
    // 本地模式：按文件所在文件夹分组
    if (this.isLocalMode) {
      const localPath = MediaUtils.getLocalPath(item);
      return localPath !== null && DownloadPage.itemLocalFolder(localPath) === this.selectedTag;
    }
    if (this.selectedTag === '更早') {
      return this.itemDownloadedAt(item) === 0;
    }
    const ts = this.itemDownloadedAt(item);
    if (ts > 0 && DownloadPage.formatMonthDay(ts) === this.selectedTag) {
      return true;
    }
    return this.itemDownloadOrigin(item) === this.selectedTag;
  }

  /** 本地文件在下载目录下的相对文件夹名（根目录返回空串） */
  private static itemLocalFolder(localPath: string): string {
    const p = FileUtils.normalizePath(localPath);
    const bases: Array<string> = [PathConst.downloadPath, PathConst.basePath + '/download/'];
    for (const base of bases) {
      const b = base.endsWith('/') ? base : base + '/';
      if (p.startsWith(b)) {
        const rel = p.substring(b.length);
        const idx = rel.lastIndexOf('/');
        return idx === -1 ? '' : rel.substring(0, idx);
      }
    }
    return '';
  }

  /** 条目下载完成时间戳（内部序列化记录，无记录返回 0） */
  private itemDownloadedAt(item: MusicItem): number {
    const rec = JsonUtil.recRecord(item.extras, INTERNAL_SERIALIZE_KEY);
    return rec === null ? 0 : JsonUtil.recNum(rec, 'downloadedAt', 0);
  }

  /** 条目下载时所在歌单名（无记录返回空串） */
  private itemDownloadOrigin(item: MusicItem): string {
    const rec = JsonUtil.recRecord(item.extras, INTERNAL_SERIALIZE_KEY);
    return rec === null ? '' : JsonUtil.recStr(rec, 'downloadOrigin');
  }

  /** 时间戳 → M月D日 标签 */
  private static formatMonthDay(ts: number): string {
    const d = new Date(ts);
    return (d.getMonth() + 1).toString() + '月' + d.getDate().toString() + '日';
  }

  /** 切换分组标签：退出批量模式并按标签过滤列表 */
  private selectTag(tag: string): void {
    if (this.selectedTag === tag) {
      return;
    }
    this.selectedTag = tag;
    if (appState.isBatchMode) {
      this.exitBatchMode();
    }
    this.refreshDownloaded();
  }

  // ---------- 本地模式：导入本地音频 / 刷新扫描 ----------

  /** 选择本地音频文件（批量，最多 20 个） */
  private pickLocalAudio(): void {
    if (this.scanning) {
      this.showToast('正在处理中，请稍候');
      return;
    }
    try {
      const documentPicker = new picker.DocumentViewPicker(ContextHolder.get());
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 20;
      options.fileSuffixFilters = SUPPORT_LOCAL_MEDIA_TYPE.slice();
      documentPicker.select(options).then((uris: Array<string>) => {
        if (uris.length === 0) {
          return;
        }
        this.copyUrisToDownloadDir(uris);
      }).catch((_e: Object): void => {
        this.showToast('选择文件失败');
      });
    } catch (error) {
      this.showToast('无法打开文件选择器');
    }
  }

  /** 将选中的音频文件复制到下载目录，完成后自动导入 */
  private copyUrisToDownloadDir(uris: Array<string>): void {
    this.scanning = true;
    this.showToast('正在导入 ' + uris.length.toString() + ' 个文件...');
    // downloadPath 可能无结尾斜杠（公共目录），先补齐再拼接，避免目录名黏连
    const base = PathConst.downloadPath.endsWith('/') ? PathConst.downloadPath : PathConst.downloadPath + '/';
    let ok = 0;
    let dup = 0;
    let fail = 0;
    for (const uri of uris) {
      let src: fs.File | null = null;
      try {
        const name = FileUtils.getFileName(FileUtils.normalizePath(uri));
        if (name.length === 0) {
          fail++;
          continue;
        }
        const destName = FileUtils.escapeCharacter(name);
        const dest = base + destName;
        if (FileUtils.exists(dest)) {
          dup++;
          // 已存在的文件也清除排除名单，保证随后的扫描能重新入库
          LocalMusicExclusion.clearExclusion(destName);
          continue;
        }
        src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        const destFile = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        try {
          fs.copyFileSync(src.fd, destFile.fd);
          ok++;
          LocalMusicExclusion.clearExclusion(destName);
        } finally {
          fs.closeSync(destFile);
        }
      } catch (e) {
        fail++;
      } finally {
        if (src !== null) {
          fs.closeSync(src);
        }
      }
    }
    this.scanning = false;
    let summary: string;
    if (ok > 0) {
      summary = '已复制 ' + ok.toString() + ' 个文件';
      if (dup > 0) {
        summary += '，' + dup.toString() + ' 个已存在';
      }
      if (fail > 0) {
        summary += '，' + fail.toString() + ' 个失败';
      }
    } else {
      summary = dup > 0 ? '文件已存在，直接扫描入库' : '导入失败';
    }
    this.showToast(summary);
    // 复制/已存在的文件统一重新扫描入库
    if (ok > 0 || dup > 0) {
      this.rescanDownloadDir();
    }
  }

  /** 重新扫描下载目录（含沙箱遗留目录），导入漏掉的音频文件；跳过排除名单中的文件 */
  private rescanDownloadDir(): void {
    if (this.scanning) {
      this.showToast('正在扫描中，请稍候');
      return;
    }
    this.scanning = true;
    const before = this.activeSheet.getMusicList().length;
    const dirs: Array<string> = [PathConst.downloadPath];
    const legacyDir = PathConst.basePath + '/download/';
    if (dirs.indexOf(legacyDir) === -1) {
      dirs.push(legacyDir);
    }
    const excluded = LocalMusicExclusion.getExcludedFiles();
    localMusicSheet.importLocal(dirs, (filename: string): boolean => !excluded.has(filename)).then((): void => {
      this.scanning = false;
      const added = this.activeSheet.getMusicList().length - before;
      this.showToast(added > 0 ? '扫描完成，新增 ' + added.toString() + ' 首' : '扫描完成，没有发现新音频');
    }).catch((_e: Object): void => {
      this.scanning = false;
      this.showToast('扫描失败');
    });
  }

  private static taskPercent(task: DownloadTaskInfo): number {
    if (task.fileSize <= 0) {
      return 0;
    }
    return Math.min(100, Math.floor(task.downloadedSize / task.fileSize * 100));
  }

  private static failReasonText(reason: string): string {
    if (reason === DownloadFailReason.NETWORK_OFFLINE) {
      return '无网络';
    }
    if (reason === DownloadFailReason.NOT_ALLOW_TO_DOWNLOAD_IN_CELLULAR) {
      return '移动网络下禁止下载';
    }
    if (reason === DownloadFailReason.FAIL_TO_FETCH_SOURCE) {
      return '无法获取音源';
    }
    if (reason === DownloadFailReason.NO_WRITE_PERMISSION) {
      return '无写入权限';
    }
    return '未知错误';
  }

  private static taskStatusText(task: DownloadTaskInfo): string {
    if (task.status === DownloadStatus.Pending) {
      return '等待下载';
    }
    if (task.status === DownloadStatus.Preparing) {
      return '准备中...';
    }
    if (task.status === DownloadStatus.Downloading) {
      if (task.fileSize > 0) {
        return '下载中 ' + DownloadPage.taskPercent(task).toString() + '%';
      }
      return '下载中...';
    }
    if (task.status === DownloadStatus.Completed) {
      return '下载完成';
    }
    // 换源后的失败任务：reason 已清空，提示可重新下载
    if (task.status === DownloadStatus.Error && task.errorReason.length === 0) {
      return '已换源，可重新下载';
    }
    return '下载失败：' + DownloadPage.failReasonText(task.errorReason);
  }

  /** 取消下载任务（仅等待/失败状态可取消） */
  private removeTask(task: DownloadTaskInfo): void {
    if (downloader.remove(task.musicItem)) {
      this.showToast('已取消下载');
    } else {
      this.showToast('正在下载中，无法取消');
    }
    this.refreshTasks();
  }

  /** 播放列表内歌曲（用整个列表作为播放队列） */
  private playDownloaded(item: MusicItem): void {
    const playList = this.dataSource.getItems();
    if (playList.length === 0) {
      return;
    }
    trackPlayer.playWithReplacePlayList(item, playList).catch((_e: Object): void => {
      this.showToast('播放失败');
    });
  }

  private playNext(): void {
    trackPlayer.addNext(this.optionsItem);
    this.showToast('将在下一首播放');
  }

  /** 分享歌曲信息（复制到剪贴板） */
  private shareCurrent(): void {
    const text = '「' + this.optionsItem.title + '」 - ' + this.optionsItem.artist +
      '（来自 ' + this.optionsItem.platform + '）';
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      this.showToast('已复制歌曲信息，可粘贴分享');
    }).catch((_e: Object): void => {
      this.showToast('复制失败');
    });
  }

  /** 移出列表（仅移除记录，保留文件）；本地模式下文件保留但不再被扫描导入 */
  private removeFromSheet(): void {
    const target = this.optionsItem;
    this.showOptions = false;
    if (this.isLocalMode) {
      LocalMusicExclusion.excludeItem(target);
      localMusicSheet.removeMusic(target, false).then((): void => {
        this.showToast('已移出本地音乐');
      });
    } else {
      downloadedSheet.removeMusic(target, false).then((): void => {
        this.showToast('已移出下载列表');
      });
    }
  }

  /** 移出列表并删除本地文件（弹窗确认，取消不删除） */
  private removeWithFile(): void {
    const target = this.optionsItem;
    this.showOptions = false;
    DialogManager.ConfirmDelete('确定删除「' + target.title + '」及其本地文件吗？', (): void => {
      this.activeSheet.removeMusic(target, true).then((): void => {
        this.showToast('已删除歌曲与本地文件');
      });
    });
  }

  // ---------- 批量多选模式 ----------

  /** titleBar 菜单按钮：本地模式含 导入本地音频/刷新（批量操作入口在各分组标题右侧） */
  private titleMenus(): Array<HdsNavigationMenuItemOptions> {
    const menus: Array<HdsNavigationMenuItemOptions> = [];
    if (this.isLocalMode) {
      menus.push({
        content: {
          icon: $r('sys.symbol.folder'),
          label: '导入本地音频',
          action: (): void => {
            this.pickLocalAudio();
          }
        }
      });
      menus.push({
        content: {
          icon: $r('sys.symbol.arrow_clockwise'),
          label: '刷新',
          action: (): void => {
            this.rescanDownloadDir();
          }
        }
      });
    }
    return menus;
  }

  /** 进入批量模式（scope：task=下载任务分组，downloaded=已下载分组） */
  private enterBatchMode(scope: string): void {
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      appState.isBatchMode = true;
    });
    this.batchScope = scope;
    this.batchSelected = [];
  }

  /** 退出批量模式 */
  private exitBatchMode(): void {
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      appState.isBatchMode = false;
    });
    this.batchScope = '';
    this.batchSelected = [];
  }

  private static itemKey(item: MusicItem): string {
    return item.platform + '_' + item.id;
  }

  /** 任务行是否可勾选（等待中/失败；准备中/下载中不可取消） */
  private isTaskSelectable(task: DownloadTaskInfo): boolean {
    return task.status === DownloadStatus.Pending || task.status === DownloadStatus.Error;
  }

  /** 可勾选任务数（任务区全选用） */
  private selectableTaskCount(): number {
    let count = 0;
    for (const task of this.taskRows) {
      if (this.isTaskSelectable(task)) {
        count++;
      }
    }
    return count;
  }

  /** 批量模式：任务是否被勾选 */
  private isTaskSelected(task: DownloadTaskInfo): boolean {
    return this.batchSelected.indexOf(DownloadPage.itemKey(task.musicItem)) !== -1;
  }

  /** 批量模式：切换任务勾选状态 */
  private toggleTaskSelect(task: DownloadTaskInfo): void {
    if (!this.isTaskSelectable(task)) {
      this.showToast('正在下载中，无法操作');
      return;
    }
    const key = DownloadPage.itemKey(task.musicItem);
    const next = this.batchSelected.slice();
    const idx = next.indexOf(key);
    if (idx === -1) {
      next.push(key);
    } else {
      next.splice(idx, 1);
    }
    this.batchSelected = next;
  }

  /** 勾选中的任务（按任务区顺序，仅可勾选状态） */
  private selectedTasks(): Array<DownloadTaskInfo> {
    const result: Array<DownloadTaskInfo> = [];
    for (const task of this.taskRows) {
      if (this.isTaskSelectable(task) && this.isTaskSelected(task)) {
        result.push(task);
      }
    }
    return result;
  }

  /** 勾选中的失败任务（换源/重新下载目标） */
  private selectedErrorTasks(): Array<DownloadTaskInfo> {
    const result: Array<DownloadTaskInfo> = [];
    for (const task of this.taskRows) {
      if (task.status === DownloadStatus.Error && this.isTaskSelected(task)) {
        result.push(task);
      }
    }
    return result;
  }

  /** 勾选中的全部歌曲（按当前批量范围） */
  private selectedAllMusic(): Array<MusicItem> {
    const result: Array<MusicItem> = [];
    if (this.batchScope === 'task') {
      for (const task of this.selectedTasks()) {
        result.push(task.musicItem);
      }
    } else {
      for (const item of this.dataSource.getItems()) {
        if (this.isSelected(item)) {
          result.push(item);
        }
      }
    }
    return result;
  }

  /** 从勾选集合中移除指定 key（任务取消/重新入队后清理残留勾选） */
  private removeSelectedKeys(keys: Array<string>): void {
    if (keys.length === 0) {
      return;
    }
    const next: Array<string> = [];
    for (const k of this.batchSelected) {
      if (keys.indexOf(k) === -1) {
        next.push(k);
      }
    }
    this.batchSelected = next;
  }

  /** 勾选集合中替换 key（失败任务换源后保持勾选状态） */
  private replaceSelectedKey(oldKey: string, newKey: string): void {
    const idx = this.batchSelected.indexOf(oldKey);
    if (idx === -1) {
      return;
    }
    const next = this.batchSelected.slice();
    next[idx] = newKey;
    this.batchSelected = next;
  }

  /** 批量底栏第三行（换源/重新下载）是否显示：仅任务区批量模式 */
  private batchFailedRowVisible(): boolean {
    return !this.isLocalMode && this.batchScope === 'task';
  }

  /** 行是否被勾选 */
  private isSelected(item: MusicItem): boolean {
    return this.batchSelected.indexOf(DownloadPage.itemKey(item)) !== -1;
  }

  /** 批量模式下点击行：切换勾选状态 */
  private toggleBatchSelect(item: MusicItem): void {
    const key = DownloadPage.itemKey(item);
    const next = this.batchSelected.slice();
    const idx = next.indexOf(key);
    if (idx === -1) {
      next.push(key);
    } else {
      next.splice(idx, 1);
    }
    this.batchSelected = next;
  }

  /** 全选/取消全选（按当前批量范围） */
  private toggleSelectAll(): void {
    const all: Array<string> = [];
    if (this.batchScope === 'task') {
      for (const task of this.taskRows) {
        if (this.isTaskSelectable(task)) {
          all.push(DownloadPage.itemKey(task.musicItem));
        }
      }
    } else {
      for (const item of this.dataSource.getItems()) {
        all.push(DownloadPage.itemKey(item));
      }
    }
    // 已全部勾选时再次点击则清空
    this.batchSelected = all.length > 0 && this.batchSelected.length === all.length ? [] : all;
  }

  /** 批量操作按钮文案·第一行（全部勾选后「全选」切换为「取消全选」；本地模式追加「移动」「搜索封面」） */
  private batchTopLabels(): Array<string> {
    const total = this.batchScope === 'task' ? this.selectableTaskCount() : this.dataSource.totalCount();
    const allSelected = total > 0 && this.batchSelected.length === total;
    const labels: Array<string> = [allSelected ? '取消全选' : '全选', '收藏', '添加到歌单'];
    if (this.isLocalMode) {
      labels.push('移动');
    }
    labels.push('搜索歌词');
    if (this.isLocalMode) {
      labels.push('搜索封面');
    }
    return labels;
  }

  /** 批量操作按钮文案·第二行 */
  private batchBottomLabels(): Array<string> {
    return ['播放', '分享', '移出', '删除'];
  }

  /** 勾选的歌曲实体列表（按列表顺序） */
  private selectedItems(): Array<MusicItem> {
    const result: Array<MusicItem> = [];
    for (const item of this.dataSource.getItems()) {
      if (this.isSelected(item)) {
        result.push(item);
      }
    }
    return result;
  }

  /** 过滤出指定歌单中尚不存在的歌曲 */
  private filterNotInSheet(items: Array<MusicItem>, sheetId: string): Array<MusicItem> {
    const existing = musicSheet.getMusicList(sheetId);
    const result: Array<MusicItem> = [];
    for (const it of items) {
      let found = false;
      for (const ex of existing) {
        if (MediaUtils.isSameMediaItem(ex, it)) {
          found = true;
          break;
        }
      }
      if (!found) {
        result.push(it);
      }
    }
    return result;
  }

  /** 批量收藏：加入「我的收藏」 */
  private batchFavorite(): void {
    const items = this.selectedAllMusic();
    if (items.length === 0) {
      this.showToast('请先勾选歌曲');
      return;
    }
    const fresh = this.filterNotInSheet(items, musicSheet.defaultSheet.id);
    if (fresh.length === 0) {
      this.showToast('所选歌曲均已收藏');
      return;
    }
    musicSheet.addMusic(musicSheet.defaultSheet.id, fresh).then((): void => {
      this.showToast('已收藏 ' + fresh.length.toString() + ' 首到「我的收藏」');
    }).catch((_e: Object): void => {
      this.showToast('收藏失败');
    });
  }

  /** 用户自建歌单列表（不含默认收藏歌单） */
  private getUserSheets(): Array<SheetItem> {
    const result: Array<SheetItem> = [];
    for (const sheet of musicSheet.sheets) {
      if (sheet.id === musicSheet.defaultSheet.id) {
        continue;
      }
      result.push(sheet);
    }
    return result;
  }

  /** 打开批量「添加到歌单」选择器 */
  private openBatchSheetPicker(): void {
    if (this.selectedAllMusic().length === 0) {
      this.showToast('请先勾选歌曲');
      return;
    }
    this.showBatchSheetPicker = true;
  }

  /** 批量添加到指定歌单 */
  private batchAddToSheet(sheet: SheetItem): void {
    const items = this.selectedAllMusic();
    this.showBatchSheetPicker = false;
    if (items.length === 0) {
      this.showToast('请先勾选歌曲');
      return;
    }
    const fresh = this.filterNotInSheet(items, sheet.id);
    if (fresh.length === 0) {
      this.showToast('所选歌曲已在「' + sheet.title + '」中');
      return;
    }
    musicSheet.addMusic(sheet.id, fresh).then((): void => {
      this.showToast('已添加 ' + fresh.length.toString() + ' 首到「' + sheet.title + '」');
    }).catch((_e: Object): void => {
      this.showToast('添加失败');
    });
  }

  /** 批量搜索歌词：逐首按来源插件搜索并缓存 */
  private batchSearchLyric(): void {
    const items = this.selectedAllMusic();
    if (items.length === 0) {
      this.showToast('请先勾选歌曲');
      return;
    }
    this.showToast('开始搜索 ' + items.length.toString() + ' 首歌词...');
    let ok = 0;
    let fail = 0;
    const searchNext = (index: number): Promise<void> => {
      if (index >= items.length) {
        this.showToast('歌词搜索完成：成功 ' + ok.toString() + ' 首' +
          (fail > 0 ? '，失败 ' + fail.toString() + ' 首' : ''));
        return Promise.resolve();
      }
      const target = items[index];
      const plugin = pluginManager.getByMedia(target);
      if (plugin === null) {
        fail++;
        return searchNext(index + 1);
      }
      return plugin.methods.getLyric(target).then((lyric: LyricSource | null): Promise<void> => {
        if (lyric !== null && !lyric.isEmpty()) {
          ok++;
        } else {
          fail++;
        }
        return searchNext(index + 1);
      }).catch((_e: Object): Promise<void> => {
        fail++;
        return searchNext(index + 1);
      });
    };
    searchNext(0);
  }

  /** 批量搜索封面（仅本地模式）：逐首搜索并写回本地条目，来源插件详情优先、其次全插件搜索 */
  private batchSearchCover(): void {
    const items = this.selectedItems();
    if (items.length === 0) {
      this.showToast('请先勾选歌曲');
      return;
    }
    this.showToast('开始搜索 ' + items.length.toString() + ' 首封面...');
    let ok = 0;
    let fail = 0;
    const searchNext = (index: number): Promise<void> => {
      if (index >= items.length) {
        this.showToast('封面搜索完成：成功 ' + ok.toString() + ' 首' +
          (fail > 0 ? '，失败 ' + fail.toString() + ' 首' : ''));
        return Promise.resolve();
      }
      return CoverSearch.searchAndApply(items[index]).then((found: boolean): Promise<void> => {
        if (found) {
          ok++;
        } else {
          fail++;
        }
        return searchNext(index + 1);
      }).catch((_e: Object): Promise<void> => {
        fail++;
        return searchNext(index + 1);
      });
    };
    searchNext(0);
  }

  /** 打开批量「移动到文件夹」弹窗（仅本地模式：输入目标分组/文件夹名，留空移到根目录） */
  private openBatchMoveDialog(): void {
    if (!this.isLocalMode) {
      return;
    }
    if (this.selectedItems().length === 0) {
      this.showToast('请先勾选歌曲');
      return;
    }
    DialogManager.downloadFolderValue = '';
    DialogManager.downloadFolderConfirm = (folder: string): void => {
      this.doBatchMoveLocal(folder);
    };
    DialogManager.OpenDialog('移动到文件夹');
  }

  /** 批量移动本地音乐到目标文件夹（物理移动文件 + 同步已下载域记录；正在播放的跳过） */
  private doBatchMoveLocal(folder: string): void {
    const items = this.selectedItems();
    if (items.length === 0) {
      return;
    }
    const target = folder.length > 0 ? FileUtils.escapeCharacter(folder) : '';
    const base = PathConst.downloadPath.endsWith('/') ? PathConst.downloadPath : PathConst.downloadPath + '/';
    const destDir = target.length > 0 ? base + target : base;
    let ok = 0;
    let fail = 0;
    let skipped = 0;
    for (const it of items) {
      // 正在播放的歌曲移动文件会中断播放，跳过
      if (trackPlayer.isCurrentMusic(it)) {
        skipped++;
        continue;
      }
      const result = localMusicSheet.moveLocalMusic(it, destDir);
      if (result === 2) {
        fail++;
      } else {
        ok++;
      }
    }
    let message = '已移动 ' + ok.toString() + ' 首';
    if (fail > 0) {
      message += '，失败 ' + fail.toString() + ' 首';
    }
    if (skipped > 0) {
      message += '（正在播放的 ' + skipped.toString() + ' 首已跳过）';
    }
    this.showToast(message);
    this.refreshDownloaded();
  }

  /** 批量播放：以选中歌曲为播放队列，从第一首开始 */
  private batchPlay(): void {
    const items = this.selectedAllMusic();
    if (items.length === 0) {
      this.showToast('请先勾选歌曲');
      return;
    }
    trackPlayer.playWithReplacePlayList(items[0], items).catch((_e: Object): void => {
      this.showToast('播放失败');
    });
    this.exitBatchMode();
  }

  /** 批量分享：复制选中歌曲信息 */
  private batchShare(): void {
    const items = this.selectedAllMusic();
    if (items.length === 0) {
      this.showToast('请先勾选歌曲');
      return;
    }
    const lines: Array<string> = [];
    for (const it of items) {
      lines.push('「' + it.title + '」 - ' + it.artist + '（来自 ' + it.platform + '）');
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, lines.join('\n'));
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      this.showToast('已复制 ' + items.length.toString() + ' 首歌曲信息，可粘贴分享');
    }).catch((_e: Object): void => {
      this.showToast('复制失败');
    });
  }

  /** 批量移出列表 / 删除歌曲文件（按当前批量范围）；删除文件时弹窗确认（取消不删除）；
   * 本地模式移出时写入排除名单防止扫描复活 */
  private batchRemove(withFile: boolean): Promise<void> {
    // 任务区：勾选任务全部取消下载
    if (this.batchScope === 'task') {
      const tasks = this.selectedTasks();
      if (tasks.length === 0) {
        this.showToast('请先勾选任务');
        return Promise.resolve();
      }
      let count = 0;
      const keys: Array<string> = [];
      for (const task of tasks) {
        keys.push(DownloadPage.itemKey(task.musicItem));
        if (downloader.remove(task.musicItem)) {
          count++;
        }
      }
      this.removeSelectedKeys(keys);
      this.refreshTasks();
      this.showToast('已取消 ' + count.toString() + ' 个下载任务');
      return Promise.resolve();
    }
    const items = this.selectedItems();
    if (items.length === 0) {
      this.showToast('请先勾选歌曲');
      return Promise.resolve();
    }
    if (withFile) {
      DialogManager.ConfirmDelete('确定删除选中的 ' + items.length.toString() + ' 首歌曲及本地文件吗？', (): void => {
        this.doBatchRemove(items, true);
      });
      return Promise.resolve();
    }
    this.doBatchRemove(items, false);
    return Promise.resolve();
  }

  /** 确认后执行批量移出/删除（已下载区） */
  private doBatchRemove(items: Array<MusicItem>, withFile: boolean): void {
    if (this.isLocalMode && !withFile) {
      for (const it of items) {
        LocalMusicExclusion.excludeItem(it);
      }
    }
    const removals: Array<Promise<void>> = [];
    for (const it of items) {
      removals.push(this.activeSheet.removeMusic(it, withFile));
    }
    Promise.all(removals).then((): void => {
      this.exitBatchMode();
      if (withFile) {
        this.showToast('已删除 ' + items.length.toString() + ' 首歌曲与本地文件');
      } else {
        this.showToast('已移出 ' + items.length.toString() + ' 首歌曲' +
          (this.isLocalMode ? '，文件保留但不再自动导入' : ''));
      }
    });
  }

  /** 取消全部可取消任务（等待中/失败，下载中/准备中跳过） */
  private cancelAllTasks(): void {
    let count = 0;
    for (const task of this.taskRows) {
      if (this.isTaskSelectable(task) && downloader.remove(task.musicItem)) {
        count++;
      }
    }
    if (count === 0) {
      this.showToast('没有可取消的任务');
      return;
    }
    this.showToast('已取消 ' + count.toString() + ' 个下载任务');
    this.refreshTasks();
  }

  /** 重试全部失败任务（断点续传，保留半成品缓存） */
  private retryAllFailed(): void {
    const network = Network.getInstance();
    if (network.isOffline) {
      this.showToast('当前无网络');
      return;
    }
    if (network.isCellular && !appConfig.getUseCellularNetworkDownload()) {
      this.showToast('移动网络下禁止下载');
      return;
    }
    let count = 0;
    for (const task of this.taskRows) {
      if (task.status === DownloadStatus.Error && downloader.retry(task.musicItem)) {
        count++;
      }
    }
    if (count === 0) {
      this.showToast('没有失败的任务');
      return;
    }
    this.showToast('已重新下载 ' + count.toString() + ' 首');
    this.refreshTasks();
  }

  /** 批量换源（仅下载失败任务，等待中的任务跳过）：逐首搜索其它插件的同一首歌，
   * 自动选第一个命中的候选，替换下载任务/播放队列/歌单中的条目 */
  private async batchChangeSource(): Promise<void> {
    if (this.batchChanging) {
      this.showToast('正在换源中，请稍候');
      return;
    }
    const tasks = this.selectedErrorTasks();
    if (tasks.length === 0) {
      this.showToast('请先勾选下载失败的任务');
      return;
    }
    const pendingSkipped = this.selectedTasks().length - tasks.length;
    // 正在播放的歌曲不支持批量换源（请单独换源）
    const targets: Array<DownloadTaskInfo> = [];
    let playingSkipped = 0;
    for (const task of tasks) {
      if (trackPlayer.isCurrentMusic(task.musicItem)) {
        playingSkipped++;
        continue;
      }
      targets.push(task);
    }
    if (targets.length === 0) {
      this.showToast('正在播放的歌曲请单独换源');
      return;
    }
    this.batchChanging = true;
    let success = 0;
    let failed = 0;
    for (let i = 0; i < targets.length; ++i) {
      const task = targets[i];
      this.batchChangeProgress = '换源中 ' + (i + 1).toString() + '/' + targets.length.toString();
      const oldItem = task.musicItem;
      try {
        const candidates = await trackPlayer.searchAlternateSources(oldItem);
        const best = candidates.length > 0 ? candidates[0] : null;
        if (best !== null) {
          const replaced = downloader.replaceTask(oldItem, best);
          const inQueue = trackPlayer.replaceInQueue(oldItem, best);
          const saved = musicSheet.replaceMusicEverywhere(oldItem, best);
          if (replaced || inQueue || saved > 0) {
            success++;
            this.replaceSelectedKey(DownloadPage.itemKey(oldItem), DownloadPage.itemKey(best));
          } else {
            failed++;
          }
        } else {
          failed++;
        }
      } catch (_e) {
        failed++;
      }
    }
    this.batchChanging = false;
    this.batchChangeProgress = '';
    let message = '换源完成：成功 ' + success.toString() + ' 首';
    if (failed > 0) {
      message += '，失败 ' + failed.toString() + ' 首';
    }
    if (pendingSkipped > 0) {
      message += '（等待中的 ' + pendingSkipped.toString() + ' 个任务不支持换源）';
    }
    if (playingSkipped > 0) {
      message += '（正在播放的 ' + playingSkipped.toString() + ' 首请单独换源）';
    }
    this.showToast(message);
    this.refreshTasks();
  }

  /** 批量重新下载（仅下载失败任务）：任务重置为待下载并保留半成品缓存断点续传；
   * 网络不满足下载条件时不动原任务，避免失败记录丢失 */
  private batchRedownload(): void {
    const tasks = this.selectedErrorTasks();
    if (tasks.length === 0) {
      this.showToast('请先勾选下载失败的任务');
      return;
    }
    const network = Network.getInstance();
    if (network.isOffline) {
      this.showToast('当前无网络');
      return;
    }
    if (network.isCellular && !appConfig.getUseCellularNetworkDownload()) {
      this.showToast('移动网络下禁止下载');
      return;
    }
    let count = 0;
    for (const task of tasks) {
      if (downloader.retry(task.musicItem)) {
        count++;
      }
    }
    if (count === 0) {
      this.showToast('重新下载失败');
      return;
    }
    let message = '已重新下载 ' + count.toString() + ' 首';
    const pendingSkipped = this.selectedTasks().length - tasks.length;
    if (pendingSkipped > 0) {
      message += '（等待中的 ' + pendingSkipped.toString() + ' 个任务已在队列中）';
    }
    this.showToast(message);
    this.refreshTasks();
  }

  private static formatDuration(sec: number): string {
    const s = Math.max(0, Math.floor(sec));
    const m = Math.floor(s / 60);
    const r = s % 60;
    const mStr = m < 10 ? '0' + m.toString() : m.toString();
    const rStr = r < 10 ? '0' + r.toString() : r.toString();
    return mStr + ':' + rStr;
  }

  // ---------- 滑动勾选（批量模式下横向滑动连续勾选划过的行，参考系统相册） ----------

  /** 任务行点击键 → 任务对象 */
  private taskByKey(key: string): DownloadTaskInfo | null {
    for (const task of this.taskRows) {
      if (DownloadPage.itemKey(task.musicItem) === key) {
        return task;
      }
    }
    return null;
  }

  /** 已下载行点击键 → 歌曲对象 */
  private itemByKey(key: string): MusicItem | null {
    for (const item of this.dataSource.getItems()) {
      if (DownloadPage.itemKey(item) === key) {
        return item;
      }
    }
    return null;
  }

  /** 列表触摸：批量模式下横向滑动激活连续勾选（纵向让位给列表滚动） */
  private onListTouch(event: TouchEvent): void {
    if (!appState.isBatchMode) {
      return;
    }
    if (event.type === TouchType.Down) {
      this.slideStartX = event.touches[0].windowX;
      this.slideStartY = event.touches[0].windowY;
      this.slideSelectActive = false;
      this.suppressRowClick = false;
    } else if (event.type === TouchType.Move) {
      const dx = event.touches[0].windowX - this.slideStartX;
      const dy = event.touches[0].windowY - this.slideStartY;
      if (!this.slideSelectActive) {
        // 横向位移超过阈值且横向主导才激活，避免与列表滚动冲突
        if (Math.abs(dx) >= 12 && Math.abs(dx) > Math.abs(dy)) {
          this.slideSelectActive = true;
          this.suppressRowClick = true;
        } else {
          return;
        }
      }
      this.slideHitSelect(event.touches[0].windowX, event.touches[0].windowY);
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.slideSelectActive = false;
    }
  }

  /** 命中测试：勾选手指位置所在的行（只加选不取消；只遍历已挂载行） */
  private slideHitSelect(x: number, y: number): void {
    const utils = this.getUIContext().getComponentUtils();
    if (this.batchScope === 'task') {
      this.taskRowIds.forEach((id: string, key: string) => {
        const task = this.taskByKey(key);
        if (task === null || !this.isTaskSelectable(task) || this.isTaskSelected(task)) {
          return;
        }
        const rect = utils.getRectangleById(id);
        if (x >= rect.windowOffset.x && x <= rect.windowOffset.x + rect.size.width &&
          y >= rect.windowOffset.y && y <= rect.windowOffset.y + rect.size.height) {
          this.toggleTaskSelect(task);
        }
      });
    } else {
      this.itemRowIds.forEach((id: string, key: string) => {
        const item = this.itemByKey(key);
        if (item === null || this.isSelected(item)) {
          return;
        }
        const rect = utils.getRectangleById(id);
        if (x >= rect.windowOffset.x && x <= rect.windowOffset.x + rect.size.width &&
          y >= rect.windowOffset.y && y <= rect.windowOffset.y + rect.size.height) {
          this.toggleBatchSelect(item);
        }
      });
    }
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf(this.isLocalMode ? '本地音乐' : $r('app.string.tab_download'), undefined,
        this.titleMenus()),
      isShowPlayBar: appState.isBatchMode ? false : true,
      doubleTapToTop: true,
      backPressed: (): boolean => {
        // 批量操作模式下返回键先退出批量模式
        if (appState.isBatchMode) {
          this.exitBatchMode();
          return true;
        }
        return false;
      }
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller }) {
        // 下载任务分组（仅下载模式）
        if (!this.isLocalMode && this.taskRows.length > 0) {
          ListItem() {
            Row({ space: 16 }) {
              Text('下载中 · ' + this.taskRows.length.toString())
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_secondary'))
              Blank()
              if (!appState.isBatchMode) {
                // 取消全部可取消任务
                SymbolGlyph($r('sys.symbol.xmark_circle'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                  .onClick(() => {
                    this.cancelAllTasks();
                  })
                // 重试全部失败任务
                SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                  .onClick(() => {
                    this.retryAllFailed();
                  })
                // 任务区批量操作
                SymbolGlyph($r('sys.symbol.list_checkmask'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                  .onClick(() => {
                    this.enterBatchMode('task');
                  })
              }
            }
            .width('100%')
            .margin({ top: 12, bottom: 4 })
          }
          ForEach(this.taskRows, (task: DownloadTaskInfo, index: number) => {
            ListItem() {
              this.TaskRowBuilder(task, index)
            }
          }, (task: DownloadTaskInfo, _index: number) =>
            task.musicItem.platform + '_' + task.musicItem.id + '_' +
            task.status.toString() + '_' + task.downloadedSize.toString() +
            (appState.isBatchMode ? '_' + this.batchScope : '') +
            (appState.isBatchMode && this.isTaskSelected(task) ? '_sel' : ''))
        }

        // 列表分组
        if (this.downloadedCount > 0) {
          ListItem() {
            Row({ space: 16 }) {
              Text((this.isLocalMode ? '本地音乐 · ' : '已下载 · ') + this.downloadedCount.toString())
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_secondary'))
              Blank()
              if (!appState.isBatchMode) {
                // 已下载/本地音乐区批量操作
                SymbolGlyph($r('sys.symbol.list_checkmask'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                  .onClick(() => {
                    this.enterBatchMode('downloaded');
                  })
              }
            }
            .width('100%')
            .margin({ top: 12, bottom: 4 })
          }
          // 分组标签（已下载：全部 + 下载日期 + 来源歌单；本地音乐：全部 + 所在文件夹；
          // 样式同主页推荐歌单标签条）
          if (this.dateTags.length > 1) {
            ListItem() {
              List({ space: 8 }) {
                ForEach(this.dateTags, (tag: string) => {
                  ListItem() {
                    Text(tag)
                      .fontSize(13)
                      .maxLines(1)
                      .fontColor(this.selectedTag === tag ?
                      $r('sys.color.font_on') : $r('sys.color.font_secondary'))
                      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                      .borderRadius(16)
                      .backgroundColor(this.selectedTag === tag ?
                      $r('sys.color.font_secondary') : $r('sys.color.comp_background_tertiary'))
                      .onClick(() => {
                        this.selectTag(tag);
                      })
                  }
                }, (tag: string) => tag + (this.selectedTag === tag ? '_on' : '_off'))
              }
              .listDirection(Axis.Horizontal)
              .scrollBar(BarState.Off)
              .edgeEffect(EdgeEffect.Spring)
              .width('100%')
              .margin({ bottom: 4 })
            }
          }
          LazyForEach(this.dataSource, (item: MusicItem, index: number) => {
            ListItem() {
              this.DownloadedRowBuilder(item, index)
            }
          }, (item: MusicItem, _index: number) => item.platform + '_' + item.id + '_' + item.artwork +
            (appState.isBatchMode ? '_' + this.batchScope : '') +
            (appState.isBatchMode && this.isSelected(item) ? '_sel' : ''))
        }

        // 空态
        if (this.taskRows.length === 0 && this.downloadedCount === 0) {
          ListItem() {
            Column({ space: 8 }) {
              SymbolGlyph(this.isLocalMode ? $r('sys.symbol.folder') : $r('sys.symbol.download'))
                .fontSize(44)
                .fontColor([$r('sys.color.icon_tertiary')])
              Text(this.isLocalMode ? '暂无本地音乐' : '暂无下载任务')
                .fontSize(14)
                .fontColor($r('sys.color.font_secondary'))
              if (this.isLocalMode) {
                Text('通过右上角「导入本地音频」将设备上的音频加入本地音乐')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
                  .textAlign(TextAlign.Center)
                  .padding({ left: 32, right: 32 })
              } else {
                Text('在歌曲操作中选择「下载」，下载完成后会出现在这里')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
                  .textAlign(TextAlign.Center)
                  .padding({ left: 32, right: 32 })
              }
            }
            .width('100%')
            .margin({ top: 48 })
            .alignItems(HorizontalAlign.Center)
          }
        }
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onTouch((event: TouchEvent) => {
        this.onListTouch(event);
      })
      .contentStartOffset(appState.topRect + 55)
      .contentEndOffset(appState.bottomRect +
        (appState.isBatchMode ? 216 + (this.batchFailedRowVisible() ? 46 : 0) : 60))
      .padding({ left: 16, right: 16 })
      .bindSheet(!this.isLocalMode && !!this.showOptions, this.OptionsSheetBuilder(), {
        scrollSizeMode: ScrollSizeMode.CONTINUOUS, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        dragBar: true,
        onWillDisappear: () => {
          this.showOptions = false;
          appState.isForegroundBlur = false
        },
        onWillAppear: () => {
          appState.isForegroundBlur = true
        }
      })

        // 批量模式底栏（透明悬浮于列表之上，列表底部渐变模糊）：
        // 第一行 全选 / 收藏 / 添加到歌单 / 搜索歌词（本地模式追加 移动 / 搜索封面）；
        // 第二行 播放 / 分享 / 移出 / 删除；
        // 第三行 换源 / 重新下载（仅任务区批量模式显示）
        if (appState.isBatchMode) {
          // 渐变模糊高度与底栏内容高度保持一致：
          // 14(顶距) + 22(已选行) + 10 + 36(按钮行1) + 10 + 36(按钮行2) + 12(底距) + 导航栏避让
          // 存在失败任务时追加 10 + 36(按钮行3)
          CommonBlur({ heightValue: appState.bottomRect + 140 +
            (this.batchFailedRowVisible() ? 46 : 0) }).position({ bottom: 0 })
            .transition(TransitionEffect.OPACITY)


          Column({ space: 10 }) {
            Row() {
              Text(this.batchChanging ? this.batchChangeProgress :
                '已选 ' + this.batchSelected.length.toString() +
                (this.batchScope === 'task' ? ' 个任务' : ' 首歌曲'))
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
              Blank()
              Text('取消')
                .fontSize(16)
                .fontColor($r('sys.color.font_secondary'))
                .onClick(() => {
                  this.exitBatchMode();
                })
            }
            .width('100%')

            Row({ space: 8 }) {
              ForEach(this.batchTopLabels(), (v: string, i: number) => {
                Button(v)
                  .layoutWeight(1)
                  .height(36)
                  .fontSize(this.isLocalMode ? 9 : 10)
                  .fontWeight(FontWeight.Medium)
                  .borderRadius(10)
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  .fontColor($r('sys.color.font_primary'))
                  .padding({ left: 2, right: 2 })
                  .onClick(() => {
                    if (v === '全选' || v === '取消全选') {
                      this.toggleSelectAll();
                    } else if (v === '收藏') {
                      this.batchFavorite();
                    } else if (v === '添加到歌单') {
                      this.openBatchSheetPicker();
                    } else if (v === '移动') {
                      this.openBatchMoveDialog();
                    } else if (v === '搜索歌词') {
                      this.batchSearchLyric();
                    } else {
                      // 搜索封面（仅本地模式）
                      this.batchSearchCover();
                    }
                  })
              }, (v: string, i: number) => v + '_' + i.toString())
            }
            .width('100%')

            Row({ space: 8 }) {
              ForEach(this.batchBottomLabels(), (v: string, i: number) => {
                Button(v)
                  .layoutWeight(1)
                  .height(36)
                  .fontSize(10)
                  .fontWeight(FontWeight.Medium)
                  .borderRadius(10)
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  .fontColor($r('sys.color.font_primary'))
                  .onClick(() => {
                    if (i === 0) {// 播放
                      this.batchPlay();
                    } else if (i === 1) {// 分享
                      this.batchShare();
                    } else if (i === 2) {// 移出列表
                      this.batchRemove(false);
                    } else {// 删除歌曲文件
                      this.batchRemove(true);
                    }
                  })
              }, (v: string, i: number) => v + '_' + i.toString())
            }
            .width('100%')

            // 第三行：换源 / 重新下载（仅任务区批量模式）
            if (this.batchFailedRowVisible()) {
              Row({ space: 8 }) {
                Button('换源')
                  .layoutWeight(1)
                  .height(36)
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .borderRadius(10)
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  .fontColor($r('sys.color.font_primary'))
                  .onClick(() => {
                    this.batchChangeSource();
                  })
                Button('重新下载')
                  .layoutWeight(1)
                  .height(36)
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .borderRadius(10)
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  .fontColor($r('sys.color.font_primary'))
                  .onClick(() => {
                    this.batchRedownload();
                  })
              }
              .width('100%')
            }
          }
          .width('100%')
          .position({ bottom: 0 })
          .padding({ top: 14, left: 16, right: 16, bottom: appState.bottomRect + 12 })
          .transition(TransitionEffect.OPACITY)
        }

        // 批量「添加到歌单」选择器锚点（独立节点挂载半模态，不与单项操作 sheet 共用宿主）
        Column()
          .width('100%')
          .height(0)
          .bindSheet(!!this.showBatchSheetPicker, this.BatchSheetPickerBuilder(), {
            scrollSizeMode: ScrollSizeMode.CONTINUOUS, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
            dragBar: true,
            onWillDisappear: () => {
              this.showBatchSheetPicker = false;
              appState.isForegroundBlur = false;
            },
            onWillAppear: () => {
              appState.isForegroundBlur = true;
            }
          })

        // 本地模式：单项操作面板与主页本地音乐条目一致，额外提供移出/删除入口
        if (this.isLocalMode) {
          MusicOptionsSheet({
            optionsItem: this.optionsItem,
            show: this.showLocalOptions,
            localListMode: true,
            onClose: (): void => {
              this.showLocalOptions = false;
            }
          })
        }
      }
      .width('100%')
      .height('100%')
    }
  }

  /** 下载任务行：状态图标 + 标题/状态文本 + 进度条 + 取消；
   * 任务区批量模式下可勾选任务显示勾选圈，点击勾选、长按进入批量模式 */
  @Builder
  TaskRowBuilder(task: DownloadTaskInfo, index: number) {
    Column() {
      Row({ space: 12 }) {
        // 任务区批量模式：可勾选任务（等待中/失败）勾选圈
        if (appState.isBatchMode && this.batchScope === 'task' && this.isTaskSelectable(task)) {
          SymbolGlyph(this.isTaskSelected(task) ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
            .fontSize(24)
            .fontColor([this.isTaskSelected(task) ? appState.accentColor : $r('sys.color.icon_tertiary')])
            .transition(TransitionEffect.OPACITY)
        }
        Column() {
          if (task.status === DownloadStatus.Preparing || task.status === DownloadStatus.Downloading) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(appState.accentColor)
          } else if (task.status === DownloadStatus.Error) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(20)
              .fontColor([$r('sys.color.icon_secondary')])
          } else {
            SymbolGlyph($r('sys.symbol.clock'))
              .fontSize(20)
              .fontColor([$r('sys.color.icon_secondary')])
          }
        }
        .width(40)
        .height(40)
        .borderRadius(10)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .justifyContent(FlexAlign.Center)

        Column({ space: 4 }) {
          Text(task.musicItem.title)
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(DownloadPage.taskStatusText(task))
            .fontSize(12)
            .fontColor(task.status === DownloadStatus.Error ?
              $r('sys.color.font_secondary') : $r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (task.status === DownloadStatus.Downloading && task.fileSize > 0) {
            Progress({ value: DownloadPage.taskPercent(task), total: 100, type: ProgressType.Linear })
              .width('100%')
              .height(3)
              .color(appState.accentColor)
              .backgroundColor($r('sys.color.comp_background_tertiary'))
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // 任务区批量模式下隐藏取消按钮（点击行即勾选/提示）
        if (!(appState.isBatchMode && this.batchScope === 'task')) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([$r('sys.color.icon_secondary')])
            .onClick(() => {
              this.removeTask(task);
            })
        }
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })
      .gesture(
        LongPressGesture({ repeat: false, duration: 500 })
          .onAction((_event: GestureEvent) => {
            // 长按任务行进入任务区批量模式并勾选当前条目（下载中/准备中仅进入）
            if (appState.isBatchMode) {
              return;
            }
            this.enterBatchMode('task');
            if (this.isTaskSelectable(task)) {
              this.toggleTaskSelect(task);
            }
          })
      )
      .onClick(() => {
        // 滑动勾选吞掉手势结束后的点击
        if (this.suppressRowClick) {
          this.suppressRowClick = false;
          return;
        }
        if (appState.isBatchMode && this.batchScope === 'task') {
          this.toggleTaskSelect(task);
        }
      })

      // 条目间分割线
      if (index < this.taskRows.length - 1) {
        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.comp_divider'))
          .margin({ left: appState.isBatchMode && this.batchScope === 'task' ? 35 : 52, right: 4 })
      }
    }
    .width('100%')
    .id('dptask-' + DownloadPage.itemKey(task.musicItem))
    .onAppear(() => {
      this.taskRowIds.set(DownloadPage.itemKey(task.musicItem), 'dptask-' + DownloadPage.itemKey(task.musicItem));
    })
    .onDisAppear(() => {
      this.taskRowIds.delete(DownloadPage.itemKey(task.musicItem));
    })
  }

  /** 列表歌曲行（风格同搜索结果行）：点击播放，更多操作进半模态；已下载区批量模式下点击勾选、长按进入批量模式。
    * 智感握姿：左手握持时 更多按钮+时长 镜像到行首，歌名与下方文本右对齐，封面镜像到最右 */
  @Builder
  DownloadedRowBuilder(item: MusicItem, index: number) {
    Column() {
      Row({ space: 12 }) {
        // 已下载区批量模式：勾选圈
        if (appState.isBatchMode && this.batchScope === 'downloaded') {
          SymbolGlyph(this.isSelected(item) ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
            .fontSize(24)
            .fontColor([this.isSelected(item) ? appState.accentColor : $r('sys.color.icon_tertiary')])
            .transition(TransitionEffect.OPACITY)
        }
        // 智感握姿左手：更多按钮 + 时长镜像到行首
        if (appState.holdingHand === 'left') {
          if (!appState.isBatchMode) {
            SymbolGlyph($r('sys.symbol.ellipsis_circle'))
              .fontSize(20)
              .fontColor([$r('sys.color.icon_secondary')])
              .transition(TransitionEffect.OPACITY)
              .onClick(() => {
                this.optionsItem = item.clone();
                // 本地模式：与主页本地音乐条目一致的完整操作面板；下载模式：本页简化面板
                if (this.isLocalMode) {
                  this.showLocalOptions = true;
                } else {
                  this.showOptions = true;
                }
              })
          }
          Text(DownloadPage.formatDuration(item.duration))
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
        }
        // 封面：有图用 Image，无图用音符占位（左手时镜像到行尾）
        if (appState.holdingHand !== 'left') {
          if (item.artwork.length > 0) {
            Image(ArtworkCache.resolve(item.artwork))
              .width(40)
              .height(40)
              .borderRadius(10)
              .objectFit(ImageFit.Cover)
              .alt($r('app.media.altImage'))
          } else {
            Column() {
              SymbolGlyph($r('sys.symbol.music'))
                .fontSize(20)
                .fontColor([$r('sys.color.icon_secondary')])
            }
            .width(40)
            .height(40)
            .borderRadius(10)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .justifyContent(FlexAlign.Center)
          }
        }

        Column({ space: 2 }) {
          Text(item.title)
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.artist + (item.album.length > 0 ? ' · ' + item.album : ''))
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(appState.holdingHand === 'left' ? HorizontalAlign.End : HorizontalAlign.Start)

        // 右手：时长 + 更多按钮保持行尾原顺序
        if (appState.holdingHand !== 'left') {
          Text(DownloadPage.formatDuration(item.duration))
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
          if (!appState.isBatchMode) {
            SymbolGlyph($r('sys.symbol.ellipsis_circle'))
              .fontSize(20)
              .fontColor([$r('sys.color.icon_secondary')])
              .transition(TransitionEffect.OPACITY)
              .onClick(() => {
                this.optionsItem = item.clone();
                // 本地模式：与主页本地音乐条目一致的完整操作面板；下载模式：本页简化面板
                if (this.isLocalMode) {
                  this.showLocalOptions = true;
                } else {
                  this.showOptions = true;
                }
              })
          }
        }
        // 智感握姿左手：封面镜像到行尾
        if (appState.holdingHand === 'left') {
          if (item.artwork.length > 0) {
            Image(ArtworkCache.resolve(item.artwork))
              .width(40)
              .height(40)
              .borderRadius(10)
              .objectFit(ImageFit.Cover)
              .alt($r('app.media.altImage'))
          } else {
            Column() {
              SymbolGlyph($r('sys.symbol.music'))
                .fontSize(20)
                .fontColor([$r('sys.color.icon_secondary')])
            }
            .width(40)
            .height(40)
            .borderRadius(10)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .justifyContent(FlexAlign.Center)
          }
        }
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })
      .gesture(
        LongPressGesture({ repeat: false, duration: 500 })
          .onAction((_event: GestureEvent) => {
            // 长按进入已下载区批量模式并勾选当前条目
            if (appState.isBatchMode) {
              return;
            }
            this.enterBatchMode('downloaded');
            this.toggleBatchSelect(item);
          })
      )
      .onClick(() => {
        // 滑动勾选吞掉手势结束后的点击
        if (this.suppressRowClick) {
          this.suppressRowClick = false;
          return;
        }
        if (appState.isBatchMode) {
          if (this.batchScope === 'downloaded') {
            this.toggleBatchSelect(item);
          }
        } else {
          this.playDownloaded(item);
        }
      })

      // 条目间分割线（智感握姿左手时镜像边距，避让行尾封面）
      if (index < this.dataSource.totalCount() - 1) {
        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.comp_divider'))
          .margin(appState.holdingHand === 'left'
            ? { left: 4, right: 52 }
            : { left: appState.isBatchMode && this.batchScope === 'downloaded' ? 35 : 52, right: 4 })
      }
    }
    .width('100%')
    .id('dlrow-' + DownloadPage.itemKey(item))
    // 分组标签切换时渐隐过渡，避免闪烁突兀
    .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.Smooth }))
    .onAppear(() => {
      this.itemRowIds.set(DownloadPage.itemKey(item), 'dlrow-' + DownloadPage.itemKey(item));
    })
    .onDisAppear(() => {
      this.itemRowIds.delete(DownloadPage.itemKey(item));
    })
  }

  /** 列表歌曲操作半模态（UI 参考插件详情的操作分组） */
  @Builder
  OptionsSheetBuilder() {
    Column() {
      // 头部：封面 + 标题 + 歌手 + 专辑
      Row({ space: 12 }) {
        if (this.optionsItem.artwork.length > 0) {
          Image(ArtworkCache.resolve(this.optionsItem.artwork))
            .width(64)
            .height(64)
            .borderRadius(10)
            .objectFit(ImageFit.Cover)
            .alt($r('app.media.altImage'))
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.music_note_list'))
              .fontSize(28)
              .fontColor([$r('sys.color.icon_tertiary')])
          }
          .width(64)
          .height(64)
          .borderRadius(10)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .justifyContent(FlexAlign.Center)
        }

        Column({ space: 3 }) {
          Text(this.optionsItem.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.optionsItem.artist)
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.optionsItem.album.length > 0 ? this.optionsItem.album : '未知专辑')
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 操作分组：播放 / 下一首播放 / 分享 / 移出列表 / 删除歌曲文件
      Text('操作')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .margin({ top: 20, bottom: 6 })
      Column() {
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
          Text('播放')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          const target = this.optionsItem;
          this.showOptions = false;
          this.playDownloaded(target);
        })

        Divider().DividerStyle()
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.forward_end_fill'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
          Text('下一首播放')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.playNext();
        })

        Divider().DividerStyle()
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.share'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
          Text('分享')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.shareCurrent();
        })

        Divider().DividerStyle()
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
          Text(this.isLocalMode ? '移出本地音乐' : '移出下载列表')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.removeFromSheet();
        })

        Divider().DividerStyle()
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
          Text('删除歌曲文件')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.removeWithFile();
        })
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor($r('sys.color.comp_background_list_card'))
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12 + sheetTopAvoidVp(), bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 批量「添加到歌单」歌单选择半模态（列表样式同单项操作的二级面板） */
  @Builder
  BatchSheetPickerBuilder() {
    Column() {
      Text('添加到歌单')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 4, bottom: 4 })
      if (this.getUserSheets().length === 0) {
        Text('暂无自建歌单，请先在歌单页创建')
          .fontSize(14)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 32, bottom: 32 })
      } else {
        List() {
          ForEach(this.getUserSheets(), (sheet: SheetItem, index: number) => {
            ListItem() {
              Row({ space: 12 }) {
                Text(sheet.title)
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(sheet.worksNum.toString() + ' 首')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.batchAddToSheet(sheet);
              })
            }
          }, (sheet: SheetItem, index: number) => sheet.id + '_' + index.toString())
        }
        .width('100%')
        .margin({ top: 4 })
        .nestedScroll({
          scrollForward: NestedScrollMode.PARENT_FIRST,
          scrollBackward: NestedScrollMode.SELF_FIRST
        })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12 + sheetTopAvoidVp(), bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }
}

@Extend(Divider)
function DividerStyle(){
  .strokeWidth(0.5)
  .color($r('sys.color.comp_divider'))
  .margin({ left: 48, right: 12 })
}
