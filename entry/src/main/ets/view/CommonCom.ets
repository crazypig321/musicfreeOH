import { SymbolGlyphModifier } from "@kit.ArkUI"
/**
 * 公共搜索组件
 */
@ComponentV2
export struct CommonSearch{
  private controller: SearchController = new SearchController()
  @Param searchValue: string = ''
  @Param placeholderValue: ResourceStr = ''

  @Event submit: () => void
  @Event change: (value: string) => void

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
 * 公共搜索组件
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