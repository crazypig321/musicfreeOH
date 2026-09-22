import { SymbolGlyphModifier, LengthMetrics } from "@kit.ArkUI"
import { SheetItem } from "../common/model/SheetTypes"
import { appState } from "../entryability/AppState";

/**
 * 公共菜单项参数（配合 MenuUtils.Open 使用）
 */
export class MenuItemParams {
  icon: ResourceStr = '';                          // 为空字符串时不显示图标
  label: string = '';
  onAction: () => void = (): void => {};
}

/**
 * 公共菜单内容参数
 */
export class MenuParams {
  items: Array<MenuItemParams> = [];
}

/**
 * 公共菜单内容（openMenu 用）：条目间带分割线
 */
@Builder
export function commonMenuBuilder(params: MenuParams) {
  Menu() {
    ForEach(params.items, (item: MenuItemParams) => {
      if (typeof item.icon === 'string') {
        MenuItem({ content: item.label })
          .onClick(() => {
            item.onAction();
          })
      } else {
        MenuItem({ startIcon: item.icon, content: item.label })
          .onClick(() => {
            item.onAction();
          })
      }
    }, (item: MenuItemParams) => item.label)
  }
  // 条目之间的分割线
  .menuItemDivider({
    strokeWidth: LengthMetrics.vp(1),
    color: $r('sys.color.comp_divider'),
    startMargin: LengthMetrics.vp(12),
    endMargin: LengthMetrics.vp(12)
  })
}

/** 供 ComponentContent 使用的包装 builder */
export const commonMenuWrapped: WrappedBuilder<[MenuParams]> = wrapBuilder(commonMenuBuilder);
/**
 * 公共搜索组件
 */
@ComponentV2
export struct CommonSearch{
  private controller: SearchController = new SearchController()
  @Param searchValue: string = ''
  @Param placeholderValue: ResourceStr = ''
  @Param isFocusable: boolean = true
  /**
   * 焦点定位 id：必须由使用方传入且保持稳定。
   * 标题栏副标题等 titleBar 内容变化会使 HdsTitleBar 重新执行底部插槽 builder，
   * 导致本组件被卸载重建；稳定 id 保证提交/清空后延时 requestFocus 仍能命中重建出的新节点
   */
  @Param focusId: string = ''
  /** 组件 id 序列（未传 focusId 时生成兜底 id） */
  private static focusIdSeq: number = 0
  /** 本实例的焦点定位 id */
  private myFocusId: string = ''

  @Event submit: (searchContent: string, event: SubmitEvent) => void
  @Event change: (value: string) => void
  @Event click: () => void
  @Event didDelete: () => void

  aboutToAppear(): void {
    if (this.focusId.length > 0) {
      this.myFocusId = this.focusId;
    } else {
      CommonSearch.focusIdSeq++;
      this.myFocusId = 'common_search_' + CommonSearch.focusIdSeq.toString();
    }
  }

  build() {
    Search({ value: this.searchValue, placeholder: this.placeholderValue, controller: this.controller })
      .id(this.myFocusId)
      .searchIcon(new SymbolGlyphModifier($r('sys.symbol.magnifyingglass')).fontColor([$r('sys.color.font')]))
      .cancelButton({
        style: CancelButtonStyle.INPUT,
        icon: new SymbolGlyphModifier($r('sys.symbol.xmark')).fontColor([$r('sys.color.font_tertiary')])
      })
      .searchButton($r('app.string.search_title'), {fontColor: appState.accentColor})
      .placeholderColor($r('sys.color.font_tertiary'))
      .placeholderFont({ size: 14, weight: 400 })
      .textFont({ size: 14, weight: 400 })
      .onSubmit((searchContent: string, event: SubmitEvent) => {// 键盘回车或者搜索按钮触发回调
        this.submit(searchContent, event)
        // 提交后收起软键盘：清除残留焦点，避免输入法重新挂载导致键盘回弹
        const focusController = this.getUIContext().getFocusController();
        setTimeout((): void => {
          try {
            focusController.clearFocus();
          } catch (e) {
            // 焦点控制器不可用时忽略
          }
        }, 200);
      })
      .onChange((value: string) => {
        if (value.length > 0) {
          this.change(value)
        }else{
          this.didDelete()
          // 文本被清空（× 或退格删空）后重新请求焦点，确保软键盘不退出；
          // 清空可能触发标题栏插槽重建（新节点），稳定 id 保证仍能命中
          const focusController = this.getUIContext().getFocusController();
          setTimeout((): void => {
            try {
              focusController.requestFocus(this.myFocusId);
            } catch (e) {
              // 组件已卸载或不可聚焦时忽略
            }
          }, 100);
        }
      })
      .onClick(()=>{
        this.click()
      })
      .focusable(this.isFocusable)// 无法获焦则无法呼出软键盘
      .defaultFocus(this.isFocusable)
  }
}

