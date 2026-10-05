import { appState } from '../entryability/AppState';
import { sheetTopAvoidVp } from '../utils/BreakpointUtils';
import { DialogManager } from '../utils/DialogUtils';
import { sliderImmersiveModifier } from '../utils/UiUtils';
import {
  EqualizerManager,
  EqPresetDef,
  EQ_BAND_LABELS,
  EQ_GAIN_MIN,
  EQ_GAIN_MAX
} from '../core/EqualizerManager';

/**
 * 均衡器半模态面板（@ospark/free-pcm 10 段均衡器）
 * 供播放设置页 / 播放页通过 bindSheet 复用：内置开关 + 预设 + 10 段竖向滑杆
 * 拖动滑杆实时下发解码器（PCM 管线即时生效），松手才落盘
 */
@ComponentV2
export struct EqualizerSheet {
  @Require @Param show: boolean;
  @Event onClose: () => void = (): void => {
  };
  @Event appear: () => void = (): void => {
  };
  /** 面板开关（与 manager 同步的本地副本） */
  @Local eqEnabled: boolean = EqualizerManager.getInstance().enabled;
  /** 10 段增益副本 */
  @Local eqGains: Array<number> = EqualizerManager.getInstance().getGains();
  @Local presetKey: string = EqualizerManager.getInstance().presetKey;

  private syncFromManager(): void {
    this.eqEnabled = EqualizerManager.getInstance().enabled;
    this.eqGains = EqualizerManager.getInstance().getGains();
    this.presetKey = EqualizerManager.getInstance().presetKey;
  }

  private static formatGain(g: number): string {
    return g > 0 ? '+' + g.toString() : g.toString();
  }

  /** 数值调节弹窗：输入 -12 ~ 12 整数精确设置该频段增益 */
  private showGainDialog(index: number): void {
    DialogManager.InputEqGain(EQ_BAND_LABELS[index], this.eqGains[index], (gain: number): void => {
      EqualizerManager.getInstance().previewBandGain(index, gain);
      EqualizerManager.getInstance().commitGains();
      this.syncFromManager();
    });
  }

  /** 更新本地增益副本（整体替换数组，保证拖动时数值标签实时刷新） */
  private applyGainToUi(index: number, v: number): void {
    const next: Array<number> = [];
    for (let i = 0; i < this.eqGains.length; i++) {
      next.push(i === index ? v : this.eqGains[i]);
    }
    this.eqGains = next;
  }

  build() {
    Column() {
      Column()
        .bindSheet(!!this.show, this.EqPanelBuilder(), {
          scrollSizeMode: ScrollSizeMode.CONTINUOUS,
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          dragBar: true,
          backgroundColor: $r('sys.color.background_secondary'),
          onWillDisappear: (): void => {
            this.onClose();
          },
          onWillAppear: (): void => {
            this.syncFromManager();
            this.appear()
          }
        })
    }
    .width('100%')
    .height(0)
  }

  /** 单个频段列：当前增益 + 竖向滑杆 + 频段名 + 数值调节入口 */
  @Builder
  private EqBandColumn(index: number) {
    Column({ space: 6 }) {
      Text(EqualizerSheet.formatGain(this.eqGains[index]))
        .fontSize(10)
        .fontColor($r('sys.color.font_tertiary'))
      Slider({
        value: this.eqGains[index],
        min: EQ_GAIN_MIN,
        max: EQ_GAIN_MAX,
        step: 1,
        direction: Axis.Vertical,
        reverse: true,
        style: SliderStyle.OutSet
      })
        .width(22)
        .height(150)
        .selectedColor(appState.accentColor)
        .trackColor($r('sys.color.comp_background_tertiary'))
        .blockColor(Color.White)
        .attributeModifier(sliderImmersiveModifier)
        .onChange((value: number, mode: SliderChangeMode): void => {
          const v = Math.round(value);
          this.applyGainToUi(index, v);
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            EqualizerManager.getInstance().previewBandGain(index, v);
            EqualizerManager.getInstance().commitGains();
            this.presetKey = EqualizerManager.getInstance().presetKey;
          } else {
            EqualizerManager.getInstance().previewBandGain(index, v);
          }
        })
      Text(EQ_BAND_LABELS[index])
        .fontSize(10)
        .fontColor($r('sys.color.font_secondary'))
      SymbolGlyph($r('sys.symbol.square_and_pencil'))
        .fontSize(13)
        .fontColor([$r('sys.color.font_secondary')])
        .padding({ left: 7, right: 7, top: 4, bottom: 4 })
        .borderRadius(10)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .margin({ top: 2 })
        .onClick(() => {
          this.showGainDialog(index);
        })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  /** 均衡器面板：标题 + 开关 / 预设 / 10 段滑杆 / 重置 */
  @Builder
  private EqPanelBuilder() {
    Column() {
      Text('均衡器')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ bottom: 22 })

      Row({ space: 10 }) {
        Column({ space: 2 }){
          Text('启动均衡器')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          Text('开启后将使用均衡解码管线播放，当前歌曲会自动重新加载')
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .margin({ bottom: 4 })
        }.width('100%').layoutWeight(1).alignItems(HorizontalAlign.Start)

        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.eqEnabled })
          .selectedColor(appState.accentColor)
          .onChange((isOn: boolean): void => {
            this.eqEnabled = isOn;
            EqualizerManager.getInstance().setEnabled(isOn);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
      .borderRadius(16)
      .padding(12)
      .backgroundColor($r('sys.color.comp_background_list_card'))

      // 预设横滑
      Scroll() {
        Row({ space: 8 }) {
          ForEach(EqualizerManager.PRESETS, (preset: EqPresetDef) => {
            Text(preset.label)
              .fontSize(13)
              .fontColor(this.presetKey === preset.key ?
                Color.White : $r('sys.color.font_secondary'))
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .borderRadius(16)
              .backgroundColor(this.presetKey === preset.key ?
                appState.accentColor : $r('sys.color.comp_background_tertiary'))
              .onClick(() => {
                EqualizerManager.getInstance().applyPreset(preset.key);
                this.syncFromManager();
              })
          }, (preset: EqPresetDef) => preset.key + (this.presetKey === preset.key ? '_on' : '_off'))

          if (this.presetKey === EqualizerManager.PRESET_CUSTOM) {
            Text('自定义')
              .fontSize(13)
              .fontColor(Color.White)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .borderRadius(16)
              .backgroundColor(appState.accentColor)
          }
        }
        .padding({ top: 8, bottom: 4 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .margin({ top: 4 })

      // 10 段竖向滑杆（固定 10 段手动展开：滑杆节点稳定复用，拖动流畅且数值标签实时刷新）
      Row() {
        this.EqBandColumn(0)
        this.EqBandColumn(1)
        this.EqBandColumn(2)
        this.EqBandColumn(3)
        this.EqBandColumn(4)
        this.EqBandColumn(5)
        this.EqBandColumn(6)
        this.EqBandColumn(7)
        this.EqBandColumn(8)
        this.EqBandColumn(9)
      }
      .width('100%')
      .margin({ top: 16 })
      .padding({ left: 4, right: 4 })
      .opacity(this.eqEnabled ? 1 : 0.4)
      .enabled(this.eqEnabled)

      // 重置
      Text('恢复默认')
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .borderRadius(16)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .margin({ top: 18 })
        .enabled(this.eqEnabled)
        .onClick(() => {
          EqualizerManager.getInstance().resetToDefault();
          this.syncFromManager();
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12 + sheetTopAvoidVp(), bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }
}
