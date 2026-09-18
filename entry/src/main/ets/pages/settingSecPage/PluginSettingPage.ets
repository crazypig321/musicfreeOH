import { CommonNav, titleBarOf } from '../../view/CommonNav';
import { appState } from '../../entryability/AppState';
import { appConfig, ConfigKeys } from '../../core/AppConfig';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';

/**
 * 插件设置页面
 * 启动时自动更新插件 / 允许旧版本插件覆盖新版本插件 / 忽略插件的应用版本要求(实验性)
 * 条目行 UI 同播放/下载设置页；智感握姿：左手时开关镜像到行首、文本右对齐、图标镜像到行尾
 */
@ComponentV2
export struct PluginSettingPage {
  scroller: Scroller = new Scroller();
  @Local autoUpdatePlugin: boolean = appConfig.getAutoUpdatePlugin();
  @Local notCheckPluginVersion: boolean = appConfig.getNotCheckPluginVersion();
  @Local ignorePluginAppVersion: boolean = appConfig.getIgnorePluginAppVersion();

  build() {
    CommonNav({
      titleBarOp: titleBarOf('插件设置'),
      scroller: this.scroller,
      doubleTapToTop: true
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 12 }) {
          // 小标题
          ListItem() {
            Text('插件')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }

          ListItem() {
            Column() {
              // 启动时自动更新插件
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.autoUpdatePlugin })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.autoUpdatePlugin = isOn;
                      appConfig.setConfig(ConfigKeys.AUTO_UPDATE_PLUGIN, isOn);
                    })
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('启动时自动更新插件')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.autoUpdatePlugin })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.autoUpdatePlugin = isOn;
                      appConfig.setConfig(ConfigKeys.AUTO_UPDATE_PLUGIN, isOn);
                    })
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)

              Divider()
                .DividerStyle()

              // 允许旧版本插件覆盖新版本插件
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.notCheckPluginVersion })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.notCheckPluginVersion = isOn;
                      appConfig.setConfig(ConfigKeys.NOT_CHECK_PLUGIN_VERSION, isOn);
                    })
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('允许旧版本插件覆盖新版本插件')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.notCheckPluginVersion })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.notCheckPluginVersion = isOn;
                      appConfig.setConfig(ConfigKeys.NOT_CHECK_PLUGIN_VERSION, isOn);
                    })
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)

              Divider()
                .DividerStyle()

              // 忽略插件的应用版本要求(实验性)
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.ignorePluginAppVersion })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.ignorePluginAppVersion = isOn;
                      appConfig.setConfig(ConfigKeys.IGNORE_PLUGIN_APP_VERSION, isOn);
                    })
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.gearshape'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('忽略插件的应用版本要求(实验性)')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.ignorePluginAppVersion })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.ignorePluginAppVersion = isOn;
                      appConfig.setConfig(ConfigKeys.IGNORE_PLUGIN_APP_VERSION, isOn);
                    })
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.gearshape'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)
            }
            .width('100%')
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

@Extend(Divider)
function DividerStyle() {
  .color($r('sys.color.comp_divider'))
  .margin(appState.holdingHand === 'left' ? { left: 4, right: 32 } : { left: 32, right: 4 })
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
