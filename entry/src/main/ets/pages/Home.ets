import { MusicItem } from '../model/MediaTypes';
import { SheetItem, SheetGroupItem, MediaTag, SupportMediaType, SearchResult, PageResult } from '../model/SheetTypes';
import { PluginAbility } from '../common/Consts';
import { pluginManager } from '../plugin/PluginManager';
import { Plugin } from '../plugin/Plugin';
import { localMusicSheet } from '../core/LocalMusicSheet';
import { trackPlayer } from '../core/TrackPlayer';
import { appState } from '../entryability/AppState';
import { TimeTipUtils } from '../utils/TimeTipUtils';

const TOP_LIST_MAX_GROUPS = 3;
const LOCAL_PREVIEW_COUNT = 10;
const GRID_COLUMNS = 3;

@ComponentV2
export struct Home {
  scroller: Scroller = new Scroller();
  @Param bootReady: boolean = false;
  @Local keyword: string = '';
  @Local searchResults: Array<MusicItem> = [];
  @Local searchStatus: string = '';
  @Local searchPluginName: string = '';
  @Local topListPluginName: string = '';
  @Local topListGroups: Array<SheetGroupItem> = [];
  @Local recommendPluginName: string = '';
  @Local recommendTags: Array<MediaTag> = [];
  @Local selectedTagIndex: number = 0;
  @Local recommendSheets: Array<SheetItem> = [];
  @Local localMusic: Array<MusicItem> = [];

  private recommendPlugin: Plugin | null = null;
  private recommendGroups: Array<SheetGroupItem> = [];

  aboutToAppear(): void {
    this.localMusic = localMusicSheet.musicList.slice();
    localMusicSheet.onLocalSheetUpdated((): void => {
      this.localMusic = localMusicSheet.musicList.slice();
    });
    pluginManager.onOrderUpdated((): void => {
      if (this.bootReady) {
        this.refreshHome();
      }
    });
    pluginManager.onPluginEnabled((_name: string, _enabled: boolean): void => {
      if (this.bootReady) {
        this.refreshHome();
      }
    });
    if (this.bootReady) {
      this.refreshHome();
    }
  }

  @Monitor('bootReady')
  onBootReadyChange(): void {
    if (this.bootReady) {
      this.refreshHome();
    }
  }

