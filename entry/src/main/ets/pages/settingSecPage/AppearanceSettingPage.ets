import { CommonNav, titleBarOf } from '../../view/CommonNav';
import { appState, themeColorOf } from '../../entryability/AppState';
import { appConfig, ConfigKeys } from '../../core/AppConfig';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';
import { SmartReach } from '../../utils/SmartReach';
import { ContextHolder } from '../../common/ContextHolder';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hdsMaterial, HdsColorPicker, HdsColorPickerTabType } from '@kit.UIDesignKit';
import { window } from '@kit.ArkUI';
import { MenuOptionEntry, OptionsMenuBuilder } from '../../view/OptionsMenu';

/**
 * 外观设置页面
 * 卡片一：主题色（HdsColorPicker 取色器内嵌条目右侧）/ 深色模式 / 沉浸光感材质 / 动画
 * 卡片二：智感握姿 / 屏幕方向
 * 选择类条目点击弹出 Menu 菜单（当前项带勾选标记，UI 参考 ting_reader；
 * 智感握姿开启且左手握持时菜单从左侧弹出，否则默认条目右侧下方）
 * 智感握姿：左手握持时行首图标镜像到行尾、文本右对齐（原理同歌单详情页条目）
 */
@ComponentV2
export struct AppearanceSettingPage {
  scroller: Scroller = new Scroller();
  /** 主题色取色器当前色 */
  @Local pickerColor: string = '';
  @Local smartReachEnabled: boolean = false;
  @Local colorModeText: string = '';
  @Local materialText: string = '';
  @Local orientationText: string = '';
  @Local animText: string = '';
  /** 各菜单手动弹出开关（bindMenu isShow 形式，便于控制 placement） */
  @Local showColorModeMenu: boolean = false;
  @Local showMaterialMenu: boolean = false;
  @Local showOrientationMenu: boolean = false;
  @Local showAnimMenu: boolean = false;

  aboutToAppear(): void {
    const stored = appConfig.getAppearanceThemeColor();
    this.pickerColor = stored.length > 0 ? stored : '#007DFF';
    this.smartReachEnabled = appConfig.getSmartReachEnabled();
    this.refreshColorModeText();
    this.refreshMaterialText();
    this.refreshOrientationText();
    this.refreshAnimText();
  }

