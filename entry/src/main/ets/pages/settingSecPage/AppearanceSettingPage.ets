import { CommonNav, titleBarOf } from '../../view/CommonNav';
import { appState, themeColorOf } from '../../entryability/AppState';
import { appConfig, ConfigKeys } from '../../core/AppConfig';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';
import { ContextHolder } from '../../common/ContextHolder';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hdsMaterial, HdsColorPicker } from '@kit.UIDesignKit';

/** 菜单项数据（bindMenu 用） */
class MenuOptionEntry {
  value: string = '';
  label: string = '';
  selected: boolean = false;

  constructor(value: string, label: string, selected: boolean) {
    this.value = value;
    this.label = label;
    this.selected = selected;
  }
}

/**
 * 外观设置页面
 * 主题色（HdsColorPicker 取色器 + Tab 文本色开关）/ 深色模式 / 沉浸光感材质 / 适人握持 / 动画
 * 选择类条目点击弹出 Menu 菜单（当前项带勾选标记）
 */
@ComponentV2
export struct AppearanceSettingPage {
  scroller: Scroller = new Scroller();
  /** 主题色取色器当前色（空串 = 跟随系统） */
  @Local themeColorEnabled: boolean = false;
  @Local pickerColor: string = '';
  @Local tabTextColorAccent: boolean = false;
  @Local colorModeText: string = '';
  @Local materialText: string = '';
  @Local barLayoutMode: boolean = true;
  @Local animText: string = '';

  aboutToAppear(): void {
    const stored = appConfig.getAppearanceThemeColor();
    this.themeColorEnabled = stored.length > 0;
    this.pickerColor = stored.length > 0 ? stored : '#007DFF';
    this.tabTextColorAccent = appConfig.getTabTextColorAccent();
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

  private refreshColorModeText(): void {
    this.colorModeText = AppearanceSettingPage.colorModeLabel(appConfig.getAppearanceColorMode());
  }

  private refreshMaterialText(): void {
    this.materialText = AppearanceSettingPage.materialLabel(appConfig.getAppearanceMaterialType());
  }

  private refreshAnimText(): void {
    this.animText = AppearanceSettingPage.animLabel(appConfig.getPlayerExpandAnim(), appConfig.getTabSwitchAnim());
  }

  /** 通用菜单 Builder：kind 分发应用逻辑（避免 Builder 传回调） */
  @Builder
  private menuOf(entries: Array<MenuOptionEntry>, kind: string): void {
    Menu() {
      ForEach(entries, (entry: MenuOptionEntry) => {
        MenuItem({ content: entry.label })
          .selectIcon(entry.selected)
          .onClick(() => {
            this.onMenuPick(kind, entry.value);
          })
      }, (entry: MenuOptionEntry) => entry.value)
    }
  }

  /** 菜单选中分发 */
  private onMenuPick(kind: string, value: string): void {
    if (kind === 'colorMode') {
      this.applyColorMode(value);
    } else if (kind === 'material') {
      this.applyMaterial(value);
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
    appConfig.setConfig(ConfigKeys.APPEARANCE_MATERIAL_TYPE, value);
    if (value === 'adaptive') {
      appState.materialType = hdsMaterial.MaterialType.ADAPTIVE;
    } else if (value === 'none') {
      appState.materialType = hdsMaterial.MaterialType.NONE;
    } else {
      appState.materialType = hdsMaterial.MaterialType.IMMERSIVE;
    }
    this.refreshMaterialText();
  }

  private materialEntries(): Array<MenuOptionEntry> {
    const types: Array<string> = ['immersive', 'adaptive', 'none'];
    const labels: Array<string> = ['沉浸光感', '跟随系统', '关闭'];
    const cur = appConfig.getAppearanceMaterialType();
    const entries: Array<MenuOptionEntry> = [];
    for (let i = 0; i < types.length; ++i) {
      entries.push(new MenuOptionEntry(types[i], labels[i], types[i] === cur));
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

  /** 应用主题色（hex；空串 = 跟随系统） */
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

          // 主题色：开关 + 取色器 + Tab 文本色开关
          ListItem() {
            Column() {
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.paintpalette'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('主题色')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.themeColorEnabled })
                  .onChange((isOn: boolean) => {
                    this.themeColorEnabled = isOn;
                    if (isOn) {
                      this.applyThemeColor(this.pickerColor);
                    } else {
                      this.applyThemeColor('');
                    }
                  })
              }
              .width('100%')
              .height(52)

              if (this.themeColorEnabled) {
                Divider()
                  .DividerStyle()

                // 取色器：网格 / 光谱 / 滑块三种方式
                HdsColorPicker({
                  initialColor: this.pickerColor,
                  onColorSelected: (selectedColor: string): void => {
                    this.pickerColor = selectedColor;
                    this.applyThemeColor(selectedColor);
                  }
                })
                .width('100%')
              }

              Divider()
                .DividerStyle()

              // Tab 文本选中色跟随主题色
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.textformat'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Column({ space: 2 }) {
                  Text('Tab 文本使用主题色')
                    .fontSize(15)
                    .fontColor($r('sys.color.font_primary'))
                  Text('底部导航选中项的文字颜色')
                    .fontSize(12)
                    .fontColor($r('sys.color.font_tertiary'))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.tabTextColorAccent })
                  .onChange((isOn: boolean) => {
                    this.tabTextColorAccent = isOn;
                    appConfig.setConfig(ConfigKeys.APPEARANCE_TAB_TEXT_COLOR, isOn);
                    appState.tabTextColorAccent = isOn;
                  })
              }
              .width('100%')
              .height(60)
            }
            .width('100%')
          }.ListItemStyle()

          // 深色模式 / 材质 / 适人握持 / 动画
          ListItem() {
            Column() {
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
              .bindMenu(this.colorModeMenu)

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
              .bindMenu(this.materialMenu)

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
              .bindMenu(this.animMenu)
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
