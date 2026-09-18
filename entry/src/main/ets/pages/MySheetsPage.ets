import { CommonNav, titleBarOf } from '../view/CommonNav';
import { ArtworkCache } from '../utils/ArtworkCache';
import { CommonBlur, MenuItemParams } from '../view/CommonCom';
import { MenuUtils } from '../utils/MenuUtils';
import { musicSheet, SheetBasePatch } from '../core/MusicSheet';
import { pluginManager } from '../plugin/PluginManager';
import { Plugin } from '../plugin/Plugin';
import { PluginState } from '../plugin/PluginTypes';
import { MusicItem } from '../common/model/MediaTypes';
import { SheetItem, SheetInfoResult } from '../common/model/SheetTypes';
import { appState } from '../entryability/AppState';
import { HdsListItem, HdsSwipeActionOptions, HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { SheetDetailNavParams, ROUTE_SHEET_DETAIL } from '../common/model/NavModels';
import { NavPathUtils } from '../utils/NavPathUtils';
import { BarScrollHelper, IsApiVersion_24 } from '../utils/BarScrollHelper';
import { JsonUtil } from '../common/JsonUtil';
import { DialogManager } from '../utils/DialogUtils';

/** 添加菜单锚点 id（openMenu 在锚点处弹出） */
const ADD_ANCHOR_ID = 'mysheets_add_anchor';

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

/**
 * 我的歌单页：展示全部本地歌单（含默认歌单「我的收藏」）
 * 顶部右侧：添加菜单（新建歌单 / 导入歌单 / 导入单曲）+ 批量操作（全选/分享/删除，UI 同歌单详情页批量底栏）
 * 条目 UI 同插件页；左滑呼出 编辑/删除（HdsListItem，默认歌单与批量模式下不提供横滑）
 * 点击进入歌单详情页（本地歌单模式），长按进入批量模式
 */
@ComponentV2
export struct MySheetsPage {
  scroller: Scroller = new Scroller();
  @Local sheetRows: Array<SheetRow> = [];
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
  /** 说明文本刷新标记：懒加载插件挂载完成后 +1 触发重绘 */
  @Local importHintRev: number = 0;

  aboutToAppear(): void {
    this.refreshSheets();
    musicSheet.onSheetBasicUpdated((): void => {
      this.refreshSheets();
    });
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

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  /** titleBar 菜单按钮（添加菜单 + 批量操作） */
  private titleMenus(): Array<HdsNavigationMenuItemOptions> {
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
        icon: $r('sys.symbol.list_checkmask'),
        label: '批量操作',
        action: (): void => {
          this.enterBatchMode();
        }
      }
    };
    return [add, batch];
  }

  private runMenuAction(action: () => void): void {
    MenuUtils.Dismiss();
    action();
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
      plugin.methods.importMusicSheet(url).then((items: Array<MusicItem>): void => {
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
          icon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil'))
            .fontColor([Color.White]).fontSize(20),
          backgroundColor: appState.accentColor,
          onAction: (): void => {
            this.openEditSheet(row);
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

  /** 批量操作按钮文案（全部勾选后「全选」切换为「取消全选」） */
  private batchButtonLabels(): Array<string> {
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

  /** 批量分享：复制选中歌单的曲目清单文本 */
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
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, parts.join('\n\n'));
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      this.showToast('已复制 ' + sheets.length.toString() + ' 个歌单的曲目清单，可粘贴分享');
    }).catch((_e: Object): void => {
      this.showToast('复制失败');
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
        '共 ' + this.sheetRows.length.toString() + ' 歌单', this.titleMenus()),
      isHideBackButton: true,
      scroller: this.scroller,
      doubleTapToTop: true,
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 16 }) {
          if (this.sheetRows.length > 0) {
            ForEach(this.sheetRows, (row: SheetRow, index: number) => {
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
              Text('暂无歌单，点击右上角「添加」新建或导入歌单')
                .fontSize(13)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ top: 32 })
            }
          }
        }
        .ListStyle()
        .onScrollFrameBegin((offset: number) => {
          BarScrollHelper.notifyScrollDelta(this.getUIContext(), offset)
          return { offsetRemain: offset }
        })
        .bindSheet(!!this.showCreateSheet, this.CreateSheetBuilder(), {
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
              Text('已选 ' + this.batchSelected.length.toString() + ' 个歌单')
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
                    if (i === 0) {// 全选/取消全选
                      this.toggleSelectAll();
                    } else if (i === 1) {// 分享
                      this.batchShare();
                    } else {// 删除
                      this.batchDelete();
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

        // 编辑歌单半模态锚点（独立节点挂载半模态，不与新建歌单 sheet 共用宿主）
        Column()
          .width('100%')
          .height(0)
          .bindSheet(!!this.showEditSheet, this.EditSheetBuilder(), {
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

        // 添加菜单锚点（标题栏下方右上角，菜单在锚点处弹出；导入半模态挂载于此）
        Row() {
          Column()
            .id(ADD_ANCHOR_ID)
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

  /** 新建歌单半模态：名称（必填）+ 简介（可选） */
  @Builder
  CreateSheetBuilder() {
    Column() {
      Text('新建歌单')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 4, bottom: 16 })
      TextInput({ text: this.newSheetTitle, placeholder: '歌单名称' })
        .width('100%')
        .height(44)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(12)
        .onChange((v: string) => {
          this.newSheetTitle = v;
        })
      TextArea({ text: this.newSheetDesc, placeholder: '简介（可选）' })
        .width('100%')
        .height(88)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(12)
        .margin({ top: 12 })
        .onChange((v: string) => {
          this.newSheetDesc = v;
        })
      Button(this.creating ? '创建中...' : '创建')
        .width('100%')
        .height(42)
        .fontSize(15)
        .margin({ top: 20 })
        .backgroundColor(appState.accentColor)
        .onClick(() => {
          this.confirmCreateSheet();
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 编辑歌单半模态：修改名称+简介（预填当前值） */
  @Builder
  EditSheetBuilder() {
    Column() {
      Text('编辑歌单')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 4, bottom: 16 })
      TextInput({ text: this.editSheetTitle, placeholder: '歌单名称' })
        .width('100%')
        .height(44)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(12)
        .onChange((v: string) => {
          this.editSheetTitle = v;
        })
      TextArea({ text: this.editSheetDesc, placeholder: '简介（可选）' })
        .width('100%')
        .height(88)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(12)
        .margin({ top: 12 })
        .onChange((v: string) => {
          this.editSheetDesc = v;
        })
      Button('保存')
        .width('100%')
        .height(42)
        .fontSize(15)
        .margin({ top: 20 })
        .backgroundColor(appState.accentColor)
        .onClick(() => {
          this.confirmEditSheet();
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 32 })
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
      Button(this.importing ? '导入中...' : '导入')
        .width('100%')
        .height(42)
        .fontSize(15)
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
    .padding({ left: 20, right: 20, top: 12, bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }
}

@Extend(List)
function ListStyle(){
  .width('100%')
  .height('100%')
  .scrollBar(BarState.Off)
  .edgeEffect(EdgeEffect.Spring)
  .contentStartOffset(appState.topRect + 66)
  // 批量模式/上下两排时底栏更高，末尾内容需多留滚动空间
  .contentEndOffset(appState.bottomRect + (appState.isBatchMode ? 170 :
    (IsApiVersion_24() && appState.hdsBarLayoutMode === 1 ? 130 : 60)))
  .padding({ left: 16, right: 16 })
}
