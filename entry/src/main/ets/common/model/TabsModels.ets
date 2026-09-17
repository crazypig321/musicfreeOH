import { SymbolGlyphModifier } from '@kit.ArkUI';

export interface MenuItem {
  symbolGlyph: SymbolGlyphModifier;
  symbolGlyph1: SymbolGlyphModifier;
  label: ResourceStr;
  defaultBgColor: ResourceColor;
  hoverBgColor: ResourceColor;
  pressBgColor: ResourceColor;
}

export function tabBarSymbolOf(item: MenuItem): TabBarSymbol {
  const symbol: TabBarSymbol = {
    normal: item.symbolGlyph,
    selected: item.symbolGlyph1
  };
  return symbol;
}

export const MENU_CONFIG: MenuItem[] = [
  {
    symbolGlyph: new SymbolGlyphModifier($r('sys.symbol.house')).renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
      .fontColor([$r('sys.color.icon_primary'), $r('sys.color.icon_secondary')]),
    symbolGlyph1: new SymbolGlyphModifier($r('sys.symbol.house')).renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
      .fontColor([$r('sys.color.icon_emphasize'), $r('sys.color.icon_primary')]),
    label: $r('app.string.tab_home'),
    defaultBgColor: Color.Transparent,
    hoverBgColor: $r('sys.color.interactive_hover'),
    pressBgColor: $r('sys.color.interactive_pressed')
  },
  {
    symbolGlyph: new SymbolGlyphModifier($r('sys.symbol.music_note_list')).renderingStrategy(SymbolRenderingStrategy.SINGLE)
      .fontColor([$r('sys.color.icon_primary')]),
    symbolGlyph1: new SymbolGlyphModifier($r('sys.symbol.music_note_list')).renderingStrategy(SymbolRenderingStrategy.SINGLE)
      .fontColor([$r('sys.color.icon_emphasize')]),
    label: $r('app.string.tab_my_sheets'),
    defaultBgColor: Color.Transparent,
    hoverBgColor: $r('sys.color.interactive_hover'),
    pressBgColor: $r('sys.color.interactive_pressed')
  },
  {
    symbolGlyph: new SymbolGlyphModifier($r('sys.symbol.AI_panels')).renderingStrategy(SymbolRenderingStrategy.SINGLE)
      .fontColor([$r('sys.color.icon_primary')]),
    symbolGlyph1: new SymbolGlyphModifier($r('sys.symbol.AI_panels')).renderingStrategy(SymbolRenderingStrategy.SINGLE)
      .fontColor([$r('sys.color.icon_emphasize')]),
    label: $r('app.string.tab_plugin'),
    defaultBgColor: Color.Transparent,
    hoverBgColor: $r('sys.color.interactive_hover'),
    pressBgColor: $r('sys.color.interactive_pressed')
  },
  {
    symbolGlyph: new SymbolGlyphModifier($r('sys.symbol.dot_radiowaves_left_and_right')).renderingStrategy(SymbolRenderingStrategy.SINGLE)
      .fontColor([$r('sys.color.icon_primary')]),
    symbolGlyph1: new SymbolGlyphModifier($r('sys.symbol.dot_radiowaves_left_and_right')).renderingStrategy(SymbolRenderingStrategy.SINGLE)
      .fontColor([$r('sys.color.icon_emphasize')]),
    label: $r('app.string.tab_subscription'),
    defaultBgColor: Color.Transparent,
    hoverBgColor: $r('sys.color.interactive_hover'),
    pressBgColor: $r('sys.color.interactive_pressed')
  },
  {
    symbolGlyph: new SymbolGlyphModifier($r('sys.symbol.gearshape')).renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
      .fontColor([$r('sys.color.icon_primary'), $r('sys.color.icon_secondary')]),
    symbolGlyph1: new SymbolGlyphModifier($r('sys.symbol.gearshape')).renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
      .fontColor([$r('sys.color.icon_emphasize'), $r('sys.color.icon_primary')]),
    label: $r('app.string.tab_settings'),
    defaultBgColor: Color.Transparent,
    hoverBgColor: $r('sys.color.interactive_hover'),
    pressBgColor: $r('sys.color.interactive_pressed')
  }
];
