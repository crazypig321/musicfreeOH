import { CommonNav, titleBarOf } from '../view/CommonNav';
import { ArtworkCache } from '../utils/ArtworkCache';
import { ShareUtils } from '../utils/ShareUtils';
import { CommonBlur, CommonLoading, CommonSearch, MenuItemParams } from '../view/CommonCom';
import { MenuUtils } from '../utils/MenuUtils';
import { musicSheet, SheetBasePatch } from '../core/MusicSheet';
import { subscribedSheets, SubscribedSheetRecord, SubscribedSheetsDataSource, SubscribedMediaType } from '../core/SubscribedSheets';
import { pluginManager } from '../plugin/PluginManager';
import { Plugin } from '../plugin/Plugin';
import { PluginState } from '../plugin/PluginTypes';
import { MusicItem } from '../common/model/MediaTypes';
import { SheetItem, SheetInfoResult } from '../common/model/SheetTypes';
import { appState } from '../entryability/AppState';
import { sheetTopAvoidVp } from '../utils/BreakpointUtils';
import { HdsListItem, HdsSwipeActionOptions, HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { SheetDetailNavParams, ROUTE_SHEET_DETAIL, MediaDetailNavParams, ROUTE_ALBUM_DETAIL, ROUTE_ARTIST_DETAIL } from '../common/model/NavModels';
import { NavPathUtils } from '../utils/NavPathUtils';
import { BarScrollHelper, IsApiVersion_24 } from '../utils/BarScrollHelper';
import { JsonUtil } from '../utils/JsonUtil';
import { DialogManager } from '../utils/DialogUtils';
import { IMPORT_TIMEOUT_MS_OPTIONS, IMPORT_TIMEOUT_LABELS } from '../common/Consts';
import { showUiToast, rowImmersiveModifier, stackImmersiveModifier } from '../utils/UiUtils';

/** 添加菜单锚点 id（openMenu 在锚点处弹出） */
const ADD_ANCHOR_ID = 'mysheets_add_anchor';
const MORE_ANCHOR_ID = 'mysheets_more_anchor';

/** 我的歌单页条目 */
interface SheetRow {
  id: string;
  title: string;
  description: string;
  coverUrl: string;
  worksNum: number;
  createAt: number;
  isDefault: boolean;
}

/** 我的歌单列表懒加载数据源（LazyForEach 用，搜索过滤后整体替换并通知刷新） */
class MySheetRowDataSource implements IDataSource {
  private rows: Array<SheetRow> = [];
  private listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): SheetRow {
    return this.rows[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) === -1) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const i = this.listeners.indexOf(listener);
    if (i >= 0) {
      this.listeners.splice(i, 1);
    }
  }

  /** 整体替换数据并通知重载 */
  reload(rows: Array<SheetRow>): void {
    this.rows = rows;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }
}

/**
 * 我的歌单页：顶部「我的歌单/订阅歌单」分段滑块切换两个列表
 * 我的歌单：展示全部本地歌单（含默认歌单「我的收藏」）
 *   顶部右侧：添加菜单（新建歌单 / 导入歌单 / 导入单曲）+ 批量操作（全选/分享/删除，UI 同歌单详情页批量底栏）
 *   条目 UI 同插件页；左滑呼出 编辑/删除（HdsListItem，默认歌单与批量模式下不提供横滑）
 *   点击进入歌单详情页（本地歌单模式），长按进入批量模式
 * 订阅歌单：展示插件歌单/榜单/专辑/歌手订阅（详情页心形按钮订阅），进入页面/手动同步拉取更新（同步中列表上层显示 loading）；
 *   左滑 分享/更新/排序/取消订阅，点击进入详情页并清除「有更新」标记；
 *   右上角菜单：订阅排序/批量操作/歌单说明；长按进入批量模式（全选/更新/分享/删除，UI 同我的歌单批量底栏）
 */
@ComponentV2
export struct MySheetsPage {
  scroller: Scroller = new Scroller();
  @Local sheetRows: Array<SheetRow> = [];
  /** 分段滑块：当前是否展示订阅歌单 tab */
  @Local showSubscribed: boolean = false;
  /** 订阅歌单记录 */
  @Local subscribedItems: Array<SubscribedSheetRecord> = [];
  /** 订阅同步进行中 */
  @Local syncing: boolean = false;
  /** 批量更新订阅进行中 */
  @Local batchUpdating: boolean = false;
  /** 订阅列表懒加载数据源（搜索过滤后整体替换） */
  private subscribedSource: SubscribedSheetsDataSource = new SubscribedSheetsDataSource();
  /** 我的歌单列表懒加载数据源（搜索过滤后整体替换） */
  private sheetSource: MySheetRowDataSource = new MySheetRowDataSource();
  @Local batchSelected: Array<string> = [];
  /** 新建歌单半模态 */
  @Local showCreateSheet: boolean = false;
  @Local newSheetTitle: string = '';
  @Local newSheetDesc: string = '';
  @Local creating: boolean = false;
  /** 编辑歌单半模态 */
  @Local showEditSheet: boolean = false;
  @Local editSheetId: string = '';
  @Local editSheetTitle: string = '';
  @Local editSheetDesc: string = '';
  /** 导入半模态（导入歌单/导入单曲共用，importSingleMode 区分） */
  @Local showImportSheet: boolean = false;
  @Local importSingleMode: boolean = false;
  @Local importUrl: string = '';
  /** 支持导入的已启用插件名列表 */
  @Local importPluginNames: Array<string> = [];
  @Local importPluginIndex: number = 0;
  /** 导入单曲：目标歌单（id/标题，取当前全部本地歌单） */
  @Local importTargetSheetIds: Array<string> = [];
  @Local importTargetSheetTitles: Array<string> = [];
  @Local importTargetIndex: number = 0;
  @Local importing: boolean = false;
  /** 导入歌单：超时时长选项序号（默认 5 分钟，大歌单导入耗时较长） */
  @Local importTimeoutIndex: number = 0;
  /** 说明文本刷新标记：懒加载插件挂载完成后 +1 触发重绘 */
  @Local importHintRev: number = 0;
  /** 标题栏搜索框：开启后按关键词过滤歌单条目（点搜索/回车才应用关键词） */
  @Local showSearchBox: boolean = false;
  @Local searchKeyword: string = '';
  /** 搜索框实时输入内容（未提交，不参与过滤） */
  @Local searchInput: string = '';
  /** 歌单排序半模态（默认歌单固定首位，仅排序其余歌单） */
  @Local showSortSheet: boolean = false;
  @Local sortSheetIds: Array<string> = [];
  /** 订阅排序半模态（按全量订阅列表顺序） */
  @Local showSubscribedSortSheet: boolean = false;
  @Local subscribedSortKeys: Array<string> = [];
  /** 当前所处 tab 序号（由 Index 传入，切走时收起搜索框） */
  @Param hostTabIndex: number = 1;

  /** 切换到其他 tab 时收起搜索框并清空关键词 */
  @Monitor('hostTabIndex')
  onTabIndexChanged(): void {
    if (this.hostTabIndex !== 1 && this.showSearchBox) {
      this.showSearchBox = false;
      this.searchKeyword = '';
      this.searchInput = '';
      appState.tabSearchClose = null;
    }
  }

  aboutToAppear(): void {
    this.refreshSheets();
    musicSheet.onSheetBasicUpdated((): void => {
      this.refreshSheets();
    });
    this.refreshSubscribed();
    subscribedSheets.onUpdated((): void => {
      this.refreshSubscribed();
    });
    // 进入页面时拉取式同步订阅（每条 10 分钟节流）
    this.syncSubscribed(false);
  }

  /** 刷新订阅列表 */
  private refreshSubscribed(): void {
    this.subscribedItems = subscribedSheets.getAll().slice();
    this.rebuildSubscribedSource();
  }

  /** 按当前关键词重建订阅列表数据源 */
  private rebuildSubscribedSource(): void {
    this.subscribedSource.reload(this.displaySubscribed());
  }

  /** 按当前关键词重建我的歌单列表数据源 */
  private rebuildSheetSource(): void {
    this.sheetSource.reload(this.displayRows());
  }

  /** 同步订阅歌单（force=true 忽略节流强制刷新，完成后提示） */
  private syncSubscribed(force: boolean): void {
    if (this.syncing) {
      return;
    }
    this.syncing = true;
    subscribedSheets.syncAll(force).then((): void => {
      this.syncing = false;
      if (force) {
        this.showToast('订阅歌单已同步');
      }
    }).catch((_e: Object): void => {
      this.syncing = false;
      if (force) {
        this.showToast('同步失败');
      }
    });
  }

  /** 手动同步订阅歌单 */
  private manualSyncSubscribed(): void {
    if (this.syncing) {
      this.showToast('正在同步，请稍候');
      return;
    }
    if (this.subscribedItems.length === 0) {
      this.showToast('暂无订阅歌单');
      return;
    }
    this.syncSubscribed(true);
  }

