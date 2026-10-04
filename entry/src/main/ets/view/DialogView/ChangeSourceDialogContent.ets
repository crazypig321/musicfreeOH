import { DialogManager } from '../../utils/DialogUtils';
import { MusicItem } from '../../common/model/MediaTypes';
import { trackPlayer } from '../../core/TrackPlayer';

/** 「更换音源」弹窗内容：打开即并发搜索可用音源（加载动画），完成后显示插件选择列表 */
@ComponentV2
export struct ChangeSourceDialogContent {
  @Local loading: boolean = true;
  @Local candidates: Array<MusicItem> = [];
  @Local selectedIndex: number = 0;
  private alive: boolean = true;

  aboutToAppear(): void {
    const item = DialogManager.changeSourceItem;
    if (item === null) {
      this.loading = false;
      return;
    }
    trackPlayer.searchAlternateSources(item).then((results: Array<MusicItem>): void => {
      if (!this.alive) {
        return;
      }
      this.candidates = results;
      this.loading = false;
      DialogManager.changeSourceCandidates = results;
    }).catch((_e: Object): void => {
      if (!this.alive) {
        return;
      }
      this.loading = false;
    });
  }

  aboutToDisappear(): void {
    this.alive = false;
  }

  build() {
    if (this.loading) {
      Column({ space: 12 }) {
        LoadingProgress()
          .width(36)
          .height(36)
          .color($r('sys.color.icon_primary'))
        Text('正在搜索可用音源…')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .height(150)
      .justifyContent(FlexAlign.Center)
    } else if (this.candidates.length === 0) {
      Column() {
        Text('未找到其它可用音源')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .height(150)
      .justifyContent(FlexAlign.Center)
    } else {
      Scroll() {
        Column() {
          ForEach(this.candidates, (candidate: MusicItem, index: number) => {
            Row({ space: 10 }) {
              SymbolGlyph(index === this.selectedIndex
                ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
                .fontSize(20)
                .fontColor([index === this.selectedIndex
                  ? $r('sys.color.icon_primary') : $r('sys.color.icon_tertiary')])
              Column({ space: 2 }) {
                Text(candidate.platform)
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(candidate.title + ' - ' + candidate.artist)
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .height(48)
            .onClick(() => {
              this.selectedIndex = index;
              DialogManager.changeSourceIndex = index;
            })
          }, (candidate: MusicItem, index: number) => candidate.platform + '_' + index.toString())
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 300 })
      .scrollBar(BarState.Off)
      .width('100%')
    }
  }
}
