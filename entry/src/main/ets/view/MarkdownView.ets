import { MarkdownUtils, MdBlock, MdSpan } from '../utils/MarkdownUtils';

/**
 * 轻量 markdown 渲染组件：按块级结构排版（标题/段落/引用/列表/代码块/分割线），
 * 行内保留加粗/斜体/代码/链接样式
 */
@ComponentV2
export struct MarkdownView {
  @Param markdown: string = '';

  @Builder
  SpanText(block: MdBlock) {
    Text() {
      ForEach(MarkdownUtils.parseSpans(block.text), (s: MdSpan, index: number) => {
        Span(s.text)
          .fontWeight(s.bold ? FontWeight.Bold : FontWeight.Normal)
          .fontStyle(s.italic ? FontStyle.Italic : FontStyle.Normal)
          .fontFamily(s.code ? 'monospace' : 'HarmonyOS Sans')
          .fontColor(s.link ? $r('sys.color.brand') : $r('sys.color.font_primary'))
      }, (s: MdSpan, index: number) => index.toString())
    }
    .fontSize(14)
    .fontColor($r('sys.color.font_primary'))
    .lineHeight(22)
    .width('100%')
  }

  @Builder
  HeadingText(block: MdBlock) {
    Text() {
      ForEach(MarkdownUtils.parseSpans(block.text), (s: MdSpan, index: number) => {
        Span(s.text)
          .fontWeight(FontWeight.Bold)
          .fontStyle(s.italic ? FontStyle.Italic : FontStyle.Normal)
          .fontFamily(s.code ? 'monospace' : 'HarmonyOS Sans')
          .fontColor($r('sys.color.font_primary'))
      }, (s: MdSpan, index: number) => index.toString())
    }
    .fontSize(block.level <= 1 ? 20 : (block.level === 2 ? 18 : (block.level === 3 ? 17 : 16)))
    .fontWeight(FontWeight.Bold)
    .fontColor($r('sys.color.font_primary'))
    .lineHeight(26)
    .width('100%')
    .margin({ top: 6, bottom: 4 })
  }

  build() {
    Column() {
      ForEach(MarkdownUtils.parseBlocks(this.markdown), (b: MdBlock, index: number) => {
        if (b.type === 'hr') {
          Divider()
            .color($r('sys.color.comp_divider'))
            .margin({ top: 8, bottom: 8 })
        } else if (b.type === 'code') {
          Text(b.text)
            .fontSize(13)
            .fontFamily('monospace')
            .fontColor($r('sys.color.font_primary'))
            .lineHeight(20)
            .width('100%')
            .padding(10)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .borderRadius(8)
            .margin({ top: 4, bottom: 4 })
        } else if (b.type === 'h') {
          this.HeadingText(b)
        } else if (b.type === 'quote') {
          Row({ space: 8 }) {
            Column()
              .width(3)
              .height('100%')
              .backgroundColor($r('sys.color.comp_divider'))
            this.SpanText(b)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .margin({ top: 2, bottom: 2 })
        } else if (b.type === 'li' || b.type === 'oli') {
          Row({ space: 6 }) {
            Text(b.type === 'li' ? '•' : b.prefix)
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
            this.SpanText(b)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .margin({ top: 2, bottom: 2 })
        } else {
          this.SpanText(b)
        }
      }, (b: MdBlock, index: number) => index.toString())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
