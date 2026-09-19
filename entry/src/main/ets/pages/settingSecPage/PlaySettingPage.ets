import { CommonNav, titleBarOf } from '../../view/CommonNav';
import { appState } from '../../entryability/AppState';
import { appConfig, ConfigKeys } from '../../core/AppConfig';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';
import { QualityKey, QUALITY_KEYS } from '../../common/model/MediaTypes';
import { MenuOptionEntry, OptionsMenuBuilder } from '../../view/OptionsMenu';

/**
 * 播放设置页面
 * 使用移动网络播放 / 启动自动续播 / 播放失败时停止播放 / 播放失败时尝试更换音源 /
 * 播放音质 / 首选音质不可用时
 * 开关类条目右侧 Toggle；选择类条目右侧当前值 + chevron，点击弹出 Menu 菜单（当前项带勾选标记，UI 同外观设置页）
 * 智感握姿：左手握持时原本行尾的开关/值镜像到行首，文本右对齐，行首图标镜像到行尾
 */
@ComponentV2
export struct PlaySettingPage {
  scroller: Scroller = new Scroller();
  @Local useCellularPlay: boolean = appConfig.getUseCellularNetworkPlay();
  @Local autoPlayWhenAppStart: boolean = appConfig.getAutoPlayWhenAppStart();
  @Local autoStopWhenError: boolean = appConfig.getAutoStopWhenError();
  @Local tryChangeSource: boolean = appConfig.getTryChangeSourceWhenPlayFail();
  /** 播放音质展示文本（设置成功后刷新） */
  @Local playQualityText: string = '';
  /** 首选音质不可用时展示文本 */
  @Local playQualityOrderText: string = '';
  /** 各菜单手动弹出开关（bindMenu isShow 形式，便于控制 placement） */
  @Local showQualityMenu: boolean = false;
  @Local showOrderMenu: boolean = false;

  aboutToAppear(): void {
    this.refreshQualityText();
  }

  private static qualityLabel(q: QualityKey): string {
    if (q === 'low') {
      return '低音质';
    }
    if (q === 'high') {
      return '高音质';
    }
    if (q === 'super') {
      return '超高音质';
    }
    return '标准音质';
  }

  private static orderLabel(order: string): string {
    return order === 'asc' ? '播放更高音质' : '播放更低音质';
  }

  private refreshQualityText(): void {
    this.playQualityText = PlaySettingPage.qualityLabel(appConfig.getDefaultPlayQuality());
    this.playQualityOrderText = PlaySettingPage.orderLabel(appConfig.getPlayQualityOrder());
  }

  /** 菜单弹出位置：智感握姿开启且左手握持 → 左下（拇指可达），否则条目右下 */
  private menuPlacement(): Placement {
    return appConfig.getSmartReachEnabled() && appState.holdingHand === 'left'
      ? Placement.BottomLeft : Placement.BottomRight;
  }

  /** 播放音质菜单（UI 同外观设置页：勾选标记 + 分割线 + 圆角） */
  @Builder
  private qualityMenu(): void {
    OptionsMenuBuilder(this.qualityEntries(), (value: string): void => {
      this.applyQuality(value);
    })
  }

  private qualityEntries(): Array<MenuOptionEntry> {
    const cur = appConfig.getDefaultPlayQuality();
    const entries: Array<MenuOptionEntry> = [];
    for (const q of QUALITY_KEYS) {
      entries.push(new MenuOptionEntry(q, PlaySettingPage.qualityLabel(q), q === cur));
    }
    return entries;
  }

  private applyQuality(value: string): void {
    for (const q of QUALITY_KEYS) {
      if (q === value) {
        appConfig.setConfig(ConfigKeys.DEFAULT_PLAY_QUALITY, q);
        this.playQualityText = PlaySettingPage.qualityLabel(q);
        return;
      }
    }
  }

  /** 首选音质不可用时菜单 */
  @Builder
  private orderMenu(): void {
    OptionsMenuBuilder(this.orderEntries(), (value: string): void => {
      this.applyOrder(value);
    })
  }

