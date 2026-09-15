import { MusicItem } from '../model/MediaTypes';
import { SearchResult, SupportMediaType } from '../model/SheetTypes';
import { pluginManager } from '../plugin/PluginManager';
import { Plugin } from '../plugin/Plugin';
import { trackPlayer } from '../core/TrackPlayer';
import { CommonNav, titleBarOf } from '../view/CommonNav';

@ComponentV2
export struct SearchPage {
  scroller: Scroller = new Scroller();
  @Local keyword: string = '';
  @Local searchResults: Array<MusicItem> = [];
  @Local searchStatus: string = '';
  @Local searching: boolean = false;
  @Local pluginName: string = '';

  private doSearch(): void {
    const kw = this.keyword.trim();
    if (kw.length === 0 || this.searching) {
      return;
    }
    const plugins = pluginManager.getSortedSearchablePlugins(SupportMediaType.Music);
    if (plugins.length === 0) {
      this.searchResults = [];
      this.searchStatus = '无可用音乐插件，请先在插件管理中安装';
      return;
    }
    const plugin: Plugin = plugins[0];
    this.pluginName = plugin.name;
    this.searchResults = [];
    this.searching = true;
    this.searchStatus = '搜索中...';
    plugin.methods.search(kw, 1, SupportMediaType.Music).then((r: SearchResult) => {
      this.searching = false;
      this.searchResults = r.musicData;
      this.searchStatus = r.musicData.length === 0 ? '未找到相关结果' : '共 ' + r.musicData.length.toString() + ' 条结果';
    }).catch((_e: Object): void => {
      this.searching = false;
      this.searchResults = [];
      this.searchStatus = '搜索失败，请重试';
    });
  }

  private clearKeyword(): void {
    this.keyword = '';
    this.searchResults = [];
    this.searchStatus = '';
  }

  private playResult(item: MusicItem): void {
    if (this.searchResults.length === 0) {
      return;
    }
    trackPlayer.playWithReplacePlayList(item, this.searchResults).catch((_e: Object): void => {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '播放失败', duration: 1500 });
      } catch (error) {
        // TODO: Implement error handling.
      }
    });
  }

  private static formatDuration(sec: number): string {
    const s = Math.max(0, Math.floor(sec));
    const m = Math.floor(s / 60);
    const r = s % 60;
    const mStr = m < 10 ? '0' + m.toString() : m.toString();
    const rStr = r < 10 ? '0' + r.toString() : r.toString();
    return mStr + ':' + rStr;
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf($r('app.string.search_title')),
      isShowPlayBar: true,
      scroller: this.scroller,
      backPressed: (): boolean => false
    }) {
      Scroll(this.scroller) {
        Column() {
          this.SearchBarBuilder()
          if (this.searchStatus.length > 0) {
            Text(this.searchStatus)
              .fontSize(12)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
              .margin({ top: 8, bottom: 4 })
              .maxLines(1)
          }
          ForEach(this.searchResults, (item: MusicItem, index: number) => {
            this.ResultRowBuilder(item, index)
          }, (item: MusicItem, index: number) => item.platform + '_' + item.id + '_' + index.toString())
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 160 })
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
  SearchBarBuilder() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(20)
        .fontColor([$r('sys.color.icon_secondary')])
      TextInput({ text: this.keyword, placeholder: $r('app.string.home_search_placeholder') })
        .layoutWeight(1)
        .height(44)
        .backgroundColor(Color.Transparent)
        .padding(0)
        .fontSize(15)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .placeholderFont({ size: 15 })
        .enterKeyType(EnterKeyType.Search)
        .defaultFocus(true)
        .onChange((v: string) => {
          this.keyword = v;
        })
        .onSubmit((_enterKey: EnterKeyType) => {
          this.doSearch();
        })
      if (this.keyword.length > 0) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(16)
          .fontColor([$r('sys.color.icon_tertiary')])
          .onClick(() => {
            this.clearKeyword();
          })
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .borderRadius(22)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .margin({ top: 4 })
  }

  @Builder
  ResultRowBuilder(item: MusicItem, index: number) {
    Row({ space: 12 }) {
      Text((index + 1).toString())
        .fontSize(14)
        .fontColor(index < 3 ? $r('sys.color.font_emphasize') : $r('sys.color.font_tertiary'))
        .width(24)
        .textAlign(TextAlign.Center)
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
      Text(SearchPage.formatDuration(item.duration))
        .fontSize(12)
        .fontColor($r('sys.color.font_tertiary'))
    }
    .width('100%')
    .height(56)
    .borderRadius(12)
    .onClick(() => {
      this.playResult(item);
    })
  }
}
