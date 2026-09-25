import { MusicItem } from '../common/model/MediaTypes';
import { SearchResult, SupportMediaType, AlbumItem, ArtistItem, SheetItem } from '../common/model/SheetTypes';
import {
  ROUTE_SHEET_DETAIL, SheetDetailNavParams,
  ROUTE_ALBUM_DETAIL, ROUTE_ARTIST_DETAIL, MediaDetailNavParams
} from '../common/model/NavModels';
import { NavPathUtils } from '../utils/NavPathUtils';
import { ArtworkCache } from '../utils/ArtworkCache';
import { pluginManager } from '../plugin/PluginManager';
import { Plugin } from '../plugin/Plugin';
import { trackPlayer } from '../core/TrackPlayer';
import { CommonNav, titleBarOf } from '../view/CommonNav';
import { MusicOptionsSheet } from '../view/MusicOptionsSheet';
import { MusicDataSource } from '../common/model/MusicDataSource';
import { StringDataSource } from '../common/model/StringDataSource';
import { AlbumDataSource } from '../common/model/AlbumDataSource';
import { ArtistDataSource } from '../common/model/ArtistDataSource';
import { SheetDataSource } from '../common/model/SheetDataSource';
import { appState } from '../entryability/AppState';
import { CommonSearch } from '../view/CommonCom';
import { KVStore } from '../infra/KVStore';
import { JsonUtil } from '../common/JsonUtil';
import { BottomBuilderShowType } from '@kit.UIDesignKit';

/** 搜索结果不足以铺满首屏时自动续拉的阈值 */
const AUTO_LOAD_MORE_THRESHOLD = 30;
/** 全部源模式单插件搜索超时（毫秒） */
const SEARCH_TIMEOUT_MS = 10000;

/** 历史搜索词存储 */
const HISTORY_STORE = 'storage';
const HISTORY_KEY = 'searchHistory';
/** 历史搜索词最大保存数量 */
const MAX_HISTORY_SIZE = 20;

@ComponentV2
export struct SearchPage {
  /** 搜索结果分类标签（与 CATEGORY_TYPES 一一对应） */
  private static readonly CATEGORY_LABELS: Array<string> = ['单曲', '专辑', '歌手', '歌单'];
  private static readonly CATEGORY_TYPES: Array<SupportMediaType> = [
    SupportMediaType.Music, SupportMediaType.Album, SupportMediaType.Artist, SupportMediaType.Sheet
  ];

  scroller: Scroller = new Scroller();
  @Param bootReady: boolean = false;
  @Local keyword: string = '';
  @Local searchStatus: string = '';
  @Local searching: boolean = false;
  @Local loadingMore: boolean = false;
  @Local resultCount: number = 0;
  @Local pluginNames: Array<string> = [];
  @Local selectedPluginIndex: number = 0;
  /** 选中的插件名（空 = 全部）：按名称跨分类保持选中，避免分类切换后插件列表变化导致选源跳回「全部」 */
  private selectedPluginName: string = '';
  @Local showOptions: boolean = false;
  @Local optionsItem: MusicItem = new MusicItem();
  /** 历史搜索词（最多 20 个，仅搜索前展示） */
  @Local searchHistory: Array<string> = [];
  /** 是否已执行过搜索（搜索后隐藏历史词、显示分类标签） */
  @Local hasSearched: boolean = false;
  /** 当前结果分类（下标对应 CATEGORY_LABELS / CATEGORY_TYPES） */
  @Local categoryIndex: number = 0;

  dataSource: MusicDataSource = new MusicDataSource();
  /** 非单曲分类的搜索结果懒加载数据源（单曲沿用 dataSource） */
  private albumSource: AlbumDataSource = new AlbumDataSource();
  private artistSource: ArtistDataSource = new ArtistDataSource();
  private sheetSource: SheetDataSource = new SheetDataSource();
  /** 插件标签条懒加载数据源（插件较多时按需创建） */
  private pluginTagSource: StringDataSource = new StringDataSource();
  private searchPlugins: Array<Plugin> = [];
  private page: number = 1;
  private isEnd: boolean = false;
  /** 全部源模式：各插件已拉取的页码与结束标记（下标对应 searchPlugins） */
  private allPages: Array<number> = [];
  private allEnds: Array<boolean> = [];
  /** 全部源模式：当前轮尚未返回的插件数 */
  private pendingCount: number = 0;
  /** 搜索序号：点击标签时中断上一次搜索，旧异步回调按序号失配丢弃结果 */
  private searchSeq: number = 0;

