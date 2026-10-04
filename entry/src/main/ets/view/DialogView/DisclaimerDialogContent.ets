/** 「免责声明」弹窗内容 */
@ComponentV2
export struct DisclaimerDialogContent {
  build() {
    Column() {
      Text('本软件仅供交流与学习使用，是一款开源、免费的本地音乐播放工具，请勿相信付费传播渠道。软件本身不内置、不提供任何音频资源。所有音源均来自第三方插件，插件由第三方开发者维护，其内容的合法性、准确性与版权状况由相应提供方负责，与本软件无关。')
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .lineHeight(22)
      Text('请遵守您所在地区的法律法规，合理、适度地使用本软件。因下载或使用本软件而产生的任何直接或间接责任，均由使用者自行承担。')
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .lineHeight(22)
        .margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
