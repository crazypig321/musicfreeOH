import { MusicItem } from '../common/model/MediaTypes';
import { LengthMetrics } from '@kit.ArkUI';

/** 列表排序选项（键 + 菜单文案） */
export class SortOption {
  readonly key: string = '';
  readonly label: string = '';

  constructor(key: string, label: string) {
    this.key = key;
    this.label = label;
  }
}

/** 列表排序工具：仅影响当前页列表的显示顺序，不改动任何存储数据 */
export class MusicSortUtil {
  static readonly KEY_DEFAULT: string = 'default';
  static readonly KEY_REVERSE: string = 'reverse';
  static readonly KEY_TITLE: string = 'title';
  static readonly KEY_ARTIST: string = 'artist';
  static readonly KEY_PLATFORM: string = 'platform';

  static readonly OPTIONS: Array<SortOption> = [
    new SortOption(MusicSortUtil.KEY_DEFAULT, '正序'),
    new SortOption(MusicSortUtil.KEY_REVERSE, '倒序'),
    new SortOption(MusicSortUtil.KEY_TITLE, '歌曲名'),
    new SortOption(MusicSortUtil.KEY_ARTIST, '歌手名'),
    new SortOption(MusicSortUtil.KEY_PLATFORM, '来源')
  ];

  /**
   * 对默认顺序的列表应用排序，返回新数组（default 原样返回引用）。
   * 排序为稳定排序：同字段值相同时保持原有相对顺序。
   */
  static sortItems(items: Array<MusicItem>, sortKey: string): Array<MusicItem> {
    if (sortKey === MusicSortUtil.KEY_REVERSE) {
      return items.slice().reverse();
    }
    if (sortKey === MusicSortUtil.KEY_TITLE) {
      return items.slice().sort(
        (a: MusicItem, b: MusicItem): number => a.title.localeCompare(b.title));
    }
    if (sortKey === MusicSortUtil.KEY_ARTIST) {
      return items.slice().sort(
        (a: MusicItem, b: MusicItem): number => a.artist.localeCompare(b.artist));
    }
    if (sortKey === MusicSortUtil.KEY_PLATFORM) {
      return items.slice().sort((a: MusicItem, b: MusicItem): number => {
        const byPlatform = a.platform.localeCompare(b.platform);
        return byPlatform !== 0 ? byPlatform : a.title.localeCompare(b.title);
      });
    }
    return items;
  }
}

/**
 * 列表排序按钮：排序图标 + 点击弹出菜单（正序/倒序/歌曲名/歌手名/来源），
 * 当前选中项带对勾，选择后回调 onPick 由页面应用到列表
 */
@ComponentV2
export struct MusicSortMenu {
  /** 当前排序方式（MusicSortUtil.KEY_*） */
  @Param current: string = MusicSortUtil.KEY_DEFAULT;
  @Event onPick: (key: string) => void = (_key: string): void => {};

  @Builder
  SortMenuBuilder() {
    Menu() {
      ForEach(MusicSortUtil.OPTIONS, (opt: SortOption) => {
        MenuItem({
          content: opt.label,
          endIcon: opt.key === this.current ? $r('sys.symbol.checkmark') : ''
        })
          .onClick(() => {
            this.onPick(opt.key);
          })
      }, (opt: SortOption) => opt.key)
    }
    .menuItemDivider({ color: $r("sys.color.comp_divider"),
      strokeWidth: LengthMetrics.vp(0.5),
      startMargin: LengthMetrics.vp(2),
      endMargin: LengthMetrics.vp(2)})
  }

  build() {
    SymbolGlyph($r('sys.symbol.sort'))
      .fontSize(20)
      .fontColor([$r('sys.color.icon_secondary')])
      .bindMenu(this.SortMenuBuilder())
  }
}
