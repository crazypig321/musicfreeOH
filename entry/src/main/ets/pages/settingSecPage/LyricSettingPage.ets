import { CommonNav, titleBarOf } from '../../view/CommonNav';
import { appState } from '../../entryability/AppState';
import { appConfig, ConfigKeys } from '../../core/AppConfig';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';

/**
 * 歌词设置页面
 * 歌词缺失时自动搜索（右侧开关）
 * 条目行 UI 同播放/下载设置页
 */
@ComponentV2
export struct LyricSettingPage {
  scroller: Scroller = new Scroller();
  @Local autoSearchLyric: boolean = appConfig.getLyricAutoSearchLyric();

  build() {
    CommonNav({
      titleBarOp: titleBarOf('歌词设置'),
      scroller: this.scroller,
      doubleTapToTop: true
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 12 }) {
          // 小标题
          ListItem() {
            Text('歌词')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }

          ListItem() {
            // 歌词缺失时自动搜索
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.doc_plaintext'))
                .fontSize(20)
                .fontColor([$r('sys.color.icon_secondary')])
              Text('歌词缺失时自动搜索')
                .fontSize(15)
                .fontColor($r('sys.color.font_primary'))
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.autoSearchLyric })
                .selectedColor(appState.accentColor)
                .onChange((isOn: boolean) => {
                  this.autoSearchLyric = isOn;
                  appConfig.setConfig(ConfigKeys.LYRIC_AUTO_SEARCH_LYRIC, isOn);
                })
            }
            .width('100%')
            .height(52)
          }.ListItemStyle()
        }
        .ListStyle()
        .onScrollFrameBegin((offset: number) => {
          BarScrollHelper.notifyScrollDelta(this.getUIContext(), offset)
          return { offsetRemain: offset }
        })
      }
    }
  }
}

@Extend(ListItem)
function ListItemStyle() {
  .width('100%')
  .borderRadius(16)
  .padding(12)
  .backgroundColor($r('sys.color.comp_background_list_card'))
}

@Extend(List)
function ListStyle() {
  .width('100%')
  .height('100%')
  .scrollBar(BarState.Off)
  .edgeEffect(EdgeEffect.Spring)
  .contentStartOffset(appState.topRect + 66)
  .contentEndOffset(appState.bottomRect + (IsApiVersion_24() && appState.hdsBarLayoutMode === 1 ? 130 : 60))
  .padding({ left: 16, right: 16 })
}
