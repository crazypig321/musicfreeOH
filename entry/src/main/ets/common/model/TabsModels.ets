import { SymbolGlyphModifier } from '@kit.ArkUI';
import { appState } from '../../entryability/AppState';

/** tab 页面键（TabContent 装配与 ForEach key 使用） */
export const TAB_KEY_HOME = 'home';
export const TAB_KEY_SHEETS = 'sheets';
export const TAB_KEY_MINE = 'mine';
export const TAB_KEY_PLUGIN = 'plugin';
export const TAB_KEY_SUBSCRIPTION = 'subscription';
export const TAB_KEY_SETTINGS = 'settings';

export interface MenuItem {
  key: string;
  icon: Resource;
  /** 多色渲染（双色图标） */
  multiColor: boolean;
  label: ResourceStr;
  defaultBgColor: ResourceColor;
  hoverBgColor: ResourceColor;
  pressBgColor: ResourceColor;
}

/** 选中态强调色：跟随主题色 */
export function tabBarSymbolOf(item: MenuItem): TabBarSymbol {
  let selected: SymbolGlyphModifier;
  let normal: SymbolGlyphModifier;
  if (item.multiColor) {
    normal = new SymbolGlyphModifier(item.icon).renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
      .fontColor([$r('sys.color.icon_primary'), $r('sys.color.icon_secondary')]);
    selected = new SymbolGlyphModifier(item.icon).renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
      .fontColor([appState.accentColor, $r('sys.color.icon_primary')]);
  } else {
    normal = new SymbolGlyphModifier(item.icon).renderingStrategy(SymbolRenderingStrategy.SINGLE)
      .fontColor([$r('sys.color.icon_primary')]);
    selected = new SymbolGlyphModifier(item.icon).renderingStrategy(SymbolRenderingStrategy.SINGLE)
      .fontColor([appState.accentColor]);
  }
  const symbol: TabBarSymbol = {
    normal: normal,
    selected: selected
  };
  return symbol;
}

const ITEM_HOME: MenuItem = {
  key: TAB_KEY_HOME,
  icon: $r('sys.symbol.house'),
  multiColor: true,
  label: $r('app.string.tab_home'),
  defaultBgColor: Color.Transparent,
  hoverBgColor: $r('sys.color.interactive_hover'),
  pressBgColor: $r('sys.color.interactive_pressed')
};

const ITEM_SHEETS: MenuItem = {
  key: TAB_KEY_SHEETS,
  icon: $r('sys.symbol.music_note_list'),
  multiColor: false,
  label: $r('app.string.tab_my_sheets'),
  defaultBgColor: Color.Transparent,
  hoverBgColor: $r('sys.color.interactive_hover'),
  pressBgColor: $r('sys.color.interactive_pressed')
};

const ITEM_MINE: MenuItem = {
  key: TAB_KEY_MINE,
  icon: $r('sys.symbol.person'),
  multiColor: false,
  label: $r('app.string.tab_mine'),
  defaultBgColor: Color.Transparent,
  hoverBgColor: $r('sys.color.interactive_hover'),
  pressBgColor: $r('sys.color.interactive_pressed')
};

const ITEM_PLUGIN: MenuItem = {
  key: TAB_KEY_PLUGIN,
  icon: $r('sys.symbol.AI_panels'),
  multiColor: false,
  label: $r('app.string.tab_plugin'),
  defaultBgColor: Color.Transparent,
  hoverBgColor: $r('sys.color.interactive_hover'),
  pressBgColor: $r('sys.color.interactive_pressed')
};

const ITEM_SUBSCRIPTION: MenuItem = {
  key: TAB_KEY_SUBSCRIPTION,
  icon: $r('sys.symbol.dot_radiowaves_left_and_right'),
  multiColor: false,
  label: $r('app.string.tab_subscription'),
  defaultBgColor: Color.Transparent,
  hoverBgColor: $r('sys.color.interactive_hover'),
  pressBgColor: $r('sys.color.interactive_pressed')
};

const ITEM_SETTINGS: MenuItem = {
  key: TAB_KEY_SETTINGS,
  icon: $r('sys.symbol.gearshape'),
  multiColor: true,
  label: $r('app.string.tab_settings'),
  defaultBgColor: Color.Transparent,
  hoverBgColor: $r('sys.color.interactive_hover'),
  pressBgColor: $r('sys.color.interactive_pressed')
};

/**
 * 主 tab 列表（手机底部 tab 与 PC 侧边栏共用），按「我的、设置页面显示样式」组合：
 * - 0 我的含设置入口：[首页, 我的歌单, 插件, 订阅, 我的]（我的在最右，设置经我的页进入）
 * - 1 设置含我的入口：[首页, 我的歌单, 插件, 订阅, 设置]（我的经设置页进入）
 * - 2 我的相关和设置单独显示（默认）：[首页, 我的歌单, 插件, 订阅, 我的, 设置]（两者置于最右）
 */
export function tabItemsOf(mineSettingStyle: number): MenuItem[] {
  if (mineSettingStyle === 0) {
    return [ITEM_HOME, ITEM_SHEETS, ITEM_PLUGIN, ITEM_SUBSCRIPTION, ITEM_MINE];
  }
  if (mineSettingStyle === 1) {
    return [ITEM_HOME, ITEM_SHEETS, ITEM_PLUGIN, ITEM_SUBSCRIPTION, ITEM_SETTINGS];
  }
  return [ITEM_HOME, ITEM_SHEETS, ITEM_PLUGIN, ITEM_SUBSCRIPTION, ITEM_MINE, ITEM_SETTINGS];
}
