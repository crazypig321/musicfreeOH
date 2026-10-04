import { DialogManager } from '../../utils/DialogUtils';
import { appState } from '../../entryability/AppState';

/** 「选择器」弹窗内容：TextPicker 滚轮选择 */
@ComponentV2
export struct TextPickerDialogContent {
  build() {
    TextPicker({ range: DialogManager.pickerOptions, selected: DialogManager.pickerIndex })
      .onChange((value: string | string[], index: number | number[]) => {
        if (typeof index === 'number') {
          DialogManager.pickerIndex = index;
        }
      })
      .divider({
        strokeWidth: 0.5,
        startMargin: 16,
        endMargin: 16
      })
      .textStyle({ color: $r('sys.color.font_tertiary') })
      .selectedTextStyle({ color: appState.accentColor })
      .width('100%')
  }
}
