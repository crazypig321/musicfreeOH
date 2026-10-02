import { ButtonItem } from "../common/model/home/HomeModel"


@ComponentV2
export struct PaySupport{
  @Local list: ButtonItem[] = [
    {icon:$r('app.media.erweima'), text: '支付宝(右下角小)\n微信(大)'},
  ]


  build() {
    Column({space: 16}){
      Text('如果你也喜欢MusicFreeOH项目，欢迎打赏作者')
        .fontSize(14)
        .fontColor($r('sys.color.font_on'))

      ForEach(this.list,(item: ButtonItem, i: number)=>{
        Column({space: 5}){
          Image(item.icon)
            .width(140)
            .height(140).borderRadius(10)

          Text(item.text)
            .textAlign(TextAlign.Center)
            .fontSize(14)
            .fontColor($r('sys.color.font_on'))
        }.borderRadius(12).padding(12).backgroundColor($r('sys.color.comp_background_list_card'))
      })
    }.width('100%').alignItems(HorizontalAlign.Center)
  }
}