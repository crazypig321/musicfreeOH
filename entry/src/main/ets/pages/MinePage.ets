import { CommonNav, ScrollToTopYOffset, titleBarOf } from '../view/CommonNav';
import { CommonSearch } from '../view/CommonCom';
import { ArtworkCache } from '../utils/ArtworkCache';
import { musicHistory } from '../core/MusicHistory';
import { trackPlayer } from '../core/TrackPlayer';
import { appState } from '../entryability/AppState';
import { MusicItem } from '../common/model/MediaTypes';
import { MusicDataSource } from '../common/model/MusicDataSource';
import { NavPathUtils } from '../utils/NavPathUtils';
import { ROUTE_LOCAL_MUSIC, ROUTE_DOWNLOAD } from '../common/model/NavModels';
import { DialogManager } from '../utils/DialogUtils';
import { showUiToast } from '../utils/UiUtils';
import { BarScrollHelper, IsApiVersion_24 } from '../utils/BarScrollHelper';
import { HdsListItem, HdsSwipeActionOptions, HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';

/** 常听排行条目（歌曲 + 播放次数） */
class TopPlayRow {
  item: MusicItem;
  count: number;

  constructor(item: MusicItem, count: number) {
    this.item = item;
    this.count = count;
  }
}

/**
 * 我的页（第 5 个主 tab）：仅播放历史（搜索样式与交互参照我的歌单页）
 * - 右上角菜单：本地音乐/下载管理入口 + 搜索按钮
 * - 搜索框固定于标题栏下方（bottomBuilder 插槽），点搜索/回车应用关键词，
 *   按歌名/歌手/专辑过滤历史记录；切走 tab 自动收起
 * - 顶部听歌数据卡片（累计收听/累计播放/听过/本周在听 + 常听 TOP5 垂直柱状图），
 *   搜索中隐藏；下方为最近收听歌曲列表（歌名/歌手·专辑 + 播放次数），点击播放
 */
@ComponentV2
export struct MinePage {
  /** 当前所处 tab 序号（由 Index 传入；插入在「设置」之前） */
  @Param hostTabIndex: number = 2;
  /** 标题栏搜索框：开启后按关键词过滤历史记录（点搜索/回车才应用关键词） */
  @Local showSearchBox: boolean = false;
  @Local searchKeyword: string = '';
  /** 搜索框实时输入内容（未提交，不参与过滤） */
  @Local searchInput: string = '';
  scroller: Scroller = new Scroller();
  historySource: MusicDataSource = new MusicDataSource();
  /** 听歌数据：累计播放次数 */
  @Local totalPlays: number = 0;
  /** 听歌数据：本周在听歌曲数 */
  @Local weekActive: number = 0;
  /** 听歌数据：累计真实收听秒数 */
  @Local totalListenSec: number = 0;
  /** 常听排行 TOP5 */
  @Local topPlays: Array<TopPlayRow> = [];

  /** 切换到其他 tab 时收起搜索框并清空关键词 */
  @Monitor('hostTabIndex')
  onTabIndexChanged(): void {
    if (this.hostTabIndex !== 2 && this.showSearchBox) {
      this.showSearchBox = false;
      this.searchKeyword = '';
      this.searchInput = '';
      appState.tabSearchClose = null;
    }
  }

  aboutToAppear(): void {
    this.refreshHistory();
    musicHistory.onHistoryUpdated((): void => {
      this.refreshHistory();
    });
  }

  /** 刷新历史记录与听歌数据（统计取全量；列表按当前关键词过滤） */
  private refreshHistory(): void {
    const items = musicHistory.history;
    let total = 0;
    let week = 0;
    let listenSec = 0;
    let idx = 0;
    const weekAgo = Date.now() - 7 * 24 * 3600 * 1000;
    const tops: Array<TopPlayRow> = [];
    for (const it of items) {
      const stat = musicHistory.getStat(it);
      if (stat !== null) {
        total += stat.count;
        listenSec += stat.duration;
        if (stat.lastAt >= weekAgo) {
          week++;
        }
        // 「最近常听」仅统计最近 50 条记录（更贴近近期口味）
        if (idx < 50) {
          tops.push(new TopPlayRow(it, stat.count));
        }
      }
      idx++;
    }
    this.totalPlays = total;
    this.weekActive = week;
    this.totalListenSec = listenSec;
    tops.sort((a: TopPlayRow, b: TopPlayRow): number => b.count - a.count);
    this.topPlays = tops.slice(0, 5);
    this.rebuildHistorySource();
  }

  /** 按关键词过滤历史记录（标题/歌手/专辑；空关键词返回全部） */
  private displayHistory(): Array<MusicItem> {
    const kw = this.searchKeyword.trim().toLowerCase();
    const items = musicHistory.history;
    if (kw.length === 0) {
      return items;
    }
    const hit: Array<MusicItem> = [];
    for (const it of items) {
      if (it.title.toLowerCase().indexOf(kw) >= 0 ||
        it.artist.toLowerCase().indexOf(kw) >= 0 ||
        it.album.toLowerCase().indexOf(kw) >= 0) {
        hit.push(it);
      }
    }
    return hit;
  }

  /** 按当前关键词重建历史列表数据源 */
  private rebuildHistorySource(): void {
    this.historySource.clear();
    this.historySource.appendData(this.displayHistory());
  }

  /** titleBar 右上角菜单：本地音乐/下载管理入口 + 搜索按钮 */
  private titleMenus(): Array<HdsNavigationMenuItemOptions> {
    const local: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.music_note_phone'),
        label: '本地音乐',
        action: (): void => {
          NavPathUtils.push(ROUTE_LOCAL_MUSIC);
        }
      }
    };
    const download: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.download'),
        label: '下载',
        action: (): void => {
          NavPathUtils.push(ROUTE_DOWNLOAD);
        }
      }
    };
    const search: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.magnifyingglass'),
        label: '搜索',
        action: (): void => {
          this.toggleSearchBox();
        }
      }
    };
    return [local, download, search];
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
      this.rebuildHistorySource();
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
        focusController.requestFocus('mine_history_search');
      } catch (e) {
        // 组件未挂载时忽略
      }
    }, 320);
    if (this.scroller.currentOffset().yOffset !== 0) {
      this.scroller.scrollTo({
        xOffset: 0, yOffset: -(appState.topRect + 66 + 56),
        animation: { duration: 250, curve: Curve.EaseOut }
      });
    }
  }

  /** 标题副文本：搜索中显示命中数量，否则显示累计播放次数 */
  private subTitleText(): string {
    if (this.searchKeyword.trim().length > 0) {
      return '找到 ' + this.historySource.totalCount().toString() + ' 首';
    }
    return '累计播放 ' + this.totalPlays.toString() + ' 次';
  }

  /** 以当前过滤结果为播放队列播放歌曲 */
  private playFrom(item: MusicItem): void {
    const list = this.historySource.getItems();
    if (list.length === 0) {
      return;
    }
    trackPlayer.playWithReplacePlayList(item, list).catch((_e: Object): void => {
      this.showToast('播放失败');
    });
  }

  /** 全部播放（参考歌单详情页 playAll）：以当前过滤结果整体替换播放队列，从第一首开始 */
  private playAll(): void {
    const playList = this.historySource.getItems();
    if (playList.length === 0) {
      this.showToast('暂无播放记录');
      return;
    }
    trackPlayer.playWithReplacePlayList(playList[0], playList).catch((_e: Object): void => {
      this.showToast('播放失败');
    });
  }

  /** 清空播放记录（DialogManager 弹窗确认，点「清空」后才执行，取消不清空） */
  private confirmClearHistory(): void {
    if (this.historySource.totalCount() === 0) {
      this.showToast('暂无播放记录');
      return;
    }
    DialogManager.ConfirmClearData('确定清空全部播放记录吗？', (): void => {
      musicHistory.clearMusic();
      this.showToast('已清空播放记录');
    });
  }

  /** 历史条目横滑操作（左滑呼出删除按钮，弹窗确认后单独删除该条记录） */
  private historySwipeOptions(item: MusicItem): HdsSwipeActionOptions {
    const options: HdsSwipeActionOptions = {
      deleteIconOptions: {
        onAction: (): void => {
          this.confirmRemoveHistoryItem(item);
        }
      }
    };
    return options;
  }

  /** 删除确认（DialogManager 弹窗，点「删除」后才执行，取消不删除） */
  private confirmRemoveHistoryItem(item: MusicItem): void {
    DialogManager.ConfirmDelete('确定删除「' + item.title + '」的播放记录吗？', (): void => {
      this.removeHistoryItem(item);
    });
  }

  /** 单独删除一条播放记录（历史与统计一并移除） */
  private removeHistoryItem(item: MusicItem): void {
    musicHistory.removeMusic(item).then((): void => {
      this.showToast('已删除「' + item.title + '」');
    });
  }

  /** 历史行副标题：歌手 · 专辑 */
  private historySub(item: MusicItem): string {
    return item.artist + (item.album.length > 0 ? ' · ' + item.album : '');
  }

  /** 历史行尾部：播放 N 次 */
  private historyTail(item: MusicItem): string {
    const stat = musicHistory.getStat(item);
    const count = stat !== null ? stat.count : 0;
    return count.toString() + ' 次';
  }

  /** 累计收听时长数值：满 1 小时显示小时（一位小数），否则显示分钟（向上取整，至少 1） */
  private listenDurationText(): string {
    if (this.totalListenSec >= 3600) {
      const hours = Math.round(this.totalListenSec / 360) / 10;
      return hours.toString();
    }
    return Math.max(1, Math.ceil(this.totalListenSec / 60)).toString();
  }

  /** 累计收听时长单位 */
  private listenDurationUnit(): string {
    return this.totalListenSec >= 3600 ? '小时' : '分钟';
  }

  private showToast(message: string): void {
    showUiToast(this.getUIContext(), message);
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf($r('app.string.tab_mine'), this.subTitleText(), this.titleMenus(),
        (this.hostTabIndex === 2) ?
          { builder: (): void => { this.TitleExtraBuilder() }, height: this.showSearchBox ? 56 : 0 } : undefined),
      isHideBackButton: true,
      embedded: true,
      // 搜索框常驻标题栏下方，不随滚动隐藏（否则上滑隐藏、下滑才重现）
      isSearchBarScroller: false,
      scroller: this.scroller,
      doubleTapToTop: true,
      scrollToTopYOffset: ScrollToTopYOffset(this.showSearchBox ? 56 : 0)
    }) {
      List({ scroller: this.scroller, space: 12 }) {
        // 搜索中隐藏统计卡，仅展示结果列表
        if (this.searchKeyword.trim().length === 0 && this.historySource.totalCount() > 0) {
          ListItem() {
            this.StatsCardBuilder()
          }
        }
        ListItem() {
          this.HistoryHeaderBuilder()
        }
        if (this.historySource.totalCount() > 0) {
          LazyForEach(this.historySource, (item: MusicItem, _index: number) => {
            // HdsListItem 不支持通用属性，链式设置会破坏横滑手势，故不挂 transition
            HdsListItem({
              customItemBuilder: (): void => {
                this.MusicRowBuilder(item, this.historySub(item), this.historyTail(item));
              },
              swipeActionOptions: this.historySwipeOptions(item)
            })
          }, (item: MusicItem, index: number) => item.platform + '_' + item.id + '_' + index.toString() +
            '_' + appState.swipeResetTick.toString())
        } else {
          ListItem() {
            this.EmptyBuilder(this.searchKeyword.trim().length > 0 ?
              '未找到匹配的播放记录' : '暂无播放记录，播放歌曲后将显示在这里')
          }
        }
      }
      .ListStyle(this.showSearchBox ? 56 : 0)
      .onScrollFrameBegin((offset: number) => {
        BarScrollHelper.notifyScrollDelta(this.getUIContext(), offset)
        return { offsetRemain: offset }
      })
    }
  }

  /** 标题栏下方扩展区：搜索框（展开时挂载，从顶部滑入） */
  @Builder
  TitleExtraBuilder() {
    Column() {
      if (this.showSearchBox) {
        this.SearchBuilder()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 搜索框（固定于标题栏下方，不随列表滚动消失；切到其他 tab 自动收起；
   * 输入不即时过滤，点搜索按钮/软键盘回车后才应用关键词）
   */
  @Builder
  SearchBuilder() {
    CommonSearch({
      searchValue: this.searchInput,
      placeholderValue: '搜索歌名、歌手或专辑',
      focusId: 'mine_history_search',
      submit: (): void => {
        this.searchKeyword = this.searchInput.trim();
        this.rebuildHistorySource();
      },
      change: (v: string): void => {
        this.searchInput = v;
      },
      didDelete: (): void => {
        this.searchInput = '';
        this.searchKeyword = '';
        this.rebuildHistorySource();
      },
    })
      .width('100%')
      .padding({ left: 16, right: 16 })
      .transition(TransitionEffect.move(TransitionEdge.TOP))
  }

  /**
   * 历史列表头部（全部播放组件样式）：大播放图标 + 「最近收听」，点击播放全部；
   * 右侧「清空」按钮（弹窗确认），无尾部箭头
   */
  @Builder
  HistoryHeaderBuilder() {
    Row() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.play_circle_fill'))
          .fontSize(36)
          .fontColor([$r('sys.color.font')])
        Text('最近收听 · ' + this.historySource.totalCount().toString())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font'))
      }
      .onClick(() => {
        this.playAll();
      })

      Blank()

      Text('清空')
        .fontSize(14)
        .fontColor(appState.accentColor)
        .padding({ left: 12, top: 6, bottom: 6 })
        .onClick(() => {
          this.confirmClearHistory();
        })
    }
    .width('100%')
    .height(44)
    .padding({ left: 4, right: 4 })
  }

  /** 歌曲行（卡片样式，风格同下载页歌曲行）：封面 + 歌名 + 副标题 + 尾部信息，点击播放 */
  @Builder
  MusicRowBuilder(item: MusicItem, sub: string, tail: string) {
    Row({ space: 12 }) {
      if (item.artwork.length > 0) {
        Image(ArtworkCache.resolve(item.artwork))
          .width(40)
          .height(40)
          .borderRadius(10)
          .objectFit(ImageFit.Cover)
          .alt($r('app.media.altImage'))
          .draggable(false)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.music'))
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
        Text(sub)
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (tail.length > 0) {
        Text(tail)
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
      }
    }
    .width('100%')
    .height(80)
    .borderRadius(16)
    .padding(12)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .onClick(() => {
      this.playFrom(item);
    })
  }

  /** 听歌数据卡片：累计收听/累计播放/听过/本周在听 四项统计 + 常听 TOP5 垂直柱状图 */
  @Builder
  StatsCardBuilder() {
    Column({ space: 14 }) {
      Row() {
        this.StatBlock(this.listenDurationText(), this.listenDurationUnit(), '累计收听')
        this.StatBlock(this.totalPlays.toString(), '次', '累计播放')
        this.StatBlock(this.historySource.totalCount().toString(), '首', '听过')
        this.StatBlock(this.weekActive.toString(), '首', '本周在听')
      }
      .width('100%')

      if (this.topPlays.length > 0) {
        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.comp_divider'))

        Text('最近常听')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')

        // 垂直柱状图：柱高按播放次数占比（TOP1 满高 72，最低 12），按名次降低透明度
        Row({ space: 4 }) {
          ForEach(this.topPlays, (row: TopPlayRow, index: number) => {
            Column({ space: 5 }) {
              Text(row.count.toString() + ' 次')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_secondary'))
              // 柱体轨道（底部对齐，保持柱高动画时数值标签稳定）
              Column() {
                Column()
                  .width('64%')
                  .height(Math.max(12, Math.round(72 * row.count / Math.max(this.topPlays[0].count, 1))))
                  .borderRadius({ topLeft: 5, topRight: 5 })
                  .backgroundColor(appState.accentColor)
                  .opacity(1 - index * 0.16)
              }
              .width('100%')
              .height(72)
              .justifyContent(FlexAlign.End)
              .alignItems(HorizontalAlign.Center)
              Text(row.item.title)
                .fontSize(11)
                .fontColor($r('sys.color.font_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .textAlign(TextAlign.Center)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
          }, (row: TopPlayRow, index: number) => row.item.platform + '_' + row.item.id + '_' + index.toString() + '_' + row.count.toString())
        }
        .width('100%')
      }
    }
    .width('100%')
    .borderRadius(16)
    .padding(16)
    .backgroundColor($r('sys.color.comp_background_list_card'))
  }

  /** 单项统计块：大号数值 + 小号单位（底对齐，基线视觉近似），下方短标签（单行防换行错位） */
  @Builder
  StatBlock(value: string, unit: string, label: string) {
    Column({ space: 3 }) {
      Row({ space: 2 }) {
        Text(value)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(appState.accentColor)
          .maxLines(1)
        Text(unit)
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .margin({ bottom: 3 })
      }
      .alignItems(VerticalAlign.Bottom)
      Text(label)
        .fontSize(11)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(1)
    }
    .layoutWeight(1)
  }

  /** 空态文案 */
  @Builder
  EmptyBuilder(message: string) {
    Text(message)
      .fontSize(13)
      .fontColor($r('sys.color.font_tertiary'))
      .width('100%')
      .textAlign(TextAlign.Center)
      .margin({ top: 32 })
  }
}

@Extend(List)
function ListStyle(extraTop: number) {
  .width('100%')
  .height('100%')
  .scrollBar(BarState.Off)
  .edgeEffect(EdgeEffect.Spring)
  // 搜索框展开时为固定搜索框让位
  .contentStartOffset(appState.topRect + 66 + extraTop)
  .contentEndOffset(appState.bottomRect +
    (IsApiVersion_24() && appState.hdsBarLayoutMode === 1 ? 130 : 60))
  .padding({ left: 16, right: 16 })
}