  /** 中断在途搜索：使旧回调失效并复位进行中标记（不清理已展示结果，随后 doSearch 会整体重置） */
  private cancelInFlightSearch(): void {
    this.searchSeq++;
    this.searching = false;
    this.loadingMore = false;
    this.pendingCount = 0;
  }

  aboutToAppear(): void {
    this.refreshPlugins();
    this.loadSearchHistory();
    this.consumePendingSearch();
    pluginManager.onOrderUpdated((): void => {
      this.refreshPlugins();
    });
    pluginManager.onPluginEnabled((_name: string, _enabled: boolean): void => {
      this.refreshPlugins();
    });
  }

  @Monitor('bootReady')
  onBootReadyChange(): void {
    if (this.bootReady) {
      this.refreshPlugins();
      this.consumePendingSearch();
    }
  }

  /** 消费外部分享带入的搜索词（分享歌曲文本接收 → 跳转搜索页自动搜索） */
  private consumePendingSearch(): void {
    const kw = appState.pendingSearchKeyword.trim();
    if (kw.length === 0) {
      return;
    }
    appState.pendingSearchKeyword = '';
    this.keyword = kw;
    if (this.bootReady) {
      this.doSearch();
    }
  }

  /** 当前分类对应的搜索类型 */
  private currentType(): SupportMediaType {
    const t = SearchPage.CATEGORY_TYPES[this.categoryIndex];
    return t !== undefined ? t : SupportMediaType.Music;
  }

  /** 插件是否支持指定类型搜索（supportedSearchType 为空视为全类型支持，与 PluginManager 口径一致） */
  private static supportsType(p: Plugin, type: SupportMediaType): boolean {
    return p.instanceInfo === null || p.instanceInfo.supportedSearchType.length === 0 ||
      p.instanceInfo.supportedSearchType.indexOf(type) !== -1;
  }

