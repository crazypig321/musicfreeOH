import { CommonNav, titleBarOf } from '../../view/CommonNav';
import { appState } from '../../entryability/AppState';
import { appConfig, ConfigKeys } from '../../core/AppConfig';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';
import { QualityKey, QUALITY_KEYS } from '../../common/model/MediaTypes';
import { MenuOptionEntry, OptionsMenuBuilder } from '../../view/OptionsMenu';
import { EqualizerSheet } from '../../view/EqualizerSheet';
import { EqualizerManager } from '../../core/EqualizerManager';
import { AudioEnhancePanel } from '../../audioenhance/AudioEnhancePanel';
import { AudioEnhanceManager } from '../../audioenhance/AudioEnhanceManager';

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
  /** 均衡器半模态 */
  @Local showEqSheet: boolean = false;
  /** 均衡器条目右侧摘要（关闭 / 预设名） */
  @Local eqSummaryText: string = '关闭';
  /** 空间音频与低延时半模态 */
  @Local showEnhanceSheet: boolean = false;
  /** 空间音频条目右侧摘要 */
  @Local enhanceSummaryText: string = '';

  aboutToAppear(): void {
    this.refreshQualityText();
    this.refreshEqSummary();
    this.refreshEnhanceSummary();
  }

  private refreshEnhanceSummary(): void {
    const state = AudioEnhanceManager.getInstance().refreshState();
    if (!state.spatializationApiAvailable) {
      this.enhanceSummaryText = '不支持';
      return;
    }
    if (!state.spatializationSupported) {
      this.enhanceSummaryText = '设备不支持';
      return;
    }
    this.enhanceSummaryText = state.spatializationEnabled ? '已开启' : '已关闭';
  }

  private refreshEqSummary(): void {
    this.eqSummaryText = EqualizerManager.getInstance().enabled ? EqualizerManager.getInstance().presetLabel : '关闭';
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
    }, (): void => {
      this.showQualityMenu = true;
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
    }, (): void => {
      this.showOrderMenu = true;
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

  /** 菜单设置行：图标 + 文本 + 当前值 + 右箭头，点击弹出选项菜单；智感握姿左手时值与箭头镜像到行首 */
  @Builder
  MenuRowBuilder(icon: Resource, label: string, value: string, showMenu: boolean, menu: CustomBuilder,
    onTap: () => void, onMenuDisappear: () => void) {
    Row({ space: 12 }) {
      if (appState.holdingHand === 'left') {
        Text(value)
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('sys.color.icon_tertiary')])
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
        Text(value)
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('sys.color.icon_tertiary')])
      }
      if (appState.holdingHand === 'left') {
        SymbolGlyph(icon)
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
      }
    }
    .width('100%')
    .height(52)
    .onClick(() => {
      onTap();
    })
    .bindMenu(showMenu, menu, {
      placement: this.menuPlacement(),
      onDisappear: onMenuDisappear
    })
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
              this.ToggleRowBuilder($r('sys.symbol.dot_radiowaves_left_and_right'), '使用移动网络播放',
                this.useCellularPlay, (isOn: boolean): void => {
                  this.useCellularPlay = isOn;
                  appConfig.setConfig(ConfigKeys.USE_CELLULAR_NETWORK_PLAY, isOn);
                })

              Divider()
                .DividerStyle()

              // 启动自动续播
              this.ToggleRowBuilder($r('sys.symbol.play_fill'), '启动自动续播',
                this.autoPlayWhenAppStart, (isOn: boolean): void => {
                  this.autoPlayWhenAppStart = isOn;
                  appConfig.setConfig(ConfigKeys.AUTO_PLAY_WHEN_APP_START, isOn);
                })

              Divider()
                .DividerStyle()

              // 播放失败时停止播放
              this.ToggleRowBuilder($r('sys.symbol.stop_circle'), '播放失败时停止播放',
                this.autoStopWhenError, (isOn: boolean): void => {
                  this.autoStopWhenError = isOn;
                  appConfig.setConfig(ConfigKeys.AUTO_STOP_WHEN_ERROR, isOn);
                })

              Divider()
                .DividerStyle()

              // 播放失败时尝试更换音源
              this.ToggleRowBuilder($r('sys.symbol.arrow_2_circlepath'), '播放失败时尝试更换音源',
                this.tryChangeSource, (isOn: boolean): void => {
                  this.tryChangeSource = isOn;
                  appConfig.setConfig(ConfigKeys.TRY_CHANGE_SOURCE_WHEN_PLAY_FAIL, isOn);
                })

              Divider()
                .DividerStyle()

              // 播放音质
              this.MenuRowBuilder($r('sys.symbol.hi_waveform_2'), '播放音质', this.playQualityText,
                this.showQualityMenu, this.qualityMenu,
                (): void => {
                  this.showQualityMenu = true;
                },
                (): void => {
                  this.showQualityMenu = false;
                })

              Divider()
                .DividerStyle()

              // 首选音质不可用时
              this.MenuRowBuilder($r('sys.symbol.waveform_headphone_slash'), '首选音质不可用时', this.playQualityOrderText,
                this.showOrderMenu, this.orderMenu,
                (): void => {
                  this.showOrderMenu = true;
                },
                (): void => {
                  this.showOrderMenu = false;
                })
            }
            .width('100%')
          }.ListItemStyle()

          // 均衡器（独立卡片入口，半模态调节）
          ListItem() {
            Row({ space: 12 }) {
              if (appState.holdingHand === 'left') {
                Text(this.eqSummaryText)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([$r('sys.color.icon_tertiary')])
              }
              if (appState.holdingHand !== 'left') {
                SymbolGlyph($r('sys.symbol.waveform_headphones'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
              }
              Text('均衡器')
                .fontSize(15)
                .fontColor($r('sys.color.font_primary'))
                .layoutWeight(1)
                .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
              if (appState.holdingHand !== 'left') {
                Text(this.eqSummaryText)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([$r('sys.color.icon_tertiary')])
              }
              if (appState.holdingHand === 'left') {
                SymbolGlyph($r('sys.symbol.waveform_headphones'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
              }
            }
            .width('100%')
            .height(52)
            .onClick(() => {
              this.showEqSheet = true;
            })
          }.ListItemStyle()

          // 空间音频与耳机低延时（独立卡片入口，半模态查看状态）
          ListItem() {
            Row({ space: 12 }) {
              if (appState.holdingHand === 'left') {
                Text(this.enhanceSummaryText)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([$r('sys.color.icon_tertiary')])
              }
              if (appState.holdingHand !== 'left') {
                SymbolGlyph($r('sys.symbol.earphone_16643_fill'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
              }
              Column({ space: 2 }){
                Text('空间音频与低延时')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                Text('仅作为查询入口，软件无法调节和开启')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
              }.layoutWeight(1).width('100%').alignItems(HorizontalAlign.Start)

              if (appState.holdingHand !== 'left') {
                Text(this.enhanceSummaryText)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([$r('sys.color.icon_tertiary')])
              }
              if (appState.holdingHand === 'left') {
                SymbolGlyph($r('sys.symbol.earphone_16643_fill'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
              }
            }
            .width('100%')
            .height(52)
            .onClick(() => {
              this.showEnhanceSheet = true;
            })
          }.ListItemStyle()
        }
        .ListStyle()
        .onScrollFrameBegin((offset: number) => {
          BarScrollHelper.notifyScrollDelta(this.getUIContext(), offset)
          return { offsetRemain: offset }
        })

        // 均衡器半模态（零高度挂载点）
        EqualizerSheet({
          show: this.showEqSheet,
          onClose: (): void => {
            this.showEqSheet = false;
            appState.isForegroundBlur = false
            this.refreshEqSummary();
          },
          appear:  (): void => {
            appState.isForegroundBlur = true
          }
        })

        // 空间音频与低延时半模态（零高度挂载点）
        AudioEnhancePanel({
          show: this.showEnhanceSheet,
          onClose: (): void => {
            this.showEnhanceSheet = false;
            appState.isForegroundBlur = false;
            this.refreshEnhanceSummary();
          },
          appear: (): void => {
            appState.isForegroundBlur = true;
          }
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
