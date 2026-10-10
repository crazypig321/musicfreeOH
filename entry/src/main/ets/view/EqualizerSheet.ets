import { appState } from '../entryability/AppState';
import { sheetPreferType, sheetTopAvoidVp } from '../utils/BreakpointUtils';
import { DialogManager } from '../utils/DialogUtils';
import { sliderImmersiveModifier } from '../utils/UiUtils';
import {
  EqualizerManager,
  EqPresetDef,
  EqUserPreset,
  EQ_BAND_LABELS,
  EQ_GAIN_MIN,
  EQ_GAIN_MAX
} from '../core/EqualizerManager';

/** 用户预设懒加载数据源（整体替换并通知刷新） */
class EqUserPresetDataSource implements IDataSource {
  private items: Array<EqUserPreset> = [];
  private listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): EqUserPreset {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) === -1) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const i = this.listeners.indexOf(listener);
    if (i >= 0) {
      this.listeners.splice(i, 1);
    }
  }

  /** 整体替换数据并通知刷新 */
  reload(items: Array<EqUserPreset>): void {
    this.items = items;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }
}

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
  /** 用户保存的预设列表 */
  @Local userPresets: Array<EqUserPreset> = EqualizerManager.getInstance().getUserPresets();
  /** 用户预设懒加载数据源 */
  private presetSource: EqUserPresetDataSource = new EqUserPresetDataSource();

  private syncFromManager(): void {
    this.eqEnabled = EqualizerManager.getInstance().enabled;
    this.eqGains = EqualizerManager.getInstance().getGains();
    this.presetKey = EqualizerManager.getInstance().presetKey;
    this.userPresets = EqualizerManager.getInstance().getUserPresets();
    this.presetSource.reload(this.userPresets);
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

  /** 格式化增益摘要（10 段数值空格分隔，正数带 + 号） */
  private static formatGainsSummary(gains: Array<number>): string {
    const parts: Array<string> = [];
    for (let i = 0; i < gains.length; i++) {
      const g = gains[i];
      parts.push(g >= 0 ? '+' + g.toString() : g.toString());
    }
    return parts.join('  ');
  }

  /** 弹出输入框保存当前均衡器参数为用户预设 */
  private showSavePresetDialog(): void {
    DialogManager.renameValue = '';
    DialogManager.renameConfirm = (name: string): void => {
      const trimmed = name.trim();
      if (trimmed.length === 0) {
        return;
      }
      EqualizerManager.getInstance().saveUserPreset(trimmed, EqualizerManager.getInstance().getGains());
      this.syncFromManager();
    };
    DialogManager.OpenDialog('重命名');
  }

  /** 确认删除用户预设 */
  private confirmDeletePreset(name: string): void {
    DialogManager.ConfirmDelete('确定删除预设「' + name + '」？', (): void => {
      EqualizerManager.getInstance().deleteUserPreset(name);
      this.syncFromManager();
    });
  }

  /** 应用用户预设 */
  private applyUserPresetItem(name: string): void {
    EqualizerManager.getInstance().applyUserPreset(name);
    this.syncFromManager();
  }

  /** 判断预设是否为当前激活（增益完全一致） */
  private isPresetActive(gains: Array<number>): boolean {
    if (this.eqGains.length !== gains.length) {
      return false;
    }
    for (let i = 0; i < gains.length; i++) {
      if (this.eqGains[i] !== gains[i]) {
        return false;
      }
    }
    return true;
  }

  /** 弹出输入框编辑预设名称 */
  private showEditPresetDialog(currentName: string): void {
    DialogManager.renameValue = currentName;
    DialogManager.renameConfirm = (name: string): void => {
      const trimmed = name.trim();
      if (trimmed.length === 0 || trimmed === currentName) {
        return;
      }
      EqualizerManager.getInstance().renameUserPreset(currentName, trimmed);
      this.syncFromManager();
    };
    DialogManager.OpenDialog('重命名');
  }

  build() {
    Column() {
      Column()
        .bindSheet(!!this.show, this.EqPanelBuilder(), {
          scrollSizeMode: ScrollSizeMode.CONTINUOUS,
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          dragBar: true, preferType: sheetPreferType(),
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

      // 恢复默认 + 保存
      Row({ space: 10 }) {
        Text('恢复默认')
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(16)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .enabled(this.eqEnabled)
          .onClick(() => {
            EqualizerManager.getInstance().resetToDefault();
            this.syncFromManager();
          })
        Text('保存')
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(16)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .enabled(this.eqEnabled)
          .onClick(() => {
            this.showSavePresetDialog();
          })
      }
      .margin({ top: 18 })

      Text('我的预设').fontSize(14) .fontColor($r('sys.color.font_tertiary')).fontWeight(FontWeight.Medium)
        .margin({ top: 14, bottom: 10 })
      // 用户保存的预设列表（懒加载）
      if (this.userPresets.length > 0) {
        List({ space: 8 }) {
          LazyForEach(this.presetSource, (preset: EqUserPreset) => {
            ListItem() {
              Row({ space: 10 }) {
                Text(preset.name)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.isPresetActive(preset.gains) ?
                    Color.White : $r('sys.color.font_primary'))

                Blank()
                Text('编辑')
                  .fontSize(12)
                  .fontColor(this.isPresetActive(preset.gains) ? Color.White : $r('sys.color.font_secondary'))
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .borderRadius(6)
                  .backgroundColor(this.isPresetActive(preset.gains) ?
                    '#33ffffff' : $r('sys.color.comp_background_tertiary'))
                  .onClick(() => {
                    this.showEditPresetDialog(preset.name);
                  })
                Text('删除')
                  .fontSize(12)
                  .fontColor(this.isPresetActive(preset.gains) ? Color.White : $r('sys.color.font_secondary'))
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .borderRadius(6)
                  .backgroundColor(this.isPresetActive(preset.gains) ?
                    '#33ffffff' : $r('sys.color.comp_background_tertiary'))
                  .onClick(() => {
                    this.confirmDeletePreset(preset.name);
                  })
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)
              .alignItems(VerticalAlign.Center)
              .borderRadius(16)
              .padding(12)
              .backgroundColor(this.isPresetActive(preset.gains) ?
                appState.accentColor : $r('sys.color.comp_background_list_card'))
              .onClick(() => {
                this.applyUserPresetItem(preset.name);
              })
            }
          }, (preset: EqUserPreset) => preset.name + '_' + preset.gains.join(','))
        }
        .width('100%')
        .height(Math.min(this.userPresets.length, 6) * 68)
        .enabled(this.eqEnabled)
      }else{
        Text('暂无自定义预设,请调整参数后点击保存').fontSize(12) .fontColor($r('sys.color.font_tertiary')).fontWeight(FontWeight.Medium)
          .width('100%').textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12 + sheetTopAvoidVp(), bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }
}
