import { CommonNav, titleBarOf } from '../../view/CommonNav';
import { appState } from '../../entryability/AppState';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';
import { floatLyricManager } from '../../core/FloatLyricManager';
import { HdsColorPicker, HdsColorPickerTabType } from '@kit.UIDesignKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { HSBColorPicker } from '@keke/color-picker';
import { sheetTopAvoidVp } from '../../utils/BreakpointUtils';

/** 背景样式选项 */
class BgOption {
  key: string = '';
  label: string = '';

  constructor(key: string, label: string) {
    this.key = key;
    this.label = label;
  }
}

/**
 * 开关行（含智感握姿镜像：左手时开关在行首、文本右对齐、图标在行尾）
 */
@ComponentV2
struct FloatToggleRow {
  @Param icon: Resource = $r('sys.symbol.gearshape');
  @Param title: string = '';
  @Param isOn: boolean = false;
  @Param rowEnabled: boolean = true;
  @Event onChange: (isOn: boolean) => void;

  build() {
    Row({ space: 12 }) {
      if (appState.holdingHand === 'left') {
        Toggle({ type: ToggleType.Switch, isOn: this.isOn })
          .selectedColor(appState.accentColor)
          .enabled(this.rowEnabled)
          .onChange((isOn: boolean) => {
            this.onChange(isOn);
          })
      }
      if (appState.holdingHand !== 'left') {
        SymbolGlyph(this.icon)
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
      }
      Text(this.title)
        .fontSize(15)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
        .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
      if (appState.holdingHand !== 'left') {
        Toggle({ type: ToggleType.Switch, isOn: this.isOn })
          .selectedColor(appState.accentColor)
          .enabled(this.rowEnabled)
          .onChange((isOn: boolean) => {
            this.onChange(isOn);
          })
      }
      if (appState.holdingHand === 'left') {
        SymbolGlyph(this.icon)
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
      }
    }
    .width('100%')
    .height(52)
    .opacity(this.rowEnabled ? 1 : 0.4)
  }
}

/**
 * 悬浮歌词设置页面
 * 开关/翻译/字号/窗口大小/字体颜色/背景样式；
 * 样式改动实时生效（经 floatLyricManager @Trace 状态驱动画中画刷新）
 */
@ComponentV2
export struct FloatLyricSettingPage {
  scroller: Scroller = new Scroller();
  /** 开关镜像：open() 为异步，失败时需回弹开关 */
  @Local enabledOn: boolean = floatLyricManager.enabled;
  /** 取色器当前色 */
  @Local pickerColor: string = floatLyricManager.color;
  /** 低 API 取色器半模态开关 */
  @Local showColorSheet: boolean = false;
  private bgOptions: Array<BgOption> = [
    new BgOption('dark', '深色'),
    new BgOption('light', '浅色'),
    new BgOption('cover', '封面')
  ];

