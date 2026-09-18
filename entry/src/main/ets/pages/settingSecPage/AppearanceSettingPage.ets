import { CommonNav, titleBarOf } from '../../view/CommonNav';
import { appState, THEME_COLOR_OPTIONS, themeColorOf } from '../../entryability/AppState';
import { appConfig, ConfigKeys } from '../../core/AppConfig';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';
import { DialogManager } from '../../utils/DialogUtils';
import { ContextHolder } from '../../common/ContextHolder';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hdsMaterial } from '@kit.UIDesignKit';

/**
 * 外观设置页面
 * 主题色 / 深色模式 / 沉浸光感材质 / 适人握持 / 动画
 * 选择类条目右侧当前值 + chevron，点击弹「选择器」滚轮；适人握持为开关
 */
@ComponentV2
export struct AppearanceSettingPage {
  scroller: Scroller = new Scroller();
  @Local themeColorName: string = '';
  @Local themeColorDot: ResourceColor = $r('sys.color.icon_emphasize');
  @Local colorModeText: string = '';
  @Local materialText: string = '';
  @Local barLayoutMode: boolean = true;
  @Local animText: string = '';

  aboutToAppear(): void {
    this.refreshThemeColor();
    this.refreshColorModeText();
    this.refreshMaterialText();
    this.barLayoutMode = appConfig.getAppearanceBarLayoutMode() === 1;
    this.refreshAnimText();
  }

  private static colorModeLabel(mode: string): string {
    if (mode === 'light') {
      return '浅色';
    }
    if (mode === 'dark') {
      return '深色';
    }
    return '跟随系统';
  }

  private static materialLabel(type: string): string {
    if (type === 'adaptive') {
      return '跟随系统';
    }
    if (type === 'none') {
      return '关闭';
    }
    return '沉浸光感';
  }

  private static animLabel(expand: boolean, tab: boolean): string {
    if (expand && tab) {
      return '全部开启';
    }
    if (expand) {
      return '仅播放页展开';
    }
    if (tab) {
      return '仅Tab切换';
    }
    return '全部关闭';
  }

  private refreshThemeColor(): void {
    const value = appConfig.getAppearanceThemeColor();
    this.themeColorDot = themeColorOf(value);
    for (const opt of THEME_COLOR_OPTIONS) {
      if (opt.value === value) {
        this.themeColorName = opt.name;
        return;
      }
    }
    this.themeColorName = '跟随系统';
  }

  private refreshColorModeText(): void {
    this.colorModeText = AppearanceSettingPage.colorModeLabel(appConfig.getAppearanceColorMode());
  }

  private refreshMaterialText(): void {
    this.materialText = AppearanceSettingPage.materialLabel(appConfig.getAppearanceMaterialType());
  }

  private refreshAnimText(): void {
    this.animText = AppearanceSettingPage.animLabel(appConfig.getPlayerExpandAnim(), appConfig.getTabSwitchAnim());
  }

  /** 主题色：TextPicker 滚轮选择，确定后全局强调色立即生效 */
  private showThemeColorPicker(): void {
    const options: Array<string> = [];
    let curIndex = 0;
    const curValue = appConfig.getAppearanceThemeColor();
    for (let i = 0; i < THEME_COLOR_OPTIONS.length; ++i) {
      options.push(THEME_COLOR_OPTIONS[i].name);
      if (THEME_COLOR_OPTIONS[i].value === curValue) {
        curIndex = i;
      }
    }
    DialogManager.pickerTitle = '主题色';
    DialogManager.pickerOptions = options;
    DialogManager.pickerIndex = curIndex;
    DialogManager.pickerConfirm = (index: number): void => {
      if (index < 0 || index >= THEME_COLOR_OPTIONS.length) {
        return;
      }
      const opt = THEME_COLOR_OPTIONS[index];
      appConfig.setConfig(ConfigKeys.APPEARANCE_THEME_COLOR, opt.value);
      appState.accentColor = themeColorOf(opt.value);
      this.refreshThemeColor();
    };
    DialogManager.OpenDialog('选择器');
  }

  /** 深色模式：跟随系统 / 浅色 / 深色，立即应用 */
  private showColorModePicker(): void {
    const modes: Array<string> = ['system', 'light', 'dark'];
    const options: Array<string> = ['跟随系统', '浅色', '深色'];
    DialogManager.pickerTitle = '深色模式';
    DialogManager.pickerOptions = options;
    DialogManager.pickerIndex = modes.indexOf(appConfig.getAppearanceColorMode());
    DialogManager.pickerConfirm = (index: number): void => {
      if (index < 0 || index >= modes.length) {
        return;
      }
      appConfig.setConfig(ConfigKeys.APPEARANCE_COLOR_MODE, modes[index]);
      try {
        let colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
        if (modes[index] === 'light') {
          colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
        } else if (modes[index] === 'dark') {
          colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
        }
        ContextHolder.get().getApplicationContext().setColorMode(colorMode);
      } catch (e) {
        // 静默失败
      }
      this.refreshColorModeText();
    };
    DialogManager.OpenDialog('选择器');
  }

