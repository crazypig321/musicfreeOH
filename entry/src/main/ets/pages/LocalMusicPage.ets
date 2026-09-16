import { localMusicSheet } from '../core/LocalMusicSheet';
import { trackPlayer } from '../core/TrackPlayer';
import { CommonNav, titleBarOf } from '../view/CommonNav';
import { MusicRow } from '../view/MusicRow';
import { MusicOptionsSheet } from '../view/MusicOptionsSheet';
import { MusicDataSource } from '../common/model/MusicDataSource';
import { MusicItem } from '../common/model/MediaTypes';
import { appState } from '../entryability/AppState';

/**
 * 本地音乐页：首页本地音乐板块的完整列表（LazyForEach 按需加载）
 */
@ComponentV2
export struct LocalMusicPage {
  @Local showOptions: boolean = false;
  @Local optionsItem: MusicItem = new MusicItem();
  @Local count: number = 0;
  private scroller: Scroller = new Scroller();
  private dataSource: MusicDataSource = new MusicDataSource();

  aboutToAppear(): void {
    this.refresh();
    localMusicSheet.onLocalSheetUpdated((): void => {
      this.refresh();
    });
  }

  private refresh(): void {
    const items = localMusicSheet.getMusicList();
    this.count = items.length;
    this.dataSource.clear();
    this.dataSource.appendData(items);
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  /** 播放本地音乐（以完整列表为播放队列） */
  private play(item: MusicItem): void {
    const playList = this.dataSource.getItems();
    if (playList.length === 0) {
      return;
    }
    trackPlayer.playWithReplacePlayList(item, playList).catch((_e: Object): void => {
      this.showToast('播放失败');
    });
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf('本地音乐', undefined, undefined),
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller }) {
          if (this.count === 0) {
            ListItem() {
              Text('暂无本地音乐')
                .fontSize(14)
                .fontColor($r('sys.color.font_secondary'))
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ top: 48 })
            }
          }
          LazyForEach(this.dataSource, (item: MusicItem, index: number) => {
            ListItem() {
              MusicRow({
                item: item,
                showDivider: index < this.count - 1,
                onTap: (): void => {
                  this.play(item);
                },
                onMore: (): void => {
                  this.optionsItem = item.clone();
                  this.showOptions = true;
                }
              })
            }
          }, (item: MusicItem, _index: number) => item.platform + '_' + item.id)
        }
        .ListStyle()

        // 条目操作半模态（与首页/搜索页共用）
        MusicOptionsSheet({
          optionsItem: this.optionsItem,
          show: this.showOptions,
          onClose: (): void => {
            this.showOptions = false;
          }
        })
      }
      .width('100%')
      .height('100%')
    }
  }
}

@Extend(List)
function ListStyle() {
  .width('100%')
  .height('100%')
  .scrollBar(BarState.Off)
  .edgeEffect(EdgeEffect.Spring)
  .contentStartOffset(appState.topRect + 55)
  .contentEndOffset(appState.bottomRect + 60)
  .padding({ left: 16, right: 16 })
}
