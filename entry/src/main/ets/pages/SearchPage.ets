import { MusicItem } from '../common/model/MediaTypes';
import { SearchResult, SupportMediaType } from '../common/model/SheetTypes';
import { pluginManager } from '../plugin/PluginManager';
import { Plugin } from '../plugin/Plugin';
import { trackPlayer } from '../core/TrackPlayer';
import { CommonNav, titleBarOf } from '../view/CommonNav';
import { MusicOptionsSheet } from '../view/MusicOptionsSheet';
import { MusicDataSource } from '../common/model/MusicDataSource';
import { appState } from '../entryability/AppState';
import { CommonSearch } from '../view/CommonCom';
import { KVStore } from '../infra/KVStore';
import { JsonUtil } from '../common/JsonUtil';

/** 搜索结果不足以铺满首屏时自动续拉的阈值 */
const AUTO_LOAD_MORE_THRESHOLD = 30;

/** 历史搜索词存储 */
const HISTORY_STORE = 'storage';
const HISTORY_KEY = 'searchHistory';
/** 历史搜索词最大保存数量 */
const MAX_HISTORY_SIZE = 20;

@ComponentV2
export struct SearchPage {
  scroller: Scroller = new Scroller();
  @Param bootReady: boolean = false;
  @Local keyword: string = '';
  @Local searchStatus: string = '';
  @Local searching: boolean = false;
  @Local loadingMore: boolean = false;
  @Local resultCount: number = 0;
  @Local pluginNames: Array<string> = [];
  @Local selectedPluginIndex: number = 0;
  @Local showOptions: boolean = false;
  @Local optionsItem: MusicItem = new MusicItem();
  /** 历史搜索词（最多 20 个，仅搜索前展示） */
  @Local searchHistory: Array<string> = [];
  /** 是否已执行过搜索（搜索后隐藏历史词） */
  @Local hasSearched: boolean = false;

  dataSource: MusicDataSource = new MusicDataSource();
  private searchPlugins: Array<Plugin> = [];
  private page: number = 1;
  private isEnd: boolean = false;

  aboutToAppear(): void {
    this.refreshPlugins();
    this.loadSearchHistory();
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
    }
  }

  private refreshPlugins(): void {
    const plugins = pluginManager.getSortedSearchablePlugins(SupportMediaType.Music);
    this.searchPlugins = plugins;
    const names: Array<string> = [];
    for (const p of plugins) {
      names.push(p.name);
    }
    this.pluginNames = names;
    if (this.selectedPluginIndex >= plugins.length) {
      this.selectedPluginIndex = 0;
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  private currentPlugin(): Plugin | null {
    const plugin = this.searchPlugins[this.selectedPluginIndex];
    return plugin !== undefined ? plugin : null;
  }

  private doSearch(): void {
    const kw = this.keyword.trim();
    if (kw.length === 0 || this.searching) {
      return;
    }
    this.refreshPlugins();
    if (this.searchPlugins.length === 0) {
      this.dataSource.clear();
      this.resultCount = 0;
      this.searchStatus = '无可用音乐插件，请先在插件管理中安装';
      return;
    }
    const plugin = this.currentPlugin();
    if (plugin === null) {
      return;
    }
    this.hasSearched = true;
    this.saveSearchHistory(kw);
    this.searching = true;
    this.loadingMore = false;
    this.page = 1;
    this.isEnd = false;
    this.dataSource.clear();
    this.resultCount = 0;
    this.searchStatus = '搜索中...';
    plugin.methods.search(kw, 1, SupportMediaType.Music).then((r: SearchResult): void => {
      this.searching = false;
      this.isEnd = r.isEnd;
      this.dataSource.appendData(r.musicData);
      this.resultCount = this.dataSource.totalCount();
      this.searchStatus = this.resultCount === 0 ? '未找到相关结果' : '共 ' + this.resultCount.toString() + ' 条结果';
      if (!this.isEnd && this.resultCount < AUTO_LOAD_MORE_THRESHOLD) {
        this.loadMore();
      }
    }).catch((_e: Object): void => {
      this.searching = false;
      this.searchStatus = '搜索失败，请重试';
    });
  }

  private loadMore(): void {
    if (this.searching || this.loadingMore || this.isEnd) {
      return;
    }
    if (this.keyword.trim().length === 0 || this.dataSource.totalCount() === 0) {
      return;
    }
    const plugin = this.currentPlugin();
    if (plugin === null) {
      return;
    }
    this.loadingMore = true;
    const nextPage = this.page + 1;
    plugin.methods.search(this.keyword.trim(), nextPage, SupportMediaType.Music).then((r: SearchResult): void => {
      this.loadingMore = false;
      this.page = nextPage;
      this.isEnd = r.isEnd;
      this.dataSource.appendData(r.musicData);
      this.resultCount = this.dataSource.totalCount();
      this.searchStatus = '共 ' + this.resultCount.toString() + ' 条结果';
    }).catch((_e: Object): void => {
      this.loadingMore = false;
    });
  }

  private onSelectPlugin(index: number): void {
    if (index === this.selectedPluginIndex) {
      return;
    }
    this.selectedPluginIndex = index;
    if (this.keyword.trim().length > 0 && !this.searching) {
      this.doSearch();
    }
  }

  /** 清除键：清空输入与结果，回到搜索前状态（恢复历史词展示） */
  private resetSearch(): void {
    this.keyword = '';
    this.dataSource.clear();
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
      titleBarOp: titleBarOf($r('app.string.search_title'), undefined, undefined, { builder: (): void => {this.SearchBarBuilder()} }),
      isShowPlayBar: false,
      scroller: this.scroller,
      doubleTapToTop: true,
      backPressed: (): boolean => false
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller }) {
          ListItem() {
            Column() {
              this.PluginSelectorBuilder()
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
        LazyForEach(this.dataSource, (item: MusicItem, index: number) => {
          ListItem() {
            this.ResultRowBuilder(item, index)
          }
        }, (item: MusicItem, _index: number) => item.platform + '_' + item.id)
        if (this.loadingMore) {
          ListItem() {
            Row({ space: 8 }) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color($r('sys.color.icon_emphasize'))
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
      .contentStartOffset(appState.topRect + 110)
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
    CommonSearch({
      searchValue: this.keyword,
      placeholderValue: $r('app.string.home_search_placeholder'),
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
    }).padding({ left: 16, right: 16 })
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
        ForEach(this.pluginNames, (name: string, index: number) => {
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
        }, (name: string, index: number) => name + '_' + index.toString())
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
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
          .fontColor(index < 3 ? $r('sys.color.font_emphasize') : $r('sys.color.font_tertiary'))
          .width(24)
          .textAlign(TextAlign.Center)
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
  }
}
