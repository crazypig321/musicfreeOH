import { MusicItem } from '../model/MediaTypes';
import { SheetItem, SheetGroupItem, MediaTag, PageResult } from '../model/SheetTypes';
import { PluginAbility } from '../common/Consts';
import { pluginManager } from '../plugin/PluginManager';
import { Plugin } from '../plugin/Plugin';
import { localMusicSheet } from '../core/LocalMusicSheet';
import { trackPlayer } from '../core/TrackPlayer';
import { appState } from '../entryability/AppState';
import { TimeTipUtils } from '../utils/TimeTipUtils';
import { CommonNav, titleBarOf } from '../view/CommonNav';
import { ROUTE_SEARCH } from '../model/NavModels';

const TOP_LIST_MAX_GROUPS = 3;
const LOCAL_PREVIEW_COUNT = 10;
const GRID_COLUMNS = 3;

@ComponentV2
export struct Home {
  scroller: Scroller = new Scroller();
  @Param bootReady: boolean = false;
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

  private openSearch(): void {
    appState.pageInfos.pushPathByName(ROUTE_SEARCH, '');
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

  build() {
    CommonNav({
      titleBarOp: titleBarOf(TimeTipUtils(), $r('app.string.home_subtitle')),
      isHideBackButton: true,
      scroller: this.scroller
    }) {
      Scroll(this.scroller) {
        Column() {
          this.SearchEntryBuilder()
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
            this.TopListsBuilder()
            this.RecommendSheetsBuilder()
            this.LocalMusicBuilder()
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 180 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
  }

  @Builder
  SearchEntryBuilder() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(20)
        .fontColor([$r('sys.color.icon_secondary')])
      Text($r('app.string.home_search_placeholder'))
        .fontSize(15)
        .fontColor($r('sys.color.font_tertiary'))
        .layoutWeight(1)
        .maxLines(1)
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .borderRadius(22)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .margin({ top: 4, bottom: 4 })
    .onClick(() => {
      this.openSearch();
    })
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
  MusicRowBuilder(item: MusicItem) {
    Row({ space: 12 }) {
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
    }
    .width('100%')
    .height(56)
    .borderRadius(12)
    .onClick(() => {
      this.playLocal(item);
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
          this.MusicRowBuilder(item)
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
