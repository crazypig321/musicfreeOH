import { CommonNav, titleBarOf } from '../view/CommonNav';
import { CommonBlur } from '../view/CommonCom';
import { musicSheet, SheetBasePatch } from '../core/MusicSheet';
import { SheetItem } from '../common/model/SheetTypes';
import { appState } from '../entryability/AppState';
import { HdsListItem, HdsSwipeActionOptions, HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { SheetDetailNavParams, ROUTE_SHEET_DETAIL } from '../common/model/NavModels';
import { NavPathUtils } from '../utils/NavPathUtils';
import { BarScrollHelper, IsApiVersion_24 } from '../utils/BarScrollHelper';

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
 * 我的歌单页：展示全部本地歌单（含默认歌单「我喜欢」）
 * 顶部右侧：添加（弹窗输入名称+简介）/ 批量操作（全选/分享/删除，UI 同歌单详情页批量底栏）
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

  /** titleBar 菜单按钮（添加 + 批量操作） */
  private titleMenus(): Array<HdsNavigationMenuItemOptions> {
    const add: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.plus'),
        label: '添加',
        action: (): void => {
          this.openCreateSheet();
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
          backgroundColor: $r('sys.color.background_emphasize'),
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

  /** 删除歌单条目 */
  private deleteSheet(row: SheetRow): void {
    if (row.isDefault) {
      this.showToast('默认歌单无法删除');
      return;
    }
    musicSheet.removeSheet(row.id);
    this.showToast('已删除「' + row.title + '」');
  }

  /** 进入批量模式（全局状态：隐藏 tab 栏、返回键退出） */
  private enterBatchMode(): void {
    appState.isBatchMode = true;
    this.batchSelected = [];
  }
  /** 退出批量模式 */
  private exitBatchMode(): void {
    appState.isBatchMode = false;
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

  /** 批量删除选中歌单 */
  private batchDelete(): void {
    const sheets = this.selectedSheets();
    if (sheets.length === 0) {
      this.showToast('请先勾选歌单');
      return;
    }
    let ok = 0;
    for (const sheet of sheets) {
      musicSheet.removeSheet(sheet.id);
      ok++;
    }
    this.exitBatchMode();
    this.refreshSheets();
    this.showToast('已删除 ' + ok.toString() + ' 个歌单');
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
              (appState.isBatchMode && this.isSelected(row) ? '_sel' : ''))
          } else {
            ListItem() {
              Text('暂无歌单，点击右上角「添加」创建')
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
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
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
        }

        // 编辑歌单半模态锚点（独立节点挂载半模态，不与新建歌单 sheet 共用宿主）
        Column()
          .width('100%')
          .height(0)
          .bindSheet(!!this.showEditSheet, this.EditSheetBuilder(), {
            detents: [SheetSize.MEDIUM, SheetSize.LARGE],
            dragBar: true,
            onWillDisappear: () => {
              this.showEditSheet = false;
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
            .fontColor([this.isSelected(row) ? $r('sys.color.icon_emphasize') : $r('sys.color.icon_tertiary')])
        }
        // 封面：有图用 Image，无图用歌单占位图标
        if (row.coverUrl.length > 0) {
          Image(row.coverUrl)
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
        .backgroundColor($r('sys.color.background_emphasize'))
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
        .backgroundColor($r('sys.color.background_emphasize'))
        .onClick(() => {
          this.confirmEditSheet();
        })
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
