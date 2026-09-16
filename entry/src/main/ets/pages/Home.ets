import { MusicItem } from '../common/model/MediaTypes';
import { SheetItem, SheetGroupItem, MediaTag, PageResult } from '../common/model/SheetTypes';
import { PluginAbility } from '../common/Consts';
import { pluginManager } from '../plugin/PluginManager';
import { Plugin } from '../plugin/Plugin';
import { localMusicSheet } from '../core/LocalMusicSheet';
import { trackPlayer } from '../core/TrackPlayer';
import { appState } from '../entryability/AppState';
import { TimeTipUtils } from '../utils/TimeTipUtils';
import { CommonNav, titleBarOf } from '../view/CommonNav';
import { ROUTE_SEARCH } from '../common/model/NavModels';
import { HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { ComponentContent } from '@kit.ArkUI';

const TOP_LIST_MAX_GROUPS = 3;
const LOCAL_PREVIEW_COUNT = 10;
const GRID_COLUMNS = 3;

const HOME_MENU_ANCHOR_ID = 'home_menu_anchor';

/** 主页插件选择菜单项参数 */
class HomeMenuItemParams {
  icon: ResourceStr = '';
  label: string = '';
  onAction: () => void = (): void => {};
}

/** 主页插件选择菜单内容参数 */
class HomeMenuParams {
  items: Array<HomeMenuItemParams> = [];
}

@Builder
function homeMenuBuilder(params: HomeMenuParams) {
  Menu() {
    ForEach(params.items, (item: HomeMenuItemParams) => {
      if (typeof item.icon === 'string') {
        MenuItem({ content: item.label })
          .onClick(() => {
            item.onAction();
          })
      } else {
        MenuItem({ startIcon: item.icon, content: item.label })
          .onClick(() => {
            item.onAction();
          })
      }
    }, (item: HomeMenuItemParams) => item.label)
  }
}

const homeMenuWrapped: WrappedBuilder<[HomeMenuParams]> = wrapBuilder(homeMenuBuilder);

@ComponentV2
export struct Home {
  scroller: Scroller = new Scroller();
  @Param bootReady: boolean = false;
  @Local topListPluginName: string = '';
  @Local topListGroups: Array<SheetGroupItem> = [];
  @Local topListSwiperIndex: number = 0;
  @Local recommendPluginName: string = '';
  @Local recommendTags: Array<MediaTag> = [];
  @Local selectedTagIndex: number = 0;
  @Local recommendSheets: Array<SheetItem> = [];
  @Local localMusic: Array<MusicItem> = [];

  private recommendPlugin: Plugin | null = null;
  private recommendGroups: Array<SheetGroupItem> = [];
  @Local homePluginName: string = '';
  private menuContent: ComponentContent<HomeMenuParams> | null = null;

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

  /** 主页可用的插件（支持榜单或推荐歌单，去重按顺序） */
  private homeCandidates(): Array<Plugin> {
    const result: Array<Plugin> = [];
    const seen: Record<string, boolean> = {};
    const groups: Array<Array<Plugin>> = [
      pluginManager.getSortedPluginsWithAbility(PluginAbility.GetTopLists),
      pluginManager.getSortedPluginsWithAbility(PluginAbility.GetRecommendSheetsByTag)
    ];
    for (const list of groups) {
      for (const p of list) {
        if (!seen[p.name]) {
          seen[p.name] = true;
          result.push(p);
        }
      }
    }
    return result;
  }

  /** 在候选插件中选择当前使用的插件（优先用户选择，否则第一个） */
  private pickPlugin(plugins: Array<Plugin>): Plugin | null {
    if (plugins.length === 0) {
      return null;
    }
    if (this.homePluginName.length > 0) {
      for (const p of plugins) {
        if (p.name === this.homePluginName) {
          return p;
        }
      }
    }
    return plugins[0];
  }

  private loadTopLists(): void {
    const plugin = this.pickPlugin(pluginManager.getSortedPluginsWithAbility(PluginAbility.GetTopLists));
    if (plugin === null) {
      this.topListGroups = [];
      this.topListPluginName = '';
      return;
    }
    this.topListPluginName = plugin.name;
    plugin.methods.getTopLists().then((groups: Array<SheetGroupItem>) => {
      this.topListGroups = groups.slice(0, TOP_LIST_MAX_GROUPS);
      this.topListSwiperIndex = 0;
    }).catch((_e: Object): void => {
      this.topListGroups = [];
    });
  }

  private loadRecommendSheets(): void {
    const plugin = this.pickPlugin(pluginManager.getSortedPluginsWithAbility(PluginAbility.GetRecommendSheetsByTag));
    if (plugin === null) {
      this.recommendPlugin = null;
      this.recommendGroups = [];
      this.recommendTags = [];
      this.recommendSheets = [];
      this.recommendPluginName = '';
      return;
    }
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

  private dismissMenu(): void {
    const content = this.menuContent;
    this.menuContent = null;
    if (content !== null) {
      this.getUIContext().getPromptAction().closeMenu(content).catch((_e: Object): void => {
      });
    }
  }

  /** 弹出插件选择菜单 */
  private openPluginMenu(): void {
    const candidates = this.homeCandidates();
    if (candidates.length === 0) {
      this.showToast('暂无可用插件');
      return;
    }
    let selectedName = '';
    for (const p of candidates) {
      if (p.name === this.homePluginName) {
        selectedName = p.name;
        break;
      }
    }
    if (selectedName.length === 0) {
      selectedName = candidates[0].name;
    }
    const params = new HomeMenuParams();
    for (const p of candidates) {
      const item = new HomeMenuItemParams();
      if (p.name === selectedName) {
        item.icon = $r('sys.symbol.checkmark');
      }
      item.label = p.name;
      const name = p.name;
      item.onAction = (): void => {
        this.dismissMenu();
        if (this.homePluginName !== name) {
          this.homePluginName = name;
          this.refreshHome();
        }
      };
      params.items.push(item);
    }
    this.dismissMenu();
    const content = new ComponentContent<HomeMenuParams>(this.getUIContext(), homeMenuWrapped, params);
    this.menuContent = content;
    this.getUIContext().getPromptAction().openMenu(content, { id: HOME_MENU_ANCHOR_ID }, {
      placement: Placement.BottomRight,
    }).then((): void => {
      if (this.menuContent === content) {
        this.menuContent = null;
      }
    }).catch((_e: Object): void => {
      this.showToast('菜单弹出失败');
    });
  }

  /** titleBar 菜单按钮（选择插件） */
  private titleMenus(): Array<HdsNavigationMenuItemOptions> {
    const menu: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.square_grid_2x2'),
        label: '选择插件',
        action: (): void => {
          this.openPluginMenu();
        }
      }
    };
    return [menu];
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
      titleBarOp: titleBarOf(TimeTipUtils(), $r('app.string.home_subtitle'), this.titleMenus()),
      isHideBackButton: true,
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller }) {
        ListItem() {
          Column() {
            this.SearchEntryBuilder()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        if (!this.bootReady) {
          ListItem() {
            Column({ space: 8 }) {
              LoadingProgress()
                .width(28)
                .height(28)
                .color($r('sys.color.icon_emphasize'))
            }
            .width('100%')
            .margin({ top: 48 })
            .justifyContent(FlexAlign.Center)
          }
        } else {
          ListItem() {
            this.TopListsBuilder()
          }
          ListItem() {
            this.RecommendSheetsBuilder()
          }
          ListItem() {
            this.LocalMusicBuilder()
          }
        }
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .contentStartOffset(appState.topRect + 66)
      .contentEndOffset(appState.bottomRect + 60)
      .padding({ left: 16, right: 16 })

        // openMenu 锚点（位于标题栏下方右上角，菜单在锚点处弹出）
        Row({ space: 12 }) {
          Column()
            .id(HOME_MENU_ANCHOR_ID)
            .width(24)
            .height(24)
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: 16 })
        .margin({ top: appState.topRect })
      }
      .width('100%')
      .height('100%')
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
          Column({ space: 16 }) {
            if (this.topListGroups.length > 1) {
              Text(group.title)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_secondary'))
            }
            if (groupIndex === 0) {
              Swiper() {
                ForEach(group.data, (sheet: SheetItem, index: number) => {
                  Column() {
                    this.TopListSwiperCardBuilder(sheet, index)
                  }
                  .width('100%')
                  .height('100%')
                }, (sheet: SheetItem, index: number) => sheet.platform + '_' + sheet.id + '_' + index.toString())
              }
              .loop(group.data.length > 1)
              .indicator(new DotIndicator()
                .color($r('sys.color.comp_background_tertiary'))
                .selectedColor($r('sys.color.icon_emphasize')))
              .prevMargin(48)
              .nextMargin(48)
              .width('100%')
              .height(216)
              .onChange((index: number) => {
                this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseOut }, (): void => {
                  this.topListSwiperIndex = index;
                });
              })
            } else {
              List({ space: 12 }) {
                ForEach(group.data, (sheet: SheetItem, index: number) => {
                  ListItem() {
                    Column() {
                      this.SheetCardBuilder(sheet)
                    }
                    .alignItems(HorizontalAlign.Start)
                  }
                }, (sheet: SheetItem, index: number) => sheet.platform + '_' + sheet.id + '_' + index.toString())
              }
              .listDirection(Axis.Horizontal)
              .scrollBar(BarState.Off)
              .edgeEffect(EdgeEffect.Spring)
              .width('100%')
            }
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
  TopListSwiperCardBuilder(sheet: SheetItem, index: number) {
    Column({ space: 8 }) {
      if (sheet.coverImg.length > 0) {
        Image(sheet.coverImg)
          .width('70%')
          .aspectRatio(1)
          .borderRadius(16)
          .objectFit(ImageFit.Cover)
          .alt($r('app.media.startIcon'))
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.music_note_list'))
            .fontSize(28)
            .fontColor([$r('sys.color.icon_tertiary')])
        }
        .width('70%')
        .aspectRatio(1)
        .borderRadius(16)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .justifyContent(FlexAlign.Center)
      }
      Text(sheet.title)
        .fontSize(13)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .scale({
      x: this.topListSwiperIndex === index ? 1 : 0.8,
      y: this.topListSwiperIndex === index ? 1 : 0.8
    })
    .opacity(this.topListSwiperIndex === index ? 1 : 0.65)
    .onClick(() => {
      this.onSheetClick();
    })
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
          List({ space: 8 }) {
            ForEach(this.recommendTags, (tag: MediaTag, index: number) => {
              ListItem() {
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
              }
            }, (tag: MediaTag, index: number) => tag.id + '_' + index.toString())
          }
          .listDirection(Axis.Horizontal)
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
