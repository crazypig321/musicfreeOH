import { CommonNav, titleBarOf } from '../view/CommonNav';
import { SheetGridItem } from '../view/SheetGridItem';
import { SheetRowDataSource } from '../common/model/SheetRowDataSource';
import { MediaTag, PageResult, SheetItem } from '../common/model/SheetTypes';
import { RecommendSheetNavParams } from '../common/model/NavModels';
import { Plugin } from '../plugin/Plugin';
import { pluginManager } from '../plugin/PluginManager';
import { appState } from '../entryability/AppState';

const GRID_COLUMNS = 3;

/**
 * 推荐歌单页：首页推荐歌单板块的完整版（标签切换 + 三列网格 + 触底续拉）
 */
@ComponentV2
export struct RecommendSheetsPage {
  @Local tags: Array<MediaTag> = [];
  @Local selectedIndex: number = 0;
  @Local sheets: Array<SheetItem> = [];
  @Local loading: boolean = false;

  private scroller: Scroller = new Scroller();
  private rowSource: SheetRowDataSource = new SheetRowDataSource();
  private plugin: Plugin | null = null;
  private page: number = 1;
  private isEnd: boolean = false;
  private reqSeq: number = 0;

  /** 歌单变化时同步行数据源（LazyForEach 按需加载行） */
  @Monitor('sheets')
  onSheetsChange(): void {
    this.rowSource.setRows(RecommendSheetsPage.chunkRows(this.sheets));
  }

  aboutToAppear(): void {
    this.plugin = pluginManager.getByName(RecommendSheetNavParams.pluginName);
    this.tags = RecommendSheetNavParams.tags;
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

  /** 歌单按列数切分成行 */
  private static chunkRows(sheets: Array<SheetItem>): Array<Array<SheetItem>> {
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
      titleBarOp: titleBarOf('推荐歌单', undefined, undefined),
    }) {
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
              ForEach(this.tags, (tag: MediaTag, index: number) => {
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
              }, (tag: MediaTag, index: number) => tag.id + '_' + index.toString())
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
                    this.showToast('歌单详情页开发中');
                  }
                })
              }, (sheet: SheetItem, index: number) =>
                sheet.platform + '_' + sheet.id + '_' + rowIndex.toString() + '_' + index.toString())
              // 不足整行时用 Blank 占位保持等宽
              if (rowItems.length === 1) {
                Blank().layoutWeight(1)
                Blank().layoutWeight(1)
              } else if (rowItems.length === 2) {
                Blank().layoutWeight(1)
              }
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
                .color($r('sys.color.icon_emphasize'))
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
