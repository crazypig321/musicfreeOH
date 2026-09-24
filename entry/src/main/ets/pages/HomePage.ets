import { TimeTipUtils } from '../utils/TimeTipUtils'
import { CommonNav, titleBarOf } from '../view/CommonNav'
import { HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { CommonLoading, CommonNull, CommonSearch, SheetCard, CardStack, MenuItemParams } from '../view/CommonCom';
import { MusicOptionsSheet } from '../view/MusicOptionsSheet';
import { NavPathUtils } from '../utils/NavPathUtils';
import { BarScrollHelper, IsApiVersion_24 } from '../utils/BarScrollHelper';
import { SheetGroupItem, SheetItem, MediaTag, PageResult } from '../common/model/SheetTypes';
import { SheetRowDataSource } from '../common/model/SheetRowDataSource';
import { MediaTagDataSource } from '../common/model/MediaTagDataSource';
import { ROUTE_DOWNLOAD, ROUTE_LOCAL_MUSIC, ROUTE_RECOMMEND_SHEETS, ROUTE_SHEET_DETAIL, RecommendSheetNavParams, SheetDetailNavParams } from '../common/model/NavModels';
import { MusicItem } from '../common/model/MediaTypes';
import { MusicRow } from '../view/MusicRow';
import { SheetGridItem } from '../view/SheetGridItem';
import { appState } from '../entryability/AppState';
import { HomeList, IconTextItem } from '../common/model/home/HomeModel';
import { Plugin } from '../plugin/Plugin';
import { pluginManager } from '../plugin/PluginManager';
import { PluginAbility } from '../common/Consts';
import { localMusicSheet } from '../core/LocalMusicSheet';
import { trackPlayer } from '../core/TrackPlayer';
import { MenuUtils } from '../utils/MenuUtils';
import { sheetGridColumns, useSidebarLayout } from '../utils/BreakpointUtils';

// ---------- 常量 ----------
const TOP_LIST_MAX_GROUPS = 3;                 // 榜单最多展示的分组数
const LOCAL_PREVIEW_COUNT = 10;                // 本地音乐预览条数
const RECOMMEND_PREVIEW_ROWS = 5;              // 推荐歌单预览行数
const HOME_MENU_ANCHOR_ID = 'home_menu_anchor';// 插件选择菜单的弹出锚点 id

@ComponentV2
export struct HomePage{
  @Param bootReady: boolean = false;

  // 榜单
  @Local topListGroups: Array<SheetGroupItem> = [];
  @Local topListPluginName: string = '';
  // 推荐歌单
  @Local recommendPluginName: string = '';
  @Local recommendTags: Array<MediaTag> = [];
  /** 推荐标签懒加载数据源（插件标签较多时按需创建） */
  private recommendTagSource: MediaTagDataSource = new MediaTagDataSource();
  @Local selectedTagIndex: number = 0;
  @Local recommendSheets: Array<SheetItem> = [];
  // 本地音乐
  @Local localMusic: Array<MusicItem> = [];
  // 首页当前使用的插件（用户通过右上角菜单选择）
  @Local homePluginName: string = '';
  // 本地音乐条目操作半模态（与搜索页共用）
  @Local showOptions: boolean = false;
  @Local optionsItem: MusicItem = new MusicItem();

  private scroller: Scroller = new Scroller();
  private recommendPlugin: Plugin | null = null;
  // 推荐歌单请求序号（仅应用最新一次请求的结果，避免标签快速切换时乱序）
  private recommendReqSeq: number = 0;
  // 推荐歌单行数据源（LazyForEach 用）
  private rowSource: SheetRowDataSource = new SheetRowDataSource();

  /** 网格列数随宽度断点变化（sm 3 / md 4 / lg 5） */
  @Computed
  get gridColumns(): number {
    return sheetGridColumns(appState.WidthBp);
  }

  /** 推荐歌单变化时同步行数据源（首页仅预览前 N 行，LazyForEach 按需加载） */
  @Monitor('recommendSheets')
  onRecommendSheetsChange(): void {
    this.rowSource.setRows(this.chunkRows(this.recommendSheets).slice(0, RECOMMEND_PREVIEW_ROWS));
  }

  /** 断点变化（旋转/折叠/分屏）时按新列数重新切分行 */
  @Monitor('gridColumns')
  onGridColumnsChange(): void {
    this.rowSource.setRows(this.chunkRows(this.recommendSheets).slice(0, RECOMMEND_PREVIEW_ROWS));
  }

  aboutToAppear(): void {
    // 本地音乐列表 + 变更监听
    this.localMusic = localMusicSheet.musicList.slice();
    localMusicSheet.onLocalSheetUpdated((): void => {
      this.localMusic = localMusicSheet.musicList.slice();
    });
    // 插件顺序/启用状态变化时刷新首页
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

  /** 主体build */
  build() {
    CommonNav({
      titleBarOp: titleBarOf(TimeTipUtils(), $r('app.string.home_subtitle'), this.titleMenus(),
      useSidebarLayout(appState.WidthBp, appState.screenWidth, appState.displayWidth) ? undefined :
        { builder: (): void => { this.search() } }),
      isHideBackButton: true,
      embedded: true,
      doubleTapToTop: true,
      scroller: this.scroller
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 12 }) {
          if (!this.bootReady) {
            // 插件尚未加载完成
            ListItem() {
              CommonLoading()
            }
          } else {
            // 三个板块：榜单 / 推荐歌单 / 本地音乐
            ForEach(HomeList, (g: IconTextItem, gi: number)=>{
              ListItemGroup({ header: this.listGroupTitleBuilder(g, this.sectionTail(gi), gi) }){
                if (gi === 0) {
                  this.TopListsBuilder()
                } else if (gi === 1) {
                  this.RecommendSheetsBuilder()
                } else {
                  this.LocalMusicBuilder()
                }
              }
            }, (g: IconTextItem, gi: number) => 'home_section_' + gi.toString())
          }
        }.ListStyle()
        .onScrollFrameBegin((offset: number) => {
          BarScrollHelper.notifyScrollDelta(this.getUIContext(), offset)
          return { offsetRemain: offset }
        })

        // 插件选择菜单锚点（隐藏组件，仅用于 openMenu 定位，位于标题栏右上角按钮下方）
        Row({ space: 12 }) {
          Column()
            .id(HOME_MENU_ANCHOR_ID)
            .width(24)
            .height(24)
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: 16 })
        .margin({ top: appState.topRect + 20 })

        // 本地音乐条目操作半模态（与搜索页共用；本地音乐条目提供移出/删除入口）
        MusicOptionsSheet({
          optionsItem: this.optionsItem,
          show: this.showOptions,
          localListMode: true,
          onClose: (): void => {
            this.showOptions = false;
          }
        })
      }
      .width('100%')
      .height('100%')
    }
  }

  // ==================== 数据加载 ====================

  /** 刷新首页全部板块 */
  private refreshHome(): void {
    this.loadTopLists();
    this.loadRecommendSheets();
  }

  /** 加载榜单（使用当前选择的插件） */
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
    }).catch((_e: Object): void => {
      this.topListGroups = [];
    });
  }

  /** 加载推荐歌单标签与歌单（使用当前选择的插件） */
  private loadRecommendSheets(): void {
    const plugin = this.pickPlugin(pluginManager.getSortedPluginsWithAbility(PluginAbility.GetRecommendSheetsByTag));
    if (plugin === null) {
      this.recommendPlugin = null;
      this.recommendTags = [];
      this.recommendTagSource.reload([]);
      this.recommendSheets = [];
      this.recommendPluginName = '';
      return;
    }
    this.recommendPlugin = plugin;
    this.recommendPluginName = plugin.name;
    plugin.methods.getRecommendSheetTags().then((result) => {
      // 标签条：默认 + 固定标签 + 各分组子标签（展平）
      const tags: Array<MediaTag> = [this.defaultTag()];
      for (const tag of result.pinned) {
        tags.push(tag);
      }
      for (const group of result.data) {
        for (const tag of group.data) {
          tags.push(tag);
        }
      }
      this.recommendTags = tags;
      this.recommendTagSource.reload(tags);
      this.selectedTagIndex = 0;
      this.applyTagSheets(0);
    }).catch((_e: Object): void => {
      this.recommendTags = [];
      this.recommendTagSource.reload([]);
      this.recommendSheets = [];
    });
  }

  /** 默认标签（空 id，由插件返回默认推荐） */
  private defaultTag(): MediaTag {
    const tag = new MediaTag();
    tag.title = '默认';
    return tag;
  }

  /** 按标签下标请求推荐歌单（总是请求插件，子标签本身不是歌单） */
  private applyTagSheets(index: number): void {
    const plugin = this.recommendPlugin;
    const tag = index >= 0 && index < this.recommendTags.length ? this.recommendTags[index] : null;
    if (plugin === null || tag === null) {
      this.recommendSheets = [];
      return;
    }
    this.recommendReqSeq++;
    const seq = this.recommendReqSeq;
    // 不清空旧内容：清空会导致外层 List 高度塌陷、滚动位置被钳制，标签条产生偏移
    plugin.methods.getRecommendSheetsByTag(tag, 1).then((r: PageResult<SheetItem>) => {
      if (seq !== this.recommendReqSeq) {
        return;
      }
      this.recommendSheets = r.data;
    }).catch((_e: Object): void => {
      if (seq !== this.recommendReqSeq) {
        return;
      }
      this.recommendSheets = [];
    });
  }

  /** 首页可用的插件（支持榜单或推荐歌单，去重、按插件顺序） */
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

  /** 推荐歌单按列数切分成行 */
  private chunkRows(sheets: Array<SheetItem>): Array<Array<SheetItem>> {
    const rows: Array<Array<SheetItem>> = [];
    let row: Array<SheetItem> = [];
    for (const sheet of sheets) {
      row.push(sheet);
      if (row.length === this.gridColumns) {
        rows.push(row);
        row = [];
      }
    }
    if (row.length > 0) {
      rows.push(row);
    }
    return rows;
  }

  /** 空位占位下标（不足整行时补 Blank，保持单元格等宽） */
  private blankIndexes(count: number): Array<number> {
    const arr: Array<number> = [];
    for (let i = 0; i < count; i++) {
      arr.push(i);
    }
    return arr;
  }

  // ==================== 交互 ====================

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  /** 板块跳转：推荐歌单 → 推荐歌单页，本地音乐 → 本地音乐页 */
  private sectionJump(gi: number): void {
    if (gi === 1) {
      if (this.recommendPluginName.length === 0) {
        return;
      }
      RecommendSheetNavParams.pluginName = this.recommendPluginName;
      RecommendSheetNavParams.tags = this.recommendTags;
      RecommendSheetNavParams.selectedIndex = this.selectedTagIndex;
      NavPathUtils.push(ROUTE_RECOMMEND_SHEETS);
    } else if (gi === 2) {
      NavPathUtils.push(ROUTE_LOCAL_MUSIC);
    }
  }

  /** 歌单卡片点击：进入歌单详情页（榜单条目的 platform 可能为空，用来源插件名） */
  private onSheetClick(sheet: SheetItem, isTopList: boolean): void {
    const pluginName = isTopList ? this.topListPluginName : this.recommendPluginName;
    if (pluginName.length === 0) {
      this.showToast('插件不可用');
      return;
    }
    SheetDetailNavParams.pluginName = pluginName;
    SheetDetailNavParams.sheet = sheet;
    SheetDetailNavParams.isTopList = isTopList;
    NavPathUtils.push(ROUTE_SHEET_DETAIL);
  }

  /** 播放本地音乐（以本地列表为播放队列） */
  private playLocal(item: MusicItem): void {
    if (this.localMusic.length === 0) {
      return;
    }
    trackPlayer.playWithReplacePlayList(item, this.localMusic).catch((_e: Object): void => {
      this.showToast('播放失败');
    });
  }

  /** 打开本地音乐条目操作半模态（与搜索结果一致） */
  private openLocalOptions(item: MusicItem): void {
    this.optionsItem = item.clone();
    this.showOptions = true;
  }

  /** 切换推荐歌单标签 */
  private onSelectTag(index: number): void {
    if (index === this.selectedTagIndex) {
      return;
    }
    this.selectedTagIndex = index;
    this.applyTagSheets(index);
  }

  /** 弹出插件选择菜单（当前插件带勾选标记） */
  private openPluginMenu(): void {
    const candidates = this.homeCandidates();
    if (candidates.length === 0) {
      this.showToast('暂无可用插件');
      return;
    }
    // 计算当前生效的插件名（用户选择 or 默认第一个）
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
    // 组装菜单项
    const items: Array<MenuItemParams> = [];
    for (const p of candidates) {
      const item = new MenuItemParams();
      if (p.name === selectedName) {
        item.icon = $r('sys.symbol.checkmark');
      }
      item.label = p.name;
      const name = p.name;
      item.onAction = (): void => {
        MenuUtils.Dismiss();
        if (this.homePluginName !== name) {
          this.homePluginName = name;
          this.refreshHome();
        }
      };
      items.push(item);
    }
    MenuUtils.Open(this.getUIContext(), HOME_MENU_ANCHOR_ID, items, {
      placement: Placement.BottomRight,
      offset: { x: 0, y: -45 }
    });
  }

  /** titleBar 菜单按钮：下载 + 选择插件 */
  private titleMenus(): Array<HdsNavigationMenuItemOptions> {
    const download: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.download'),
        label: '下载',
        action: (): void => {
          NavPathUtils.push(ROUTE_DOWNLOAD);
        }
      }
    };
    const menu: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.AI_panels'),
        label: '选择插件',
        action: (): void => {
          this.openPluginMenu();
        }
      }
    };
    return [download, menu];
  }

  // ==================== UI 构建 ====================

  /** 搜索框（挂在标题栏底部 bottomBuilder） */
  @Builder
  search(){
    CommonSearch({
      searchValue: '',
      placeholderValue: $r('app.string.home_search_placeholder'),
      isFocusable: false,
      click: () => {
        NavPathUtils.push('search')
      }
    }).padding({ left: 16, right: 16 })
  }

  /** listgroup 顶部组件：图标 + 标题 + 右侧附加信息（插件名/数量），推荐/本地板块可点击标题跳转 */
  @Builder
  listGroupTitleBuilder(g: IconTextItem, tail: string, gi: number) {
    Row({ space: 5 }){
      SymbolGlyph(g.icon)
        .fontColor([$r('sys.color.font_tertiary')])
        .fontWeight(FontWeight.Bold)
        .fontSize(18)
        .padding(5)
        .backgroundColor($r('sys.color.comp_background_secondary'))
        .borderRadius(5)

      Text(g.text1)
        .fontColor($r('sys.color.font'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .onClick(() => {
          if (gi === 1 || gi === 2) {
            this.sectionJump(gi);
          }
        })

      if (tail.length > 0) {
        Text(tail)
          .fontSize(10)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .padding({ top: 3, bottom: 3, left: 5, right: 5 })
          .borderRadius(3)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
      }

      if (gi === 1 || gi === 2) {
        Blank()
        Row({ space: 10 }){
          Text('更多')
            .fontSize(14)
            .fontColor($r('sys.color.icon_tertiary'))
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('sys.color.icon_tertiary')])
        }
      }
    }
    .width('100%')
    .padding({ bottom: 12 })
    .onClick(() => {
      this.sectionJump(gi);
    })
  }

  /** 板块标题右侧附加信息：榜单/推荐显示插件名，本地音乐显示总数 */
  private sectionTail(gi: number): string {
    if (gi === 0) {
      return this.topListPluginName;
    }
    if (gi === 1) {
      return this.recommendPluginName;
    }
    return this.localMusic.length > 0 ? '共 ' + this.localMusic.length.toString() + ' 首' : '';
  }

  /** 榜单板块：第一组为 Swiper 轮播（选中卡片放大），其余为横向卡片列表 */
  @Builder
  TopListsBuilder() {
    if (this.topListGroups.length === 0) {
      ListItem() {
        CommonNull({ message: $r('app.string.home_no_plugin') })
      }
    } else {
      ForEach(this.topListGroups, (l: SheetGroupItem, i: number)=>{
        ListItem() {
          Column({ space: 16 }) {
            if (this.topListGroups.length > 1) {
              Text(l.title)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_secondary'))
            }
            if (i === 0) {
              // 第一组：卡片堆叠轮播（后面卡片露出上边缘，滑动/点击切换）
              CardStack({
                items: l.data,
                cardWidth: useSidebarLayout(appState.WidthBp, appState.screenWidth, appState.displayWidth) ? 180 : 160,
                coverAspect: 0.8,
                sideCount: useSidebarLayout(appState.WidthBp, appState.screenWidth, appState.displayWidth) ? 3 : 2,
                spacing: useSidebarLayout(appState.WidthBp, appState.screenWidth, appState.displayWidth) ? 90 : 70,
                dimOpacity: 0.7,
                scaleStep: 0.12,
                itemClick: (sheet: SheetItem): void => {
                  this.onSheetClick(sheet, true);
                }
              }).padding({ bottom: 16 })
            } else {
              // 其余组：横向滑动的歌单卡片
              List({ space: 12 }) {
                ForEach(l.data, (sheet: SheetItem, index: number) => {
                  ListItem() {
                    Column() {
                      SheetCard({
                        sheet: sheet,
                        widthValue: 90,
                        click: (): void => {
                          this.onSheetClick(sheet, true);
                        }
                      })
                    }
                    .alignItems(HorizontalAlign.Start)
                  }.padding({ bottom: 16 })
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
        }
      }, (l: SheetGroupItem, lIndex: number) => l.title + '_' + lIndex.toString())
    }
  }

  /** 推荐歌单板块：标签横向切换 + 三列网格 */
  @Builder
  RecommendSheetsBuilder() {
    if (this.recommendTags.length === 0 && this.recommendSheets.length === 0) {
      ListItem() {
        CommonNull({ message: $r('app.string.home_no_plugin') })
      }
    } else {
      // 标签条
      if (this.recommendTags.length > 0) {
        ListItem() {
          List({ space: 8 }) {
            LazyForEach(this.recommendTagSource, (tag: MediaTag, index: number) => {
              ListItem() {
                Text(tag.title)
                  .fontSize(13)
                  .fontColor(this.selectedTagIndex === index ? $r('sys.color.font_on') : $r('sys.color.font_secondary'))
                  .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                  .borderRadius(16)
                  .backgroundColor(this.selectedTagIndex === index ? $r('sys.color.font_secondary') : $r('sys.color.comp_background_tertiary'))
                  .maxLines(1)
                  .onClick(() => {
                    this.onSelectTag(index);
                  })
              }
            }, (tag: MediaTag, _index: number) => tag.id + '_' + tag.title)
          }
          .listDirection(Axis.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }
      }
      // 歌单网格（LazyForEach 按需创建行，避免歌单过多时卡顿）
      if (this.recommendSheets.length === 0) {
        ListItem() {
          CommonNull({ message: '暂无推荐歌单' })
        }
      } else {
        LazyForEach(this.rowSource, (rowItems: Array<SheetItem>, rowIndex: number) => {
          ListItem() {
            Row({ space: 12 }) {
              ForEach(rowItems, (sheet: SheetItem, index: number) => {
                SheetGridItem({
                  sheet: sheet,
                  onTap: (): void => {
                    this.onSheetClick(sheet, false);
                  }
                })
              }, (sheet: SheetItem, index: number) => sheet.platform + '_' + sheet.id + '_' + rowIndex.toString() + '_' + index.toString())
              // 不足整行时用 Blank 占位保持等宽
              ForEach(this.blankIndexes(this.gridColumns - rowItems.length), (_i: number, bi: number) => {
                Blank().layoutWeight(1)
              }, (_i: number, bi: number) => 'blank_' + bi.toString())
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            // 标签切换时渐隐过渡，避免闪烁突兀
            .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.Smooth }))
          }.padding({top: 10, bottom: 10})
        }, (rowItems: Array<SheetItem>, rowIndex: number) => {
          // key 带上行内容，标签切换后即使行数相同也能刷新
          let key = 'recommend_row_' + rowIndex.toString();
          for (const s of rowItems) {
            key += '_' + s.platform + '_' + s.id;
          }
          return key;
        })
      }
    }
  }

  /** 本地音乐板块：预览前 N 条（条目间分割线，点击播放） */
  @Builder
  LocalMusicBuilder() {
    if (this.localMusic.length === 0) {
      ListItem() {
        CommonNull({ message: $r('app.string.home_no_local_music') })
      }
    } else {
      ForEach(this.localMusic.slice(0, LOCAL_PREVIEW_COUNT), (item: MusicItem, index: number) => {
        ListItem() {
          MusicRow({
            item: item,
            showDivider: index < Math.min(this.localMusic.length, LOCAL_PREVIEW_COUNT) - 1,
            onTap: (): void => {
              this.playLocal(item);
            },
            onMore: (): void => {
              this.openLocalOptions(item);
            }
          })
        }
      }, (item: MusicItem, index: number) => item.platform + '_' + item.id + '_' + item.artwork + '_' + index.toString())
    }
  }
}

@Extend(List)
function ListStyle(){
  .width('100%')
  .height('100%')
  .scrollBar(BarState.Off)
  .edgeEffect(EdgeEffect.Spring)
  .contentStartOffset(useSidebarLayout(appState.WidthBp, appState.screenWidth, appState.displayWidth) ? 64 : appState.topRect + 120)
  // 上下两排时底栏更高，末尾内容需多留滚动空间
  .contentEndOffset(appState.bottomRect + (IsApiVersion_24() && appState.hdsBarLayoutMode === 1 ? 130 : 60))
  .padding({ left: 16, right: 16 })
}