  private orderEntries(): Array<MenuOptionEntry> {
    const cur = appConfig.getPlayQualityOrder();
    const entries: Array<MenuOptionEntry> = [
      new MenuOptionEntry('asc', '播放更高音质', cur === 'asc'),
      new MenuOptionEntry('desc', '播放更低音质', cur === 'desc')
    ];
    return entries;
  }

  private applyOrder(value: string): void {
    appConfig.setConfig(ConfigKeys.PLAY_QUALITY_ORDER, value);
    this.playQualityOrderText = PlaySettingPage.orderLabel(value);
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf('播放设置'),
      scroller: this.scroller,
      doubleTapToTop: true
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 12 }) {
          // 小标题
          ListItem() {
            Text('播放')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }

          ListItem() {
            Column() {
              // 使用移动网络播放
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.useCellularPlay })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.useCellularPlay = isOn;
                      appConfig.setConfig(ConfigKeys.USE_CELLULAR_NETWORK_PLAY, isOn);
                    })
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('使用移动网络播放')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.useCellularPlay })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.useCellularPlay = isOn;
                      appConfig.setConfig(ConfigKeys.USE_CELLULAR_NETWORK_PLAY, isOn);
                    })
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)

              Divider()
                .DividerStyle()

              // 启动自动续播
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.autoPlayWhenAppStart })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.autoPlayWhenAppStart = isOn;
                      appConfig.setConfig(ConfigKeys.AUTO_PLAY_WHEN_APP_START, isOn);
                    })
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.play_fill'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('启动自动续播')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.autoPlayWhenAppStart })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.autoPlayWhenAppStart = isOn;
                      appConfig.setConfig(ConfigKeys.AUTO_PLAY_WHEN_APP_START, isOn);
                    })
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.play_fill'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)

              Divider()
                .DividerStyle()

              // 播放失败时停止播放
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.autoStopWhenError })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.autoStopWhenError = isOn;
                      appConfig.setConfig(ConfigKeys.AUTO_STOP_WHEN_ERROR, isOn);
                    })
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.stop_circle'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('播放失败时停止播放')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.autoStopWhenError })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.autoStopWhenError = isOn;
                      appConfig.setConfig(ConfigKeys.AUTO_STOP_WHEN_ERROR, isOn);
                    })
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.stop_circle'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)

              Divider()
                .DividerStyle()

              // 播放失败时尝试更换音源
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.tryChangeSource })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.tryChangeSource = isOn;
                      appConfig.setConfig(ConfigKeys.TRY_CHANGE_SOURCE_WHEN_PLAY_FAIL, isOn);
                    })
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('播放失败时尝试更换音源')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.tryChangeSource })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.tryChangeSource = isOn;
                      appConfig.setConfig(ConfigKeys.TRY_CHANGE_SOURCE_WHEN_PLAY_FAIL, isOn);
                    })
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)

              Divider()
                .DividerStyle()

              // 播放音质
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Text(this.playQualityText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.icon_tertiary')])
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.hi_waveform_2'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('播放音质')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Text(this.playQualityText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.icon_tertiary')])
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.hi_waveform_2'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.showQualityMenu = true;
              })
              .bindMenu(this.showQualityMenu, this.qualityMenu, {
                placement: this.menuPlacement(),
                onDisappear: (): void => {
                  this.showQualityMenu = false;
                }
              })

              Divider()
                .DividerStyle()

              // 首选音质不可用时
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Text(this.playQualityOrderText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.icon_tertiary')])
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.waveform_headphone_slash'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('首选音质不可用时')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Text(this.playQualityOrderText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.icon_tertiary')])
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.waveform_headphone_slash'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.showOrderMenu = true;
              })
              .bindMenu(this.showOrderMenu, this.orderMenu, {
                placement: this.menuPlacement(),
                onDisappear: (): void => {
                  this.showOrderMenu = false;
                }
              })
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
