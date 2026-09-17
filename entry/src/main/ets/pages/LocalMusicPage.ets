import { localMusicSheet } from '../core/LocalMusicSheet';
import { trackPlayer } from '../core/TrackPlayer';
import { CommonNav, titleBarOf } from '../view/CommonNav';
import { MusicRow } from '../view/MusicRow';
import { MusicOptionsSheet } from '../view/MusicOptionsSheet';
import { MusicDataSource } from '../common/model/MusicDataSource';
import { MusicItem } from '../common/model/MediaTypes';
import { appState } from '../entryability/AppState';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { SUPPORT_LOCAL_MEDIA_TYPE } from '../common/Consts';
import { PathConst } from '../common/PathConst';
import { FileUtils } from '../utils/FileUtils';
import { ContextHolder } from '../common/ContextHolder';

/**
 * 本地音乐页：首页本地音乐板块的完整列表（LazyForEach 按需加载）
 * 右上角：导入本地音频（复制到下载目录后自动入库）/ 刷新（重新扫描下载目录）
 */
@ComponentV2
export struct LocalMusicPage {
  @Local showOptions: boolean = false;
  @Local optionsItem: MusicItem = new MusicItem();
  @Local count: number = 0;
  @Local scanning: boolean = false;
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

  /** titleBar 菜单按钮：导入本地音频 + 刷新扫描 */
  private titleMenus(): Array<HdsNavigationMenuItemOptions> {
    const importMenu: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.folder'),
        label: '导入本地音频',
        action: (): void => {
          this.pickLocalAudio();
        }
      }
    };
    const refreshMenu: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.arrow_clockwise'),
        label: '刷新',
        action: (): void => {
          this.rescanDownloadDir();
        }
      }
    };
    return [importMenu, refreshMenu];
  }

  /** 选择本地音频文件（批量，最多 20 个） */
  private pickLocalAudio(): void {
    if (this.scanning) {
      this.showToast('正在处理中，请稍候');
      return;
    }
    try {
      const documentPicker = new picker.DocumentViewPicker(ContextHolder.get());
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 20;
      options.fileSuffixFilters = SUPPORT_LOCAL_MEDIA_TYPE.slice();
      documentPicker.select(options).then((uris: Array<string>) => {
        if (uris.length === 0) {
          return;
        }
        this.copyUrisToDownloadDir(uris);
      }).catch((_e: Object): void => {
        this.showToast('选择文件失败');
      });
    } catch (error) {
      this.showToast('无法打开文件选择器');
    }
  }

  /** 将选中的音频文件复制到下载目录，完成后自动导入 */
  private copyUrisToDownloadDir(uris: Array<string>): void {
    this.scanning = true;
    this.showToast('正在导入 ' + uris.length.toString() + ' 个文件...');
    // downloadPath 可能无结尾斜杠（公共目录），先补齐再拼接，避免目录名黏连
    const base = PathConst.downloadPath.endsWith('/') ? PathConst.downloadPath : PathConst.downloadPath + '/';
    let ok = 0;
    let dup = 0;
    let fail = 0;
    for (const uri of uris) {
      let src: fs.File | null = null;
      try {
        const name = FileUtils.getFileName(FileUtils.normalizePath(uri));
        if (name.length === 0) {
          fail++;
          continue;
        }
        const dest = base + FileUtils.escapeCharacter(name);
        if (FileUtils.exists(dest)) {
          dup++;
          continue;
        }
        src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        const destFile = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        try {
          fs.copyFileSync(src.fd, destFile.fd);
          ok++;
        } finally {
          fs.closeSync(destFile);
        }
      } catch (e) {
        fail++;
      } finally {
        if (src !== null) {
          fs.closeSync(src);
        }
      }
    }
    this.scanning = false;
    if (ok === 0) {
      this.showToast(dup > 0 ? '文件已存在，无需重复导入' : '导入失败');
      return;
    }
    let summary = '已复制 ' + ok.toString() + ' 个文件';
    if (dup > 0) {
      summary += '，' + dup.toString() + ' 个已存在';
    }
    if (fail > 0) {
      summary += '，' + fail.toString() + ' 个失败';
    }
    this.showToast(summary);
    // 复制完成后扫描下载目录入库
    this.rescanDownloadDir();
  }

  /** 重新扫描下载目录，导入漏掉的音频文件 */
  private rescanDownloadDir(): void {
    if (this.scanning) {
      this.showToast('正在扫描中，请稍候');
      return;
    }
    this.scanning = true;
    const before = localMusicSheet.getMusicList().length;
    localMusicSheet.importLocal([PathConst.downloadPath]).then((): void => {
      this.scanning = false;
      const added = localMusicSheet.getMusicList().length - before;
      this.showToast(added > 0 ? '扫描完成，新增 ' + added.toString() + ' 首' : '扫描完成，没有发现新音频');
    }).catch((_e: Object): void => {
      this.scanning = false;
      this.showToast('扫描失败');
    });
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf('本地音乐', undefined, this.titleMenus()),
      scroller: this.scroller,
      doubleTapToTop: true
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
