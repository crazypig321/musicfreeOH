import { SymbolGlyphModifier } from "@kit.ArkUI"
import { SheetItem } from "../common/model/SheetTypes"
/**
 * 公共搜索组件
 */
@ComponentV2
export struct CommonSearch{
  private controller: SearchController = new SearchController()
  @Param searchValue: string = ''
  @Param placeholderValue: ResourceStr = ''
  @Param isFocusable: boolean = true

  @Event submit: () => void
  @Event change: (value: string) => void
  @Event click: () => void
  @Event didDelete: () => void

  build() {
    Search({ value: this.searchValue, placeholder: this.placeholderValue, controller: this.controller })
      .searchIcon(new SymbolGlyphModifier($r('sys.symbol.magnifyingglass')).fontColor([$r('sys.color.font')]))
      .cancelButton({
        style: CancelButtonStyle.INPUT,
        icon: new SymbolGlyphModifier($r('sys.symbol.xmark')).fontColor([$r('sys.color.font_tertiary')])
      })
      .searchButton($r('app.string.search_title'))
      .placeholderColor($r('sys.color.font_tertiary'))
      .placeholderFont({ size: 14, weight: 400 })
      .textFont({ size: 14, weight: 400 })
      .onSubmit(() => {// 键盘回车或者搜索按钮触发回调
       // animStyle.animTo(async ()=> {
        this.submit()
     //   })
      })
      .onChange((value: string) => {
       // animStyle.animTo(async ()=>{
        this.change(value)
       // })
      })
      .onClick(()=>{
        this.click()
      })
      .onDidDelete(()=>{
        this.didDelete()
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
 */
@ComponentV2
export struct CommonCover{
  @Param src: string = ''
  @Param widthValue: Length = 104
  @Param aspect: number = 1
  @Param radius: number = 12

  build() {
    if (this.src.length > 0) {
      Image(this.src)
        .width(this.widthValue)
        .aspectRatio(this.aspect)
        .borderRadius(this.radius)
        .objectFit(ImageFit.Cover)
        .alt($r('app.media.startIcon'))
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.music_note_list'))
          .fontSize(28)
          .fontColor([$r('sys.color.icon_tertiary')])
      }
      .width(this.widthValue)
      .aspectRatio(this.aspect)
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
  @Param titleLines: number = 2
  @Event click: () => void = (): void => {}

  build() {
    Column({ space: 6 }) {
      CommonCover({ src: this.sheet.coverImg, widthValue: this.widthValue })
      Text(this.sheet.title)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(this.titleLines)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(this.widthValue)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.click()
    })
  }
}