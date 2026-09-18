import { CommonNav, titleBarOf } from '../../view/CommonNav';
import { appState } from '../../entryability/AppState';
import { appConfig, ConfigKeys } from '../../core/AppConfig';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';
import { DialogManager } from '../../utils/DialogUtils';
import { QualityKey, QUALITY_KEYS } from '../../common/model/MediaTypes';

/**
 * 下载设置页面
 * 使用移动网络下载 / 下载音质 / 首选音质不可用时 / 最大同时下载数 / 任务间隔
 * 开关类条目右侧 Toggle；选择类条目右侧当前值 + chevron，点击弹「选择器」滚轮
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

  aboutToAppear(): void {
    this.refreshTexts();
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

  /** 下载音质：TextPicker 滚轮选择，确定生效 */
  private showQualityPicker(): void {
    const options: Array<string> = [];
    for (const q of QUALITY_KEYS) {
      options.push(DownloadSettingPage.qualityLabel(q));
    }
    DialogManager.pickerTitle = '下载音质';
    DialogManager.pickerOptions = options;
    DialogManager.pickerIndex = QUALITY_KEYS.indexOf(appConfig.getDefaultDownloadQuality());
    DialogManager.pickerConfirm = (index: number): void => {
      if (index < 0 || index >= QUALITY_KEYS.length) {
        return;
      }
      appConfig.setConfig(ConfigKeys.DEFAULT_DOWNLOAD_QUALITY, QUALITY_KEYS[index]);
      this.downloadQualityText = DownloadSettingPage.qualityLabel(QUALITY_KEYS[index]);
    };
    DialogManager.OpenDialog('选择器');
  }

  /** 首选音质不可用时：TextPicker 滚轮选择，确定生效 */
  private showQualityOrderPicker(): void {
    const orders: Array<string> = ['asc', 'desc'];
    const options: Array<string> = ['下载更高音质', '下载更低音质'];
    const cur = appConfig.getDownloadQualityOrder();
    DialogManager.pickerTitle = '首选音质不可用时';
    DialogManager.pickerOptions = options;
    DialogManager.pickerIndex = orders.indexOf(cur) >= 0 ? orders.indexOf(cur) : 0;
    DialogManager.pickerConfirm = (index: number): void => {
      if (index < 0 || index >= orders.length) {
        return;
      }
      appConfig.setConfig(ConfigKeys.DOWNLOAD_QUALITY_ORDER, orders[index]);
      this.downloadQualityOrderText = DownloadSettingPage.orderLabel(orders[index]);
    };
    DialogManager.OpenDialog('选择器');
  }

  /** 最大同时下载数：TextPicker 滚轮选择（1-10），确定生效 */
  private showMaxDownloadPicker(): void {
    const values: Array<number> = [];
    const options: Array<string> = [];
    for (let n = 1; n <= 10; ++n) {
      values.push(n);
      options.push(n.toString() + ' 个');
    }
    const cur = Math.max(1, Math.min(appConfig.getMaxDownload(), 10));
    DialogManager.pickerTitle = '最大同时下载数';
    DialogManager.pickerOptions = options;
    DialogManager.pickerIndex = cur - 1;
    DialogManager.pickerConfirm = (index: number): void => {
      if (index < 0 || index >= values.length) {
        return;
      }
      appConfig.setConfig(ConfigKeys.MAX_DOWNLOAD, values[index]);
      this.maxDownloadText = values[index].toString() + ' 个';
    };
    DialogManager.OpenDialog('选择器');
  }

  /** 任务间隔：TextPicker 滚轮选择，确定生效（新任务启动时刻错开，减轻音源接口压力） */
  private showTaskIntervalPicker(): void {
    const values = DownloadSettingPage.INTERVAL_VALUES;
    const options: Array<string> = [];
    for (const v of values) {
      options.push(DownloadSettingPage.intervalLabel(v));
    }
    const cur = appConfig.getDownloadTaskInterval();
    let curIndex = values.indexOf(cur);
    if (curIndex < 0) {
      curIndex = 0;
    }
    DialogManager.pickerTitle = '任务间隔';
    DialogManager.pickerOptions = options;
    DialogManager.pickerIndex = curIndex;
    DialogManager.pickerConfirm = (index: number): void => {
      if (index < 0 || index >= values.length) {
        return;
      }
      appConfig.setConfig(ConfigKeys.DOWNLOAD_TASK_INTERVAL, values[index]);
      this.taskIntervalText = DownloadSettingPage.intervalLabel(values[index]);
    };
    DialogManager.OpenDialog('选择器');
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
                SymbolGlyph($r('sys.symbol.download'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('使用移动网络下载')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.useCellularDownload })
                  .onChange((isOn: boolean) => {
                    this.useCellularDownload = isOn;
                    appConfig.setConfig(ConfigKeys.USE_CELLULAR_NETWORK_DOWNLOAD, isOn);
                  })
              }
              .width('100%')
              .height(52)

              Divider()
                .DividerStyle()

              // 下载音质
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.hi_waveform_2'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('下载音质')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Text(this.downloadQualityText)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([$r('sys.color.icon_tertiary')])
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.showQualityPicker();
              })

              Divider()
                .DividerStyle()

              // 首选音质不可用时
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.waveform'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('首选音质不可用时')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Text(this.downloadQualityOrderText)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([$r('sys.color.icon_tertiary')])
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.showQualityOrderPicker();
              })

              Divider()
                .DividerStyle()

              // 最大同时下载数
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.square_stack_3d'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('最大同时下载数')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Text(this.maxDownloadText)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([$r('sys.color.icon_tertiary')])
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.showMaxDownloadPicker();
              })

              Divider()
                .DividerStyle()

              // 任务间隔
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.timer'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('任务间隔')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Text(this.taskIntervalText)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([$r('sys.color.icon_tertiary')])
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.showTaskIntervalPicker();
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
  .margin({ left: 32, right: 4 })
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
