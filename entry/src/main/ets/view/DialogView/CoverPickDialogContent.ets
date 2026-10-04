import { DialogManager } from '../../utils/DialogUtils';
import { appState } from '../../entryability/AppState';
import { CoverSearch } from '../../utils/CoverSearch';
import { ArtworkCache } from '../../utils/ArtworkCache';

/** 「选择封面」弹窗内容：打开即并发搜索候选封面（加载动画），完成后展示封面网格点选 */
@ComponentV2
export struct CoverPickDialogContent {
  @Local loading: boolean = true;
  @Local candidates: Array<string> = [];
  @Local selectedIndex: number = 0;
  private alive: boolean = true;

  aboutToAppear(): void {
    const item = DialogManager.coverPickItem;
    if (item === null) {
      this.loading = false;
      return;
    }
    CoverSearch.searchCandidates(item).then((artworks: Array<string>): void => {
      if (!this.alive) {
        return;
      }
      this.candidates = artworks;
      this.loading = false;
      DialogManager.coverPickCandidates = artworks;
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
          .color(appState.accentColor)
        Text('正在搜索封面…')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .height(160)
      .justifyContent(FlexAlign.Center)
    } else if (this.candidates.length === 0) {
      Column() {
        Text('未找到可用封面')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .height(160)
      .justifyContent(FlexAlign.Center)
    } else {
      Scroll() {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(this.candidates, (artwork: string, index: number) => {
            Stack({ alignContent: Alignment.BottomEnd }) {
              Image(ArtworkCache.resolve(artwork))
                .width(84)
                .height(84)
                .borderRadius(12)
                .border({
                  width: index === this.selectedIndex ? 2 : 0,
                  color: index === this.selectedIndex ? appState.accentColor : $r('sys.color.comp_divider')
                })
                .objectFit(ImageFit.Cover)
                .alt($r('app.media.altImage'))
              if (index === this.selectedIndex) {
                Toggle({ type: ToggleType.Checkbox, isOn: true })
                  .width(20)
                  .height(20)
                  .selectedColor(appState.accentColor)
              }
            }
            .width(84)
            .height(84)
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
                this.selectedIndex = index;
                DialogManager.coverPickIndex = index;
              });
            })
          }, (artwork: string, index: number) => artwork + '_' + index.toString())
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 340 })
      .scrollBar(BarState.Off)
      .width('100%')
    }
  }
}
