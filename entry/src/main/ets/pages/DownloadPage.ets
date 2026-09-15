import { downloader } from '../core/Downloader';
import { DownloadTaskInfo } from '../core/Downloader';
import { CommonNav, titleBarOf } from '../view/CommonNav';

@ComponentV2
export struct DownloadPage {
  @Local queueCount: number = 0;

  aboutToAppear(): void {
    this.queueCount = downloader.getDownloadQueue().length;
    downloader.onDownloadTaskUpdate((_task: DownloadTaskInfo) => {
      this.queueCount = downloader.getDownloadQueue().length;
    });
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf($r('app.string.tab_download')),
      isHideBackButton: true
    }) {
      Column({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.download'))
          .fontSize(48)
          .fontColor([$r('sys.color.icon_tertiary')])
        Text($r('app.string.page_under_construction'))
          .fontSize(14)
          .fontColor($r('sys.color.font_tertiary'))
        if (this.queueCount > 0) {
          Text('等待下载: ' + this.queueCount.toString() + ' 首')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: 96, bottom: 180 })
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center)
    }
  }
}
