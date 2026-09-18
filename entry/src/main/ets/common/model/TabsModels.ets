import { SymbolGlyphModifier } from '@kit.ArkUI';
import { appState } from '../../entryability/AppState';

export interface MenuItem {
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

export const MENU_CONFIG: MenuItem[] = [
  {
    icon: $r('sys.symbol.house'),
    multiColor: true,
    label: $r('app.string.tab_home'),
    defaultBgColor: Color.Transparent,
    hoverBgColor: $r('sys.color.interactive_hover'),
    pressBgColor: $r('sys.color.interactive_pressed')
  },
  {
    icon: $r('sys.symbol.music_note_list'),
    multiColor: false,
    label: $r('app.string.tab_my_sheets'),
    defaultBgColor: Color.Transparent,
    hoverBgColor: $r('sys.color.interactive_hover'),
    pressBgColor: $r('sys.color.interactive_pressed')
  },
  {
    icon: $r('sys.symbol.AI_panels'),
    multiColor: false,
    label: $r('app.string.tab_plugin'),
    defaultBgColor: Color.Transparent,
    hoverBgColor: $r('sys.color.interactive_hover'),
    pressBgColor: $r('sys.color.interactive_pressed')
  },
  {
    icon: $r('sys.symbol.dot_radiowaves_left_and_right'),
    multiColor: false,
    label: $r('app.string.tab_subscription'),
    defaultBgColor: Color.Transparent,
    hoverBgColor: $r('sys.color.interactive_hover'),
    pressBgColor: $r('sys.color.interactive_pressed')
  },
  {
    icon: $r('sys.symbol.gearshape'),
    multiColor: true,
    label: $r('app.string.tab_settings'),
    defaultBgColor: Color.Transparent,
    hoverBgColor: $r('sys.color.interactive_hover'),
    pressBgColor: $r('sys.color.interactive_pressed')
  }
];
