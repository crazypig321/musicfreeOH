import { CommonNav, titleBarOf } from '../../view/CommonNav';
import { appState } from '../../entryability/AppState';
import { appConfig, ConfigKeys } from '../../core/AppConfig';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';
import { QualityKey, QUALITY_KEYS } from '../../common/model/MediaTypes';
import { MenuOptionEntry, OptionsMenuBuilder } from '../../view/OptionsMenu';
import { PathConst } from '../../common/PathConst';
import { pasteboard } from '@kit.BasicServicesKit';

/**
 * 下载设置页面
 * 使用移动网络下载 / 下载音质 / 首选音质不可用时 / 最大同时下载数 / 任务间隔
 * 开关类条目右侧 Toggle；选择类条目右侧当前值 + chevron，点击弹出 Menu 菜单（当前项带勾选标记，UI 同外观设置页）
 * 智感握姿：左手握持时原本行尾的开关/值镜像到行首，文本右对齐，行首图标镜像到行尾
 */
@ComponentV2
export struct DownloadSettingPage {
  scroller: Scroller = new Scroller();
  @Local useCellularDownload: boolean = appConfig.getUseCellularNetworkDownload();
  /** 下载音质展示文本（设置成功后刷新） */
  @Local downloadQualityText: string = '';
  /** 首选音质不可用时展示文本 */
  @Local downloadQualityOrderText: string = '';
  /** 最大同时下载数展示文本 */
  @Local maxDownloadText: string = '';
  /** 任务间隔展示文本 */
  @Local taskIntervalText: string = '';
  /** 任务间隔候选（秒） */
  private static readonly INTERVAL_VALUES: Array<number> = [0, 1, 2, 3, 5, 10];
  /** 各菜单手动弹出开关（bindMenu isShow 形式，便于控制 placement） */
  @Local showQualityMenu: boolean = false;
  @Local showOrderMenu: boolean = false;
  @Local showMaxMenu: boolean = false;
  @Local showIntervalMenu: boolean = false;
  /** 当前实际下载路径（公共目录解析完成后刷新） */
  @Local downloadPathText: string = '';

  aboutToAppear(): void {
    this.refreshTexts();
    this.refreshDownloadPath();
  }

  /** 下载路径：先取当前值，再等公共目录解析完成后兜底刷新（覆盖启动早期竞态） */
  private refreshDownloadPath(): void {
    this.downloadPathText = appConfig.getDownloadPath();
    PathConst.bootstrapPublicDownloadDir().then((): void => {
      this.downloadPathText = appConfig.getDownloadPath();
    });
  }

