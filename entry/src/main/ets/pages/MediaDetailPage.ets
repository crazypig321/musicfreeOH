import { CommonNav, titleBarOf } from '../view/CommonNav';
import { ArtworkCache } from '../utils/ArtworkCache';
import { CommonBlur, CommonSearch } from '../view/CommonCom';
import { HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { MusicOptionsSheet } from '../view/MusicOptionsSheet';
import { MusicItem } from '../common/model/MediaTypes';
import { MusicRow } from '../view/MusicRow';
import { DetailHeader } from '../view/DetailHeader';
import { BatchSheetPicker } from '../view/BatchSheetPicker';
import { AlbumItem, ArtistItem, SheetItem, SupportMediaType } from '../common/model/SheetTypes';
import { MusicDataSource } from '../common/model/MusicDataSource';
import { MediaDetailNavParams } from '../common/model/NavModels';
import { Plugin } from '../plugin/Plugin';
import { pluginManager } from '../plugin/PluginManager';
import { trackPlayer } from '../core/TrackPlayer';
import { downloader } from '../core/Downloader';
import { downloadedSheet, localMusicSheet } from '../core/LocalMusicSheet';
import { musicSheet, SheetBasePatch } from '../core/MusicSheet';
import { appConfig } from '../core/AppConfig';
import { MediaUtils } from '../utils/MediaUtils';
import { appState } from '../entryability/AppState';
import { sheetTopAvoidVp } from '../utils/BreakpointUtils';
import { LOCAL_PLUGIN_PLATFORM, MAX_PLAYLIST_SIZE } from '../common/Consts';
import { DialogManager } from '../utils/DialogUtils';

/** 一次分页加载结果（专辑/歌手统一封装） */
class MediaDetailPageResult {
  musicList: Array<MusicItem> = [];
  isEnd: boolean = false;
  /** 专辑模式：首页返回的合并专辑信息 */
  albumItem: AlbumItem | null = null;
}

/**
 * 专辑/歌手详情页（搜索结果进入；UI 与歌单详情页一致）
 * 专辑走 getAlbumInfo（首页合并专辑信息），歌手走 getArtistWorks(music)，触底续拉
 * 顶部头部：封面全宽渐变 + 名称 + 简介 + 全部播放 + 批量操作
 * 批量模式（UI 同歌单详情页插件歌单）：全选/下一首播放/换源 + 添加到歌单/下载
 */
@ComponentV2
export struct MediaDetailPage {
  /** 专辑模式（false 为歌手模式） */
  private isAlbum: boolean = true;
  /** 头部标题（专辑名/歌手名） */
  @Local headerTitle: string = '';
  /** 头部封面（专辑封面/歌手头像） */
  @Local coverUrl: string = '';
  /** 简介 */
  @Local description: string = '';
  /** 歌手模式统计行（作品数/粉丝数） */
  @Local artistStats: string = '';
  /** 首次加载中 */
  @Local loading: boolean = false;
  /** 触底续拉中 */
  @Local loadingMore: boolean = false;
  /** 已加载歌曲数 */
  @Local musicCount: number = 0;
  /** 首次加载失败 */
  @Local loadFailed: boolean = false;
  /** 单项操作半模态 */
  @Local showOptions: boolean = false;
  @Local optionsItem: MusicItem = new MusicItem();
  /** 批量模式勾选的条目 key（platform_id） */
  @Local batchSelected: Array<string> = [];
  /** 批量「添加到歌单」选择器 */
  @Local showBatchSheetPicker: boolean = false;
  /** 批量换源进行中 */
  @Local batchChanging: boolean = false;
  /** 批量换源进度文案 */
  @Local batchChangeProgress: string = '';
  /** 标题栏搜索框展开 */
  @Local showSearchBox: boolean = false;
  /** 已应用的搜索关键词（点搜索/回车后生效） */
  @Local searchKeyword: string = '';
  /** 搜索框输入内容 */
  @Local searchInput: string = '';

  dataSource: MusicDataSource = new MusicDataSource();
  /** 搜索结果数据源（关键词生效时替代全量列表展示） */
  private searchSource: MusicDataSource = new MusicDataSource();
  private scroller: Scroller = new Scroller();
  private plugin: Plugin | null = null;
  private album: AlbumItem | null = null;
  private artist: ArtistItem | null = null;
  private page: number = 1;
  private isEnd: boolean = false;
  /** 请求序号（仅应用最新一次请求的结果） */
  private reqSeq: number = 0;
  /** 后台补齐播放队列进行中 */
  private bgLoadingAll: boolean = false;
  /** 导入我的歌单进行中 */
  private importing: boolean = false;
  /** 页面存活标记（销毁后停止 UI 写入，队列补齐继续） */
  private pageAlive: boolean = true;
  /** 后台补齐安全页数上限 */
  private static readonly MAX_BG_PAGES: number = 100;

  aboutToAppear(): void {
    this.album = MediaDetailNavParams.album;
    this.artist = MediaDetailNavParams.artist;
    this.isAlbum = this.album !== null;
    if (this.isAlbum && this.album !== null) {
      this.headerTitle = this.album.title;
      this.coverUrl = this.album.artwork;
      this.description = this.album.description;
    } else if (this.artist !== null) {
      this.headerTitle = this.artist.name;
      this.coverUrl = this.artist.avatar;
      this.description = this.artist.description;
      this.artistStats = MediaDetailPage.formatArtistStats(this.artist);
    }
    const name = MediaDetailNavParams.pluginName;
    this.plugin = name.length > 0 ? pluginManager.getByName(name) : null;
    this.loadPage(true);
  }

  aboutToDisappear(): void {
    this.pageAlive = false;
  }

  /** 拉取一页歌曲（专辑：getAlbumInfo；歌手：getArtistWorks(music)） */
  private async fetchPage(page: number): Promise<MediaDetailPageResult | null> {
    const plugin = this.plugin;
    if (plugin === null) {
      return null;
    }
    const result = new MediaDetailPageResult();
    if (this.isAlbum) {
      const album = this.album;
      if (album === null) {
        return null;
      }
      const r = await plugin.methods.getAlbumInfo(album, page);
      if (r === null) {
        return null;
      }
      result.musicList = r.musicList;
      result.isEnd = r.isEnd;
      result.albumItem = r.albumItem;
      return result;
    }
    const artist = this.artist;
    if (artist === null) {
      return null;
    }
    const r = await plugin.methods.getArtistWorks(artist, page, SupportMediaType.Music);
    result.musicList = r.musicData;
    result.isEnd = r.isEnd;
    return result;
  }

  /** 加载歌曲：reset 重新加载第一页，否则触底续拉 */
  private loadPage(reset: boolean): void {
    if (this.plugin === null || this.loading || this.loadingMore) {
      return;
    }
    if (!reset && this.isEnd) {
      return;
    }
    if (reset) {
      this.loading = true;
      this.loadFailed = false;
    } else {
      this.loadingMore = true;
    }
    this.reqSeq++;
    const seq = this.reqSeq;
    const page = reset ? 1 : this.page + 1;
    this.fetchPage(page).then((r: MediaDetailPageResult | null): void => {
      if (r === null) {
        this.onLoadError(seq, reset);
        return;
      }
      this.applyResult(r, seq, reset, page);
    }).catch((_e: Object): void => {
      this.onLoadError(seq, reset);
    });
  }

  /** 应用一次加载结果 */
  private applyResult(r: MediaDetailPageResult, seq: number, reset: boolean, page: number): void {
    if (seq !== this.reqSeq) {
      return;
    }
    this.loading = false;
    this.loadingMore = false;
    this.page = page;
    this.isEnd = r.isEnd;
    if (reset) {
      this.dataSource.clear();
    }
    this.dataSource.appendData(r.musicList);
    this.musicCount = this.dataSource.totalCount();
    // 搜索中：新到达的页同样纳入过滤结果
    this.applySearchFilter();
    // 专辑模式：首页返回的合并信息补全头部
    if (r.albumItem !== null) {
      if (r.albumItem.title.length > 0) {
        this.headerTitle = r.albumItem.title;
      }
      if (this.coverUrl.length === 0 && r.albumItem.artwork.length > 0) {
        this.coverUrl = r.albumItem.artwork;
      }
      if (r.albumItem.description.length > 0 && this.description.length === 0) {
        this.description = r.albumItem.description;
      }
    }
  }

  /** 加载失败 */
  private onLoadError(seq: number, reset: boolean): void {
    if (seq !== this.reqSeq) {
      return;
    }
    this.loading = false;
    this.loadingMore = false;
    if (reset) {
      this.loadFailed = true;
    }
  }

  /** 播放（以已加载列表为播放队列） */
  private playItem(item: MusicItem): void {
    const playList = this.visibleMusicList();
    if (playList.length === 0) {
      return;
    }
    trackPlayer.playWithReplacePlayList(item, playList).catch((_e: Object): void => {
      this.showToast('播放失败');
    });
  }

  /** 全部播放：立即以已加载歌曲开始播放，剩余页后台补齐到播放队列 */
  private playAll(): void {
    const playList = this.visibleMusicList();
    if (playList.length === 0) {
      this.showToast(this.loading ? '加载中，请稍候' : '暂无歌曲');
      return;
    }
    trackPlayer.playWithReplacePlayList(playList[0], playList).catch((_e: Object): void => {
      this.showToast('播放失败');
    });
    if (!this.isSearching()) {
      this.loadRemainingToQueue();
    }
  }

  // ---------- 标题栏搜索（已加载列表内过滤，点搜索/回车应用关键词） ----------

  /** 搜索中（关键词已生效） */
  private isSearching(): boolean {
    return this.searchKeyword.trim().length > 0;
  }

  /** 当前展示列表：搜索中返回过滤结果，否则返回全量已加载列表 */
  private visibleMusicList(): Array<MusicItem> {
    return this.isSearching() ? this.searchSource.getItems() : this.dataSource.getItems();
  }

  /** 当前展示歌曲数 */
  private visibleMusicCount(): number {
    return this.isSearching() ? this.searchSource.totalCount() : this.musicCount;
  }

  /** 关键词匹配（歌名/歌手/专辑，不区分大小写） */
  private itemMatchesKeyword(item: MusicItem): boolean {
    const kw = this.searchKeyword.trim().toLowerCase();
    if (kw.length === 0) {
      return true;
    }
    return item.title.toLowerCase().indexOf(kw) >= 0 ||
      item.artist.toLowerCase().indexOf(kw) >= 0 ||
      item.album.toLowerCase().indexOf(kw) >= 0;
  }

  /** 按关键词重建搜索结果数据源 */
  private applySearchFilter(): void {
    this.searchSource.clear();
    if (!this.isSearching()) {
      return;
    }
    const filtered: Array<MusicItem> = [];
    for (const item of this.dataSource.getItems()) {
      if (this.itemMatchesKeyword(item)) {
        filtered.push(item);
      }
    }
    this.searchSource.appendData(filtered);
  }

  /** 展开/收起标题栏搜索框（收起时清空关键词恢复全部；展开时列表回顶） */
  private toggleSearchBox(): void {
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      this.showSearchBox = !this.showSearchBox;
    });

    if (!this.showSearchBox) {
      this.searchKeyword = '';
      this.searchInput = '';
      return;
    }
    // 展开后请求焦点呼出软键盘（延时等待插槽挂载与展开过渡完成；id 需与 SearchBuilder 中一致）
    const focusController = this.getUIContext().getFocusController();
    setTimeout((): void => {
      try {
        focusController.requestFocus('media_detail_search');
      } catch (e) {
        // 组件未挂载时忽略
      }
    }, 320);
    if (this.scroller.currentOffset().yOffset !== 0) {
      this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: 250, curve: Curve.EaseOut } });
    }
  }

  /** titleBar 搜索按钮 */
  private titleMenus(): Array<HdsNavigationMenuItemOptions> {
    const search: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.magnifyingglass'),
        label: '搜索',
        action: (): void => {
          this.toggleSearchBox();
        }
      }
    };
    return [search];
  }

  /** 后台加载剩余页并追加到播放队列尾部（同时补全页面列表）；loadingMore=true 阻断手动触底加载 */
  private loadRemainingToQueue(): void {
    if (this.bgLoadingAll || this.isEnd || this.plugin === null) {
      return;
    }
    this.bgLoadingAll = true;
    this.loadingMore = true;
    this.loadNextPageToQueue();
  }

  /** 逐页拉取剩余歌曲：终止条件（已结束/超过安全页数/超过队列上限）后收尾 */
  private loadNextPageToQueue(): void {
    if (this.plugin === null || this.isEnd ||
      this.page >= MediaDetailPage.MAX_BG_PAGES || this.dataSource.totalCount() >= MAX_PLAYLIST_SIZE) {
      this.finishBgLoad(false);
      return;
    }
    const nextPage = this.page + 1;
    this.fetchPage(nextPage).then((r: MediaDetailPageResult | null): void => {
      if (r === null) {
        this.finishBgLoad(true);
        return;
      }
      this.applyBgPage(r, nextPage);
    }).catch((_e: Object): void => {
      this.finishBgLoad(true);
    });
  }

  /** 应用一页后台加载结果：补全页面列表 + 追加到播放队列（传 clone 副本，避免 addAll 原地改写污染 dataSource 对象） */
  private applyBgPage(r: MediaDetailPageResult, page: number): void {
    this.page = page;
    // 空页但未声明结束：视为结束，防止死循环
    this.isEnd = r.isEnd || r.musicList.length === 0;
    if (r.musicList.length > 0) {
      if (this.pageAlive) {
        this.dataSource.appendData(r.musicList);
        this.musicCount = this.dataSource.totalCount();
      }
      const copies: Array<MusicItem> = [];
      for (const it of r.musicList) {
        copies.push(it.clone());
      }
      trackPlayer.addAll(copies);
    }
    this.loadNextPageToQueue();
  }

  /** 后台补齐收尾 */
  private finishBgLoad(failed: boolean): void {
    this.bgLoadingAll = false;
    if (this.pageAlive) {
      this.loadingMore = false;
      if (failed) {
        this.showToast('剩余歌曲加载中断');
      }
    }
  }

  /** 打开单项操作半模态（与搜索结果一致） */
  private openOptions(item: MusicItem): void {
    this.optionsItem = item.clone();
    this.showOptions = true;
  }

  // ---------- 导入我的歌单 ----------

  /** 一键加入歌单：已加载歌曲立即入册，未加载完时逐页补齐后整体导入（保留原名称与简介） */
  private importToMySheets(): void {
    if (this.importing) {
      this.showToast('正在导入，请稍候');
      return;
    }
    if (this.bgLoadingAll || this.loading || this.loadingMore) {
      this.showToast('正在加载，请稍候');
      return;
    }
    if (this.plugin === null) {
      this.showToast('导入失败');
      return;
    }
    if (this.musicCount === 0) {
      this.showToast(this.loading ? '加载中，请稍候' : '暂无歌曲');
      return;
    }
    this.importing = true;
    // loadingMore=true 阻断手动触底加载，与导入链互斥
    this.loadingMore = true;
    this.showToast('正在导入歌单…');
    if (this.isEnd) {
      this.finishImport();
      return;
    }
    this.importNextPage();
  }

  /** 逐页拉取剩余歌曲（仅补全页面列表，不动播放队列） */
  private importNextPage(): void {
    if (this.plugin === null ||
      this.page >= MediaDetailPage.MAX_BG_PAGES || this.dataSource.totalCount() >= MAX_PLAYLIST_SIZE) {
      this.finishImport();
      return;
    }
    const nextPage = this.page + 1;
    this.fetchPage(nextPage).then((r: MediaDetailPageResult | null): void => {
      if (r === null) {
        this.finishImport();
        return;
      }
      this.page = nextPage;
      // 空页但未声明结束：视为结束，防止死循环
      this.isEnd = r.isEnd || r.musicList.length === 0;
      if (r.musicList.length > 0) {
        this.dataSource.appendData(r.musicList);
        this.musicCount = this.dataSource.totalCount();
      }
      if (this.isEnd) {
        this.finishImport();
      } else {
        this.importNextPage();
      }
    }).catch((_e: Object): void => {
      this.finishImport();
    });
  }

  /** 导入收尾：新建歌单 → 写入全部歌曲 → 回写原简介/封面 */
  private finishImport(): void {
    this.importing = false;
    this.loadingMore = false;
    const items = this.dataSource.getItems();
    if (items.length === 0) {
      this.showToast('导入失败：歌单为空');
      return;
    }
    let newSheetId = '';
    musicSheet.addSheet(this.headerTitle).then((id: string): Promise<void> => {
      newSheetId = id;
      return musicSheet.addMusic(newSheetId, items);
    }).then((): void => {
      // addMusic 会把封面改成本地第一首，这里回写原简介与封面
      const patch = new SheetBasePatch();
      if (this.description.length > 0) {
        patch.description = this.description;
      }
      if (this.coverUrl.length > 0) {
        patch.coverImg = this.coverUrl;
      }
      const author = this.importAuthorName();
      if (author.length > 0) {
        patch.artist = author;
      }
      musicSheet.updateMusicSheetBase(newSheetId, patch);
      this.showToast('已导入到我的歌单');
    }).catch((_e: Object): void => {
      this.showToast('导入失败');
    });
  }

  /** 导入时回写的作者名（专辑：歌手名；歌手：歌手名） */
  private importAuthorName(): string {
    if (this.isAlbum && this.album !== null) {
      return this.album.artist;
    }
    if (!this.isAlbum && this.artist !== null) {
      return this.artist.name;
    }
    return '';
  }

  // ---------- 批量多选模式 ----------

  /** 进入批量模式（全局状态：隐藏 tab 栏、返回键退出；显式动画包裹避免突兀） */
  private enterBatchMode(): void {
    if (this.musicCount === 0) {
      this.showToast('暂无歌曲');
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
    return this.batchSelected.indexOf(MediaDetailPage.itemKey(item)) !== -1;
  }

  /** 批量模式下点击行：切换勾选状态 */
  private toggleBatchSelect(item: MusicItem): void {
    const key = MediaDetailPage.itemKey(item);
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
    for (const item of this.dataSource.getItems()) {
      all.push(MediaDetailPage.itemKey(item));
    }
    this.batchSelected = this.batchSelected.length === all.length ? [] : all;
  }

  /** 批量操作按钮文案（第一行：全部勾选后「全选」切换为「取消全选」） */
  private batchTopLabels(): Array<string> {
    const allSelected = this.musicCount > 0 && this.batchSelected.length === this.musicCount;
    const selectLabel = allSelected ? '取消全选' : '全选';
    return [selectLabel, '下一首播放', '换源'];
  }

  /** 批量换源：逐首搜索其它插件的同一首歌，自动选第一个命中的候选，替换队列并保存到歌单 */
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
      if (localMusicSheet.isLocalMusic(it) !== null || downloadedSheet.isLocalMusic(it) !== null ||
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
          const inQueue = trackPlayer.replaceInQueue(item, best);
          const saved = musicSheet.replaceMusicEverywhere(item, best);
          if (inQueue || saved > 0) {
            success++;
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
    if (playingSkipped > 0) {
      message += '（正在播放的 ' + playingSkipped.toString() + ' 首请单独换源）';
    }
    this.showToast(message);
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
      if (downloadedSheet.isLocalMusic(it) !== null) {
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

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  /** 专辑模式副标题：歌手名 + 发行日期 */
  private albumSubTitle(): string {
    const album = this.album;
    if (album === null) {
      return '';
    }
    return album.artist + (album.date.length > 0 ? ' · ' + album.date : '');
  }

  /** 歌手统计行：作品数 + 粉丝数 */
  private static formatArtistStats(artist: ArtistItem): string {
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

  private static formatDuration(sec: number): string {
    const s = Math.max(0, Math.floor(sec));
    const m = Math.floor(s / 60);
    const r = s % 60;
    const mStr = m < 10 ? '0' + m.toString() : m.toString();
    const rStr = r < 10 ? '0' + r.toString() : r.toString();
    return mStr + ':' + rStr;
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf(this.isAlbum ? '专辑详情' : '歌手详情',
        this.isSearching() ? '找到 ' + this.visibleMusicCount().toString() + ' 首' : undefined,
        this.titleMenus(),
        this.showSearchBox ? { builder: (): void => { this.SearchBuilder() } } : undefined),
      scroller: this.scroller,
      doubleTapToTop: true,
      isShowPlayBar: true,
      backPressed: (): boolean => {
        // 批量操作模式下返回键先退出批量模式
        if (appState.isBatchMode) {
          this.exitBatchMode();
          return true;
        }
        // 搜索框展开时返回键先收起搜索框并清空关键词
        if (this.showSearchBox) {
          this.toggleSearchBox();
          return true;
        }
        return false;
      }
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller }) {
          // 头部：封面（向下渐变融入背景，不避让标题栏）+ 名称 + 简介 + 全部播放/批量操作
          ListItem() {
            this.HeaderBuilder()
          }

          if (this.plugin === null) {
            // 插件不可用
            ListItem() {
              Text('插件不可用，请返回重新进入')
                .fontSize(13)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
                .margin({ top: 16 })
            }
          } else if (this.loading && this.musicCount === 0) {
            // 首次加载中
            ListItem() {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color(appState.accentColor)
                Text('加载中...')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
              }
              .width('100%')
              .height(48)
              .justifyContent(FlexAlign.Center)
            }
          } else if (this.loadFailed && this.musicCount === 0) {
            // 首次加载失败
            ListItem() {
              Column({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                  .fontSize(44)
                  .fontColor([$r('sys.color.icon_tertiary')])
                Text('加载失败，请返回重试')
                  .fontSize(14)
                  .fontColor($r('sys.color.font_secondary'))
              }
              .width('100%')
              .margin({ top: 32 })
              .alignItems(HorizontalAlign.Center)
            }
          } else if (this.musicCount === 0) {
            // 空态
            ListItem() {
              Column({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.music_note_list'))
                  .fontSize(44)
                  .fontColor([$r('sys.color.icon_tertiary')])
                Text('暂无歌曲')
                  .fontSize(14)
                  .fontColor($r('sys.color.font_secondary'))
              }
              .width('100%')
              .margin({ top: 32 })
              .alignItems(HorizontalAlign.Center)
            }
          } else if (this.isSearching()) {
            // 搜索结果列表（仅过滤已加载内容）
            if (this.searchSource.totalCount() === 0) {
              ListItem() {
                Text('未找到匹配的歌曲')
                  .fontSize(13)
                  .fontColor($r('sys.color.font_tertiary'))
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .margin({ top: 32 })
              }
            } else {
              LazyForEach(this.searchSource, (item: MusicItem, index: number) => {
                ListItem() {
                  this.MusicRowBuilder(item, index)
                }
              }, (item: MusicItem, _index: number) => item.platform + '_' + item.id +
                (appState.isBatchMode && this.isSelected(item) ? '_sel' : ''))
            }
          } else {
            // 歌曲列表
            LazyForEach(this.dataSource, (item: MusicItem, index: number) => {
              ListItem() {
                this.MusicRowBuilder(item, index)
              }
            }, (item: MusicItem, _index: number) => item.platform + '_' + item.id +
              (appState.isBatchMode && this.isSelected(item) ? '_sel' : ''))
            // 底部加载状态
            if (this.loadingMore) {
              ListItem() {
                Row({ space: 8 }) {
                  LoadingProgress()
                    .width(18)
                    .height(18)
                    .color(appState.accentColor)
                  Text('加载中...')
                    .fontSize(12)
                    .fontColor($r('sys.color.font_tertiary'))
                }
                .width('100%')
                .height(48)
                .justifyContent(FlexAlign.Center)
              }
            } else if (this.isEnd && this.musicCount > 0) {
              ListItem() {
                Text('没有更多了')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: 12, bottom: 12 })
              }
            }
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .contentEndOffset(appState.bottomRect + (appState.isBatchMode ? 154 : 60))
        .onReachEnd(() => {
          // 搜索中：仅过滤已加载内容，不触发续拉
          if (!this.isSearching()) {
            this.loadPage(false);
          }
        })

        // 批量模式底栏（透明悬浮于列表之上，列表底部渐变模糊）：
        // 已选行 + 全选 / 下一首播放 / 换源 + 添加到歌单 / 下载
        if (appState.isBatchMode) {
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
              Button('添加到歌单')
                .layoutWeight(1)
                .height(36)
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .borderRadius(10)
                .padding({ left: 2, right: 2 })
                .backgroundColor($r('sys.color.comp_background_tertiary'))
                .fontColor($r('sys.color.font_primary'))
                .onClick(() => {
                  this.openBatchSheetPicker();
                })
              Button('下载')
                .layoutWeight(1)
                .height(36)
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .borderRadius(10)
                .padding({ left: 2, right: 2 })
                .backgroundColor($r('sys.color.comp_background_tertiary'))
                .fontColor($r('sys.color.font_primary'))
                .onClick(() => {
                  this.batchDownload();
                })
            }
            .width('100%')
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

        // 单项操作半模态（与搜索页/歌单详情页共用）
        MusicOptionsSheet({
          optionsItem: this.optionsItem,
          show: this.showOptions,
          onClose: (): void => {
            this.showOptions = false;
          }
        })
      }
      .width('100%')
      .height('100%')
    }
  }

  /**
   * 搜索框（固定于标题栏下方，不随列表滚动消失；输入不即时过滤，
   * 点搜索按钮/软键盘回车后才应用关键词）
   */
  @Builder
  SearchBuilder() {
    CommonSearch({
      searchValue: this.searchInput,
      placeholderValue: '搜索歌曲名、歌手或专辑',
      focusId: 'media_detail_search',
      submit: (): void => {
        this.searchKeyword = this.searchInput.trim();
        this.applySearchFilter();
      },
      change: (v: string): void => {
        this.searchInput = v;
      },
      didDelete: (): void => {
        this.searchInput = '';
        this.searchKeyword = '';
        this.applySearchFilter();
      },
    })
      .width('100%')
      .padding({ left: 16, right: 16 })
      .transition(TransitionEffect.move(TransitionEdge.TOP))
  }

  /** 头部：复用 DetailHeader 公共组件 */
  @Builder
  HeaderBuilder() {
    DetailHeader({
      coverUrl: this.coverUrl,
      title: this.headerTitle,
      subTitle: this.isAlbum ? this.albumSubTitle() : this.artistStats,
      description: this.description,
      musicCount: this.visibleMusicCount(),
      showImport: true,
      onPlayAll: (): void => {
        this.playAll();
      },
      onImport: (): void => {
        this.importToMySheets();
      },
      onBatchMode: (): void => {
        this.enterBatchMode();
      }
    })
  }

  /** 歌曲行：复用 MusicRow 公共组件，支持批量勾选、时长、来源标签、长按进入批量模式 */
  @Builder
  MusicRowBuilder(item: MusicItem, index: number) {
    MusicRow({
      item: item,
      showCheckbox: appState.isBatchMode,
      selected: this.isSelected(item),
      showDuration: true,
      showPlatform: true,
      showMore: true,
      usePaddingHeight: true,
      showDivider: index < this.dataSource.totalCount() - 1,
      wideDivider: true,
      onTap: (): void => {
        if (appState.isBatchMode) {
          this.toggleBatchSelect(item);
        } else {
          this.playItem(item);
        }
      },
      onMore: (): void => {
        this.openOptions(item);
      },
      onLongPress: (): void => {
        if (appState.isBatchMode) {
          return;
        }
        this.enterBatchMode();
        this.toggleBatchSelect(item);
      }
    })
  }

  /** 批量「添加到歌单」歌单选择半模态 */
  @Builder
  BatchSheetPickerBuilder() {
    BatchSheetPicker({
      sheets: this.getUserSheets(),
      onPick: (sheet: SheetItem): void => {
        this.batchAddToSheet(sheet);
      }
    })
  }
}