  /** 沉浸光感材质：沉浸光感 / 跟随系统 / 关闭，立即生效 */
  private showMaterialPicker(): void {
    const types: Array<string> = ['immersive', 'adaptive', 'none'];
    const options: Array<string> = ['沉浸光感', '跟随系统', '关闭'];
    DialogManager.pickerTitle = '沉浸光感材质';
    DialogManager.pickerOptions = options;
    DialogManager.pickerIndex = types.indexOf(appConfig.getAppearanceMaterialType());
    DialogManager.pickerConfirm = (index: number): void => {
      if (index < 0 || index >= types.length) {
        return;
      }
      appConfig.setConfig(ConfigKeys.APPEARANCE_MATERIAL_TYPE, types[index]);
      if (types[index] === 'adaptive') {
        appState.materialType = hdsMaterial.MaterialType.ADAPTIVE;
      } else if (types[index] === 'none') {
        appState.materialType = hdsMaterial.MaterialType.NONE;
      } else {
        appState.materialType = hdsMaterial.MaterialType.IMMERSIVE;
      }
      this.refreshMaterialText();
    };
    DialogManager.OpenDialog('选择器');
  }

  /** 动画：播放页展开动画 + Tab 切换动画的组合选择 */
  private showAnimPicker(): void {
    const options: Array<string> = ['全部开启', '仅播放页展开', '仅Tab切换', '全部关闭'];
    const expand = appConfig.getPlayerExpandAnim();
    const tab = appConfig.getTabSwitchAnim();
    let curIndex = 3;
    if (expand && tab) {
      curIndex = 0;
    } else if (expand) {
      curIndex = 1;
    } else if (tab) {
      curIndex = 2;
    }
    DialogManager.pickerTitle = '动画';
    DialogManager.pickerOptions = options;
    DialogManager.pickerIndex = curIndex;
    DialogManager.pickerConfirm = (index: number): void => {
      if (index < 0 || index >= options.length) {
        return;
      }
      const expandOn = index === 0 || index === 1;
      const tabOn = index === 0 || index === 2;
      appConfig.setConfig(ConfigKeys.APPEARANCE_PLAYER_EXPAND_ANIM, expandOn);
      appConfig.setConfig(ConfigKeys.APPEARANCE_TAB_SWITCH_ANIM, tabOn);
      appState.tabSwitchAnim = tabOn;
      this.refreshAnimText();
    };
    DialogManager.OpenDialog('选择器');
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf('外观设置'),
      scroller: this.scroller,
      doubleTapToTop: true
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 12 }) {
          // 小标题
          ListItem() {
            Text('外观')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }

          ListItem() {
            Column() {
              // 主题色
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.paintpalette'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('主题色')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Column()
                  .width(16)
                  .height(16)
                  .borderRadius(8)
                  .backgroundColor(this.themeColorDot)
                Text(this.themeColorName)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([$r('sys.color.icon_tertiary')])
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.showThemeColorPicker();
              })

              Divider()
                .DividerStyle()

              // 深色模式
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.moon'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('深色模式')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Text(this.colorModeText)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([$r('sys.color.icon_tertiary')])
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.showColorModePicker();
              })

              Divider()
                .DividerStyle()

              // 沉浸光感材质
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.camera_filters'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('沉浸光感材质')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Text(this.materialText)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([$r('sys.color.icon_tertiary')])
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.showMaterialPicker();
              })

              Divider()
                .DividerStyle()

              // 适人握持
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.rectangle_stack'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Column({ space: 2 }) {
                  Text('适人握持')
                    .fontSize(15)
                    .fontColor($r('sys.color.font_primary'))
                  Text('底部导航与迷你播控上下两排布局')
                    .fontSize(12)
                    .fontColor($r('sys.color.font_tertiary'))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.barLayoutMode })
                  .onChange((isOn: boolean) => {
                    this.barLayoutMode = isOn;
                    appConfig.setConfig(ConfigKeys.APPEARANCE_BAR_LAYOUT_MODE, isOn ? 1 : 0);
                    appState.hdsBarLayoutMode = isOn ? 1 : 0;
                  })
              }
              .width('100%')
              .height(60)

              Divider()
                .DividerStyle()

              // 动画
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.wand_and_stars'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('动画')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Text(this.animText)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([$r('sys.color.icon_tertiary')])
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.showAnimPicker();
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