  /** 复制下载路径到剪贴板 */
  private copyDownloadPath(): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.downloadPathText);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      this.getUIContext().getPromptAction().showToast({ message: '已复制下载路径', duration: 1500 });
    }).catch((_e: Object): void => {
      this.getUIContext().getPromptAction().showToast({ message: '复制失败', duration: 1500 });
    });
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
    return order === 'asc' ? '下载更高音质' : '下载更低音质';
  }

  private static intervalLabel(sec: number): string {
    return sec === 0 ? '无间隔' : sec.toString() + ' 秒';
  }

  private refreshTexts(): void {
    this.downloadQualityText = DownloadSettingPage.qualityLabel(appConfig.getDefaultDownloadQuality());
    this.downloadQualityOrderText = DownloadSettingPage.orderLabel(appConfig.getDownloadQualityOrder());
    this.maxDownloadText = appConfig.getMaxDownload().toString() + ' 个';
    this.taskIntervalText = DownloadSettingPage.intervalLabel(appConfig.getDownloadTaskInterval());
  }

  /** 菜单弹出位置：智感握姿开启且左手握持 → 左下（拇指可达），否则条目右下 */
  private menuPlacement(): Placement {
    return appConfig.getSmartReachEnabled() && appState.holdingHand === 'left'
      ? Placement.BottomLeft : Placement.BottomRight;
  }

  /** 下载音质菜单（UI 同外观设置页：勾选标记 + 分割线 + 圆角） */
  @Builder
  private qualityMenu(): void {
    OptionsMenuBuilder(this.qualityEntries(), (value: string): void => {
      this.applyQuality(value);
    })
  }

  private qualityEntries(): Array<MenuOptionEntry> {
    const cur = appConfig.getDefaultDownloadQuality();
    const entries: Array<MenuOptionEntry> = [];
    for (const q of QUALITY_KEYS) {
      entries.push(new MenuOptionEntry(q, DownloadSettingPage.qualityLabel(q), q === cur));
    }
    return entries;
  }

  private applyQuality(value: string): void {
    for (const q of QUALITY_KEYS) {
      if (q === value) {
        appConfig.setConfig(ConfigKeys.DEFAULT_DOWNLOAD_QUALITY, q);
        this.downloadQualityText = DownloadSettingPage.qualityLabel(q);
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
    const cur = appConfig.getDownloadQualityOrder();
    const entries: Array<MenuOptionEntry> = [
      new MenuOptionEntry('asc', '下载更高音质', cur === 'asc'),
      new MenuOptionEntry('desc', '下载更低音质', cur === 'desc')
    ];
    return entries;
  }

  private applyOrder(value: string): void {
    appConfig.setConfig(ConfigKeys.DOWNLOAD_QUALITY_ORDER, value);
    this.downloadQualityOrderText = DownloadSettingPage.orderLabel(value);
  }

  /** 最大同时下载数菜单（1-10） */
  @Builder
  private maxDownloadMenu(): void {
    OptionsMenuBuilder(this.maxDownloadEntries(), (value: string): void => {
      this.applyMaxDownload(value);
    })
  }

  private maxDownloadEntries(): Array<MenuOptionEntry> {
    const cur = Math.max(1, Math.min(appConfig.getMaxDownload(), 10));
    const entries: Array<MenuOptionEntry> = [];
    for (let n = 1; n <= 10; ++n) {
      entries.push(new MenuOptionEntry(n.toString(), n.toString() + ' 个', n === cur));
    }
    return entries;
  }

  private applyMaxDownload(value: string): void {
    const n = Number.parseInt(value, 10);
    if (Number.isNaN(n) || n < 1 || n > 10) {
      return;
    }
    appConfig.setConfig(ConfigKeys.MAX_DOWNLOAD, n);
    this.maxDownloadText = n.toString() + ' 个';
  }

  /** 任务间隔菜单（新任务启动时刻错开，减轻音源接口压力） */
  @Builder
  private intervalMenu(): void {
    OptionsMenuBuilder(this.intervalEntries(), (value: string): void => {
      this.applyTaskInterval(value);
    })
  }

  private intervalEntries(): Array<MenuOptionEntry> {
    const cur = appConfig.getDownloadTaskInterval();
    const entries: Array<MenuOptionEntry> = [];
    for (const v of DownloadSettingPage.INTERVAL_VALUES) {
      entries.push(new MenuOptionEntry(v.toString(), DownloadSettingPage.intervalLabel(v), v === cur));
    }
    return entries;
  }

  private applyTaskInterval(value: string): void {
    const n = Number.parseInt(value, 10);
    if (Number.isNaN(n) || !DownloadSettingPage.INTERVAL_VALUES.includes(n)) {
      return;
    }
    appConfig.setConfig(ConfigKeys.DOWNLOAD_TASK_INTERVAL, n);
    this.taskIntervalText = DownloadSettingPage.intervalLabel(n);
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf('下载设置'),
      scroller: this.scroller,
      doubleTapToTop: true
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 12 }) {
          // 小标题
          ListItem() {
            Text('下载')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }

          ListItem() {
            Column() {
              // 使用移动网络下载
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.useCellularDownload })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.useCellularDownload = isOn;
                      appConfig.setConfig(ConfigKeys.USE_CELLULAR_NETWORK_DOWNLOAD, isOn);
                    })
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.download'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('使用移动网络下载')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.useCellularDownload })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.useCellularDownload = isOn;
                      appConfig.setConfig(ConfigKeys.USE_CELLULAR_NETWORK_DOWNLOAD, isOn);
                    })
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.download'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)

              Divider()
                .DividerStyle()

              // 下载音质
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Text(this.downloadQualityText)
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
                Text('下载音质')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Text(this.downloadQualityText)
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
                  Text(this.downloadQualityOrderText)
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
                  Text(this.downloadQualityOrderText)
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

              Divider()
                .DividerStyle()

              // 最大同时下载数
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Text(this.maxDownloadText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.icon_tertiary')])
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.square_stack_3d'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('最大同时下载数')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Text(this.maxDownloadText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.icon_tertiary')])
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.square_stack_3d'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.showMaxMenu = true;
              })
              .bindMenu(this.showMaxMenu, this.maxDownloadMenu, {
                placement: this.menuPlacement(),
                onDisappear: (): void => {
                  this.showMaxMenu = false;
                }
              })

              Divider()
                .DividerStyle()

              // 任务间隔
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Text(this.taskIntervalText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.icon_tertiary')])
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.timer'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('任务间隔')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Text(this.taskIntervalText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.icon_tertiary')])
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.timer'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.showIntervalMenu = true;
              })
              .bindMenu(this.showIntervalMenu, this.intervalMenu, {
                placement: this.menuPlacement(),
                onDisappear: (): void => {
                  this.showIntervalMenu = false;
                }
              })

              Divider()
                .DividerStyle()

              // 下载位置
              Column() {
                Row({ space: 12 }) {
                  SymbolGlyph($r('sys.symbol.folder'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                  Text('下载位置')
                    .fontSize(15)
                    .fontColor($r('sys.color.font_primary'))
                    .layoutWeight(1)
                  Text('点击复制')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                }
                .width('100%')
                .height(52)

                Text(this.downloadPathText)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                  .maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .padding({ bottom: 12 })
              }
              .width('100%')
              .onClick(() => {
                this.copyDownloadPath();
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
