/** 「歌单说明」弹窗内容：我的歌单与订阅歌单的区别 */
@ComponentV2
export struct SheetIntroDialogContent {
  build() {
    Scroll() {
      Column({ space: 14 }) {
        Column({ space: 6 }) {
          Text('我的歌单')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')
          Text('保存在本地的歌单（含默认歌单「我的收藏」，为静态歌单），支持新建、编辑、导入、排序与批量管理；歌曲加入本地歌单后可下载离线播放，歌单数据随应用备份保留。')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .lineHeight(20)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column({ space: 6 }) {
          Text('订阅歌单')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')
          Text('来自音乐插件的歌单 / 榜单 / 专辑 / 歌手的订阅入口，在对应详情页点击右上角订阅按钮即可订阅。订阅只保存条目快照、不保存歌曲（为动态歌单）：进入页面或点击「同步」时拉取源端最新曲目数，数量变化会标记「有更新」，点击条目进入详情即可查看最新内容。左滑条目可分享、更新、排序或取消订阅，长按进入批量操作；取消订阅不会影响源端数据。')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .lineHeight(20)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
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
