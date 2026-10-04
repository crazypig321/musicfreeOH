import { DialogManager } from '../../utils/DialogUtils';

/** 「选择歌词音源」弹窗内容：Select 下拉选择音源插件 */
@ComponentV2
export struct LyricSourceDialogContent {
  @Local options: Array<SelectOption> = [];
  @Local selectedIndex: number = 0;
  @Local selectedName: string = '';

  aboutToAppear(): void {
    const opts: Array<SelectOption> = [];
    for (const name of DialogManager.lyricSourceOptions) {
      opts.push({ value: name });
    }
    this.options = opts;
    this.selectedIndex = DialogManager.lyricSourceIndex;
    this.selectedName = DialogManager.lyricSourceOptions[DialogManager.lyricSourceIndex] ?? '';
  }

  build() {
    Column({ space: 12 }) {
      Text('选择用于搜索歌词的音源插件')
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
      Select(this.options)
        .selected(this.selectedIndex)
        .value(this.selectedName)
        .font({ size: 15 })
        .fontColor($r('sys.color.font_primary'))
        .selectedOptionFont({ size: 16, weight: FontWeight.Medium })
        .optionFont({ size: 15 })
        .onSelect((index: number, _text?: string) => {
          this.selectedIndex = index;
          this.selectedName = DialogManager.lyricSourceOptions[index] ?? '';
          DialogManager.lyricSourceIndex = index;
        })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
