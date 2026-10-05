import { CommonNav, ScrollToTopYOffset, titleBarOf } from '../../view/CommonNav';
import { appState } from '../../entryability/AppState';
import { appConfig, ConfigKeys } from '../../core/AppConfig';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';
import { floatLyricManager } from '../../core/FloatLyricManager';
import { showUiToast } from '../../utils/UiUtils';

/**
 * 歌词设置页面
 * 歌词缺失时自动搜索（右侧开关）
 * 条目行 UI 同播放/下载设置页；智感握姿：左手时开关镜像到行首、文本右对齐、图标镜像到行尾
 */
@ComponentV2
export struct LyricSettingPage {
  scroller: Scroller = new Scroller();
  @Local autoSearchLyric: boolean = appConfig.getLyricAutoSearchLyric();

  private showToast(message: string): void {
    showUiToast(this.getUIContext(), message);
  }

  /** 开关设置行：图标 + 文本 + 开关；智感握姿左手时开关镜像到行首、文本右对齐、图标镜像到行尾 */
  @Builder
  ToggleRowBuilder(icon: Resource, label: string, isOn: boolean, onToggle: (isOn: boolean) => void) {
    Row({ space: 12 }) {
      if (appState.holdingHand === 'left') {
        Toggle({ type: ToggleType.Switch, isOn: isOn })
          .selectedColor(appState.accentColor)
          .onChange((v: boolean) => {
            onToggle(v);
          })
      }
      if (appState.holdingHand !== 'left') {
        SymbolGlyph(icon)
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
      }
      Text(label)
        .fontSize(15)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
        .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
      if (appState.holdingHand !== 'left') {
        Toggle({ type: ToggleType.Switch, isOn: isOn })
          .selectedColor(appState.accentColor)
          .onChange((v: boolean) => {
            onToggle(v);
          })
      }
      if (appState.holdingHand === 'left') {
        SymbolGlyph(icon)
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
      }
    }
    .width('100%')
    .height(52)
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf('歌词设置'),
      scroller: this.scroller,
      doubleTapToTop: true,
      scrollToTopYOffset: ScrollToTopYOffset()
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
            this.ToggleRowBuilder($r('sys.symbol.doc_plaintext'), '歌词缺失时自动搜索', this.autoSearchLyric,
              (isOn: boolean): void => {
                this.autoSearchLyric = isOn;
                appConfig.setConfig(ConfigKeys.LYRIC_AUTO_SEARCH_LYRIC, isOn);
              })
          }.ListItemStyle()

          // 桌面歌词开关
          ListItem() {
            this.ToggleRowBuilder($r('sys.symbol.text_bubble_left_2'), '桌面歌词', floatLyricManager.enabled,
              (isOn: boolean): void => {
                this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
                  if (isOn) {
                    floatLyricManager.open().then((ok: boolean): void => {
                      if (!ok) {
                        this.showToast('桌面歌词不可用，请检查系统设置');
                      }
                    });
                  } else {
                    floatLyricManager.close().catch((): void => {
                    });
                  }
                });
              })
          }.ListItemStyle()

          // 提示：样式由系统桌面歌词设置管理
          ListItem() {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.info_circle'))
                .fontSize(16)
                .fontColor([$r('sys.color.icon_tertiary')])
              Text('字体颜色、背景等样式请在系统桌面歌词设置中调整')
                .fontSize(13)
                .fontColor($r('sys.color.font_tertiary'))
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 4, bottom: 4 })
          }.ListItemStyle()

          // 桌面歌词锁定开关（仅桌面歌词开启时显示）
          if (floatLyricManager.enabled)
            ListItem() {
              this.ToggleRowBuilder($r('sys.symbol.lock'), '锁定桌面歌词', floatLyricManager.locked,
                (isOn: boolean): void => {
                  floatLyricManager.toggleLocked(isOn).catch((): void => {
                  });
                })
            }.ListItemStyle().transition(TransitionEffect.OPACITY)
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
