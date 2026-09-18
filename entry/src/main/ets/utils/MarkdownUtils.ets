/**
 * Markdown 解析工具：把 markdown 文本解析为块级/行内结构，供 MarkdownView 渲染
 * （RN 原版用 marked 渲染 HTML；此处解析为结构化数据用原生组件排版）
 */

/** 行内片段：携带加粗/斜体/代码/链接标记 */
export class MdSpan {
  text: string = '';
  bold: boolean = false;
  italic: boolean = false;
  code: boolean = false;
  link: boolean = false;
}

/** 块级元素：p 段落 / h 标题 / quote 引用 / li 列表 / oli 有序列表 / code 代码块 / hr 分割线 */
export class MdBlock {
  type: string = 'p';
  /** 标题级别（h1-h6） */
  level: number = 0;
  /** 文本内容（行内标记未解析，交由 parseSpans） */
  text: string = '';
  /** 有序列表前缀（如 "1. "） */
  prefix: string = '';
}

export class MarkdownUtils {
  /** 解析块级结构 */
  static parseBlocks(md: string): Array<MdBlock> {
    const blocks: Array<MdBlock> = [];
    if (md.length === 0) {
      return blocks;
    }
    const lines = md.split('\n');
    let codeLines: Array<string> | null = null;
    let pendingText: string = '';
    const flushParagraph = (): void => {
      if (pendingText.length > 0) {
        const b = new MdBlock();
        b.type = 'p';
        b.text = pendingText;
        blocks.push(b);
        pendingText = '';
      }
    };
    for (const raw of lines) {
      const trimmed = raw.trim();
      // 围栏代码块
      if (trimmed.startsWith('```')) {
        if (codeLines === null) {
          flushParagraph();
          codeLines = [];
        } else {
          const b = new MdBlock();
          b.type = 'code';
          b.text = codeLines.join('\n');
          blocks.push(b);
          codeLines = null;
        }
        continue;
      }
      if (codeLines !== null) {
        codeLines.push(raw);
        continue;
      }
      if (trimmed.length === 0) {
        flushParagraph();
        continue;
      }
      // 水平分割线
      if (/^(-{3,}|\*{3,}|_{3,})$/.test(trimmed)) {
        flushParagraph();
        const b = new MdBlock();
        b.type = 'hr';
        blocks.push(b);
        continue;
      }
      // 标题
      const heading = /^#{1,6}\s+(.*)$/.exec(trimmed);
      if (heading !== null) {
        flushParagraph();
        const b = new MdBlock();
        b.type = 'h';
        const hashCount = trimmed.indexOf(' ');
        b.level = hashCount > 0 ? hashCount : 1;
        b.text = heading[1];
        blocks.push(b);
        continue;
      }
      // 引用
      const quote = /^>\s?(.*)$/.exec(trimmed);
      if (quote !== null) {
        flushParagraph();
        const b = new MdBlock();
        b.type = 'quote';
        b.text = quote[1];
        blocks.push(b);
        continue;
      }
      // 无序列表
      const li = /^[-*+]\s+(.*)$/.exec(trimmed);
      if (li !== null) {
        flushParagraph();
        const b = new MdBlock();
        b.type = 'li';
        b.text = li[1];
        blocks.push(b);
        continue;
      }
      // 有序列表
      const oli = /^(\d+)[.、)]\s+(.*)$/.exec(trimmed);
      if (oli !== null) {
        flushParagraph();
        const b = new MdBlock();
        b.type = 'oli';
        b.prefix = oli[1] + '. ';
        b.text = oli[2];
        blocks.push(b);
        continue;
      }
      // 普通段落：连续行合并
      pendingText = pendingText.length > 0 ? pendingText + '\n' + trimmed : trimmed;
    }
    if (codeLines !== null) {
      const b = new MdBlock();
      b.type = 'code';
      b.text = codeLines.join('\n');
      blocks.push(b);
    }
    flushParagraph();
    return blocks;
  }

  /** 解析行内片段：加粗/斜体/行内代码/链接/图片 */
  static parseSpans(text: string): Array<MdSpan> {
    const spans: Array<MdSpan> = [];
    if (text.length === 0) {
      return spans;
    }
    const pattern = /!\[([^\]]*?)\]\([^)]*?\)|\[([^\]]+?)\]\([^)]+?\)|\*\*([^*]+?)\*\*|__([^_]+?)__|\*([^*]+?)\*|`([^`]+?)`/g;
    let last = 0;
    let m = pattern.exec(text);
    while (m !== null) {
      if (m.index > last) {
        MarkdownUtils.pushPlain(spans, text.substring(last, m.index));
      }
      const s = new MdSpan();
      if (m[1] !== undefined) {
        // 图片 → 保留 alt 文本
        s.text = m[1].length > 0 ? m[1] : '[图片]';
      } else if (m[2] !== undefined) {
        // 链接 → 保留文字
        s.text = m[2];
        s.link = true;
      } else if (m[3] !== undefined || m[4] !== undefined) {
        s.text = m[3] !== undefined ? m[3] : m[4];
        s.bold = true;
      } else if (m[5] !== undefined) {
        s.text = m[5];
        s.italic = true;
      } else {
        s.text = m[6] !== undefined ? m[6] : '';
        s.code = true;
      }
      if (s.text.length > 0) {
        spans.push(s);
      }
      last = pattern.lastIndex;
      m = pattern.exec(text);
    }
    if (last < text.length) {
      MarkdownUtils.pushPlain(spans, text.substring(last));
    }
    if (spans.length === 0) {
      MarkdownUtils.pushPlain(spans, text);
    }
    return spans;
  }

  private static pushPlain(spans: Array<MdSpan>, text: string): void {
    const s = new MdSpan();
    s.text = text;
    spans.push(s);
  }
}