/**
 * 公共数据空组件
 */
@ComponentV2
export struct CommonNull{
  @Param message: ResourceStr = ''

  build() {
    Text(this.message)
      .fontSize(13)
      .fontColor($r('sys.color.font_tertiary'))
      .width('100%')
      .textAlign(TextAlign.Center)
  }
}


/**
 * 公共加载组件
 */
@ComponentV2
export struct CommonLoading{
  @Param sizeValue: Length = 28

  build() {
    LoadingProgress()
      .width(this.sizeValue)
      .height(this.sizeValue)
      .color($r('sys.color.icon'))
  }
}

/**
 * 公共封面组件：有封面显示图片，无封面显示占位图标（可配置宽、比例、圆角）
 * aspect <= 0 时不强制比例，按图片原始比例显示（圆形封面直接显示圆形，不裁切、不加背景）
 */
@ComponentV2
export struct CommonCover{
  @Param src: string = ''
  @Param widthValue: Length = 104
  @Param aspect: number = 1
  @Param radius: number = 12

  build() {
    if (this.src.length > 0) {
      if (this.aspect > 0) {
        Image(this.src)
          .width(this.widthValue)
          .aspectRatio(this.aspect)
          .borderRadius(this.radius)
          .objectFit(ImageFit.Cover)
          .alt($r('app.media.altImage'))
      } else {
        Image(this.src)
          .width(this.widthValue)
          .borderRadius(this.radius)
          .alt($r('app.media.altImage'))
      }
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.music_note_list'))
          .fontSize(28)
          .fontColor([$r('sys.color.icon_tertiary')])
      }
      .width(this.widthValue)
      .aspectRatio(this.aspect > 0 ? this.aspect : 1)
      .borderRadius(this.radius)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .justifyContent(FlexAlign.Center)
    }
  }
}

/**
 * 公共歌单卡片：封面 + 标题（可配置宽度与标题行数）
 */
@ComponentV2
export struct SheetCard{
  @Param sheet: SheetItem = new SheetItem()
  @Param widthValue: Length = 104
  @Param titleLines: number = 1
  @Event click: () => void = (): void => {}

  build() {
    Column({ space: 6 }) {
      CommonCover({ src: this.sheet.coverUrl(), widthValue: this.widthValue })
      Text(this.sheet.title)
        .fontSize(12)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(this.titleLines)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(this.widthValue)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.click()
    })
  }
}

/**
 * 公共卡片堆叠轮播：最前面的卡片居中完整展示（带标题），左右两侧露出缩小且半透明的卡片（无标题）；
 * 支持左右滑动切换、点击两侧卡片直接切到该层，底部带指示点（超过 9 个不显示）
 */
@ComponentV2
export struct CardStack{
  /** 轮播数据 */
  @Param items: Array<SheetItem> = []
  /** 卡片宽度（vp） */
  @Param cardWidth: number = 140
  /** 封面宽高比：0=按图片原始比例显示（圆形封面直接显示圆形），>0 强制指定比例 */
  @Param coverAspect: number = 0
  /** 相邻层的水平间距（vp） */
  @Param spacing: number = 100
  /** 两侧卡片的基础透明度（越远越淡） */
  @Param dimOpacity: number = 0.3
  /** 每层缩放递减 */
  @Param scaleStep: number = 0.06
  /** 单侧可见层数（不含最前层） */
  @Param sideCount: number = 1
  /** 点击最前面卡片的回调 */
  @Event itemClick: (sheet: SheetItem) => void = (_sheet: SheetItem): void => {}

  @Local currentIndex: number = 0

  /** 数据变化时回到第一张 */
  @Monitor('items')
  onItemsChange(): void {
    this.currentIndex = 0
  }

