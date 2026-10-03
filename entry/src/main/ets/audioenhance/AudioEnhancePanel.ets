import { appState } from '../entryability/AppState';
import { sheetTopAvoidVp } from '../utils/BreakpointUtils';
import { AudioEnhanceManager, AudioEnhanceState } from './AudioEnhanceManager';

/**
 * 空间音频与耳机低延时半模态面板
 * 供播放设置页通过 bindSheet 复用：展示当前输出设备、空间音频能力与开关状态、低延时说明
 * 三方应用无法直接开关系统空间音频与耳机低延时，面板提供状态展示与系统设置引导
 */
@ComponentV2
export struct AudioEnhancePanel {
  @Require @Param show: boolean;
  @Event onClose: () => void = (): void => {
  };
  @Event appear: () => void = (): void => {
  };

  /** 空间音频 API 是否可用 */
  @Local spatialApiAvailable: boolean = true;
  /** 当前输出设备展示名 */
  @Local deviceNameText: string = '';
  /** 当前输出设备类型标签 */
  @Local deviceTypeText: string = '';
  /** 当前输出是否为耳机 */
  @Local headphoneConnected: boolean = false;
  /** 当前设备是否支持空间音频 */
  @Local spatialSupported: boolean = false;
  /** 空间音频是否开启 */
  @Local spatialEnabled: boolean = false;

  /** 状态订阅取消函数 */
  private offStateChange: () => void = (): void => {
  };

  aboutToAppear(): void {
    // 构造期先取一次快照，首次打开即显示真实状态（不闪默认值）
    this.syncFromManager();
  }

  private applyState(state: AudioEnhanceState): void {
    this.spatialApiAvailable = state.spatializationApiAvailable;
    this.deviceNameText = state.deviceName;
    this.deviceTypeText = state.deviceTypeLabel;
    this.headphoneConnected = state.headphoneConnected;
    this.spatialSupported = state.spatializationSupported;
    this.spatialEnabled = state.spatializationEnabled;
  }

  private syncFromManager(): void {
    this.applyState(AudioEnhanceManager.getInstance().refreshState());
  }

  build() {
    Column() {
      Column()
        .bindSheet(!!this.show, this.panelBuilder(), {
          scrollSizeMode: ScrollSizeMode.CONTINUOUS,
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          dragBar: true,
          backgroundColor: $r('sys.color.background_secondary'),
          onWillDisappear: (): void => {
            this.offStateChange();
            this.offStateChange = (): void => {
            };
            this.onClose();
          },
          onWillAppear: (): void => {
            this.offStateChange = AudioEnhanceManager.getInstance()
              .onChanged((state: AudioEnhanceState): void => {
                this.applyState(state);
              });
            this.syncFromManager();
            this.appear();
          }
        })
    }
    .width('100%')
    .height(0)
  }

  /** 说明文字 */
  @Builder
  private noteText(textContent: string) {
    Text(textContent)
      .fontSize(12)
      .fontColor($r('sys.color.font_tertiary'))
      .lineHeight(18)
      .margin({ top: 10 })
  }

  /** 面板：空间音频状态 / 耳机低延时说明 */
  @Builder
  private panelBuilder() {
    Column() {
      Text('空间音频与耳机低延时')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ bottom: 22 })

      // 空间音频
      Column({ space: 12 }) {
        Text('空间音频')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')

        Row() {
          Text('当前输出设备')
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
          Blank()
          Text(this.deviceNameText)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        if (this.spatialApiAvailable) {
          Row() {
            Text('设备支持')
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
            Text(this.spatialSupported ? '支持' : '不支持')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          Row() {
            Text('空间音频')
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
            Text(this.spatialEnabled ? '已开启' : '已关闭')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          this.noteText('空间音频开关由系统统一控制，可在控制中心或系统设置的音频选项中开启；搭配支持空间音频的耳机可获得更沉浸的听感。')
        } else {
          this.noteText('当前系统不支持空间音频能力，无法查询状态。')
        }
      }
      .width('100%')
      .borderRadius(16)
      .padding(12)
      .backgroundColor($r('sys.color.comp_background_list_card'))
      .alignItems(HorizontalAlign.Start)

      // 耳机低延时
      Column({ space: 12 }) {
        Text('耳机低延时')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')

        Row() {
          Text('当前输出')
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
          Blank()
          Text(this.headphoneConnected ? this.deviceNameText : this.deviceTypeText)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        this.noteText('耳机低延时模式由耳机与系统侧控制，应用无法直接开关。蓝牙耳机可在系统「设置 > 蓝牙」的设备详情中查看低延时选项；有线耳机自身时延较低。')
      }
      .width('100%')
      .borderRadius(16)
      .padding(12)
      .backgroundColor($r('sys.color.comp_background_list_card'))
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 12 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12 + sheetTopAvoidVp(), bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }
}