  private refreshHome(): void {
    this.loadTopLists();
    this.loadRecommendSheets();
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  private loadTopLists(): void {
    const plugins = pluginManager.getSortedPluginsWithAbility(PluginAbility.GetTopLists);
    if (plugins.length === 0) {
      this.topListGroups = [];
      this.topListPluginName = '';
      return;
    }
    const plugin = plugins[0];
    this.topListPluginName = plugin.name;
    plugin.methods.getTopLists().then((groups: Array<SheetGroupItem>) => {
      this.topListGroups = groups.slice(0, TOP_LIST_MAX_GROUPS);
    }).catch((_e: Object): void => {
      this.topListGroups = [];
    });
  }

  private loadRecommendSheets(): void {
    const plugins = pluginManager.getSortedPluginsWithAbility(PluginAbility.GetRecommendSheetsByTag);
    if (plugins.length === 0) {
      this.recommendPlugin = null;
      this.recommendGroups = [];
      this.recommendTags = [];
      this.recommendSheets = [];
      this.recommendPluginName = '';
      return;
    }
    const plugin = plugins[0];
    this.recommendPlugin = plugin;
    this.recommendPluginName = plugin.name;
    plugin.methods.getRecommendSheetTags().then((result) => {
      this.recommendGroups = result.data;
      const tags: Array<MediaTag> = [];
      for (const group of result.data) {
        const tag = new MediaTag();
        tag.id = group.title;
        tag.title = group.title;
        tags.push(tag);
      }
      this.recommendTags = tags;
      this.selectedTagIndex = 0;
      if (result.data.length === 0 && result.pinned.length > 0) {
        this.recommendSheets = result.pinned;
      } else {
        this.applyTagSheets(0);
      }
    }).catch((_e: Object): void => {
      this.recommendTags = [];
      this.recommendSheets = [];
    });
  }

  private applyTagSheets(index: number): void {
    const group = index >= 0 && index < this.recommendGroups.length ? this.recommendGroups[index] : null;
    if (group !== null && group.data.length > 0) {
      this.recommendSheets = group.data;
      return;
    }
    const plugin = this.recommendPlugin;
    const tag = index >= 0 && index < this.recommendTags.length ? this.recommendTags[index] : null;
    if (plugin === null || tag === null) {
      this.recommendSheets = [];
      return;
    }
    plugin.methods.getRecommendSheetsByTag(tag, 1).then((r: PageResult<SheetItem>) => {
      this.recommendSheets = r.data;
    }).catch((_e: Object): void => {
      this.recommendSheets = [];
    });
  }

  private onSelectTag(index: number): void {
    if (index === this.selectedTagIndex) {
      return;
    }
    this.selectedTagIndex = index;
    this.applyTagSheets(index);
  }

  private doSearch(): void {
    const kw = this.keyword.trim();
    if (kw.length === 0) {
      return;
    }
    const plugins = pluginManager.getSortedSearchablePlugins(SupportMediaType.Music);
    if (plugins.length === 0) {
      this.searchResults = [];
      this.searchStatus = '无可用音乐插件';
      return;
    }
    const plugin = plugins[0];
    this.searchPluginName = plugin.name;
    this.searchResults = [];
    this.searchStatus = '搜索中...';
    plugin.methods.search(kw, 1, SupportMediaType.Music).then((r: SearchResult) => {
      this.searchResults = r.musicData;
      this.searchStatus = r.musicData.length === 0 ? '未找到相关结果' : '共 ' + r.musicData.length.toString() + ' 条结果';
    }).catch((_e: Object): void => {
      this.searchResults = [];
      this.searchStatus = '搜索失败，请重试';
    });
  }

  private clearSearch(): void {
    this.keyword = '';
    this.searchResults = [];
    this.searchStatus = '';
  }

  private playSearchResult(item: MusicItem): void {
    if (this.searchResults.length === 0) {
      return;
    }
    trackPlayer.playWithReplacePlayList(item, this.searchResults).catch((_e: Object): void => {
      this.showToast('播放失败');
    });
  }

  private playLocal(item: MusicItem): void {
    if (this.localMusic.length === 0) {
      return;
    }
    trackPlayer.playWithReplacePlayList(item, this.localMusic).catch((_e: Object): void => {
      this.showToast('播放失败');
    });
  }

  private onSheetClick(): void {
    this.showToast('歌单详情页开发中');
  }

  private chunkRows(sheets: Array<SheetItem>): Array<Array<SheetItem>> {
    const rows: Array<Array<SheetItem>> = [];
    let row: Array<SheetItem> = [];
    for (const sheet of sheets) {
      row.push(sheet);
      if (row.length === GRID_COLUMNS) {
        rows.push(row);
        row = [];
      }
    }
    if (row.length > 0) {
      rows.push(row);
    }
    return rows;
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
    Scroll(this.scroller) {
      Column() {
        this.HeaderBuilder()
        this.SearchBarBuilder()
        if (!this.bootReady) {
          Column({ space: 8 }) {
            LoadingProgress()
              .width(28)
              .height(28)
              .color($r('sys.color.icon_emphasize'))
          }
          .width('100%')
          .margin({ top: 48 })
          .justifyContent(FlexAlign.Center)
        } else {
          if (this.searchResults.length > 0 || this.searchStatus.length > 0) {
            this.SearchResultsBuilder()
          }
          this.TopListsBuilder()
          this.RecommendSheetsBuilder()
          this.LocalMusicBuilder()
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: appState.topRect, bottom: 180 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  HeaderBuilder() {
    Column({ space: 2 }) {
      Text(TimeTipUtils())
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
      Text('MusicFree')
        .fontSize(13)
        .fontColor($r('sys.color.font_tertiary'))
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ top: 12, bottom: 16 })
  }

  @Builder
  SearchBarBuilder() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(20)
        .fontColor([$r('sys.color.icon_secondary')])
      TextInput({ text: this.keyword, placeholder: $r('app.string.home_search_placeholder') })
        .layoutWeight(1)
        .height(44)
        .backgroundColor(Color.Transparent)
        .padding(0)
        .fontSize(15)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .placeholderFont({ size: 15 })
        .enterKeyType(EnterKeyType.Search)
        .onChange((v: string) => {
          this.keyword = v;
        })
        .onSubmit((_enterKey: EnterKeyType) => {
          this.doSearch();
        })
      if (this.keyword.length > 0) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(16)
          .fontColor([$r('sys.color.icon_tertiary')])
          .onClick(() => {
            this.clearSearch();
          })
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .borderRadius(22)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
  }

  @Builder
  SectionTitleBuilder(title: ResourceStr, tag: string, tail: string) {
    Row({ space: 8 }) {
      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
      if (tag.length > 0) {
        Text(tag)
          .fontSize(10)
          .fontColor($r('sys.color.font_secondary'))
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(8)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .maxLines(1)
      }
      Blank()
      if (tail.length > 0) {
        Text(tail)
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
      }
    }
    .width('100%')
    .margin({ top: 28, bottom: 12 })
  }

  @Builder
  SearchResultsBuilder() {
    Column() {
      this.SectionTitleBuilder($r('app.string.home_search_results'), this.searchPluginName, this.searchStatus)
      ForEach(this.searchResults, (item: MusicItem, index: number) => {
        this.MusicRowBuilder(item, index, true)
      }, (item: MusicItem, index: number) => item.platform + '_' + item.id + '_' + index.toString())
    }
    .width('100%')
  }

  @Builder
  MusicRowBuilder(item: MusicItem, index: number, showIndex: boolean) {
    Row({ space: 12 }) {
      if (showIndex) {
        Text((index + 1).toString())
          .fontSize(14)
          .fontColor(index < 3 ? $r('sys.color.font_emphasize') : $r('sys.color.font_tertiary'))
          .width(24)
          .textAlign(TextAlign.Center)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.music_note_list'))
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
        Text(item.artist + (item.album.length > 0 ? ' · ' + item.album : ''))
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text(Home.formatDuration(item.duration))
        .fontSize(12)
        .fontColor($r('sys.color.font_tertiary'))
    }
    .width('100%')
    .height(56)
    .borderRadius(12)
    .onClick(() => {
      if (showIndex) {
        this.playSearchResult(item);
      } else {
        this.playLocal(item);
      }
    })
  }

  @Builder
  TopListsBuilder() {
    Column() {
      this.SectionTitleBuilder($r('app.string.home_toplists'), this.topListPluginName, '')
      if (this.topListGroups.length === 0) {
        this.EmptyHintBuilder($r('app.string.home_no_plugin'))
      } else {
        ForEach(this.topListGroups, (group: SheetGroupItem, groupIndex: number) => {
          Column({ space: 10 }) {
            if (this.topListGroups.length > 1) {
              Text(group.title)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_secondary'))
            }
            Scroll() {
              Row({ space: 12 }) {
                ForEach(group.data, (sheet: SheetItem, index: number) => {
                  this.SheetCardBuilder(sheet)
                }, (sheet: SheetItem, index: number) => sheet.platform + '_' + sheet.id + '_' + index.toString())
              }
              .alignItems(VerticalAlign.Top)
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }, (group: SheetGroupItem, groupIndex: number) => group.title + '_' + groupIndex.toString())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SheetCardBuilder(sheet: SheetItem) {
    Column({ space: 6 }) {
      if (sheet.coverImg.length > 0) {
        Image(sheet.coverImg)
          .width(104)
          .aspectRatio(1)
          .borderRadius(12)
          .objectFit(ImageFit.Cover)
          .alt($r('app.media.startIcon'))
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.music_note_list'))
            .fontSize(28)
            .fontColor([$r('sys.color.icon_tertiary')])
        }
        .width(104)
        .aspectRatio(1)
        .borderRadius(12)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .justifyContent(FlexAlign.Center)
      }
      Text(sheet.title)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(104)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onSheetClick();
    })
  }

  @Builder
  RecommendSheetsBuilder() {
    Column() {
      this.SectionTitleBuilder($r('app.string.home_recommend_sheets'), this.recommendPluginName, '')
      if (this.recommendTags.length === 0 && this.recommendSheets.length === 0) {
        this.EmptyHintBuilder($r('app.string.home_no_plugin'))
      } else {
        if (this.recommendTags.length > 0) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.recommendTags, (tag: MediaTag, index: number) => {
                Text(tag.title)
                  .fontSize(13)
                  .fontColor(this.selectedTagIndex === index ? $r('sys.color.font_emphasize') : $r('sys.color.font_secondary'))
                  .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                  .borderRadius(16)
                  .backgroundColor(this.selectedTagIndex === index ? $r('sys.color.background_emphasize') : $r('sys.color.comp_background_tertiary'))
                  .maxLines(1)
                  .onClick(() => {
                    this.onSelectTag(index);
                  })
              }, (tag: MediaTag, index: number) => tag.id + '_' + index.toString())
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .margin({ bottom: 12 })
        }
        if (this.recommendSheets.length === 0) {
          this.EmptyHintBuilder('暂无推荐歌单')
        } else {
          ForEach(this.chunkRows(this.recommendSheets), (rowItems: Array<SheetItem>, rowIndex: number) => {
            Row({ space: 8 }) {
              ForEach(rowItems, (sheet: SheetItem, index: number) => {
                Column({ space: 6 }) {
                  if (sheet.coverImg.length > 0) {
                    Image(sheet.coverImg)
                      .width('100%')
                      .aspectRatio(1)
                      .borderRadius(12)
                      .objectFit(ImageFit.Cover)
                      .alt($r('app.media.startIcon'))
                  } else {
                    Column() {
                      SymbolGlyph($r('sys.symbol.music_note_list'))
                        .fontSize(28)
                        .fontColor([$r('sys.color.icon_tertiary')])
                    }
                    .width('100%')
                    .aspectRatio(1)
                    .borderRadius(12)
                    .backgroundColor($r('sys.color.comp_background_tertiary'))
                    .justifyContent(FlexAlign.Center)
                  }
                  Text(sheet.title)
                    .fontSize(12)
                    .fontColor($r('sys.color.font_secondary'))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .onClick(() => {
                  this.onSheetClick();
                })
              }, (sheet: SheetItem, index: number) => sheet.platform + '_' + sheet.id + '_' + rowIndex.toString() + '_' + index.toString())
              if (rowItems.length === 1) {
                Blank().layoutWeight(1)
                Blank().layoutWeight(1)
              } else if (rowItems.length === 2) {
                Blank().layoutWeight(1)
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }, (rowItems: Array<SheetItem>, rowIndex: number) => 'row_' + rowIndex.toString())
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  LocalMusicBuilder() {
    Column() {
      this.SectionTitleBuilder($r('app.string.home_local_music'), '',
        '共 ' + this.localMusic.length.toString() + ' 首')
      if (this.localMusic.length === 0) {
        this.EmptyHintBuilder($r('app.string.home_no_local_music'))
      } else {
        ForEach(this.localMusic.slice(0, LOCAL_PREVIEW_COUNT), (item: MusicItem, index: number) => {
          this.MusicRowBuilder(item, index, false)
        }, (item: MusicItem, index: number) => item.platform + '_' + item.id + '_' + index.toString())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  EmptyHintBuilder(message: ResourceStr) {
    Text(message)
      .fontSize(13)
      .fontColor($r('sys.color.font_tertiary'))
      .width('100%')
      .textAlign(TextAlign.Center)
      .padding({ top: 16, bottom: 16 })
  }
}
