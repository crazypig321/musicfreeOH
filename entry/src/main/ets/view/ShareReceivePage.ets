import { ShareReceiveStore, SharedPreviewItem } from '../sharereceive/ShareReceiveStore';

/**
 * 系统分享详情页（分享面板内嵌）：展示接收内容摘要，确认后暂存并拉起主应用导入
 */
@Entry
@Component
struct ShareReceivePage {
  @State importing: boolean = false;
  @State message: string = '';
  private items: Array<SharedPreviewItem> = [];

  aboutToAppear(): void {
    this.items = ShareReceiveStore.getItems();
  }

  build() {
    Column({ space: 12 }) {
      Text('导入到 MusicFreeOH')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))

      Column({ space: 4 }) {
        ForEach(this.items, (item: SharedPreviewItem, index: number) => {
          if (index < 3) {
            Text(item.name)
              .fontSize(13)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor($r('sys.color.font_secondary'))
          }
        }, (item: SharedPreviewItem, index: number): string => index.toString())
        if (this.items.length > 3) {
          Text('等 ' + this.items.length.toString() + ' 项')
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
        }
      }
      .width('100%')

      if (this.message.length > 0) {
        Text(this.message)
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
      }

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .buttonStyle(ButtonStyleMode.NORMAL)
          .enabled(!this.importing)
          .onClick(() => {
            ShareReceiveStore.cancel();
          })
        Button(this.importing ? '正在导入…' : '导入')
          .layoutWeight(1)
          .buttonStyle(ButtonStyleMode.EMPHASIZED)
          .enabled(!this.importing)
          .onClick(() => {
            this.importing = true;
            this.message = '';
            ShareReceiveStore.confirm((ok: boolean, msg: string): void => {
              this.importing = false;
              this.message = msg;
            });
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