  /** 计算环形相对层数：0=最前，正数=露出的后面层，负数=隐藏（首尾相接处理） */
  private coefficientOf(index: number): number {
    const n = this.items.length
    if (n === 0) {
      return 0
    }
    const half = Math.floor(n / 2)
    let d = index - this.currentIndex
    if (d < 0) {
      d += n
    }
    if (d > half) {
      d -= n
    }
    return d
  }

  /** 卡片整体高度：封面高度（原始比例时按正方形估算）+ 标题区域 */
  private cardHeight(): number {
    const aspect = this.coverAspect > 0 ? this.coverAspect : 1
    return this.cardWidth / aspect + 26
  }

  /** 相对层数的绝对值：0=最前层，1、2...=两侧依次露出的层 */
  private layerOf(index: number): number {
    return Math.abs(this.coefficientOf(index))
  }

  /** 切换到相对当前层 delta 的卡片 */
  private switchBy(delta: number): void {
    const n = this.items.length
    if (n === 0 || delta === 0) {
      return
    }
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseOut }, (): void => {
      this.currentIndex = (this.currentIndex + delta + n) % n
    })
  }

  build() {
    Column({ space: 8 }) {
      // 堆叠区域：最前层居中，两侧层左右错开、缩小并降透明度，zIndex 越靠前越高
      Stack({ alignContent: Alignment.Center }) {
        ForEach(this.items, (item: SheetItem, index: number) => {
          Column({ space: 8 }) {
            CommonCover({ src: item.coverUrl(), widthValue: '100%', aspect: this.coverAspect, radius: 16 })
            Text(item.title)
              .fontSize(13)
              .fontColor($r('sys.color.font_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .opacity(this.layerOf(index) === 0 ? 1 : 0)  // 只有最前层显示标题
          }
          .width(this.cardWidth)
          .alignItems(HorizontalAlign.Center)
          .offset({ x: this.spacing * this.coefficientOf(index), y: 0 })
          .scale({
            x: 1 - this.scaleStep * this.layerOf(index),
            y: 1 - this.scaleStep * this.layerOf(index)
          })
          .opacity(this.layerOf(index) === 0 ? 1 :
            (this.layerOf(index) > this.sideCount ? 0 : Math.max(0.2, this.dimOpacity - 0.15 * (this.layerOf(index) - 1))))
          .zIndex(this.layerOf(index) > this.sideCount ? 0 : this.sideCount + 1 - this.layerOf(index))
          .onClick(() => {
            const coef = this.coefficientOf(index)
            if (coef === 0) {
              this.itemClick(item)            // 点击最前面的卡片
            } else if (Math.abs(coef) <= this.sideCount) {
              this.switchBy(coef)             // 点击两侧露出的卡片直接切到该层
            }
          })
        }, (item: SheetItem, index: number) => item.platform + '_' + item.id + '_' + index.toString())
      }
      .width('100%')
      .height(this.cardHeight())
      .gesture(
        // 左右滑动切换（超过阈值才算一次滑动）
        PanGesture({ direction: PanDirection.Horizontal, fingers: 1 })
          .onActionEnd((event: GestureEvent) => {
            if (Math.abs(event.offsetX) > 30) {
              this.switchBy(event.offsetX < 0 ? 1 : -1)
            }
          })
      )

      // 指示点
      if (this.items.length > 1) {
        Row({ space: 6 }) {
          ForEach(this.items, (_sheet: SheetItem, index: number) => {
            Column()
              .width(index === this.currentIndex ? 16 : 6)
              .height(6)
              .borderRadius(3)
              .backgroundColor(index === this.currentIndex ? $r('sys.color.icon_secondary') : $r('sys.color.comp_background_tertiary'))
          }, (_sheet: SheetItem, index: number) => index.toString())
        }
      }
    }
    .width('100%')
  }
}

/**
 * 底部公共渐变模糊组件
 */
@ComponentV2
export struct CommonBlur{
  @Param heightValue: Length = 116
  @Param gradientDirection: GradientDirection = GradientDirection.Bottom

  build() {
    Column()
      .width('100%')
      .height(this.heightValue)
      .linearGradientBlur(60,
        { fractionStops: [[0, 0], [0.9, 0.15], [1, 0.3], [1, 1]], direction: this.gradientDirection })
  }
}