  private refreshPlugins(): void {
    // 插件标签列表不按分类过滤（保持跨分类恒定），选中插件按名称跨分类保持；
    // 分类支持性在搜索时按插件各自判断，避免声明不全的插件在切分类后被挤出列表
    const prevName = this.selectedPluginName;
    const plugins = pluginManager.getSortedSearchablePlugins();
    this.searchPlugins = plugins;
    const names: Array<string> = ['全部'];
    for (const p of plugins) {
      names.push(p.name);
    }
    this.pluginNames = names;
    this.pluginTagSource.reload(names);
    let index = 0;
    if (prevName.length > 0) {
      for (let i = 0; i < plugins.length; i++) {
        if (plugins[i].name === prevName) {
          index = i + 1;
          break;
        }
      }
    }
    if (index === 0) {
      this.selectedPluginName = '';
    }
    this.selectedPluginIndex = index;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  /** 当前选中插件（选源下标 0 为「全部」，返回 null） */
  private currentPlugin(): Plugin | null {
    if (this.selectedPluginIndex <= 0) {
      return null;
    }
    const plugin = this.searchPlugins[this.selectedPluginIndex - 1];
    return plugin !== undefined ? plugin : null;
  }

  private doSearch(): void {
    const kw = this.keyword.trim();
    if (kw.length === 0 || this.searching) {
      return;
    }
    const seq = ++this.searchSeq;
    this.refreshPlugins();
    if (this.searchPlugins.length === 0) {
      this.dataSource.clear();
      this.resultCount = 0;
      this.searchStatus = '无可用音乐插件，请先在插件管理中安装';
      return;
    }
    this.hasSearched = true;
    this.saveSearchHistory(kw);
    this.searching = true;
    this.loadingMore = false;
    this.page = 1;
    this.isEnd = false;
    this.dataSource.clear();
    this.albumSource.clear();
    this.artistSource.clear();
    this.sheetSource.clear();
    this.resultCount = 0;
    this.searchStatus = '搜索中...';
    if (this.selectedPluginIndex === 0) {
      // 全部源：清空分页状态，由 fetchAllRound 重建（不支持当前分类的插件直接标记结束）
      this.allPages = [];
      this.allEnds = [];
      this.fetchAllRound(kw, seq);
      return;
    }
    const plugin = this.currentPlugin();
    if (plugin === null) {
      this.searching = false;
      return;
    }
    plugin.methods.search(kw, 1, this.currentType()).then((r: SearchResult): void => {
      if (seq !== this.searchSeq) {
        return;
      }
      this.searching = false;
      this.isEnd = r.isEnd;
      this.appendSearchResult(r);
      this.searchStatus = this.resultCount === 0 ? '未找到相关结果' : '共 ' + this.resultCount.toString() + ' 条结果';
      if (!this.isEnd && this.resultCount < AUTO_LOAD_MORE_THRESHOLD) {
        this.loadMore();
      }
    }).catch((_e: Object): void => {
      if (seq !== this.searchSeq) {
        return;
      }
      this.searching = false;
      this.searchStatus = '搜索失败，请重试';
    });
  }

  /** 按当前分类追加搜索结果并刷新计数/状态文本 */
  private appendSearchResult(r: SearchResult): void {
    const type = this.currentType();
    if (type === SupportMediaType.Music) {
      this.dataSource.appendData(r.musicData);
      this.resultCount = this.dataSource.totalCount();
    } else if (type === SupportMediaType.Album) {
      this.albumSource.appendData(r.albumData);
      this.resultCount = this.albumSource.totalCount();
    } else if (type === SupportMediaType.Artist) {
      this.artistSource.appendData(r.artistData);
      this.resultCount = this.artistSource.totalCount();
    } else {
      this.sheetSource.appendData(r.sheetData);
      this.resultCount = this.sheetSource.totalCount();
    }
    if (this.resultCount > 0) {
      this.searchStatus = '共 ' + this.resultCount.toString() + ' 条结果';
    }
  }

  /** 当前分类在该结果中的条数 */
  private resultDataLength(r: SearchResult): number {
    const type = this.currentType();
    if (type === SupportMediaType.Music) {
      return r.musicData.length;
    }
    if (type === SupportMediaType.Album) {
      return r.albumData.length;
    }
    if (type === SupportMediaType.Artist) {
      return r.artistData.length;
    }
    return r.sheetData.length;
  }

  private loadMore(): void {
    if (this.searching || this.loadingMore || this.isEnd) {
      return;
    }
    if (this.keyword.trim().length === 0) {
      return;
    }
    if (this.selectedPluginIndex === 0) {
      // 全部源：向未结束的插件并行拉取下一页
      this.loadingMore = true;
      this.fetchAllRound(this.keyword.trim(), this.searchSeq);
      return;
    }
    if (this.dataSource.totalCount() === 0) {
      return;
    }
    const plugin = this.currentPlugin();
    if (plugin === null) {
      return;
    }
    this.loadingMore = true;
    const seq = this.searchSeq;
    const nextPage = this.page + 1;
    plugin.methods.search(this.keyword.trim(), nextPage, this.currentType()).then((r: SearchResult): void => {
      if (seq !== this.searchSeq) {
        return;
      }
      this.loadingMore = false;
      this.page = nextPage;
      this.isEnd = r.isEnd;
      this.appendSearchResult(r);
    }).catch((_e: Object): void => {
      if (seq !== this.searchSeq) {
        return;
      }
      this.loadingMore = false;
    });
  }

  /**
   * 全部源模式：向所有未结束的插件并行请求其下一页；
   * 单个插件失败/超时按该源结束处理，不影响其他源；
   * 每个插件结果到达即增量展示，整轮结束后不足首屏则自动续拉
   */
  private fetchAllRound(kw: string, seq: number): void {
    const plugins = this.searchPlugins;
    const type = this.currentType();
    if (this.allPages.length !== plugins.length) {
      this.allPages = [];
      this.allEnds = [];
      for (let i = 0; i < plugins.length; i++) {
        this.allPages.push(0);
        this.allEnds.push(!SearchPage.supportsType(plugins[i], type));
      }
    }
    let pending = 0;
    for (let i = 0; i < plugins.length; i++) {
      if (!this.allEnds[i]) {
        pending++;
      }
    }
    if (pending === 0) {
      this.searching = false;
      this.loadingMore = false;
      this.isEnd = true;
      if (this.resultCount === 0) {
        this.searchStatus = '未找到相关结果';
      }
      return;
    }
    this.pendingCount = pending;
    for (let i = 0; i < plugins.length; i++) {
      if (this.allEnds[i]) {
        continue;
      }
      const idx = i;
      const nextPage = this.allPages[idx] + 1;
      SearchPage.searchWithTimeout(plugins[idx], kw, nextPage, type, SEARCH_TIMEOUT_MS)
        .then((r: SearchResult): void => {
          if (seq !== this.searchSeq) {
            return;
          }
          this.allPages[idx] = nextPage;
          this.allEnds[idx] = r.isEnd;
          if (this.resultDataLength(r) > 0) {
            this.appendSearchResult(r);
          }
          this.afterPluginRound();
        })
        .catch((_e: Object): void => {
          if (seq !== this.searchSeq) {
            return;
          }
          this.allEnds[idx] = true;
          this.afterPluginRound();
        });
    }
  }

  /** 全部源一轮中单个插件完成：全部完成后收尾并按需自动续拉 */
  private afterPluginRound(): void {
    this.pendingCount--;
    if (this.pendingCount > 0) {
      return;
    }
    this.searching = false;
    this.loadingMore = false;
    let allEnded = true;
    for (const e of this.allEnds) {
      if (!e) {
        allEnded = false;
        break;
      }
    }
    this.isEnd = allEnded;
    if (this.resultCount === 0) {
      this.searchStatus = allEnded ? '未找到相关结果' : '搜索中...';
    }
    if (!this.isEnd && this.resultCount < AUTO_LOAD_MORE_THRESHOLD) {
      this.loadMore();
    }
  }

  /** 插件搜索超时包装：超时按失败处理，避免单个挂起的源拖住整轮 */
  private static searchWithTimeout(plugin: Plugin, kw: string, page: number, type: SupportMediaType,
    timeoutMs: number): Promise<SearchResult> {
    return new Promise<SearchResult>((resolve: (r: SearchResult) => void,
      reject: (e: Object) => void): void => {
      let settled = false;
      const timer = setTimeout((): void => {
        if (!settled) {
          settled = true;
          reject(new Error('搜索超时'));
        }
      }, timeoutMs);
      plugin.methods.search(kw, page, type).then((r: SearchResult): void => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          resolve(r);
        }
      }).catch((e: Object): void => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          reject(e);
        }
      });
    });
  }

  private onSelectPlugin(index: number): void {
    if (index === this.selectedPluginIndex) {
      return;
    }
    this.selectedPluginIndex = index;
    const plugin = index > 0 ? this.searchPlugins[index - 1] : undefined;
    this.selectedPluginName = plugin !== undefined ? plugin.name : '';
    if (this.keyword.trim().length > 0) {
      // 在途搜索直接中断，用新选中的插件 + 当前文本重搜
      this.cancelInFlightSearch();
      this.doSearch();
    }
  }

  /** 切换结果分类：有搜索词时中断在途搜索并按新分类重新搜索 */
  private onSelectCategory(index: number): void {
    if (index === this.categoryIndex) {
      return;
    }
    this.categoryIndex = index;
    if (this.keyword.trim().length > 0) {
      // 在途搜索直接中断，用新选中的分类 + 当前文本重搜
      this.cancelInFlightSearch();
      this.doSearch();
    }
  }

  /** 歌单结果点击：进入歌单详情页 */
  private openSheetDetail(sheet: SheetItem): void {
    const current = this.currentPlugin();
    const pluginName = sheet.platform.length > 0 ? sheet.platform :
      (current !== null ? current.name : '');
    if (pluginName.length === 0) {
      this.showToast('插件不可用');
      return;
    }
    SheetDetailNavParams.pluginName = pluginName;
    SheetDetailNavParams.sheet = sheet;
    SheetDetailNavParams.isTopList = false;
    NavPathUtils.push(ROUTE_SHEET_DETAIL);
  }

  /** 专辑结果点击：进入专辑详情页 */
  private openAlbumDetail(album: AlbumItem): void {
    const current = this.currentPlugin();
    const pluginName = album.platform.length > 0 ? album.platform :
      (current !== null ? current.name : '');
    if (pluginName.length === 0) {
      this.showToast('插件不可用');
      return;
    }
    MediaDetailNavParams.pluginName = pluginName;
    MediaDetailNavParams.album = album;
    MediaDetailNavParams.artist = null;
    NavPathUtils.push(ROUTE_ALBUM_DETAIL);
  }

  /** 歌手结果点击：进入歌手详情页 */
  private openArtistDetail(artist: ArtistItem): void {
    const current = this.currentPlugin();
    const pluginName = artist.platform.length > 0 ? artist.platform :
      (current !== null ? current.name : '');
    if (pluginName.length === 0) {
      this.showToast('插件不可用');
      return;
    }
    MediaDetailNavParams.pluginName = pluginName;
    MediaDetailNavParams.album = null;
    MediaDetailNavParams.artist = artist;
    NavPathUtils.push(ROUTE_ARTIST_DETAIL);
  }

  /** 清除键：清空输入与结果，回到搜索前状态（恢复历史词展示） */
  private resetSearch(): void {
    // 先中断在途搜索：使尚未返回的旧搜索回调失效，避免清空后结果又被异步填回
    this.cancelInFlightSearch();
    this.isEnd = false;
    this.page = 1;
    this.keyword = '';
    this.dataSource.clear();
    this.albumSource.clear();
    this.artistSource.clear();
    this.sheetSource.clear();
    this.resultCount = 0;
    this.searchStatus = '';
    this.hasSearched = false;
  }

  /** 从 KV 存储加载历史搜索词 */
  private loadSearchHistory(): void {
    const raw = KVStore.getOrCreate(HISTORY_STORE).get(HISTORY_KEY);
    const parsed = JsonUtil.parseStringArray(raw);
    if (parsed !== null) {
      this.searchHistory = parsed.length > MAX_HISTORY_SIZE ? parsed.slice(0, MAX_HISTORY_SIZE) : parsed;
    }
  }

  /** 保存搜索词：去重、新词置顶、最多 20 个 */
  private saveSearchHistory(kw: string): void {
    const next: Array<string> = [kw];
    for (const h of this.searchHistory) {
      if (h !== kw && next.length < MAX_HISTORY_SIZE) {
        next.push(h);
      }
    }
    this.searchHistory = next;
    KVStore.getOrCreate(HISTORY_STORE).set(HISTORY_KEY, JSON.stringify(next));
  }

  /** 清空历史搜索词 */
  private clearSearchHistory(): void {
    this.searchHistory = [];
    KVStore.getOrCreate(HISTORY_STORE).delete(HISTORY_KEY);
    this.showToast('已清空历史搜索');
  }

  /** 点击历史词回填并搜索 */
  private searchFromHistory(kw: string): void {
    this.keyword = kw;
    this.doSearch();
  }

  private playResult(item: MusicItem): void {
    const playList = this.dataSource.getItems();
    if (playList.length === 0) {
      return;
    }
    trackPlayer.playWithReplacePlayList(item, playList).catch((_e: Object): void => {
      this.showToast('播放失败');
    });
  }

  private openOptions(item: MusicItem): void {
    this.optionsItem = item.clone();
    this.showOptions = true;
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
      titleBarOp: titleBarOf($r('app.string.search_title'), undefined, undefined,
        { builder: (): void => { this.SearchBarBuilder() }, height: this.hasSearched ? 140 : 80 }),
      isShowPlayBar: true,
      scroller: this.scroller,
      doubleTapToTop: true,
      isSearchBarScroller: false,
      backPressed: (): boolean => false
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller }) {
          ListItem() {
            Column() {
              if (this.searchStatus.length > 0) {
                Text(this.searchStatus)
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
                  .width('100%')
                  .margin({ top: 8, bottom: 4 })
                  .maxLines(1)
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        // 历史搜索词（仅搜索前展示）
        if (!this.hasSearched && this.searchHistory.length > 0) {
          ListItem() {
            this.HistoryBuilder()
          }
        }
        // 单曲结果（懒加载）
        if (this.categoryIndex === 0) {
          LazyForEach(this.dataSource, (item: MusicItem, index: number) => {
            ListItem() {
              this.ResultRowBuilder(item, index)
            }
          }, (item: MusicItem, _index: number) => item.platform + '_' + item.id)
        } else if (this.categoryIndex === 1) {
          // 专辑结果（懒加载）
          LazyForEach(this.albumSource, (item: AlbumItem, index: number) => {
            ListItem() {
              this.AlbumRowBuilder(item, index)
            }
          }, (item: AlbumItem, _index: number) => item.platform + '_' + item.id)
        } else if (this.categoryIndex === 2) {
          // 歌手结果（懒加载）
          LazyForEach(this.artistSource, (item: ArtistItem, index: number) => {
            ListItem() {
              this.ArtistRowBuilder(item, index)
            }
          }, (item: ArtistItem, _index: number) => item.platform + '_' + item.id)
        } else {
          // 歌单结果（懒加载）
          LazyForEach(this.sheetSource, (item: SheetItem, index: number) => {
            ListItem() {
              this.SheetRowBuilder(item, index)
            }
          }, (item: SheetItem, _index: number) => item.platform + '_' + item.id)
        }
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
        } else if (this.isEnd && this.resultCount > 0) {
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
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .contentStartOffset(this.hasSearched ? 235 : appState.topRect + 160)
      .contentEndOffset(appState.bottomRect)
      .padding({ left: 16, right: 16 })
      .onReachEnd(() => {
        this.loadMore();
      })

        // 歌曲操作半模态（与首页本地音乐共用）
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

  @Builder
  SearchBarBuilder() {
    Column(){
      CommonSearch({
        searchValue: this.keyword,
        placeholderValue: $r('app.string.home_search_placeholder'),
        focusId: 'search_page_search',
        change: (v) => {
          this.keyword = v;
        },
        submit: () => {
          this.doSearch();
        },
        didDelete: ()=>{
          // 清除键：清空输入与结果，回到搜索前状态（恢复历史词展示）
          this.resetSearch()
        }
      })

      this.PluginSelectorBuilder()

      // 分类标签条（搜索后出现）
      if (this.hasSearched) {
      this.CategoryTabsBuilder()
      }
    }.padding({ left: 16, right: 16 })
    .width('100%')
    .height('100%')
  }

  /** 历史搜索词区块：标题 + 清空按钮 + 词标签 */
  @Builder
  HistoryBuilder() {
    Column() {
      Row() {
        Text('历史搜索')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_secondary'))
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(18)
          .fontColor([$r('sys.color.icon_tertiary')])
          .onClick(() => {
            this.clearSearchHistory();
          })
      }
      .width('100%')
      .margin({ top: 18, bottom: 10 })

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.searchHistory, (kw: string) => {
          Text(kw)
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '80%' })
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              this.searchFromHistory(kw);
            })
        }, (kw: string, index: number) => kw + '_' + index.toString())
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  PluginSelectorBuilder() {
    if (this.pluginNames.length > 0) {
      List({ space: 8 }) {
        LazyForEach(this.pluginTagSource, (name: string, index: number) => {
          ListItem() {
            Text(name)
              .fontSize(13)
              .fontColor(this.selectedPluginIndex === index ?
              $r('sys.color.font_on') : $r('sys.color.font_secondary'))
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .borderRadius(16)
              .backgroundColor(this.selectedPluginIndex === index ?
              $r('sys.color.font_secondary') : $r('sys.color.comp_background_tertiary'))
              .maxLines(1)
              .onClick(() => {
                this.onSelectPlugin(index);
              })
          }
        }, (name: string, _index: number) => name)
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .height(36)
      .margin({ top: 10 })
    } else {
      Text('无可用音乐插件，请先在「插件管理」中安装并启用')
        .fontSize(12)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
        .margin({ top: 10 })
    }
  }

  @Builder
  ResultRowBuilder(item: MusicItem, index: number) {
    Column() {
      Row({ space: 12 }) {
        Text((index + 1).toString())
          .fontSize(14)
          .fontColor(index < 3 ? appState.accentColor : $r('sys.color.font_tertiary'))
          .width(24)
          .textAlign(TextAlign.Center)
        Column({ space: 2 }) {
          Text(item.title)
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: 6 }) {
            // 来源标签（位于副文本前，圆角同歌单详情页来源标签）
            if (item.platform.length > 0) {
              Text(item.platform)
                .fontSize(10)
                .fontColor($r('sys.color.font_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 84 })
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(3)
                .backgroundColor($r('sys.color.comp_background_tertiary'))
            }
            Text(item.artist + (item.album.length > 0 ? ' · ' + item.album : ''))
              .fontSize(12)
              .fontColor($r('sys.color.font_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(SearchPage.formatDuration(item.duration))
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
        SymbolGlyph($r('sys.symbol.ellipsis_circle'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
          .onClick(() => {
            this.openOptions(item);
          })
      }
      .width('100%')
      .height(56)
      .borderRadius(12)
      .onClick(() => {
        this.playResult(item);
      })
      if (index < this.resultCount - 1) {
        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.comp_divider'))
          .margin({ left: 33 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    // 插件/分类标签切换时渐隐过渡，避免闪烁突兀
    .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.Smooth }))
  }

  /** 结果分类标签条（搜索后出现于插件选择条下方）：四项均分一排，中间竖向分割线 */
  @Builder
  CategoryTabsBuilder() {
    Row() {
      ForEach(SearchPage.CATEGORY_LABELS, (label: string, index: number) => {
        Column({ space: 4 }) {
          Text(label)
            .fontSize(15)
            .fontWeight(this.categoryIndex === index ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.categoryIndex === index ?
              $r('sys.color.font_primary') : $r('sys.color.font_tertiary'))
          Divider()
            .strokeWidth(2)
            .width(18)
            .color(this.categoryIndex === index ? appState.accentColor : 'transparent')
        }
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          this.onSelectCategory(index);
        })
      }, (label: string, index: number) => label + '_' + index.toString())
    }
    .justifyContent(FlexAlign.SpaceAround)
    .width('100%')
    .margin({ top: 10 })
  }

  /** 专辑结果行：封面 + 标题/歌手 + 歌曲数 */
  @Builder
  AlbumRowBuilder(item: AlbumItem, index: number) {
    Column() {
      Row({ space: 12 }) {
        Text((index + 1).toString())
          .fontSize(14)
          .fontColor(index < 3 ? appState.accentColor : $r('sys.color.font_tertiary'))
          .width(24)
          .textAlign(TextAlign.Center)
        Image(ArtworkCache.resolve(item.artwork))
          .width(48)
          .height(48)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .alt($r('app.media.altImage'))
        Column({ space: 2 }) {
          Text(item.title)
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.artist + (item.date.length > 0 ? ' · ' + item.date : ''))
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(item.worksNum > 0 ? item.worksNum.toString() + '首' : '')
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      .height(64)
      .onClick(() => {
        this.openAlbumDetail(item);
      })
      if (index < this.albumSource.totalCount() - 1) {
        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.comp_divider'))
          .margin({ left: 96 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    // 标签切换时渐隐过渡
    .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.Smooth }))
  }

  /** 歌手结果行：头像 + 名称 + 作品/粉丝数 */
  @Builder
  ArtistRowBuilder(item: ArtistItem, index: number) {
    Column() {
      Row({ space: 12 }) {
        Text((index + 1).toString())
          .fontSize(14)
          .fontColor(index < 3 ? appState.accentColor : $r('sys.color.font_tertiary'))
          .width(24)
          .textAlign(TextAlign.Center)
        Image(ArtworkCache.resolve(item.avatar))
          .width(44)
          .height(44)
          .borderRadius(22)
          .objectFit(ImageFit.Cover)
          .alt($r('app.media.altImage'))
        Column({ space: 2 }) {
          Text(item.name)
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(SearchPage.formatArtistSub(item))
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height(60)
      .onClick(() => {
        this.openArtistDetail(item);
      })
      if (index < this.artistSource.totalCount() - 1) {
        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.comp_divider'))
          .margin({ left: 92 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    // 标签切换时渐隐过渡
    .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.Smooth }))
  }

  /** 歌单结果行：封面 + 标题/作者 + 歌曲数，点击进入歌单详情 */
  @Builder
  SheetRowBuilder(item: SheetItem, index: number) {
    Column() {
      Row({ space: 12 }) {
        Text((index + 1).toString())
          .fontSize(14)
          .fontColor(index < 3 ? appState.accentColor : $r('sys.color.font_tertiary'))
          .width(24)
          .textAlign(TextAlign.Center)
        Image(ArtworkCache.resolve(item.coverUrl()))
          .width(48)
          .height(48)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .alt($r('app.media.altImage'))
        Column({ space: 2 }) {
          Text(item.title)
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.artist + (item.worksNum > 0 ? ' · ' + item.worksNum.toString() + '首' : ''))
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('sys.color.icon_tertiary')])
      }
      .width('100%')
      .height(64)
      .onClick(() => {
        this.openSheetDetail(item);
      })
      if (index < this.sheetSource.totalCount() - 1) {
        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.comp_divider'))
          .margin({ left: 96 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    // 标签切换时渐隐过渡
    .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.Smooth }))
  }

  /** 歌手副文本：作品数 + 粉丝数 */
  private static formatArtistSub(item: ArtistItem): string {
    const parts: Array<string> = [];
    if (item.worksNum > 0) {
      parts.push(item.worksNum.toString() + '首歌曲');
    }
    if (item.fans > 0) {
      parts.push(item.fans >= 10000 ?
        (item.fans / 10000).toFixed(1) + '万粉丝' : item.fans.toString() + '粉丝');
    }
    return parts.join(' · ');
  }
}
