import { CommonNav, ScrollToTopYOffset, titleBarOf } from '../view/CommonNav';
import { CommonSearch, CommonBlur } from '../view/CommonCom';
import { BatchSheetPicker } from '../view/BatchSheetPicker';
import { ArtworkCache } from '../utils/ArtworkCache';
import { musicHistory } from '../core/MusicHistory';
import { trackPlayer } from '../core/TrackPlayer';
import { musicSheet } from '../core/MusicSheet';
import { subscribedSheets } from '../core/SubscribedSheets';
import { pluginManager } from '../plugin/PluginManager';
import { Subscriptions } from '../plugin/Subscriptions';
import { downloader } from '../core/Downloader';
import { appConfig } from '../core/AppConfig';
import { localMusicSheet, downloadedSheet } from '../core/LocalMusicSheet';
import { MediaUtils } from '../utils/MediaUtils';
import { appState } from '../entryability/AppState';
import { MusicItem } from '../common/model/MediaTypes';
import { SheetItem } from '../common/model/SheetTypes';
import { MusicDataSource } from '../common/model/MusicDataSource';
import { NavPathUtils } from '../utils/NavPathUtils';
import { ROUTE_LOCAL_MUSIC, ROUTE_DOWNLOAD } from '../common/model/NavModels';
import { LOCAL_PLUGIN_PLATFORM } from '../common/Consts';
import { DialogManager } from '../utils/DialogUtils';
import { showUiToast, sheetImmersiveModifier } from '../utils/UiUtils';
import { sheetPreferType } from '../utils/BreakpointUtils';
import { BarScrollHelper, IsApiVersion_24 } from '../utils/BarScrollHelper';
import { HdsListItem, HdsSwipeActionOptions, HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';

/** 常听排行条目（歌曲 + 播放次数） */
class TopPlayRow {
  item: MusicItem;
  count: number;

  constructor(item: MusicItem, count: number) {
    this.item = item;
    this.count = count;
  }
}

/**
 * 我的页（第 5 个主 tab）：仅播放历史（搜索样式与交互参照我的歌单页）
 * - 右上角菜单：本地音乐/下载管理入口 + 搜索按钮
 * - 搜索框固定于标题栏下方（bottomBuilder 插槽），点搜索/回车应用关键词，
 *   按歌名/歌手/专辑过滤历史记录；切走 tab 自动收起
 * - 顶部听歌数据卡片（累计收听/累计播放/听过/本周在听 + 常听 TOP5 垂直柱状图），
 *   搜索中隐藏；下方为最近收听歌曲列表（歌名/歌手·专辑 + 播放次数），点击播放
 */
@ComponentV2
export struct MinePage {
  /** 当前所处 tab 序号（由 Index 传入；插入在「设置」之前） */
  @Param hostTabIndex: number = 2;
  /** 标题栏搜索框：开启后按关键词过滤历史记录（点搜索/回车才应用关键词） */
  @Local showSearchBox: boolean = false;
  @Local searchKeyword: string = '';
  /** 搜索框实时输入内容（未提交，不参与过滤） */
  @Local searchInput: string = '';
  scroller: Scroller = new Scroller();
  historySource: MusicDataSource = new MusicDataSource();
  /** 听歌数据：累计播放次数 */
  @Local totalPlays: number = 0;
  /** 听歌数据：本周在听歌曲数 */
  @Local weekActive: number = 0;
  /** 听歌数据：累计真实收听秒数 */
  @Local totalListenSec: number = 0;
  /** 常听排行 TOP5 */
  @Local topPlays: Array<TopPlayRow> = [];
  /** 乐库统计：收藏歌曲数（我的收藏歌单） */
  @Local favorCount: number = 0;
  /** 乐库统计：我的歌单数（含默认收藏歌单） */
  @Local mySheetCount: number = 0;
  /** 乐库统计：订阅歌单数 */
  @Local subscribedSheetCount: number = 0;
  /** 乐库统计：插件数 */
  @Local pluginCount: number = 0;
  /** 乐库统计：订阅源数 */
  @Local subscriptionSourceCount: number = 0;
  /** 批量多选模式选中键（platform_id） */
  @Local batchSelected: Array<string> = [];
  /** 批量「添加到歌单」选择器 */
  @Local showBatchSheetPicker: boolean = false;
  /** 批量换源进行中 */
  @Local batchChanging: boolean = false;
  /** 批量换源进度文案 */
  @Local batchChangeProgress: string = '';

  /** 切换到其他 tab 时收起搜索框并清空关键词；切回本 tab 时刷新乐库统计 */
  @Monitor('hostTabIndex')
  onTabIndexChanged(): void {
    if (this.hostTabIndex !== 2 && this.showSearchBox) {
      this.showSearchBox = false;
      this.searchKeyword = '';
      this.searchInput = '';
      appState.tabSearchClose = null;
    }
    if (this.hostTabIndex === 2) {
      this.refreshLibraryStats();
    }
  }

  aboutToAppear(): void {
    this.refreshHistory();
    this.refreshLibraryStats();
    musicHistory.onHistoryUpdated((): void => {
      this.refreshHistory();
    });
  }

  /** 刷新历史记录与听歌数据（统计取全量；列表按当前关键词过滤） */
  private refreshHistory(): void {
    const items = musicHistory.history;
    let total = 0;
    let week = 0;
    let listenSec = 0;
    let idx = 0;
    const weekAgo = Date.now() - 7 * 24 * 3600 * 1000;
    const tops: Array<TopPlayRow> = [];
    for (const it of items) {
      const stat = musicHistory.getStat(it);
      if (stat !== null) {
        total += stat.count;
        listenSec += stat.duration;
        if (stat.lastAt >= weekAgo) {
          week++;
        }
        // 「最近常听」仅统计最近 50 条记录（更贴近近期口味）
        if (idx < 50) {
          tops.push(new TopPlayRow(it, stat.count));
        }
      }
      idx++;
    }
    this.totalPlays = total;
    this.weekActive = week;
    this.totalListenSec = listenSec;
    tops.sort((a: TopPlayRow, b: TopPlayRow): number => b.count - a.count);
    this.topPlays = tops.slice(0, 5);
    this.rebuildHistorySource();
  }

  /** 按关键词过滤历史记录（标题/歌手/专辑；空关键词返回全部） */
  private displayHistory(): Array<MusicItem> {
    const kw = this.searchKeyword.trim().toLowerCase();
    const items = musicHistory.history;
    if (kw.length === 0) {
      return items;
    }
    const hit: Array<MusicItem> = [];
    for (const it of items) {
      if (it.title.toLowerCase().indexOf(kw) >= 0 ||
        it.artist.toLowerCase().indexOf(kw) >= 0 ||
        it.album.toLowerCase().indexOf(kw) >= 0) {
        hit.push(it);
      }
    }
    return hit;
  }

  /** 按当前关键词重建历史列表数据源 */
  private rebuildHistorySource(): void {
    this.historySource.clear();
    this.historySource.appendData(this.displayHistory());
  }

  /** 刷新乐库统计（收藏/歌单/订阅歌单/插件/订阅源；进入本 tab 或挂载时调用） */
  private refreshLibraryStats(): void {
    // 收藏歌曲数 = 我的收藏歌单内曲目数
    this.favorCount = musicSheet.getMusicList(musicSheet.defaultSheet.id).length;
    this.mySheetCount = musicSheet.sheets.length;
    this.subscribedSheetCount = subscribedSheets.getAll().length;
    this.pluginCount = pluginManager.getPlugins().length;
    this.subscriptionSourceCount = Subscriptions.getSources().length;
  }

  /** titleBar 右上角菜单：本地音乐/下载管理入口 + 搜索按钮 */
  private titleMenus(): Array<HdsNavigationMenuItemOptions> {
    const local: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.music_note_phone'),
        label: '本地音乐',
        action: (): void => {
          NavPathUtils.push(ROUTE_LOCAL_MUSIC);
        }
      }
    };
    const download: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.download'),
        label: '下载',
        action: (): void => {
          NavPathUtils.push(ROUTE_DOWNLOAD);
        }
      }
    };
    const search: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.magnifyingglass'),
        label: '搜索',
        action: (): void => {
          this.toggleSearchBox();
        }
      }
    };
    return [local, download, search];
  }

  /** 展开/收起标题栏搜索框（展开时列表回顶；收起时清空关键词恢复全部） */
  private toggleSearchBox(): void {
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      this.showSearchBox = !this.showSearchBox;
    });

    if (!this.showSearchBox) {
      this.searchKeyword = '';
      this.searchInput = '';
      appState.tabSearchClose = null;
      this.rebuildHistorySource();
      return;
    }
    // 登记收起回调：tab 页的返回手势由 Index 统一拦截，优先收起搜索框
    appState.tabSearchClose = (): void => {
      this.toggleSearchBox();
    };
    // 展开后请求焦点呼出软键盘（延时等待插槽挂载与展开过渡完成；id 需与 SearchBuilder 中一致）
    const focusController = this.getUIContext().getFocusController();
    setTimeout((): void => {
      try {
        focusController.requestFocus('mine_history_search');
      } catch (e) {
        // 组件未挂载时忽略
      }
    }, 320);
    if (this.scroller.currentOffset().yOffset !== 0) {
      this.scroller.scrollTo({
        xOffset: 0, yOffset: -(appState.topRect + 66 + 56),
        animation: { duration: 250, curve: Curve.EaseOut }
      });
    }
  }

  /** 标题副文本：搜索中显示命中数量，否则显示累计收听时长 */
  private subTitleText(): string {
    if (this.searchKeyword.trim().length > 0) {
      return '找到 ' + this.historySource.totalCount().toString() + ' 首';
    }
    return '累计收听 ' + this.listenDurationText() + ' ' + this.listenDurationUnit();
  }

  /** 以当前过滤结果为播放队列播放歌曲 */
  private playFrom(item: MusicItem): void {
    const list = this.historySource.getItems();
    if (list.length === 0) {
      return;
    }
    trackPlayer.playWithReplacePlayList(item, list).catch((_e: Object): void => {
      this.showToast('播放失败');
    });
  }

  /** 全部播放（参考歌单详情页 playAll）：以当前过滤结果整体替换播放队列，从第一首开始 */
  private playAll(): void {
    const playList = this.historySource.getItems();
    if (playList.length === 0) {
      this.showToast('暂无播放记录');
      return;
    }
    trackPlayer.playWithReplacePlayList(playList[0], playList).catch((_e: Object): void => {
      this.showToast('播放失败');
    });
  }

  /** 清空播放记录（DialogManager 弹窗确认，点「清空」后才执行，取消不清空） */
  private confirmClearHistory(): void {
    if (this.historySource.totalCount() === 0) {
      this.showToast('暂无播放记录');
      return;
    }
    DialogManager.ConfirmClearData('确定清空全部播放记录吗？', (): void => {
      musicHistory.clearMusic();
      this.showToast('已清空播放记录');
    });
  }

  /** 历史条目横滑操作（左滑呼出删除按钮，弹窗确认后单独删除该条记录）；批量模式下禁用 */
  private historySwipeOptions(item: MusicItem): HdsSwipeActionOptions | undefined {
    if (appState.isBatchMode) {
      return undefined;
    }
    const options: HdsSwipeActionOptions = {
      deleteIconOptions: {
        onAction: (): void => {
          this.confirmRemoveHistoryItem(item);
        }
      }
    };
    return options;
  }

  /** 删除确认（DialogManager 弹窗，点「删除」后才执行，取消不删除） */
  private confirmRemoveHistoryItem(item: MusicItem): void {
    DialogManager.ConfirmDelete('确定删除「' + item.title + '」的播放记录吗？', (): void => {
      this.removeHistoryItem(item);
    });
  }

  /** 单独删除一条播放记录（历史与统计一并移除） */
  private removeHistoryItem(item: MusicItem): void {
    musicHistory.removeMusic(item).then((): void => {
      this.showToast('已删除「' + item.title + '」');
    });
  }

  // ---------- 批量多选模式（样式与操作对齐歌单详情页） ----------

  /** 进入批量模式（全局状态：隐藏 tab 栏、返回键退出；显式动画包裹避免突兀） */
  private enterBatchMode(): void {
    if (this.historySource.totalCount() === 0) {
      this.showToast('暂无播放记录');
      return;
    }
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      appState.isBatchMode = true;
    });
    this.batchSelected = [];
  }

  /** 退出批量模式 */
  private exitBatchMode(): void {
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      appState.isBatchMode = false;
    });
    this.batchSelected = [];
  }

  private static itemKey(item: MusicItem): string {
    return item.platform + '_' + item.id;
  }

  /** 行是否被勾选 */
  private isSelected(item: MusicItem): boolean {
    return this.batchSelected.indexOf(MinePage.itemKey(item)) !== -1;
  }

  /** 批量模式下点击行：切换勾选状态 */
  private toggleBatchSelect(item: MusicItem): void {
    const key = MinePage.itemKey(item);
    const next = this.batchSelected.slice();
    const idx = next.indexOf(key);
    if (idx === -1) {
      next.push(key);
    } else {
      next.splice(idx, 1);
    }
    this.batchSelected = next;
  }

  /** 全选/取消全选 */
  private toggleSelectAll(): void {
    const all: Array<string> = [];
    for (const item of this.historySource.getItems()) {
      all.push(MinePage.itemKey(item));
    }
    this.batchSelected = this.batchSelected.length === all.length ? [] : all;
  }

  /** 勾选的歌曲实体列表（按列表顺序） */
  private selectedItems(): Array<MusicItem> {
    const result: Array<MusicItem> = [];
    for (const item of this.historySource.getItems()) {
      if (this.isSelected(item)) {
        result.push(item);
      }
    }
    return result;
  }

  /** 批量操作按钮文案（第一行：全部勾选后「全选」切换为「取消全选」） */
  private batchTopLabels(): Array<string> {
    const total = this.historySource.totalCount();
    const allSelected = total > 0 && this.batchSelected.length === total;
    return [allSelected ? '取消全选' : '全选', '下一首播放', '换源'];
  }

  /** 批量操作按钮文案（第二行：播放历史为 添加到歌单/下载） */
  private batchBottomLabels(): Array<string> {
    return ['添加到歌单', '下载'];
  }

  /** 批量下一首播放 */
  private batchPlayNext(): void {
    const items = this.selectedItems();
    if (items.length === 0) {
      this.showToast('请先勾选歌曲');
      return;
    }
    trackPlayer.addNext(items);
    this.showToast('已添加 ' + items.length.toString() + ' 首到下一首播放');
  }

  /** 打开批量「添加到歌单」选择器 */
  private openBatchSheetPicker(): void {
    if (this.selectedItems().length === 0) {
      this.showToast('请先勾选歌曲');
      return;
    }
    this.showBatchSheetPicker = true;
  }

  /** 批量添加到指定歌单 */
  private batchAddToSheet(sheet: SheetItem): void {
    const items = this.selectedItems();
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

  /**
   * 批量换源：逐首搜索其它插件的同一首歌，自动选第一个命中的候选，
   * 替换队列/歌单/播放历史（保留原顺序与统计）
   */
  private async batchChangeSource(): Promise<void> {
    if (this.batchChanging) {
      this.showToast('正在换源中，请稍候');
      return;
    }
    const items = this.selectedItems();
    if (items.length === 0) {
      this.showToast('请先勾选歌曲');
      return;
    }
    // 本地/已下载音乐与正在播放的歌曲不支持批量换源（正在播放的歌曲请单独换源）
    const targets: Array<MusicItem> = [];
    let playingSkipped = 0;
    for (const it of items) {
      if (localMusicSheet.isLocalMusicExisting(it) !== null || downloadedSheet.isLocalMusicExisting(it) !== null ||
        it.platform === LOCAL_PLUGIN_PLATFORM) {
        continue;
      }
      if (trackPlayer.isCurrentMusic(it)) {
        playingSkipped++;
        continue;
      }
      targets.push(it);
    }
    if (targets.length === 0) {
      this.showToast(playingSkipped > 0 ? '正在播放的歌曲请单独换源' : '所选歌曲不支持换源（本地音乐）');
      return;
    }
    this.batchChanging = true;
    let success = 0;
    let failed = 0;
    for (let i = 0; i < targets.length; ++i) {
      const item = targets[i];
      this.batchChangeProgress = '换源中 ' + (i + 1).toString() + '/' + targets.length.toString();
      try {
        const candidates = await trackPlayer.searchAlternateSources(item);
        const best = candidates.length > 0 ? candidates[0] : null;
        if (best !== null) {
          trackPlayer.replaceInQueue(item, best);
          musicSheet.replaceMusicEverywhere(item, best);
          await musicHistory.replaceMusic(item, best);
          success++;
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
    if (playingSkipped > 0) {
      message += '（正在播放的 ' + playingSkipped.toString() + ' 首请单独换源）';
    }
    this.showToast(message);
  }

  /** 批量下载：跳过下载中与已下载的条目 */
  private batchDownload(): void {
    const items = this.selectedItems();
    if (items.length === 0) {
      this.showToast('请先勾选歌曲');
      return;
    }
    const fresh: Array<MusicItem> = [];
    for (const it of items) {
      if (downloader.getDownloadTask(it) !== null) {
        continue;
      }
      if (downloadedSheet.isLocalMusicExisting(it) !== null) {
        continue;
      }
      fresh.push(it);
    }
    if (fresh.length === 0) {
      this.showToast('所选歌曲均已下载或正在下载');
      return;
    }
    // 弹窗填写目标子文件夹（留空 = 默认下载目录）
    DialogManager.downloadFolderValue = '';
    DialogManager.downloadFolderConfirm = (folder: string): void => {
      downloader.download(fresh, appConfig.getDefaultDownloadQuality(), folder);
      this.showToast('已加入 ' + fresh.length.toString() + ' 首到下载队列');
    };
    DialogManager.OpenDialog('下载到文件夹');
  }

  /** 历史行副标题：歌手 · 专辑 */
  private historySub(item: MusicItem): string {
    return item.artist + (item.album.length > 0 ? ' · ' + item.album : '');
  }

  /** 历史行尾部：播放 N 次 */
  private historyTail(item: MusicItem): string {
    const stat = musicHistory.getStat(item);
    const count = stat !== null ? stat.count : 0;
    return count.toString() + ' 次';
  }

  /** 累计收听时长数值：满 1 小时显示小时（一位小数），否则显示分钟（向上取整，至少 1） */
  private listenDurationText(): string {
    if (this.totalListenSec >= 3600) {
      const hours = Math.round(this.totalListenSec / 360) / 10;
      return hours.toString();
    }
    return Math.max(1, Math.ceil(this.totalListenSec / 60)).toString();
  }

  /** 累计收听时长单位 */
  private listenDurationUnit(): string {
    return this.totalListenSec >= 3600 ? '小时' : '分钟';
  }

  private showToast(message: string): void {
    showUiToast(this.getUIContext(), message);
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf($r('app.string.tab_mine'), this.subTitleText(), this.titleMenus(),
        (this.hostTabIndex === 2) ?
          { builder: (): void => { this.TitleExtraBuilder() }, height: this.showSearchBox ? 56 : 0 } : undefined),
      isHideBackButton: true,
      embedded: true,
      // 搜索框常驻标题栏下方，不随滚动隐藏（否则上滑隐藏、下滑才重现）
      isSearchBarScroller: false,
      scroller: this.scroller,
      doubleTapToTop: true,
      scrollToTopYOffset: ScrollToTopYOffset(this.showSearchBox ? 56 : 0)
    }) {
      // Stack 承载列表 + 批量模式底栏 + 「添加到歌单」选择器锚点
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 12 }) {
        // 搜索中隐藏乐库/听歌数据卡，仅展示结果列表
        if (this.searchKeyword.trim().length === 0 && this.historySource.totalCount() > 0) {
          ListItem() {
            this.LibraryCardBuilder()
          }
          ListItem() {
            this.StatsCardBuilder()
          }
        }
          ListItem() {
            this.HistoryHeaderBuilder()
          }
          if (this.historySource.totalCount() > 0) {
            LazyForEach(this.historySource, (item: MusicItem, _index: number) => {
              // HdsListItem 不支持通用属性，链式设置会破坏横滑手势，故不挂 transition
              HdsListItem({
                customItemBuilder: (): void => {
                  this.MusicRowBuilder(item, this.historySub(item), this.historyTail(item));
                },
                swipeActionOptions: this.historySwipeOptions(item)
              })
            }, (item: MusicItem, index: number) => item.platform + '_' + item.id + '_' + index.toString() +
              '_' + appState.swipeResetTick.toString() +
              (appState.isBatchMode && this.isSelected(item) ? '_sel' : ''))
          } else {
            ListItem() {
              this.EmptyBuilder(this.searchKeyword.trim().length > 0 ?
                '未找到匹配的播放记录' : '暂无播放记录，播放歌曲后将显示在这里')
            }
          }
        }
        .ListStyle(this.showSearchBox ? 56 : 0)
        .onScrollFrameBegin((offset: number) => {
          BarScrollHelper.notifyScrollDelta(this.getUIContext(), offset)
          return { offsetRemain: offset }
        })

        // 批量模式底栏（透明悬浮于列表之上，列表底部渐变模糊）：
        // 已选行 + 全选 / 下一首播放 / 换源 + 添加到歌单 / 下载
        if (appState.isBatchMode) {
          // 渐变模糊高度与底栏内容高度一致（样式同歌单详情页）
          CommonBlur({ heightValue: appState.bottomRect + 138 }).position({ bottom: 0 })
            .transition(TransitionEffect.OPACITY)

          Column({ space: 10 }) {
            Row() {
              Text(this.batchChanging ? this.batchChangeProgress :
                '已选 ' + this.batchSelected.length.toString() + ' 首歌曲')
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
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .borderRadius(10)
                  .padding({ left: 2, right: 2 })
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  .fontColor($r('sys.color.font_primary'))
                  .onClick(() => {
                    if (i === 0) {
                      this.toggleSelectAll();
                    } else if (i === 1) {
                      this.batchPlayNext();
                    } else {
                      this.batchChangeSource();
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
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .borderRadius(10)
                  .padding({ left: 2, right: 2 })
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  .fontColor($r('sys.color.font_primary'))
                  .onClick(() => {
                    if (i === 0) {
                      this.openBatchSheetPicker();
                    } else {
                      this.batchDownload();
                    }
                  })
              }, (v: string, i: number) => v + '_' + i.toString())
            }
            .width('100%')
          }
          .width('100%')
          .position({ bottom: 0 })
          .padding({ top: 14, left: 16, right: 16, bottom: appState.bottomRect + 12 })
          .transition(TransitionEffect.OPACITY)
        }

        // 批量「添加到歌单」选择器锚点（零高度节点挂载半模态）
        Column()
          .width('100%')
          .height(0)
          .bindSheet(!!this.showBatchSheetPicker, this.BatchSheetPickerBuilder(), {
            systemMaterial: sheetImmersiveModifier(),
            scrollSizeMode: ScrollSizeMode.CONTINUOUS, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
            dragBar: true, preferType: sheetPreferType(),
            onWillDisappear: () => {
              this.showBatchSheetPicker = false;
              appState.isForegroundBlur = false;
            },
            onWillAppear: () => {
              appState.isForegroundBlur = true;
            }
          })
      }
      .width('100%')
      .height('100%')
    }
  }

  /** 批量「添加到歌单」选择器内容 */
  @Builder
  BatchSheetPickerBuilder() {
    BatchSheetPicker({
      sheets: this.getUserSheets(),
      onPick: (sheet: SheetItem): void => {
        this.batchAddToSheet(sheet);
      }
    })
  }

  /** 标题栏下方扩展区：搜索框（展开时挂载，从顶部滑入） */
  @Builder
  TitleExtraBuilder() {
    Column() {
      if (this.showSearchBox) {
        this.SearchBuilder()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 搜索框（固定于标题栏下方，不随列表滚动消失；切到其他 tab 自动收起；
   * 输入不即时过滤，点搜索按钮/软键盘回车后才应用关键词）
   */
  @Builder
  SearchBuilder() {
    CommonSearch({
      searchValue: this.searchInput,
      placeholderValue: '搜索歌名、歌手或专辑',
      focusId: 'mine_history_search',
      submit: (): void => {
        this.searchKeyword = this.searchInput.trim();
        this.rebuildHistorySource();
      },
      change: (v: string): void => {
        this.searchInput = v;
      },
      didDelete: (): void => {
        this.searchInput = '';
        this.searchKeyword = '';
        this.rebuildHistorySource();
      },
    })
      .width('100%')
      .padding({ left: 16, right: 16 })
      .transition(TransitionEffect.move(TransitionEdge.TOP))
  }

  /**
   * 历史列表头部（全部播放组件样式）：大播放图标 + 「最近收听」，点击播放全部；
   * 右侧「清空」按钮（弹窗确认），无尾部箭头
   */
  @Builder
  HistoryHeaderBuilder() {
    Row() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.play_circle_fill'))
          .fontSize(36)
          .fontColor([$r('sys.color.font')])
        Text('最近收听 · ' + this.historySource.totalCount().toString())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font'))
      }
      .onClick(() => {
        this.playAll();
      })

      Blank()

      if (!appState.isBatchMode) {
        // 批量操作入口（最近收听右侧、清空前）
        SymbolGlyph($r('sys.symbol.list_checkmask'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
          .padding({ left: 12, top: 6, bottom: 6 })
          .onClick(() => {
            this.enterBatchMode();
          })
        // 清空播放记录（删除图标，弹窗确认后执行）
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
          .padding({ left: 12, right: 4, top: 6, bottom: 6 })
          .onClick(() => {
            this.confirmClearHistory();
          })
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 4, right: 4 })
  }

  /** 歌曲行（卡片样式，风格同下载页歌曲行）：封面 + 歌名 + 副标题 + 尾部信息；
   *  正常点击播放，长按进入批量模式，批量模式下点击切换勾选 */
  @Builder
  MusicRowBuilder(item: MusicItem, sub: string, tail: string) {
    Row({ space: 12 }) {
      if (appState.isBatchMode) {
        SymbolGlyph(this.isSelected(item) ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
          .fontSize(24)
          .fontColor([this.isSelected(item) ? appState.accentColor : $r('sys.color.icon_tertiary')])
          .transition(TransitionEffect.OPACITY)
      }
      if (item.artwork.length > 0) {
        Image(ArtworkCache.resolve(item.artwork))
          .width(40)
          .height(40)
          .borderRadius(10)
          .objectFit(ImageFit.Cover)
          .alt($r('app.media.altImage'))
          .draggable(false)
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

      Column({ space: 2 }) {
        Text(item.title)
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(sub)
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (tail.length > 0) {
        Text(tail)
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
      }
    }
    .width('100%')
    .height(80)
    .borderRadius(16)
    .padding(12)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .onClick(() => {
      if (appState.isBatchMode) {
        this.toggleBatchSelect(item);
      } else {
        this.playFrom(item);
      }
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          if (appState.isBatchMode) {
            return;
          }
          this.enterBatchMode();
          this.toggleBatchSelect(item);
        })
    )
  }

  /**
   * 我的乐库卡片（列表顶部独立卡片）：
   * 收藏歌曲 / 我的歌单 / 订阅歌单 / 插件 / 订阅源（图标 + 数值 + 标签）
   */
  @Builder
  LibraryCardBuilder() {
    Column() {
      Row() {
        this.LibraryStatEntry($r('sys.symbol.heart_fill'), this.favorCount.toString(), '收藏歌曲')
        this.LibraryStatEntry($r('sys.symbol.music_note_list'), this.mySheetCount.toString(), '我的歌单')
        this.LibraryStatEntry($r('sys.symbol.music_note_list_square'), this.subscribedSheetCount.toString(),
          '订阅歌单')
        this.LibraryStatEntry($r('sys.symbol.AI_panels'), this.pluginCount.toString(), '插件')
        this.LibraryStatEntry($r('sys.symbol.dot_radiowaves_left_and_right'),
          this.subscriptionSourceCount.toString(), '订阅源')
      }
      .width('100%')
    }
    .width('100%')
    .borderRadius(16)
    .padding(16)
    .backgroundColor($r('sys.color.comp_background_list_card'))
  }

  /** 听歌数据卡片：累计收听/累计播放/听过/本周在听 四项统计 + 常听 TOP5 垂直柱状图 */
  @Builder
  StatsCardBuilder() {
    Column({ space: 14 }) {
      Row() {
        this.StatBlock(this.listenDurationText(), this.listenDurationUnit(), '累计收听')
        this.StatBlock(this.totalPlays.toString(), '次', '累计播放')
        this.StatBlock(this.historySource.totalCount().toString(), '首', '听过')
        this.StatBlock(this.weekActive.toString(), '首', '本周在听')
      }
      .width('100%')

      if (this.topPlays.length > 0) {
        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.comp_divider'))

        Text('最近常听')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')

        // 垂直柱状图：柱高按播放次数占比（TOP1 满高 72，最低 12），按名次降低透明度
        Row({ space: 4 }) {
          ForEach(this.topPlays, (row: TopPlayRow, index: number) => {
            Column({ space: 5 }) {
              Text(row.count.toString() + ' 次')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_secondary'))
              // 柱体轨道（底部对齐，保持柱高动画时数值标签稳定）
              Column() {
                Column()
                  .width('64%')
                  .height(Math.max(12, Math.round(72 * row.count / Math.max(this.topPlays[0].count, 1))))
                  .borderRadius({ topLeft: 5, topRight: 5 })
                  .backgroundColor(appState.accentColor)
                  .opacity(1 - index * 0.16)
              }
              .width('100%')
              .height(72)
              .justifyContent(FlexAlign.End)
              .alignItems(HorizontalAlign.Center)
              Text(row.item.title)
                .fontSize(11)
                .fontColor($r('sys.color.font_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .textAlign(TextAlign.Center)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
          }, (row: TopPlayRow, index: number) => row.item.platform + '_' + row.item.id + '_' + index.toString() + '_' + row.count.toString())
        }
        .width('100%')
      }
    }
    .width('100%')
    .borderRadius(16)
    .padding(16)
    .backgroundColor($r('sys.color.comp_background_list_card'))
  }

  /** 单项统计块：大号数值 + 小号单位（底对齐，基线视觉近似），下方短标签（单行防换行错位） */
  @Builder
  StatBlock(value: string, unit: string, label: string) {
    Column({ space: 3 }) {
      Row({ space: 2 }) {
        Text(value)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(appState.accentColor)
          .maxLines(1)
        Text(unit)
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .margin({ bottom: 3 })
      }
      .alignItems(VerticalAlign.Bottom)
      Text(label)
        .fontSize(11)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(1)
    }
    .layoutWeight(1)
  }

  /** 乐库统计项：主题色图标 + 数值同行，下方灰色标签 */
  @Builder
  LibraryStatEntry(icon: Resource, value: string, label: string) {
    Column({ space: 4 }) {
      Row({ space: 5 }) {
        SymbolGlyph(icon)
          .fontSize(17)
          .fontColor([appState.accentColor])
        Text(value)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
      }
      .alignItems(VerticalAlign.Center)

      Text(label)
        .fontSize(11)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(1)
    }
    .layoutWeight(1)
  }

  /** 空态文案 */
  @Builder
  EmptyBuilder(message: string) {
    Text(message)
      .fontSize(13)
      .fontColor($r('sys.color.font_tertiary'))
      .width('100%')
      .textAlign(TextAlign.Center)
      .margin({ top: 32 })
  }
}

@Extend(List)
function ListStyle(extraTop: number) {
  .width('100%')
  .height('100%')
  .scrollBar(BarState.Off)
  .edgeEffect(EdgeEffect.Spring)
  // 搜索框展开时为固定搜索框让位
  .contentStartOffset(appState.topRect + 66 + extraTop)
  // 批量模式下为底部操作栏让位（样式同歌单详情页）
  .contentEndOffset(appState.bottomRect + (appState.isBatchMode ? 154 :
    (IsApiVersion_24() && appState.hdsBarLayoutMode === 1 ? 130 : 60)))
  .padding({ left: 16, right: 16 })
}
