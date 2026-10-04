import { DialogManager } from '../../utils/DialogUtils';

/** 「设置缓存」弹窗内容：缓存上限输入框 + 单位选择（并排显示） */
@ComponentV2
export struct CacheInputDialogContent {
  @Local unit: string = DialogManager.cacheInputUnit;

  /** 单位选项（MB / GB） */
  private static unitOptions(): Array<SelectOption> {
    const opts: Array<SelectOption> = [];
    const mb: SelectOption = { value: 'MB' };
    const gb: SelectOption = { value: 'GB' };
    opts.push(mb, gb);
    return opts;
  }

  build() {
    Row({ space: 8 }) {
      TextInput({ text: DialogManager.cacheInputValue, placeholder: '100M-8G' })
        .type(InputType.Number)
        .layoutWeight(1)
        .height(44)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(10)
        .onChange((v: string): void => {
          DialogManager.cacheInputValue = v;
        })

      Select(CacheInputDialogContent.unitOptions())
        .selected(this.unit === 'G' ? 1 : 0)
        .value(this.unit === 'G' ? 'GB' : 'MB')
        .font({ size: 14 })
        .fontColor($r('sys.color.font_primary'))
        .selectedOptionFont({ size: 14 })
        .optionFont({ size: 14 })
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(10)
        .height(44)
        .width(96)
        .onSelect((index: number, _text: string) => {
          this.unit = index === 1 ? 'G' : 'M';
          DialogManager.cacheInputUnit = this.unit;
        })
    }
    .width('100%')
  }
}
