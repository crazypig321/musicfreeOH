import { SheetItem } from '../common/model/SheetTypes';

/**
 * 推荐歌单网格单元格（首页预览 / 推荐歌单页共用）
 * 尺寸随父容器 layoutWeight 均分，封面 1:1 圆角
 */
@ComponentV2
export struct SheetGridItem {
  @Require @Param sheet: SheetItem;
  @Event onTap: () => void = (): void => {};

  build() {
    Column({ space: 6 }) {
      Image(this.sheet.coverUrl())
        .width('100%')
        .aspectRatio(1)
        .borderRadius(12)
        .objectFit(ImageFit.Cover)
        .alt($r('app.media.startIcon'))
      Text(this.sheet.title)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.onTap();
    })
  }
}