  aboutToAppear(): void {
    this.pickerColor = floatLyricManager.color;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // 忽略
    }
  }

  /** 应用字体颜色 */
  private applyColor(hex: string): void {
    this.pickerColor = hex;
    floatLyricManager.setColor(hex);
  }

  /** 低 API 取色器半模态 */
  @Builder
  ColorSheetBuilder() {
    Column() {
      HSBColorPicker({
        color: this.pickerColor,
        radius: 8,
        showAlpha: true,
        predefine: ['#FFFFFFFF', '#FF000000', '#FFFFD700', '#FFFF69B4',
          '#FF00E5E5', '#FFFF8C00', '#FF00FF00', '#FF0000FF'],
        onChange: (value: string): void => {
          this.applyColor(value);
        }
      })
        .height(270)
    }
    .padding({ left: 20, right: 20, top: 12 + sheetTopAvoidVp(), bottom: 32 })
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf('悬浮歌词设置'),
      scroller: this.scroller,
      doubleTapToTop: true
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 12 }) {
          // 小标题
          ListItem() {
            Text('桌面歌词')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }

          // 开启桌面歌词
          ListItem() {
            FloatToggleRow({
              icon: $r('sys.symbol.text_bubble_left_2'),
              title: '开启桌面歌词',
              isOn: this.enabledOn,
              onChange: (isOn: boolean): void => {
                if (isOn) {
                  this.enabledOn = true;
                  floatLyricManager.open().then((ok: boolean): void => {
                    if (!ok) {
                      this.enabledOn = false;
                      this.showToast('画中画不可用，请检查系统设置');
                    }
                  });
                } else {
                  this.enabledOn = false;
                  floatLyricManager.close().catch((): void => {
                  });
                }
              }
            })
          }.ListItemStyle()

          // 翻译行
          ListItem() {
            FloatToggleRow({
              icon: $r('sys.symbol.translate'),
              title: '显示翻译',
              isOn: floatLyricManager.showTranslation,
              onChange: (isOn: boolean): void => {
                floatLyricManager.setShowTranslation(isOn);
              }
            })
          }.ListItemStyle()

          // 字号
          ListItem() {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.textformat'))
                .fontSize(20)
                .fontColor([$r('sys.color.icon_secondary')])
              Text('字号')
                .fontSize(15)
                .fontColor($r('sys.color.font_primary'))
              Slider({
                value: floatLyricManager.fontSize,
                min: 12,
                max: 32,
                step: 1
              })
                .layoutWeight(1)
                .selectedColor(appState.accentColor)
                .onChange((value: number, _mode: SliderChangeMode) => {
                  floatLyricManager.setFontSize(Math.round(value));
                })
              Text(`${floatLyricManager.fontSize}fp`)
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
                .width(38)
                .textAlign(TextAlign.End)
            }
            .width('100%')
            .height(52)
          }.ListItemStyle()

          // 窗口大小
          ListItem() {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.fullscreen'))
                .fontSize(20)
                .fontColor([$r('sys.color.icon_secondary')])
              Text('窗口大小')
                .fontSize(15)
                .fontColor($r('sys.color.font_primary'))
              Slider({
                value: floatLyricManager.windowSize,
                min: 60,
                max: 200,
                step: 10
              })
                .layoutWeight(1)
                .selectedColor(appState.accentColor)
                .onChange((value: number, _mode: SliderChangeMode) => {
                  floatLyricManager.setWindowSize(Math.round(value));
                })
              Text(`${floatLyricManager.windowSize}`)
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
                .width(38)
                .textAlign(TextAlign.End)
            }
            .width('100%')
            .height(52)
          }.ListItemStyle()

          // 字体颜色（取色器，同外观设置主题色组件）
          ListItem() {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.paintpalette'))
                .fontSize(20)
                .fontColor([$r('sys.color.icon_secondary')])
              Text('字体颜色')
                .fontSize(15)
                .fontColor($r('sys.color.font_primary'))
                .layoutWeight(1)
              Row() {
                if (deviceInfo.apiAvailable('26.0.0')) {
                  HdsColorPicker({
                    initialColor: this.pickerColor,
                    onColorSelected: (selectedColor: string): void => {
                      this.applyColor(selectedColor);
                    },
                    options: { tabs: [HdsColorPickerTabType.GRID] }
                  })
                } else {
                  Row().width(20).height(20).borderRadius(10)
                    .backgroundColor(this.pickerColor)
                    .onClick(() => {
                      this.showColorSheet = true;
                    })
                    .bindSheet(!!this.showColorSheet, this.ColorSheetBuilder(), {
                      dragBar: true,
                      onWillDisappear: () => {
                        this.showColorSheet = false;
                      }
                    })
                }
              }
            }
            .width('100%')
            .height(52)
          }.ListItemStyle()

          // 背景样式
          ListItem() {
            Column({ space: 12 }) {
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.square_grid_2x2'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('背景样式')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
              }
              .width('100%')

              Row({ space: 10 }) {
                ForEach(this.bgOptions, (opt: BgOption) => {
                  Text(opt.label)
                    .fontSize(13)
                    .fontColor(floatLyricManager.bg === opt.key ? Color.White :
                      $r('sys.color.font_primary'))
                    .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                    .borderRadius(15)
                    .backgroundColor(floatLyricManager.bg === opt.key ? appState.accentColor :
                      $r('sys.color.comp_background_list_card'))
                    .onClick(() => {
                      floatLyricManager.setBg(opt.key);
                    })
                }, (opt: BgOption) => opt.key)
              }
              .width('100%')
              .justifyContent(FlexAlign.End)
            }
            .width('100%')
            .padding({ top: 4, bottom: 8 })
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