  /** 分段滑块切换 我的歌单/订阅歌单（退出批量模式并回顶；单一状态源，滑块位移由 animateTo 驱动） */
  private switchTab(showSubscribed: boolean): void {
    if (this.showSubscribed === showSubscribed) {
      return;
    }
    if (appState.isBatchMode) {
      this.exitBatchMode();
    }
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      this.showSubscribed = showSubscribed;
    });
    // 回顶目标为内容区起点（contentStartOffset 的负偏移处，首条目位于标题栏下方）；
    // 滚到 0 会把首条目顶进标题栏下方被遮挡（短列表切长列表时无法被钳制复位）
    const top = -(appState.topRect + 66 + 44 + (this.showSearchBox ? 56 : 0));
    if (this.scroller.currentOffset().yOffset !== top) {
      this.scroller.scrollTo({ xOffset: 0, yOffset: top, animation: { duration: 250, curve: Curve.EaseOut } });
    }
  }

  /** 刷新歌单列表 */
  private refreshSheets(): void {
    const rows: Array<SheetRow> = [];
    for (const sheet of musicSheet.sheets) {
      const row: SheetRow = {
        id: sheet.id,
        title: sheet.title,
        description: sheet.description,
        coverUrl: sheet.coverUrl(),
        worksNum: sheet.worksNum,
        createAt: sheet.createAt,
        isDefault: sheet.id === musicSheet.defaultSheet.id
      };
      rows.push(row);
    }
    this.sheetRows = rows;
    this.rebuildSheetSource();
  }

  private static formatDate(ts: number): string {
    if (ts <= 0) {
      return '';
    }
    const d = new Date(ts);
    const m = d.getMonth() + 1;
    const day = d.getDate();
    const mStr = m < 10 ? '0' + m.toString() : m.toString();
    const dStr = day < 10 ? '0' + day.toString() : day.toString();
    return d.getFullYear().toString() + '/' + mStr + '/' + dStr;
  }

  /** 条目副标题：共 N 首 · 创建日期 */
  private rowSubtitle(row: SheetRow): string {
    const countText = '共 ' + row.worksNum.toString() + ' 首';
    const date = MySheetsPage.formatDate(row.createAt);
    return date.length > 0 ? countText + ' · ' + date : countText;
  }

  /** 按关键词过滤歌单条目（名称/简介，不区分大小写；空关键词返回全部） */
  private displayRows(): Array<SheetRow> {
    const kw = this.searchKeyword.trim().toLowerCase();
    if (kw.length === 0) {
      return this.sheetRows;
    }
    const rows: Array<SheetRow> = [];
    for (const row of this.sheetRows) {
      if (row.title.toLowerCase().indexOf(kw) >= 0 ||
        row.description.toLowerCase().indexOf(kw) >= 0) {
        rows.push(row);
      }
    }
    return rows;
  }

  /** 按关键词过滤订阅条目（名称，不区分大小写；空关键词返回全部） */
  private displaySubscribed(): Array<SubscribedSheetRecord> {
    const kw = this.searchKeyword.trim().toLowerCase();
    if (kw.length === 0) {
      return this.subscribedItems;
    }
    const rows: Array<SubscribedSheetRecord> = [];
    for (const rec of this.subscribedItems) {
      if (rec.title.toLowerCase().indexOf(kw) >= 0) {
        rows.push(rec);
      }
    }
    return rows;
  }

  /** 订阅条目副标题：来源插件 · 共 N 首 */
  private subscribedRowSubtitle(rec: SubscribedSheetRecord): string {
    let text = rec.platform;
    if (rec.worksNum > 0) {
      text += ' · 共 ' + rec.worksNum.toString() + ' 首';
    }
    return text;
  }

  /** 进入订阅条目详情页（歌单/榜单/专辑/歌手按类型路由），并清除「有更新」标记 */
  private openSubscribedDetail(rec: SubscribedSheetRecord): void {
    if (rec.mediaType === SubscribedMediaType.ALBUM) {
      MediaDetailNavParams.pluginName = rec.platform;
      MediaDetailNavParams.album = rec.albumItem();
      MediaDetailNavParams.artist = null;
      NavPathUtils.push(ROUTE_ALBUM_DETAIL);
    } else if (rec.mediaType === SubscribedMediaType.ARTIST) {
      MediaDetailNavParams.pluginName = rec.platform;
      MediaDetailNavParams.album = null;
      MediaDetailNavParams.artist = rec.artistItem();
      NavPathUtils.push(ROUTE_ARTIST_DETAIL);
    } else {
      SheetDetailNavParams.pluginName = rec.platform;
      SheetDetailNavParams.sheet = rec.sheetItem();
      SheetDetailNavParams.isTopList = rec.mediaType === SubscribedMediaType.TOP_LIST;
      NavPathUtils.push(ROUTE_SHEET_DETAIL);
    }
    subscribedSheets.markViewed(rec.platform, rec.id);
  }

  /** 订阅条目横滑操作（左滑 分享/更新/排序/取消订阅）；批量模式下不提供 */
  private subscribedSwipeOptions(rec: SubscribedSheetRecord): HdsSwipeActionOptions | undefined {
    if (appState.isBatchMode) {
      return undefined;
    }
    const options: HdsSwipeActionOptions = {
      icons: [
        {
          icon: new SymbolGlyphModifier($r('sys.symbol.share'))
            .fontColor([Color.White]).fontSize(20),
          backgroundColor: appState.accentColor,
          onAction: (): void => {
            this.shareSubscribed(rec);
          }
        },
        {
          icon: new SymbolGlyphModifier($r('sys.symbol.arrow_clockwise'))
            .fontColor([Color.White]).fontSize(20),
          backgroundColor: appState.accentColor,
          onAction: (): void => {
            this.updateSubscribed(rec);
          }
        },
        {
          icon: new SymbolGlyphModifier($r('sys.symbol.arrow_left_arrow_right'))
            .fontColor([Color.White]).fontSize(20),
          backgroundColor: appState.accentColor,
          onAction: (): void => {
            this.editSubscribedSort(rec);
          }
        }
      ],
      deleteIconOptions: {
        onAction: (): void => {
          this.confirmUnsubscribe(rec);
        }
      }
    };
    return options;
  }

  /** 订阅类型文案（分享内容用） */
  private static mediaTypeLabel(mediaType: string): string {
    if (mediaType === SubscribedMediaType.TOP_LIST) {
      return '榜单';
    }
    if (mediaType === SubscribedMediaType.ALBUM) {
      return '专辑';
    }
    if (mediaType === SubscribedMediaType.ARTIST) {
      return '歌手';
    }
    return '歌单';
  }

  /** 分享单个订阅（文本：名称/类型/来源插件） */
  private shareSubscribed(rec: SubscribedSheetRecord): void {
    const content = '「' + rec.title + '」（' + MySheetsPage.mediaTypeLabel(rec.mediaType) +
      '）· 来源插件：' + rec.platform;
    ShareUtils.shareText(rec.title, content, (message: string): void => {
      this.showToast(message);
    });
  }

  /** 手动更新单个订阅（同步期间列表上层显示 loading，完成后气泡提示结果） */
  private updateSubscribed(rec: SubscribedSheetRecord): void {
    if (rec.mediaType === SubscribedMediaType.ARTIST) {
      this.showToast('歌手订阅暂不支持更新');
      return;
    }
    if (this.syncing) {
      this.showToast('正在同步，请稍候');
      return;
    }
    this.syncing = true;
    subscribedSheets.syncRecord(rec.platform, rec.id).then((success: boolean): void => {
      this.syncing = false;
      this.showToast(success ? '已更新「' + rec.title + '」' : '更新失败');
    }).catch((_e: Object): void => {
      this.syncing = false;
      this.showToast('更新失败');
    });
  }

  /** 订阅排序：弹「跳转排序」对话框，确认后移动并保存（按全量订阅列表顺序） */
  private editSubscribedSort(rec: SubscribedSheetRecord): void {
    const index = subscribedSheets.indexOf(rec.platform, rec.id);
    if (index < 0 || this.subscribedItems.length === 0) {
      return;
    }
    DialogManager.sortJumpValue = (index + 1).toString();
    DialogManager.sortJumpMax = this.subscribedItems.length;
    DialogManager.sortJumpConfirm = (target: number): void => {
      subscribedSheets.moveRecordTo(rec.platform, rec.id, target);
      this.showToast('已移动到第 ' + (target + 1).toString() + ' 位');
    };
    DialogManager.OpenDialog('跳转排序');
  }

  /** 取消订阅（弹窗确认，取消不移除） */
  private confirmUnsubscribe(rec: SubscribedSheetRecord): void {
    DialogManager.ConfirmDelete('确定取消订阅「' + rec.title + '」吗？', (): void => {
      subscribedSheets.unsubscribe(rec.platform, rec.id);
      this.showToast('已取消订阅');
    });
  }

  /** 标题副文本：搜索中显示命中数量；订阅 tab 显示订阅数 */
  private subTitleText(): string {
    if (this.searchKeyword.trim().length > 0) {
      const hit = this.showSubscribed ? this.displaySubscribed().length : this.displayRows().length;
      return '找到 ' + hit.toString() + ' 歌单';
    }
    if (this.showSubscribed) {
      return '共 ' + this.subscribedItems.length.toString() + ' 个订阅';
    }
    return '共 ' + this.sheetRows.length.toString() + ' 个歌单';
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
      this.rebuildSheetSource();
      this.rebuildSubscribedSource();
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
        focusController.requestFocus('my_sheets_search');
      } catch (e) {
        // 组件未挂载时忽略
      }
    }, 320);
    if (this.scroller.currentOffset().yOffset !== 0) {
      this.scroller.scrollTo({ xOffset: 0, yOffset: -(appState.topRect + 66 + 44 + 56), animation: { duration: 250, curve: Curve.EaseOut } });
    }
  }

  private showToast(message: string): void {
    showUiToast(this.getUIContext(), message);
  }

  /** titleBar 菜单按钮（订阅 tab：同步+搜索；我的歌单 tab：添加菜单+搜索+批量操作） */
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
    if (this.showSubscribed) {
      const sync: HdsNavigationMenuItemOptions = {
        content: {
          icon: $r('sys.symbol.arrow_clockwise'),
          label: '同步',
          action: (): void => {
            this.manualSyncSubscribed();
          }
        }
      };
      const menu: HdsNavigationMenuItemOptions = {
        content: {
          icon: $r('sys.symbol.dot_grid_2x2'),
          label: '批量操作',
          action: (): void => {
            this.openSubscribedMenu();
          }
        }
      };
      return [sync, search, menu];
    }
    const add: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.plus'),
        label: '添加',
        action: (): void => {
          this.openAddMenu();
        }
      }
    };
    const batch: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.dot_grid_2x2'),
        label: '批量操作',
        action: (): void => {
          this.openMoreMenu()
        }
      }
    };
    return [add, search, batch];
  }

  private openMoreMenu(): void {
    const batchItem = new MenuItemParams();
    batchItem.icon = $r('sys.symbol.arrow_clockwise');
    batchItem.label = '批量操作';
    batchItem.onAction = (): void => {
      this.runMenuAction((): void => {
        this.enterBatchMode();
      });
    };
    const sortItem = new MenuItemParams();
    sortItem.icon = $r('sys.symbol.line_3_horizontal');
    sortItem.label = '歌单排序';
    sortItem.onAction = (): void => {
      this.runMenuAction((): void => {
        this.openSortSheet()
      });
    };
    const introItem = new MenuItemParams();
    introItem.icon = $r('sys.symbol.info_circle');
    introItem.label = '歌单说明';
    introItem.onAction = (): void => {
      this.runMenuAction((): void => {
        DialogManager.OpenDialog('歌单说明');
      });
    };
    MenuUtils.Open(this.getUIContext(), MORE_ANCHOR_ID, [sortItem, batchItem, introItem], {
      placement: Placement.BottomRight
    });
  }

  /** 订阅 tab 菜单：订阅排序 / 批量操作 / 歌单说明 */
  private openSubscribedMenu(): void {
    const sortItem = new MenuItemParams();
    sortItem.icon = $r('sys.symbol.line_3_horizontal');
    sortItem.label = '订阅排序';
    sortItem.onAction = (): void => {
      this.runMenuAction((): void => {
        this.openSubscribedSortSheet();
      });
    };
    const batchItem = new MenuItemParams();
    batchItem.icon = $r('sys.symbol.dot_grid_2x2');
    batchItem.label = '批量操作';
    batchItem.onAction = (): void => {
      this.runMenuAction((): void => {
        this.openSubscribedBatch();
      });
    };
    const introItem = new MenuItemParams();
    introItem.icon = $r('sys.symbol.info_circle');
    introItem.label = '歌单说明';
    introItem.onAction = (): void => {
      this.runMenuAction((): void => {
        DialogManager.OpenDialog('歌单说明');
      });
    };
    MenuUtils.Open(this.getUIContext(), MORE_ANCHOR_ID, [sortItem, batchItem, introItem], {
      placement: Placement.BottomRight
    });
  }

  private runMenuAction(action: () => void): void {
    MenuUtils.Dismiss();
    action();
  }

  /** 进入订阅批量操作模式（空列表提示） */
  private openSubscribedBatch(): void {
    if (this.subscribedItems.length === 0) {
      this.showToast('暂无订阅歌单');
      return;
    }
    this.enterBatchMode();
  }

  /** 添加菜单：新建歌单 / 导入歌单 / 导入单曲 */
  private openAddMenu(): void {
    if (appState.isBatchMode) {
      this.exitBatchMode();
    }
    const newItem = new MenuItemParams();
    newItem.icon = $r('sys.symbol.plus');
    newItem.label = '新建歌单';
    newItem.onAction = (): void => {
      this.runMenuAction((): void => {
        this.openCreateSheet();
      });
    };
    const importSheetItem = new MenuItemParams();
    importSheetItem.icon = $r('sys.symbol.square_and_arrow_down');
    importSheetItem.label = '导入歌单';
    importSheetItem.onAction = (): void => {
      this.runMenuAction((): void => {
        this.openImportSheet(false);
      });
    };
    const importMusicItem = new MenuItemParams();
    importMusicItem.icon = $r('sys.symbol.music');
    importMusicItem.label = '导入单曲';
    importMusicItem.onAction = (): void => {
      this.runMenuAction((): void => {
        this.openImportSheet(true);
      });
    };
    MenuUtils.Open(this.getUIContext(), ADD_ANCHOR_ID, [newItem, importSheetItem, importMusicItem], {
      placement: Placement.BottomRight
    });
  }

  /** 打开新建歌单半模态 */
  private openCreateSheet(): void {
    if (appState.isBatchMode) {
      this.exitBatchMode();
    }
    this.newSheetTitle = '';
    this.newSheetDesc = '';
    this.showCreateSheet = true;
  }

  /** 确认新建歌单（名称必填，简介可选） */
  private confirmCreateSheet(): void {
    const title = this.newSheetTitle.trim();
    if (title.length === 0) {
      this.showToast('请输入歌单名称');
      return;
    }
    if (this.creating) {
      return;
    }
    this.creating = true;
    musicSheet.addSheet(title).then((sheetId: string): void => {
      const desc = this.newSheetDesc.trim();
      if (desc.length > 0) {
        const patch = new SheetBasePatch();
        patch.description = desc;
        musicSheet.updateMusicSheetBase(sheetId, patch);
      }
      this.creating = false;
      this.showCreateSheet = false;
      this.showToast('已创建歌单');
    }).catch((_e: Object): void => {
      this.creating = false;
      this.showToast('创建失败');
    });
  }

  /** 打开导入半模态：收集支持导入的已启用插件（importSingleMode 区分单曲/歌单） */
  private openImportSheet(singleMode: boolean): void {
    if (appState.isBatchMode) {
      this.exitBatchMode();
    }
    const method: string = singleMode ? 'importMusicItem' : 'importMusicSheet';
    const names: Array<string> = [];
    for (const p of pluginManager.getEnabledPlugins()) {
      if (p.hasMethod(method)) {
        names.push(p.name);
      }
    }
    this.importSingleMode = singleMode;
    this.importPluginNames = names;
    this.importPluginIndex = names.length > 0 ? 0 : -1;
    if (singleMode) {
      const ids: Array<string> = [];
      const titles: Array<string> = [];
      for (const sheet of musicSheet.sheets) {
        ids.push(sheet.id);
        titles.push(sheet.title);
      }
      this.importTargetSheetIds = ids;
      this.importTargetSheetTitles = titles;
      this.importTargetIndex = ids.length > 0 ? 0 : -1;
    }
    this.importUrl = '';
    this.importing = false;
    this.showImportSheet = true;
    this.refreshImportHintFor(this.selectedImportPluginName());
  }

  /** 懒加载插件挂载完成后刷新说明文本 */
  private refreshImportHintFor(name: string): void {
    const plugin = pluginManager.getByName(name);
    if (plugin !== null && plugin.state === PluginState.Initializing) {
      plugin.ensureMounted().then((): void => {
        this.importHintRev++;
      }).catch((_e: Object): void => {
      });
    }
  }

  /** Select 选项（无可用插件时给出占位项） */
  private importSelectOptions(): Array<SelectOption> {
    const opts: Array<SelectOption> = [];
    for (const name of this.importPluginNames) {
      opts.push({ value: name });
    }
    if (opts.length === 0) {
      opts.push({ value: '暂无支持导入的插件' });
    }
    return opts;
  }

  /** Select 当前展示值 */
  private selectedImportPluginName(): string {
    if (this.importPluginIndex >= 0 && this.importPluginIndex < this.importPluginNames.length) {
      return this.importPluginNames[this.importPluginIndex];
    }
    return '暂无支持导入的插件';
  }

  /** 目标歌单 Select 选项 */
  private importTargetOptions(): Array<SelectOption> {
    const opts: Array<SelectOption> = [];
    for (const title of this.importTargetSheetTitles) {
      opts.push({ value: title });
    }
    if (opts.length === 0) {
      opts.push({ value: '暂无可加入的歌单' });
    }
    return opts;
  }

  /** 目标歌单 Select 当前展示值 */
  private selectedImportTargetName(): string {
    if (this.importTargetIndex >= 0 && this.importTargetIndex < this.importTargetSheetTitles.length) {
      return this.importTargetSheetTitles[this.importTargetIndex];
    }
    return '暂无可加入的歌单';
  }

  /** 超时时长 Select 选项 */
  private importTimeoutOptions(): Array<SelectOption> {
    const opts: Array<SelectOption> = [];
    for (const label of IMPORT_TIMEOUT_LABELS) {
      opts.push({ value: label });
    }
    return opts;
  }

  /** 超时时长 Select 当前展示值 */
  private selectedImportTimeoutLabel(): string {
    if (this.importTimeoutIndex >= 0 && this.importTimeoutIndex < IMPORT_TIMEOUT_LABELS.length) {
      return IMPORT_TIMEOUT_LABELS[this.importTimeoutIndex];
    }
    return IMPORT_TIMEOUT_LABELS[0];
  }

  /** 当前选中的超时时长（毫秒） */
  private importTimeoutMs(): number {
    if (this.importTimeoutIndex >= 0 && this.importTimeoutIndex < IMPORT_TIMEOUT_MS_OPTIONS.length) {
      return IMPORT_TIMEOUT_MS_OPTIONS[this.importTimeoutIndex];
    }
    return IMPORT_TIMEOUT_MS_OPTIONS[0];
  }

  /** 底部说明文字：与 RN 原版一致，取插件 hints（string[]），逐条 ￮ 前缀显示；未提供则不显示 */
  private importHintText(): string {
    const pluginName = this.selectedImportPluginName();
    const plugin = pluginManager.getByName(pluginName);
    if (plugin !== null && plugin.instanceInfo !== null && plugin.instanceInfo.hints !== null) {
      const arr = JsonUtil.recArray(plugin.instanceInfo.hints,
        this.importSingleMode ? 'importMusicItem' : 'importMusicSheet');
      if (arr !== null) {
        const parts: Array<string> = [];
        for (const it of arr) {
          if (typeof it === 'string' && it.length > 0) {
            parts.push('· ' + it);
          }
        }
        return parts.join('\n');
      }
    }
    return '';
  }

  /** 确认导入：歌单 → 建新歌单并写入全部歌曲；单曲 → 导入后加入所选歌单 */
  private confirmImport(): void {
    if (this.importing) {
      return;
    }
    if (this.importPluginNames.length === 0 || this.importPluginIndex < 0) {
      this.showToast('暂无支持导入的插件');
      return;
    }
    if (this.importSingleMode &&
      (this.importTargetSheetIds.length === 0 || this.importTargetIndex < 0 ||
        this.importTargetIndex >= this.importTargetSheetIds.length)) {
      this.showToast('暂无可加入的歌单');
      return;
    }
    const url = this.importUrl.trim();
    if (url.length === 0) {
      this.showToast(this.importSingleMode ? '请输入目标歌曲' : '请输入目标歌单');
      return;
    }
    const plugin = pluginManager.getByName(this.importPluginNames[this.importPluginIndex]);
    if (plugin === null) {
      this.showToast('插件不存在');
      return;
    }
    this.importing = true;
    if (this.importSingleMode) {
      const targetId = this.importTargetSheetIds[this.importTargetIndex];
      const targetTitle = this.importTargetSheetTitles[this.importTargetIndex];
      plugin.methods.importMusicItem(url).then((item: MusicItem | null): void => {
        this.importing = false;
        if (item === null) {
          this.showToast('导入歌曲失败');
          return;
        }
        musicSheet.addMusic(targetId, item).then((): void => {
          this.showImportSheet = false;
          this.showToast('已将「' + item.title + '」加入「' + targetTitle + '」');
        }).catch((_e: Object): void => {
          this.showToast('加入歌单失败');
        });
      }).catch((_e: Object): void => {
        this.importing = false;
        this.showToast('导入歌曲失败');
      });
    } else {
      plugin.methods.importMusicSheet(url, this.importTimeoutMs()).then((items: Array<MusicItem>): void => {
        if (items.length === 0) {
          this.importing = false;
          this.showToast('链接有误或目标歌单为空');
          return;
        }
        this.resolveImportTitle(plugin).then((title: string): Promise<void> => {
          return musicSheet.addSheet(title).then((sheetId: string): Promise<void> => {
            return musicSheet.addMusic(sheetId, items);
          });
        }).then((): void => {
          this.importing = false;
          this.showImportSheet = false;
          this.showToast('已导入 ' + items.length.toString() + ' 首歌曲');
        }).catch((_e: Object): void => {
          this.importing = false;
          this.showToast('创建歌单失败');
        });
      }).catch((_e: Object): void => {
        this.importing = false;
        this.showToast('导入歌单失败');
      });
    }
  }

  /** 解析导入歌单的标题：优先通过 getMusicSheetInfo 取原歌单名，失败回退「导入歌单(插件名)」 */
  private resolveImportTitle(plugin: Plugin): Promise<string> {
    const fallback = '导入歌单(' + plugin.name + ')';
    if (!plugin.hasMethod('getMusicSheetInfo')) {
      return Promise.resolve(fallback);
    }
    const query = new SheetItem();
    query.id = this.importUrl.trim();
    query.platform = plugin.name;
    query.title = this.importUrl.trim();
    return plugin.methods.getMusicSheetInfo(query, 1).then((info: SheetInfoResult | null): string => {
      if (info !== null && info.sheetItem !== null && info.sheetItem.title.trim().length > 0) {
        return info.sheetItem.title.trim();
      }
      return fallback;
    }).catch((_e: Object): string => {
      return fallback;
    });
  }

  /** 横滑操作（左滑呼出 编辑/删除）；默认歌单与批量模式下不提供 */
  private swipeOptions(row: SheetRow): HdsSwipeActionOptions | undefined {
    if (row.isDefault || appState.isBatchMode) {
      return undefined;
    }
    const options: HdsSwipeActionOptions = {
      icons: [
        {
          icon: new SymbolGlyphModifier($r('sys.symbol.share'))
            .fontColor([Color.White]).fontSize(20),
          backgroundColor: appState.accentColor,
          onAction: (): void => {
            this.shareRowSheet(row);
          }
        },
        {
          icon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil'))
            .fontColor([Color.White]).fontSize(20),
          backgroundColor: appState.accentColor,
          onAction: (): void => {
            this.openEditSheet(row);
          }
        },
        {
          icon: new SymbolGlyphModifier($r('sys.symbol.arrow_left_arrow_right'))
            .fontColor([Color.White]).fontSize(20),
          backgroundColor: appState.accentColor,
          onAction: (): void => {
            this.editRowSort(row);
          }
        }
      ],
      deleteIconOptions: {
        onAction: (): void => {
          this.deleteSheet(row);
        }
      }
    };
    return options;
  }

    /** 按 id 查歌单实体 */
  private sheetById(id: string): SheetItem | null {
    for (const sheet of musicSheet.sheets) {
      if (sheet.id === id) {
        return sheet;
      }
    }
    return null;
  }

  /** 左滑分享单个歌单（可导入的 json 文件，接收端 MusicFreeOH 打开后自动导入） */
  private shareRowSheet(row: SheetRow): void {
    const sheet = this.sheetById(row.id);
    if (sheet === null) {
      return;
    }
    ShareUtils.shareSheets(sheet.title, [sheet], (message: string): void => {
      this.showToast(message);
    });
  }

  /** 打开编辑歌单半模态（预填当前名称/简介） */
  private openEditSheet(row: SheetRow): void {
    this.editSheetId = row.id;
    this.editSheetTitle = row.title;
    this.editSheetDesc = row.description;
    this.showEditSheet = true;
  }

  /** 确认保存歌单编辑（名称+简介） */
  private confirmEditSheet(): void {
    const title = this.editSheetTitle.trim();
    if (title.length === 0) {
      this.showToast('请输入歌单名称');
      return;
    }
    const patch = new SheetBasePatch();
    patch.title = title;
    patch.description = this.editSheetDesc.trim();
    musicSheet.updateMusicSheetBase(this.editSheetId, patch);
    this.showEditSheet = false;
    this.showToast('已保存');
  }

  /** 删除歌单条目（弹窗确认，取消不删除） */
  private deleteSheet(row: SheetRow): void {
    if (row.isDefault) {
      this.showToast('默认歌单无法删除');
      return;
    }
    DialogManager.ConfirmDelete('确定删除歌单「' + row.title + '」吗？', (): void => {
      musicSheet.removeSheet(row.id);
      this.showToast('已删除「' + row.title + '」');
    });
  }

  /** 收集可排序歌单 id（排除默认歌单，保持当前顺序） */
  private collectSortableSheetIds(): Array<string> {
    const ids: Array<string> = [];
    for (const sheet of musicSheet.sheets) {
      if (sheet.id !== musicSheet.defaultSheet.id) {
        ids.push(sheet.id);
      }
    }
    return ids;
  }

  /** 歌单排序标题（按 id 查找） */
  private sortSheetTitle(id: string): string {
    for (const sheet of musicSheet.sheets) {
      if (sheet.id === id) {
        return sheet.title;
      }
    }
    return '';
  }

  /** 打开歌单排序半模态 */
  private openSortSheet(): void {
    if (appState.isBatchMode) {
      this.exitBatchMode();
    }
    const ids = this.collectSortableSheetIds();
    if (ids.length === 0) {
      this.showToast('暂无可排序的歌单');
      return;
    }
    this.sortSheetIds = ids;
    this.showSortSheet = true;
  }

  private moveSortItem(index: number, delta: number): void {
    const target = index + delta;
    if (index < 0 || index >= this.sortSheetIds.length || target < 0 || target >= this.sortSheetIds.length) {
      return;
    }
    const ids = this.sortSheetIds.slice();
    const tmp = ids[index];
    ids[index] = ids[target];
    ids[target] = tmp;
    this.sortSheetIds = ids;
  }

  /** 打开「跳转排序」弹窗：将当前条目直接移动到输入的序号位置 */
  private openSortJump(index: number): void {
    DialogManager.sortJumpValue = (index + 1).toString();
    DialogManager.sortJumpMax = this.sortSheetIds.length;
    DialogManager.sortJumpConfirm = (target: number): void => {
      this.moveSortItemTo(index, target);
    };
    DialogManager.OpenDialog('跳转排序');
  }

  /** 将排序条目从 from 移动到 to（0 基索引） */
  private moveSortItemTo(from: number, to: number): void {
    if (from === to || from < 0 || from >= this.sortSheetIds.length ||
      to < 0 || to >= this.sortSheetIds.length) {
      return;
    }
    const ids = this.sortSheetIds.slice();
    const item = ids.splice(from, 1)[0];
    ids.splice(to, 0, item);
    this.sortSheetIds = ids;
    this.showToast('已移动到第 ' + (to + 1).toString() + ' 位');
  }

  private saveSortOrder(): void {
    musicSheet.setSheetOrder(this.sortSheetIds);
    this.showSortSheet = false;
    this.showToast('歌单排序已保存');
  }

  /** 行内排序：弹「跳转排序」对话框，确认后直接改序并保存 */
  private editRowSort(row: SheetRow): void {
    const ids = this.collectSortableSheetIds();
    const index = ids.indexOf(row.id);
    if (index < 0) {
      this.showToast('默认歌单不支持排序');
      return;
    }
    this.sortSheetIds = ids;
    DialogManager.sortJumpValue = (index + 1).toString();
    DialogManager.sortJumpMax = ids.length;
    DialogManager.sortJumpConfirm = (target: number): void => {
      this.moveSortItemTo(index, target);
      this.saveSortOrder();
    };
    DialogManager.OpenDialog('跳转排序');
  }

  /** 打开订阅排序半模态 */
  private openSubscribedSortSheet(): void {
    if (appState.isBatchMode) {
      this.exitBatchMode();
    }
    if (this.subscribedItems.length === 0) {
      this.showToast('暂无可排序的订阅');
      return;
    }
    const keys: Array<string> = [];
    for (const rec of this.subscribedItems) {
      keys.push(this.subscribedKey(rec));
    }
    this.subscribedSortKeys = keys;
    this.showSubscribedSortSheet = true;
  }

  /** 订阅排序条目标题（按勾选键查找） */
  private subscribedSortTitle(key: string): string {
    for (const rec of this.subscribedItems) {
      if (this.subscribedKey(rec) === key) {
        return rec.title;
      }
    }
    return '';
  }

  private moveSubscribedSortItem(index: number, delta: number): void {
    const target = index + delta;
    if (index < 0 || index >= this.subscribedSortKeys.length ||
      target < 0 || target >= this.subscribedSortKeys.length) {
      return;
    }
    const keys = this.subscribedSortKeys.slice();
    const tmp = keys[index];
    keys[index] = keys[target];
    keys[target] = tmp;
    this.subscribedSortKeys = keys;
  }

  /** 打开订阅「跳转排序」弹窗：将当前条目直接移动到输入的序号位置 */
  private openSubscribedSortJump(index: number): void {
    DialogManager.sortJumpValue = (index + 1).toString();
    DialogManager.sortJumpMax = this.subscribedSortKeys.length;
    DialogManager.sortJumpConfirm = (target: number): void => {
      this.moveSubscribedSortItemTo(index, target);
    };
    DialogManager.OpenDialog('跳转排序');
  }

  /** 将订阅排序条目从 from 移动到 to（0 基索引） */
  private moveSubscribedSortItemTo(from: number, to: number): void {
    if (from === to || from < 0 || from >= this.subscribedSortKeys.length ||
      to < 0 || to >= this.subscribedSortKeys.length) {
      return;
    }
    const keys = this.subscribedSortKeys.slice();
    const item = keys.splice(from, 1)[0];
    keys.splice(to, 0, item);
    this.subscribedSortKeys = keys;
    this.showToast('已移动到第 ' + (to + 1).toString() + ' 位');
  }

  private saveSubscribedSortOrder(): void {
    subscribedSheets.setOrder(this.subscribedSortKeys);
    this.showSubscribedSortSheet = false;
    this.showToast('订阅排序已保存');
  }

  /** 进入批量模式（全局状态：隐藏 tab 栏、返回键退出；显式动画包裹避免突兀） */
  private enterBatchMode(): void {
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

  /** 行是否被勾选 */
  private isSelected(row: SheetRow): boolean {
    return this.batchSelected.indexOf(row.id) !== -1;
  }

  /** 批量模式下点击行：切换勾选状态（默认歌单不可选） */
  private toggleBatchSelect(row: SheetRow): void {
    if (row.isDefault) {
      this.showToast('默认歌单不支持批量操作');
      return;
    }
    const next = this.batchSelected.slice();
    const idx = next.indexOf(row.id);
    if (idx === -1) {
      next.push(row.id);
    } else {
      next.splice(idx, 1);
    }
    this.batchSelected = next;
  }

  /** 全选/取消全选（不含默认歌单） */
  private toggleSelectAll(): void {
    const all: Array<string> = [];
    for (const row of this.sheetRows) {
      if (!row.isDefault) {
        all.push(row.id);
      }
    }
    this.batchSelected = this.batchSelected.length === all.length ? [] : all;
  }

  /** 订阅条目勾选键（platform_id） */
  private subscribedKey(rec: SubscribedSheetRecord): string {
    return rec.platform + '_' + rec.id;
  }

  /** 订阅条目是否被勾选 */
  private isSubscribedSelected(rec: SubscribedSheetRecord): boolean {
    return this.batchSelected.indexOf(this.subscribedKey(rec)) !== -1;
  }

  /** 批量模式下点击订阅条目：切换勾选状态 */
  private toggleSubscribedSelect(rec: SubscribedSheetRecord): void {
    const key = this.subscribedKey(rec);
    const next = this.batchSelected.slice();
    const idx = next.indexOf(key);
    if (idx === -1) {
      next.push(key);
    } else {
      next.splice(idx, 1);
    }
    this.batchSelected = next;
  }

  /** 订阅 tab 全选/取消全选（按全量订阅列表） */
  private toggleSelectAllSubscribed(): void {
    if (this.subscribedItems.length > 0 && this.batchSelected.length === this.subscribedItems.length) {
      this.batchSelected = [];
      return;
    }
    const keys: Array<string> = [];
    for (const rec of this.subscribedItems) {
      keys.push(this.subscribedKey(rec));
    }
    this.batchSelected = keys;
  }

  /** 勾选的订阅记录列表 */
  private selectedSubscribedRecords(): Array<SubscribedSheetRecord> {
    const result: Array<SubscribedSheetRecord> = [];
    for (const key of this.batchSelected) {
      for (const rec of this.subscribedItems) {
        if (this.subscribedKey(rec) === key) {
          result.push(rec);
          break;
        }
      }
    }
    return result;
  }

  /** 批量更新选中订阅（逐条拉取源端对比；歌手订阅/插件不可用计入失败；同步期间列表上层显示 loading） */
  private async batchUpdateSubscribed(): Promise<void> {
    const recs = this.selectedSubscribedRecords();
    if (recs.length === 0) {
      this.showToast('请先勾选订阅');
      return;
    }
    if (this.batchUpdating) {
      this.showToast('正在更新，请稍候');
      return;
    }
    this.batchUpdating = true;
    this.syncing = true;
    let ok = 0;
    try {
      for (const rec of recs) {
        const success = await subscribedSheets.syncRecord(rec.platform, rec.id);
        if (success) {
          ok++;
        }
      }
    } catch (_e) {
      // 中途异常时保留已更新计数，最终统一气泡提示
    }
    this.batchUpdating = false;
    this.syncing = false;
    this.showToast('已更新 ' + ok.toString() + '/' + recs.length.toString() + ' 个订阅');
  }

  /** 批量分享选中订阅（文本清单：名称/类型/来源插件） */
  private batchShareSubscribed(): void {
    const recs = this.selectedSubscribedRecords();
    if (recs.length === 0) {
      this.showToast('请先勾选订阅');
      return;
    }
    const lines: Array<string> = [];
    for (const rec of recs) {
      lines.push('「' + rec.title + '」（' + MySheetsPage.mediaTypeLabel(rec.mediaType) +
        '）· 来源插件：' + rec.platform);
    }
    const title = recs.length === 1 ? recs[0].title : '订阅分享（' + recs.length.toString() + ' 个）';
    ShareUtils.shareText(title, lines.join('\n'), (message: string): void => {
      this.showToast(message);
    });
  }

  /** 批量取消订阅（弹窗确认，取消不删除） */
  private batchDeleteSubscribed(): void {
    const recs = this.selectedSubscribedRecords();
    if (recs.length === 0) {
      this.showToast('请先勾选订阅');
      return;
    }
    DialogManager.ConfirmDelete('确定取消订阅选中的 ' + recs.length.toString() + ' 个订阅吗？', (): void => {
      for (const rec of recs) {
        subscribedSheets.unsubscribe(rec.platform, rec.id);
      }
      this.exitBatchMode();
      this.showToast('已取消订阅 ' + recs.length.toString() + ' 个');
    });
  }

  /** 批量操作按钮文案（全部勾选后「全选」切换为「取消全选」；订阅 tab 为 全选/更新/分享/删除） */
  private batchButtonLabels(): Array<string> {
    if (this.showSubscribed) {
      const allSelected = this.subscribedItems.length > 0 &&
        this.batchSelected.length === this.subscribedItems.length;
      return [allSelected ? '取消全选' : '全选', this.batchUpdating ? '更新中…' : '更新', '分享', '删除'];
    }
    let selectable = 0;
    for (const row of this.sheetRows) {
      if (!row.isDefault) {
        selectable++;
      }
    }
    const allSelected = selectable > 0 && this.batchSelected.length === selectable;
    return [allSelected ? '取消全选' : '全选', '分享', '删除'];
  }

  /** 勾选的歌单实体列表 */
  private selectedSheets(): Array<SheetItem> {
    const result: Array<SheetItem> = [];
    for (const id of this.batchSelected) {
      for (const sheet of musicSheet.sheets) {
        if (sheet.id === id) {
          result.push(sheet);
          break;
        }
      }
    }
    return result;
  }

  /** 批量分享：系统分享面板分享选中歌单的曲目清单文本 */
  private batchShare(): void {
    const sheets = this.selectedSheets();
    if (sheets.length === 0) {
      this.showToast('请先勾选歌单');
      return;
    }
    const parts: Array<string> = [];
    for (const sheet of sheets) {
      const lines: Array<string> = ['「' + sheet.title + '」共 ' + sheet.worksNum.toString() + ' 首'];
      const list = musicSheet.getMusicList(sheet.id);
      for (let i = 0; i < list.length; i++) {
        lines.push((i + 1).toString() + '. ' + list[i].title + ' - ' + list[i].artist);
      }
      parts.push(lines.join('\n'));
    }
    const title = sheets.length === 1 ? sheets[0].title : '歌单曲目清单（' + sheets.length.toString() + ' 个歌单）';
    ShareUtils.shareText(title, parts.join('\n\n'), (message: string): void => {
      this.showToast(message);
    });
  }

  /** 批量分享选中歌单（可导入的 json 文件，接收端 MusicFreeOH 打开后自动导入；多歌单合并为一个文件） */
  private batchShareSheets(): void {
    const sheets = this.selectedSheets();
    if (sheets.length === 0) {
      this.showToast('请先勾选歌单');
      return;
    }
    const title = sheets.length === 1 ? sheets[0].title : '歌单分享（' + sheets.length.toString() + ' 个歌单）';
    ShareUtils.shareSheets(title, sheets, (message: string): void => {
      this.showToast(message);
    });
  }

  /** 批量删除选中歌单（弹窗确认，取消不删除） */
  private batchDelete(): void {
    const sheets = this.selectedSheets();
    if (sheets.length === 0) {
      this.showToast('请先勾选歌单');
      return;
    }
    DialogManager.ConfirmDelete('确定删除选中的 ' + sheets.length.toString() + ' 个歌单吗？', (): void => {
      let ok = 0;
      for (const sheet of sheets) {
        musicSheet.removeSheet(sheet.id);
        ok++;
      }
      this.exitBatchMode();
      this.refreshSheets();
      this.showToast('已删除 ' + ok.toString() + ' 个歌单');
    });
  }

  /** 进入歌单详情页（本地歌单模式） */
  private openSheetDetail(row: SheetRow): void {
    let target: SheetItem | null = null;
    for (const sheet of musicSheet.sheets) {
      if (sheet.id === row.id) {
        target = sheet;
        break;
      }
    }
    if (target === null) {
      return;
    }
    SheetDetailNavParams.pluginName = target.platform;
    SheetDetailNavParams.sheet = target;
    SheetDetailNavParams.isTopList = false;
    NavPathUtils.push(ROUTE_SHEET_DETAIL);
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf($r('app.string.tab_my_sheets'),
        this.subTitleText(), this.titleMenus(),
        (this.hostTabIndex === 1) ?
          { builder: (): void => { this.TitleExtraBuilder() }, height: this.showSearchBox ? 110 : 40 } : undefined),
      isHideBackButton: true,
      embedded: true,
      // 分段滑块常驻标题栏下方，不随滚动隐藏（否则上滑隐藏、下滑才重现）
      isSearchBarScroller: false,
      scroller: this.scroller,
      doubleTapToTop: true,
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 16 }) {
          if (this.showSubscribed) {
            // 订阅歌单列表（懒加载；HdsListItem 不支持通用属性，链式设置会破坏横滑手势，故不挂 transition）
            if (this.subscribedSource.totalCount() > 0) {
              LazyForEach(this.subscribedSource, (rec: SubscribedSheetRecord, _index: number) => {
                HdsListItem({
                  customItemBuilder: (): void => {
                    this.SubscribedRowBuilder(rec);
                  },
                  swipeActionOptions: this.subscribedSwipeOptions(rec)
                })
              }, (rec: SubscribedSheetRecord, _index: number) => rec.platform + '_' + rec.id +
                '_' + rec.title + '_' + rec.worksNum.toString() + (rec.hasUpdate ? '_upd' : '') +
                (appState.isBatchMode && this.isSubscribedSelected(rec) ? '_sel' : '') +
                '_' + appState.swipeResetTick.toString())
            } else {
              ListItem() {
                Text(this.subscribedItems.length > 0 ? '未找到匹配的订阅' : '暂无订阅，进入歌单、专辑或歌手详情页点击订阅按钮订阅')
                  .fontSize(13)
                  .fontColor($r('sys.color.font_tertiary'))
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .margin({ top: 32 })
              }
            }
          } else if (this.sheetSource.totalCount() > 0) {
            // 我的歌单列表（懒加载；HdsListItem 不支持通用属性，链式设置会破坏横滑手势，故不挂 transition）
            LazyForEach(this.sheetSource, (row: SheetRow, index: number) => {
              HdsListItem({
                customItemBuilder: (): void => {
                  this.SheetRowBuilder(row);
                },
                swipeActionOptions: this.swipeOptions(row)
              })
            }, (row: SheetRow, index: number) => row.id + '_' + index.toString() + '_' + row.title +
              '_' + row.coverUrl + '_' + row.worksNum.toString() +
              (appState.isBatchMode && this.isSelected(row) ? '_sel' : '') +
              '_' + appState.swipeResetTick.toString())
          } else {
            ListItem() {
              Text(this.sheetRows.length > 0 ? '未找到匹配的歌单' : '暂无歌单，点击右上角「添加」新建或导入歌单')
                .fontSize(13)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ top: 32 })
            }
          }
        }
        .ListStyle(44 + (this.showSearchBox ? 56 : 0))
        .onScrollFrameBegin((offset: number) => {
          BarScrollHelper.notifyScrollDelta(this.getUIContext(), offset)
          return { offsetRemain: offset }
        })
        .bindSheet(!!this.showCreateSheet, this.SheetMetaFormBuilder(true), {
          scrollSizeMode: ScrollSizeMode.CONTINUOUS, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          dragBar: true,
          onWillDisappear: () => {
            this.showCreateSheet = false;
            appState.isForegroundBlur = false
          },
          onWillAppear: () => {
            appState.isForegroundBlur = true
          }
        })

        // 批量模式底栏（UI 同歌单详情页）：已选行 + 全选 / 分享 / 删除
        if (appState.isBatchMode) {
          CommonBlur({ heightValue: appState.bottomRect + 94 }).position({ bottom: 0 })
            .transition(TransitionEffect.OPACITY)

          Column({ space: 10 }) {
            Row() {
              Text('已选 ' + this.batchSelected.length.toString() + (this.showSubscribed ? ' 个订阅' : ' 个歌单'))
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
              ForEach(this.batchButtonLabels(), (v: string, i: number) => {
                Button(v)
                  .layoutWeight(1)
                  .height(36)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .borderRadius(10)
                  .padding({ left: 2, right: 2 })
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  .fontColor($r('sys.color.font_primary'))
                  .onClick(() => {
                    if (this.showSubscribed) {
                      if (i === 0) {// 全选/取消全选
                        this.toggleSelectAllSubscribed();
                      } else if (i === 1) {// 更新
                        this.batchUpdateSubscribed();
                      } else if (i === 2) {// 分享
                        this.batchShareSubscribed();
                      } else {// 删除
                        this.batchDeleteSubscribed();
                      }
                    } else {
                      if (i === 0) {// 全选/取消全选
                        this.toggleSelectAll();
                      } else if (i === 1) {// 分享
                        this.batchShareSheets();
                      } else {// 删除
                        this.batchDelete();
                      }
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

        // 订阅同步 loading 遮罩（同步期间叠加在列表上层，阻断误操作）
        if (this.showSubscribed && this.syncing) {
          Column({ space: 10 }) {
            CommonLoading({ sizeValue: 36, loadColor: Color.White })
            Text('同步中…')
              .fontSize(13)
              .fontColor(Color.White)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#66000000')
          .transition(TransitionEffect.OPACITY)
        }

        // 编辑歌单半模态锚点（独立节点挂载半模态，不与新建歌单 sheet 共用宿主）
        Column()
          .width('100%')
          .height(0)
          .bindSheet(!!this.showEditSheet, this.SheetMetaFormBuilder(false), {
            scrollSizeMode: ScrollSizeMode.CONTINUOUS, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
            dragBar: true,
            onWillDisappear: () => {
              this.showEditSheet = false;
              appState.isForegroundBlur = false
            },
            onWillAppear: () => {
              appState.isForegroundBlur = true
            }
          })

        // 歌单排序半模态锚点（独立节点挂载半模态，不与新建/编辑 sheet 共用宿主）
        Column()
          .width('100%')
          .height(0)
          .bindSheet(!!this.showSortSheet, this.SortListSheetBuilder(true), {
            scrollSizeMode: ScrollSizeMode.CONTINUOUS, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
            dragBar: true,
            onWillDisappear: () => {
              this.showSortSheet = false;
              appState.isForegroundBlur = false
            },
            onWillAppear: () => {
              appState.isForegroundBlur = true
            }
          })

        // 订阅排序半模态锚点（独立节点挂载半模态）
        Column()
          .width('100%')
          .height(0)
          .bindSheet(!!this.showSubscribedSortSheet, this.SortListSheetBuilder(false), {
            scrollSizeMode: ScrollSizeMode.CONTINUOUS, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
            dragBar: true,
            onWillDisappear: () => {
              this.showSubscribedSortSheet = false;
              appState.isForegroundBlur = false
            },
            onWillAppear: () => {
              appState.isForegroundBlur = true
            }
          })

        // 添加菜单锚点（标题栏下方右上角，菜单在锚点处弹出；导入半模态挂载于此）
        Row() {
          Column()
            .id(ADD_ANCHOR_ID)
            .width(24)
            .height(24)
          Column()
            .id(MORE_ANCHOR_ID)
            .width(24)
            .height(24)
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: 16 })
        .margin({ top: appState.topRect + 20 })
        .bindSheet(!!this.showImportSheet, this.ImportSheetBuilder(), {
          scrollSizeMode: ScrollSizeMode.CONTINUOUS, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          dragBar: true,
          onWillDisappear: () => {
            this.showImportSheet = false;
            appState.isForegroundBlur = false
          },
          onWillAppear: () => {
            appState.isForegroundBlur = true
          }
        })
      }
      .width('100%')
      .height('100%')
    }
  }

  /** 歌单条目行（卡片样式；批量模式下点击勾选、长按进入批量模式，否则点击进入详情） */
  @Builder
  SheetRowBuilder(row: SheetRow) {
    Column() {
      Row({ space: 12 }) {
        // 批量模式：勾选圈
        if (appState.isBatchMode) {
          SymbolGlyph(this.isSelected(row) ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
            .fontSize(24)
            .fontColor([this.isSelected(row) ? appState.accentColor : $r('sys.color.icon_tertiary')])
            .transition(TransitionEffect.OPACITY)
        }
        // 封面：有图用 Image，无图用歌单占位图标
        if (row.coverUrl.length > 0) {
          Image(ArtworkCache.resolve(row.coverUrl))
            .width(40)
            .height(40)
            .borderRadius(10)
            .objectFit(ImageFit.Cover)
            .alt($r('app.media.altImage'))
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
          Text(row.title)
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.rowSubtitle(row))
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (!appState.isBatchMode) {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('sys.color.icon_tertiary')])
            .transition(TransitionEffect.OPACITY)
        }
      }
      .width('100%')
      .height(56)
      .gesture(
        LongPressGesture({ repeat: false, duration: 500 })
          .onAction((_event: GestureEvent) => {
            // 长按进入批量模式并勾选当前条目（默认歌单仅进入批量模式）
            if (appState.isBatchMode) {
              return;
            }
            this.enterBatchMode();
            this.toggleBatchSelect(row);
          })
      )
      .onClick(() => {
        if (appState.isBatchMode) {
          this.toggleBatchSelect(row);
        } else {
          this.openSheetDetail(row);
        }
      })
    }
    .width('100%')
    .borderRadius(16)
    .padding(12)
    .backgroundColor($r('sys.color.comp_background_list_card'))
  }

  /** 标题栏下方扩展区：「我的歌单/订阅歌单」分段滑块（样式仿播放页封面/歌词切换）+ 可展开搜索框 */
  @Builder
  TitleExtraBuilder() {
    Column() {
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('50%')
          .height(26)
          .borderRadius(13)
          .backgroundColor($r('sys.color.background_secondary'))
          // 位移必须用绝对值：'50%' 与 0 之间无法插值，animateTo 会瞬移；81 = 滑轨内宽 162 的一半
          .offset({ x: this.showSubscribed ? 81 : 0 })
          .attributeModifier(rowImmersiveModifier)

        Row() {
          Text('我的歌单')
            .fontSize(12)
            .fontWeight(!this.showSubscribed ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(!this.showSubscribed ? appState.accentColor : $r('sys.color.font_tertiary'))
            .height(26)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.switchTab(false);
            })
          Text('订阅歌单')
            .fontSize(12)
            .fontWeight(this.showSubscribed ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.showSubscribed ? appState.accentColor : $r('sys.color.font_tertiary'))
            .height(26)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.switchTab(true);
            })
        }
        .width('100%')
      }
      .width(168)
      .height(30)
      .borderRadius(15)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .padding(3)
      .margin({ top: 4, bottom: 10 })
      .attributeModifier(stackImmersiveModifier)

      if (this.showSearchBox) {
        this.SearchBuilder()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /** 订阅条目行（卡片样式；批量模式下点击勾选、长按进入批量模式，否则点击进详情并清除更新标记） */
  @Builder
  SubscribedRowBuilder(rec: SubscribedSheetRecord) {
    Column() {
      Row({ space: 12 }) {
        // 批量模式：勾选圈
        if (appState.isBatchMode) {
          SymbolGlyph(this.isSubscribedSelected(rec) ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
            .fontSize(24)
            .fontColor([this.isSubscribedSelected(rec) ? appState.accentColor : $r('sys.color.icon_tertiary')])
            .transition(TransitionEffect.OPACITY)
        }
        // 封面：有图用 Image，无图用歌单占位图标
        if (rec.coverUrl().length > 0) {
          Image(ArtworkCache.resolve(rec.coverUrl()))
            .width(40)
            .height(40)
            .borderRadius(10)
            .objectFit(ImageFit.Cover)
            .alt($r('app.media.altImage'))
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
          Row({ space: 6 }) {
            Text(rec.title)
              .fontSize(15)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (rec.hasUpdate) {
              Text('有更新')
                .fontSize(10)
                .fontColor(Color.White)
                .backgroundColor('#e5484d')
                .borderRadius(8)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            }
          }
          .width('100%')

          Text(this.subscribedRowSubtitle(rec))
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (!appState.isBatchMode) {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('sys.color.icon_tertiary')])
            .transition(TransitionEffect.OPACITY)
        }
      }
      .width('100%')
      .height(56)
      .gesture(
        LongPressGesture({ repeat: false, duration: 500 })
          .onAction((_event: GestureEvent) => {
            // 长按进入批量模式并勾选当前条目
            if (appState.isBatchMode) {
              return;
            }
            this.enterBatchMode();
            this.toggleSubscribedSelect(rec);
          })
      )
      .onClick(() => {
        if (appState.isBatchMode) {
          this.toggleSubscribedSelect(rec);
        } else {
          this.openSubscribedDetail(rec);
        }
      })
    }
    .width('100%')
    .borderRadius(16)
    .padding(12)
    .backgroundColor($r('sys.color.comp_background_list_card'))
  }

  /**
   * 搜索框（固定于标题栏下方，不随列表滚动消失；切到其他 tab 自动收起；
   * 输入不即时过滤，点搜索按钮/软键盘回车后才应用关键词）
   */
  @Builder
  SearchBuilder() {
    CommonSearch({
      searchValue: this.searchInput,
      placeholderValue: '搜索歌单名称或简介',
      focusId: 'my_sheets_search',
      submit: (): void => {
        this.searchKeyword = this.searchInput.trim();
        this.rebuildSheetSource();
        this.rebuildSubscribedSource();
      },
      change: (v: string): void => {
        this.searchInput = v;
      },
      didDelete: (): void => {
        this.searchInput = '';
        this.searchKeyword = '';
        this.rebuildSheetSource();
        this.rebuildSubscribedSource();
      },
    })
      .width('100%')
      .padding({ left: 16, right: 16 })
      .transition(TransitionEffect.move(TransitionEdge.TOP))
  }

  /** 新建/编辑歌单半模态（共用表单）：名称（必填）+ 简介（可选），编辑模式预填当前值 */
  @Builder
  SheetMetaFormBuilder(isCreate: boolean) {
    Column() {
      Text(isCreate ? '新建歌单' : '编辑歌单')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 4, bottom: 16 })
      TextInput({ text: isCreate ? this.newSheetTitle : this.editSheetTitle, placeholder: '歌单名称' })
        .width('100%')
        .height(44)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(12)
        .onChange((v: string) => {
          if (isCreate) {
            this.newSheetTitle = v;
          } else {
            this.editSheetTitle = v;
          }
        })
      TextArea({ text: isCreate ? this.newSheetDesc : this.editSheetDesc, placeholder: '简介（可选）' })
        .width('100%')
        .height(88)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(12)
        .margin({ top: 12 })
        .onChange((v: string) => {
          if (isCreate) {
            this.newSheetDesc = v;
          } else {
            this.editSheetDesc = v;
          }
        })
      Button(isCreate ? (this.creating ? '创建中...' : '创建') : '保存')
        .width('100%')
        .height(42)
        .fontSize(15)
        .margin({ top: 20 })
        .backgroundColor(appState.accentColor)
        .onClick(() => {
          if (isCreate) {
            this.confirmCreateSheet();
          } else {
            this.confirmEditSheet();
          }
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12 + sheetTopAvoidVp(), bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 歌单/订阅排序半模态（共用表单）：上移/下移/跳转，保存后生效（默认歌单固定首位，不参与排序） */
  @Builder
  SortListSheetBuilder(isSheetSort: boolean) {
    Column() {
      Text(isSheetSort ? '歌单排序' : '订阅排序')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 4, bottom: 8 })
      List() {
        ForEach(isSheetSort ? this.sortSheetIds : this.subscribedSortKeys, (key: string, index: number) => {
          ListItem() {
            Row({ space: 12 }) {
              Text((index + 1).toString())
                .fontSize(13)
                .fontColor($r('sys.color.font_tertiary'))
                .width(20)
                .textAlign(TextAlign.Center)
              Text(isSheetSort ? this.sortSheetTitle(key) : this.subscribedSortTitle(key))
                .fontSize(15)
                .fontColor($r('sys.color.font_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)

              ForEach([$r('sys.symbol.chevron_up'), $r('sys.symbol.chevron_down'), $r('sys.symbol.arrow_left_arrow_right')],(v: Resource, i: number)=>{
                SymbolGlyph(v)
                  .fontSize(18)
                  .fontColor([$r('sys.color.icon_secondary')])
                  .onClick(() => {
                    if (i === 0) {// 上移
                      if (isSheetSort) {
                        this.moveSortItem(index, -1);
                      } else {
                        this.moveSubscribedSortItem(index, -1);
                      }
                    }else if (i === 1) {// 下移
                      if (isSheetSort) {
                        this.moveSortItem(index, 1);
                      } else {
                        this.moveSubscribedSortItem(index, 1);
                      }
                    }else{// 跳转
                      if (isSheetSort) {
                        this.openSortJump(index);
                      } else {
                        this.openSubscribedSortJump(index);
                      }
                    }
                  })
              }, (v: Resource, i: number) => i.toString())
            }
            .width('100%')
            .height(52)
          }
        }, (key: string, index: number) => key + '_' + index.toString())
      }
      .divider({
        strokeWidth: 0.5,
        color: $r('sys.color.comp_divider'),
      })
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .margin({ top: 4 })
      Button('保存排序')
        .width('100%')
        .height(42)
        .fontSize(15)
        .margin({ top: 12 })
        .backgroundColor(appState.accentColor)
        .onClick(() => {
          if (isSheetSort) {
            this.saveSortOrder();
          } else {
            this.saveSubscribedSortOrder();
          }
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 12 + sheetTopAvoidVp(), bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 导入半模态：选择插件 + 输入链接/ID + 底部说明（导入歌单/导入单曲共用） */
  @Builder
  ImportSheetBuilder() {
    Column() {
      Text(this.importSingleMode ? '导入单曲' : '导入歌单')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 4, bottom: 16 })
      Text('来源插件')
        .fontSize(13)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
        .margin({ bottom: 8 })
      Select(this.importSelectOptions())
        .selected(this.importPluginIndex)
        .value(this.selectedImportPluginName())
        .font({ size: 14 })
        .fontColor($r('sys.color.font_primary'))
        .selectedOptionFont({ size: 14 })
        .optionFont({ size: 14 })
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(12)
        .height(44)
        .width('100%')
        .onSelect((index: number, _text: string) => {
          if (this.importPluginNames.length > 0) {
            this.importPluginIndex = index;
            this.refreshImportHintFor(this.selectedImportPluginName());
          }
        })
      if (!this.importSingleMode) {
        Text('超时时长'+'(歌单较大时，可适当选择时间较长选项)')
          .fontSize(13)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .margin({ top: 12, bottom: 8 })
        Select(this.importTimeoutOptions())
          .selected(this.importTimeoutIndex)
          .value(this.selectedImportTimeoutLabel())
          .font({ size: 14 })
          .fontColor($r('sys.color.font_primary'))
          .selectedOptionFont({ size: 14 })
          .optionFont({ size: 14 })
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .borderRadius(12)
          .height(44)
          .width('100%')
          .onSelect((index: number, _text: string) => {
            this.importTimeoutIndex = index;
          })
      }
      if (this.importSingleMode) {
        Text('加入歌单')
          .fontSize(13)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .margin({ top: 12, bottom: 8 })
        Select(this.importTargetOptions())
          .selected(this.importTargetIndex)
          .value(this.selectedImportTargetName())
          .font({ size: 14 })
          .fontColor($r('sys.color.font_primary'))
          .selectedOptionFont({ size: 14 })
          .optionFont({ size: 14 })
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .borderRadius(12)
          .height(44)
          .width('100%')
          .onSelect((index: number, _text: string) => {
            if (this.importTargetSheetIds.length > 0) {
              this.importTargetIndex = index;
            }
          })
      }
      TextInput({
        text: this.importUrl,
        placeholder: this.importSingleMode ? '输入目标歌曲' : '输入目标歌单'
      })
        .width('100%')
        .height(44)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(12)
        .margin({ top: 12 })
        .onChange((v: string) => {
          this.importUrl = v;
        })
        .onSubmit((_enterKey: EnterKeyType) => {
          this.confirmImport();
        })
      Button()
        {
          if (this.importing){
            Row({ space: 5 }){
              CommonLoading({loadColor: Color.White})
              Text('导入中...')
                .fontSize(15)
                .fontColor(Color.White)
            }
          }else{
            Text('导入')
              .fontSize(15) .fontColor(Color.White)
          }
        }
        .width('100%')
        .height(42)
        .margin({ top: 20 })
        .backgroundColor(appState.accentColor)
        .enabled(this.importPluginNames.length > 0)
        .onClick(() => {
          this.confirmImport();
        })
      if (this.importHintText().length > 0) {
        Text(this.importHintText())
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .margin({ top: 16 })
          .lineHeight(18)
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12 + sheetTopAvoidVp(), bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }
}

@Extend(List)
function ListStyle(extraTop: number){
  .width('100%')
  .height('100%')
  .scrollBar(BarState.Off)
  .edgeEffect(EdgeEffect.Spring)
  // 搜索框展开时为固定搜索框让位
  .contentStartOffset(appState.topRect + 66 + extraTop)
  // 批量模式/上下两排时底栏更高，末尾内容需多留滚动空间
  .contentEndOffset(appState.bottomRect + (appState.isBatchMode ? 216 :
    (IsApiVersion_24() && appState.hdsBarLayoutMode === 1 ? 130 : 60)))
  .padding({ left: 16, right: 16 })
}
