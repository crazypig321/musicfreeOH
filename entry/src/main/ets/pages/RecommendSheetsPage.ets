import { CommonNav, titleBarOf } from '../view/CommonNav';
import { SheetGridItem } from '../view/SheetGridItem';
import { SheetRowDataSource } from '../common/model/SheetRowDataSource';
import { MediaTagDataSource } from '../common/model/MediaTagDataSource';
import { MediaTag, PageResult, RecommendSheetTagsResult, SheetItem } from '../common/model/SheetTypes';
import { RecommendSheetNavParams, ROUTE_SHEET_DETAIL, SheetDetailNavParams } from '../common/model/NavModels';
import { Plugin } from '../plugin/Plugin';
import { pluginManager } from '../plugin/PluginManager';
import { PluginAbility } from '../common/Consts';
import { MenuItemParams } from '../view/CommonCom';
import { MenuUtils } from '../utils/MenuUtils';
import { NavPathUtils } from '../utils/NavPathUtils';
import { HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { appState } from '../entryability/AppState';
import { sheetGridColumns } from '../utils/BreakpointUtils';

const RECOMMEND_MENU_ANCHOR_ID = 'recommend_menu_anchor';

/**
 * 推荐歌单页：首页推荐歌单板块的完整版（标签切换 + 三列网格 + 触底续拉）
 * 右上角插件选择菜单与首页一致，切换后本页重新加载标签与歌单
 */
@ComponentV2
export struct RecommendSheetsPage {
  @Local tags: Array<MediaTag> = [];
  /** 标签懒加载数据源（插件标签较多时按需创建） */
  private tagSource: MediaTagDataSource = new MediaTagDataSource();
  @Local selectedIndex: number = 0;
  @Local sheets: Array<SheetItem> = [];
  @Local loading: boolean = false;
  /** 当前使用的插件名（菜单中带勾选标记） */
  @Local pluginName: string = '';

  private scroller: Scroller = new Scroller();
  private rowSource: SheetRowDataSource = new SheetRowDataSource();
  private plugin: Plugin | null = null;
  private page: number = 1;
  private isEnd: boolean = false;
  private reqSeq: number = 0;

  /** 网格列数随宽度断点变化（sm 3 / md 4 / lg 5） */
  @Computed
  get gridColumns(): number {
    return sheetGridColumns(appState.WidthBp);
  }

  /** 歌单变化时同步行数据源（LazyForEach 按需加载行） */
  @Monitor('sheets')
  onSheetsChange(): void {
    this.rowSource.setRows(this.chunkRows(this.sheets));
  }

  /** 断点变化（旋转/折叠/分屏）时按新列数重新切分行 */
  @Monitor('gridColumns')
  onGridColumnsChange(): void {
    this.rowSource.setRows(this.chunkRows(this.sheets));
  }

  aboutToAppear(): void {
    this.plugin = pluginManager.getByName(RecommendSheetNavParams.pluginName);
    this.pluginName = RecommendSheetNavParams.pluginName;
    this.tags = RecommendSheetNavParams.tags;
    this.tagSource.reload(this.tags);
    this.selectedIndex = RecommendSheetNavParams.selectedIndex;
    this.loadSheets(true);
  }

  /** 按页加载歌单：reset 重新加载第一页，否则触底续拉 */
  private loadSheets(reset: boolean): void {
    const plugin = this.plugin;
    const tag = this.selectedIndex >= 0 && this.selectedIndex < this.tags.length ?
      this.tags[this.selectedIndex] : null;
    if (plugin === null || tag === null || this.loading) {
      return;
    }
    if (!reset && this.isEnd) {
      return;
    }
    this.loading = true;
    this.reqSeq++;
    const seq = this.reqSeq;
    const page = reset ? 1 : this.page + 1;
    plugin.methods.getRecommendSheetsByTag(tag, page).then((r: PageResult<SheetItem>): void => {
      if (seq !== this.reqSeq) {
        return;
      }
      this.loading = false;
      this.page = page;
      this.isEnd = r.isEnd;
      this.sheets = reset ? r.data : this.sheets.concat(r.data);
    }).catch((_e: Object): void => {
      if (seq !== this.reqSeq) {
        return;
      }
      this.loading = false;
      if (reset) {
        this.sheets = [];
      }
    });
  }

  /** 切换标签 */
  private onSelectTag(index: number): void {
    if (index === this.selectedIndex) {
      return;
    }
    this.selectedIndex = index;
    this.loadSheets(true);
  }

  /** 歌单点击：进入歌单详情页 */
  private onSheetClick(sheet: SheetItem): void {
    if (this.pluginName.length === 0 || this.plugin === null) {
      this.showToast('插件不可用');
      return;
    }
    SheetDetailNavParams.pluginName = this.pluginName;
    SheetDetailNavParams.sheet = sheet;
    SheetDetailNavParams.isTopList = false;
    NavPathUtils.push(ROUTE_SHEET_DETAIL);
  }

  /** 弹出插件选择菜单（当前插件带勾选标记，与首页一致） */
  private openPluginMenu(): void {
    const candidates = pluginManager.getSortedPluginsWithAbility(PluginAbility.GetRecommendSheetsByTag);
    if (candidates.length === 0) {
      this.showToast('暂无可用插件');
      return;
    }
    // 计算当前生效的插件名（用户选择 or 默认第一个）
    let selectedName = '';
    for (const p of candidates) {
      if (p.name === this.pluginName) {
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
        this.switchPlugin(name);
      };
      items.push(item);
    }
    MenuUtils.Open(this.getUIContext(), RECOMMEND_MENU_ANCHOR_ID, items, {
      placement: Placement.BottomRight,
      offset: { x: 0, y: -45 }
    });
  }

  /** 切换插件：重新拉取标签并加载默认标签下的第一页歌单 */
  private switchPlugin(name: string): void {
    if (name === this.pluginName) {
      return;
    }
    this.pluginName = name;
    this.plugin = pluginManager.getByName(name);
    if (this.plugin === null) {
      this.tags = [];
      this.tagSource.reload([]);
      this.sheets = [];
      return;
    }
    this.plugin.methods.getRecommendSheetTags().then((result: RecommendSheetTagsResult): void => {
      // 标签条：默认 + 固定标签 + 各分组子标签（展平），与首页一致
      const tags: Array<MediaTag> = [RecommendSheetsPage.defaultTag()];
      for (const tag of result.pinned) {
        tags.push(tag);
      }
      for (const group of result.data) {
        for (const tag of group.data) {
          tags.push(tag);
        }
      }
      this.tags = tags;
      this.tagSource.reload(tags);
      this.selectedIndex = 0;
      this.loadSheets(true);
    }).catch((_e: Object): void => {
      this.tags = [];
      this.tagSource.reload([]);
      this.sheets = [];
    });
  }

  /** 默认标签（空 id，由插件返回默认推荐） */
  private static defaultTag(): MediaTag {
    const tag = new MediaTag();
    tag.title = '默认';
    return tag;
  }

  /** titleBar 菜单按钮：选择插件 */
  private titleMenus(): Array<HdsNavigationMenuItemOptions> {
    const menu: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.AI_panels'),
        label: '选择插件',
        action: (): void => {
          this.openPluginMenu();
        }
      }
    };
    return [menu];
  }

  /** 歌单按列数切分成行 */
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

  build() {
    CommonNav({
      titleBarOp: titleBarOf('推荐歌单', undefined, this.titleMenus()),
      scroller: this.scroller,
      isShowPlayBar: true,
      doubleTapToTop: true
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 12 }) {
        // 插件不可用提示
        if (this.plugin === null) {
          ListItem() {
            Text('插件不可用，请返回首页重新进入')
              .fontSize(13)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
              .margin({ top: 16 })
          }
        }
        // 标签条
        if (this.tags.length > 0) {
          ListItem() {
            List({ space: 8 }) {
              LazyForEach(this.tagSource, (tag: MediaTag, index: number) => {
                ListItem() {
                  Text(tag.title)
                    .fontSize(13)
                    .fontColor(this.selectedIndex === index ?
                    $r('sys.color.font_on') : $r('sys.color.font_secondary'))
                    .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                    .borderRadius(16)
                    .backgroundColor(this.selectedIndex === index ?
                    $r('sys.color.font_secondary') : $r('sys.color.comp_background_tertiary'))
                    .maxLines(1)
                    .onClick(() => {
                      this.onSelectTag(index);
                    })
                }
              }, (tag: MediaTag, _index: number) => tag.id + '_' + tag.title)
            }
            .listDirection(Axis.Horizontal)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .width('100%')
          }.padding({ top: 16 })
        }
        // 歌单网格（LazyForEach 按需创建行）
        if (this.sheets.length === 0 && !this.loading) {
          ListItem() {
            Text('暂无推荐歌单')
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 48 })
          }
        }
        LazyForEach(this.rowSource, (rowItems: Array<SheetItem>, rowIndex: number) => {
          ListItem() {
            Row({ space: 12 }) {
              ForEach(rowItems, (sheet: SheetItem, index: number) => {
                SheetGridItem({
                  sheet: sheet,
                  onTap: (): void => {
                    this.onSheetClick(sheet);
                  }
                })
              }, (sheet: SheetItem, index: number) =>
                sheet.platform + '_' + sheet.id + '_' + rowIndex.toString() + '_' + index.toString())
              // 不足整行时用 Blank 占位保持等宽
              ForEach(this.blankIndexes(this.gridColumns - rowItems.length), (_i: number, bi: number) => {
                Blank().layoutWeight(1)
              }, (_i: number, bi: number) => 'blank_' + bi.toString())
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }
        }, (rowItems: Array<SheetItem>, rowIndex: number) => {
          // key 带上行内容，标签切换后即使行数相同也能刷新
          let key = 'recommend_row_' + rowIndex.toString();
          for (const s of rowItems) {
            key += '_' + s.platform + '_' + s.id;
          }
          return key;
        })
        // 底部加载状态
        if (this.loading) {
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
        } else if (this.isEnd && this.sheets.length > 0) {
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
      .ListStyle()
      .onReachEnd(() => {
        this.loadSheets(false);
      })

      // 插件选择菜单锚点（隐藏组件，仅用于 openMenu 定位，位于标题栏右上角按钮下方）
      Row({ space: 12 }) {
        Column()
          .id(RECOMMEND_MENU_ANCHOR_ID)
          .width(24)
          .height(24)
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ right: 16 })
      .margin({ top: appState.topRect + 20 })
      }
      .width('100%')
      .height('100%')
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }
}

@Extend(List)
function ListStyle() {
  .width('100%')
  .height('100%')
  .scrollBar(BarState.Off)
  .edgeEffect(EdgeEffect.Spring)
  .contentStartOffset(appState.topRect + 46)
  .contentEndOffset(appState.bottomRect + 60)
  .padding({ left: 16, right: 16 })
}
