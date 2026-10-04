import { MarkdownView } from '../MarkdownView';
import { DialogManager } from '../../utils/DialogUtils';

/** 「使用说明」弹窗内容（markdown 渲染，隐藏滚动条） */
@ComponentV2
export struct UsageDialogContent {
  build() {
    Scroll() {
      MarkdownView({ markdown: DialogManager.usageMessage })
    }
    .constraintSize({ maxHeight: 420 })
    .scrollBar(BarState.Off)
    .nestedScroll({
      scrollForward: NestedScrollMode.PARALLEL,
      scrollBackward: NestedScrollMode.PARALLEL
    })
    .width('100%')
  }
}
