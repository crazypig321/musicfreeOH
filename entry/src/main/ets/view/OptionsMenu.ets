import { appState } from '../entryability/AppState';
import { SymbolGlyphModifier, LengthMetrics } from '@kit.ArkUI';

/** 菜单项数据（bindMenu 用） */
export class MenuOptionEntry {
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
 * 通用选项菜单 Builder（UI 同外观设置页）：
 * 选中项右侧勾选图标（主题色）+ 分割线 + 圆角；onPick 回调分发选中值
 * reopen：选中后重新打开菜单（实现"回弹再打开"效果）
 */
@Builder
export function OptionsMenuBuilder(entries: Array<MenuOptionEntry>, onPick: (value: string) => void,
  reopen?: () => void) {
  Menu() {
    ForEach(entries, (entry: MenuOptionEntry) => {
      MenuItem({
        content: entry.label,
        symbolEndIcon: entry.selected
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark')).fontColor([appState.accentColor]) : undefined
      })
        .contentFont({ size: 15 })
        .contentFontColor($r('sys.color.font_primary'))
        .onClick(() => {
          onPick(entry.value);
          if (reopen !== undefined) {
            setTimeout(reopen, 50);
          }
        })
    }, (entry: MenuOptionEntry) => entry.value)
  }
  .menuItemDivider({
    color: $r('sys.color.comp_divider'),
    strokeWidth: LengthMetrics.vp(1),
    startMargin: LengthMetrics.vp(12),
    endMargin: LengthMetrics.vp(12)
  })
  .borderRadius(20)
}