  /** 菜单弹出位置：智感握姿开启且左手握持 → 左侧（拇指可达），否则条目右侧下方 */
  private menuPlacement(): Placement {
    return this.smartReachEnabled && appState.holdingHand === 'left'
      ? Placement.BottomLeft : Placement.BottomRight;
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

  private static materialLabel(type: string, level: string): string {
    if (type === 'adaptive') {
      return '跟随系统';
    }
    if (type === 'none') {
      return '关闭';
    }
    if (level === 'exquisite') {
      return '沉浸光感·精致';
    }
    if (level === 'gentle') {
      return '沉浸光感·轻柔';
    }
    if (level === 'smooth') {
      return '沉浸光感·顺滑';
    }
    return '沉浸光感';
  }

  private static orientationLabel(orientation: string): string {
    if (orientation === 'portrait') {
      return '竖屏';
    }
    if (orientation === 'landscape') {
      return '横屏';
    }
    return '跟随系统';
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

  private refreshColorModeText(): void {
    this.colorModeText = AppearanceSettingPage.colorModeLabel(appConfig.getAppearanceColorMode());
  }

  private refreshMaterialText(): void {
    this.materialText = AppearanceSettingPage.materialLabel(
      appConfig.getAppearanceMaterialType(), appConfig.getAppearanceMaterialLevel());
  }

  private refreshOrientationText(): void {
    this.orientationText = AppearanceSettingPage.orientationLabel(appConfig.getAppearanceOrientation());
  }

  private refreshAnimText(): void {
    this.animText = AppearanceSettingPage.animLabel(appConfig.getPlayerExpandAnim(), appConfig.getTabSwitchAnim());
  }

  /** 通用菜单 Builder：复用共享 OptionsMenuBuilder，kind 分发应用逻辑 */
  @Builder
  private menuOf(entries: Array<MenuOptionEntry>, kind: string): void {
    OptionsMenuBuilder(entries, (value: string): void => {
      this.onMenuPick(kind, value);
    })
  }

  /** 菜单选中分发 */
  private onMenuPick(kind: string, value: string): void {
    if (kind === 'colorMode') {
      this.applyColorMode(value);
    } else if (kind === 'material') {
      this.applyMaterial(value);
    } else if (kind === 'orientation') {
      this.applyOrientation(value);
    } else if (kind === 'anim') {
      this.applyAnim(value);
    }
  }

  /** 深色模式菜单 */
  @Builder
  private colorModeMenu(): void {
    this.menuOf(this.colorModeEntries(), 'colorMode')
  }

  private applyColorMode(value: string): void {
    appConfig.setConfig(ConfigKeys.APPEARANCE_COLOR_MODE, value);
    try {
      let colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      if (value === 'light') {
        colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      } else if (value === 'dark') {
        colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      }
      ContextHolder.get().getApplicationContext().setColorMode(colorMode);
    } catch (e) {
      // 静默失败
    }
    this.refreshColorModeText();
  }

  private colorModeEntries(): Array<MenuOptionEntry> {
    const modes: Array<string> = ['system', 'light', 'dark'];
    const labels: Array<string> = ['跟随系统', '浅色', '深色'];
    const cur = appConfig.getAppearanceColorMode();
    const entries: Array<MenuOptionEntry> = [];
    for (let i = 0; i < modes.length; ++i) {
      entries.push(new MenuOptionEntry(modes[i], labels[i], modes[i] === cur));
    }
    return entries;
  }

  /** 沉浸光感材质菜单 */
  @Builder
  private materialMenu(): void {
    this.menuOf(this.materialEntries(), 'material')
  }

  private applyMaterial(value: string): void {
    if (value === 'adaptive') {
      appConfig.setConfig(ConfigKeys.APPEARANCE_MATERIAL_TYPE, 'adaptive');
      appState.materialType = hdsMaterial.MaterialType.ADAPTIVE;
    } else {
      // 沉浸光感材质等级：exquisite 精致 / gentle 轻柔 / smooth 顺滑
      appConfig.setConfig(ConfigKeys.APPEARANCE_MATERIAL_TYPE, 'immersive');
      appConfig.setConfig(ConfigKeys.APPEARANCE_MATERIAL_LEVEL, value);
      appState.materialType = hdsMaterial.MaterialType.IMMERSIVE;
      if (value === 'exquisite') {
        appState.materialLevel = hdsMaterial.MaterialLevel.EXQUISITE;
      } else if (value === 'gentle') {
        appState.materialLevel = hdsMaterial.MaterialLevel.GENTLE;
      } else {
        appState.materialLevel = hdsMaterial.MaterialLevel.SMOOTH;
      }
    }
    this.refreshMaterialText();
  }

  private materialEntries(): Array<MenuOptionEntry> {
    const type = appConfig.getAppearanceMaterialType();
    const level = appConfig.getAppearanceMaterialLevel();
    const entries: Array<MenuOptionEntry> = [
      new MenuOptionEntry('adaptive', '跟随系统', type === 'adaptive'),
      new MenuOptionEntry('exquisite', '精致', type === 'immersive' && level === 'exquisite'),
      new MenuOptionEntry('gentle', '轻柔', type === 'immersive' && level === 'gentle'),
      new MenuOptionEntry('smooth', '顺滑', type === 'immersive' && level === 'smooth')
    ];
    return entries;
  }

  /** 屏幕方向菜单 */
  @Builder
  private orientationMenu(): void {
    this.menuOf(this.orientationEntries(), 'orientation')
  }

  private applyOrientation(value: string): void {
    appConfig.setConfig(ConfigKeys.APPEARANCE_ORIENTATION, value);
    window.getLastWindow(ContextHolder.get()).then((win: window.Window): Promise<void> => {
      let orientation = window.Orientation.UNSPECIFIED;
      if (value === 'portrait') {
        orientation = window.Orientation.PORTRAIT;
      } else if (value === 'landscape') {
        orientation = window.Orientation.LANDSCAPE;
      }
      return win.setPreferredOrientation(orientation);
    }).catch((): void => {
      // 静默失败
    });
    this.refreshOrientationText();
  }

  private orientationEntries(): Array<MenuOptionEntry> {
    const values: Array<string> = ['system', 'portrait', 'landscape'];
    const labels: Array<string> = ['跟随系统', '竖屏', '横屏'];
    const cur = appConfig.getAppearanceOrientation();
    const entries: Array<MenuOptionEntry> = [];
    for (let i = 0; i < values.length; ++i) {
      entries.push(new MenuOptionEntry(values[i], labels[i], values[i] === cur));
    }
    return entries;
  }

  /** 动画菜单：播放页展开 + Tab 切换组合 */
  @Builder
  private animMenu(): void {
    this.menuOf(this.animEntries(), 'anim')
  }

  private applyAnim(value: string): void {
    const expandOn = value === 'all' || value === 'expand';
    const tabOn = value === 'all' || value === 'tab';
    appConfig.setConfig(ConfigKeys.APPEARANCE_PLAYER_EXPAND_ANIM, expandOn);
    appConfig.setConfig(ConfigKeys.APPEARANCE_TAB_SWITCH_ANIM, tabOn);
    appState.tabSwitchAnim = tabOn;
    this.refreshAnimText();
  }

  private animEntries(): Array<MenuOptionEntry> {
    const values: Array<string> = ['all', 'expand', 'tab', 'none'];
    const labels: Array<string> = ['全部开启', '仅播放页展开', '仅Tab切换', '全部关闭'];
    const expand = appConfig.getPlayerExpandAnim();
    const tab = appConfig.getTabSwitchAnim();
    let cur = 'none';
    if (expand && tab) {
      cur = 'all';
    } else if (expand) {
      cur = 'expand';
    } else if (tab) {
      cur = 'tab';
    }
    const entries: Array<MenuOptionEntry> = [];
    for (let i = 0; i < values.length; ++i) {
      entries.push(new MenuOptionEntry(values[i], labels[i], values[i] === cur));
    }
    return entries;
  }

  /** 应用主题色（hex） */
  private applyThemeColor(hex: string): void {
    appConfig.setConfig(ConfigKeys.APPEARANCE_THEME_COLOR, hex);
    appState.accentColor = themeColorOf(hex);
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

          // 卡片一：主题色 / 深色模式 / 沉浸光感材质 / 动画
          ListItem() {
            Column() {
              // 主题色（Tab 文本选中色直接适配主题色）
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  // 取色器（仅网格取色，紧凑内嵌；左手时镜像到行首）
                  Row() {
                    HdsColorPicker({
                      initialColor: this.pickerColor,
                      onColorSelected: (selectedColor: string): void => {
                        this.pickerColor = selectedColor;
                        this.applyThemeColor(selectedColor);
                      },
                      options: { tabs: [HdsColorPickerTabType.GRID] }
                    })
                  }
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.paintpalette'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('主题色')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  // 取色器（仅网格取色，紧凑内嵌，靠行尾右对齐）
                  Row() {
                    HdsColorPicker({
                      initialColor: this.pickerColor,
                      onColorSelected: (selectedColor: string): void => {
                        this.pickerColor = selectedColor;
                        this.applyThemeColor(selectedColor);
                      },
                      options: { tabs: [HdsColorPickerTabType.GRID] }
                    })
                  }
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.paintpalette'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)

              Divider()
                .DividerStyle()

              // 深色模式
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Text(this.colorModeText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.icon_tertiary')])
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.moon'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('深色模式')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Text(this.colorModeText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.icon_tertiary')])
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.moon'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.showColorModeMenu = true;
              })
              .bindMenu(this.showColorModeMenu, this.colorModeMenu, {
                placement: this.menuPlacement(),
                onDisappear: (): void => {
                  this.showColorModeMenu = false;
                }
              })

              Divider()
                .DividerStyle()

              // 沉浸光感材质
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Text(this.materialText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.icon_tertiary')])
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.camera_filters'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('沉浸光感材质')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Text(this.materialText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.icon_tertiary')])
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.camera_filters'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.showMaterialMenu = true;
              })
              .bindMenu(this.showMaterialMenu, this.materialMenu, {
                placement: this.menuPlacement(),
                onDisappear: (): void => {
                  this.showMaterialMenu = false;
                }
              })

              Divider()
                .DividerStyle()

              // 动画
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Text(this.animText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.icon_tertiary')])
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.wand_and_stars'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('动画')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Text(this.animText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.icon_tertiary')])
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.wand_and_stars'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.showAnimMenu = true;
              })
              .bindMenu(this.showAnimMenu, this.animMenu, {
                placement: this.menuPlacement(),
                onDisappear: (): void => {
                  this.showAnimMenu = false;
                }
              })
            }
            .width('100%')
          }.ListItemStyle()

          // 卡片二：智感握姿 / 屏幕方向
          ListItem() {
            Column() {
              // 智感握姿（适人握持）
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.smartReachEnabled })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.smartReachEnabled = isOn;
                      appConfig.setConfig(ConfigKeys.APPEARANCE_SMART_REACH, isOn);
                      SmartReach.setEnabled(isOn);
                    })
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.hand_thumbsup'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Column({ space: 2 }) {
                  Text('智感握姿')
                    .fontSize(15)
                    .fontColor($r('sys.color.font_primary'))
                    .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                    .width('100%')
                  Text('识别握持手，列表封面与更多按钮随拇指可达区域切换')
                    .fontSize(12)
                    .fontColor($r('sys.color.font_tertiary'))
                    .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                    .width('100%')
                }
                .layoutWeight(1)
                .alignItems(appState.holdingHand === 'left' ? HorizontalAlign.End : HorizontalAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.smartReachEnabled })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.smartReachEnabled = isOn;
                      appConfig.setConfig(ConfigKeys.APPEARANCE_SMART_REACH, isOn);
                      SmartReach.setEnabled(isOn);
                    })
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.hand_thumbsup'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(60)

              Divider()
                .DividerStyle()

              // 屏幕方向
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Text(this.orientationText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.icon_tertiary')])
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.rotate_left'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('屏幕方向')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Text(this.orientationText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.icon_tertiary')])
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.rotate_left'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.showOrientationMenu = true;
              })
              .bindMenu(this.showOrientationMenu, this.orientationMenu, {
                placement: this.menuPlacement(),
                onDisappear: (): void => {
                  this.showOrientationMenu = false;
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
