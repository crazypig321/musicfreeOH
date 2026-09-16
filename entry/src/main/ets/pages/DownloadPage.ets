import { downloader, DownloadTaskInfo, DownloadStatus, DownloadFailReason } from '../core/Downloader';
import { localMusicSheet } from '../core/LocalMusicSheet';
import { trackPlayer } from '../core/TrackPlayer';
import { CommonNav, titleBarOf } from '../view/CommonNav';
import { appState } from '../entryability/AppState';
import { MusicItem } from '../common/model/MediaTypes';
import { MusicDataSource } from '../common/model/MusicDataSource';
import { pasteboard } from '@kit.BasicServicesKit';

/**
 * 下载页面：上半部分为下载任务（等待/准备中/下载中/失败，带进度条），
 * 下半部分为已下载列表（本地音乐歌单），条目风格与搜索结果一致
 */
@ComponentV2
export struct DownloadPage {
  scroller: Scroller = new Scroller();
  /** 下载任务行（队列快照，进度事件驱动刷新） */
  @Local taskRows: Array<DownloadTaskInfo> = [];
  /** 已下载歌曲数（分组标题与空态使用） */
  @Local downloadedCount: number = 0;
  @Local showOptions: boolean = false;
  @Local optionsItem: MusicItem = new MusicItem();

  /** 已下载列表懒加载数据源（复用搜索页的数据源） */
  dataSource: MusicDataSource = new MusicDataSource();

  aboutToAppear(): void {
    this.refreshTasks();
    this.refreshDownloaded();
    // 下载任务状态/进度变化 → 刷新任务行
    downloader.onDownloadTaskUpdate((_task: DownloadTaskInfo): void => {
      this.refreshTasks();
    });
    // 队列全部结束 → 刷新任务与已下载列表
    downloader.onDownloadQueueCompleted((): void => {
      this.refreshTasks();
      this.refreshDownloaded();
    });
    // 本地歌单变化（下载完成/删除） → 刷新已下载列表
    localMusicSheet.onLocalSheetUpdated((): void => {
      this.refreshDownloaded();
    });
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  /** 刷新下载任务行（队列快照，键含进度以驱动重建；跳过已完成任务） */
  private refreshTasks(): void {
    const rows: Array<DownloadTaskInfo> = [];
    for (const m of downloader.getDownloadQueue()) {
      const task = downloader.getDownloadTask(m);
      if (task !== null && task.status !== DownloadStatus.Completed) {
        rows.push(task);
      }
    }
    this.taskRows = rows;
  }

  /** 刷新已下载列表 */
  private refreshDownloaded(): void {
    const items = localMusicSheet.getMusicList();
    this.downloadedCount = items.length;
    this.dataSource.clear();
    this.dataSource.appendData(items);
  }

  private static taskPercent(task: DownloadTaskInfo): number {
    if (task.fileSize <= 0) {
      return 0;
    }
    return Math.min(100, Math.floor(task.downloadedSize / task.fileSize * 100));
  }

  private static failReasonText(reason: string): string {
    if (reason === DownloadFailReason.NETWORK_OFFLINE) {
      return '无网络';
    }
    if (reason === DownloadFailReason.NOT_ALLOW_TO_DOWNLOAD_IN_CELLULAR) {
      return '移动网络下禁止下载';
    }
    if (reason === DownloadFailReason.FAIL_TO_FETCH_SOURCE) {
      return '无法获取音源';
    }
    if (reason === DownloadFailReason.NO_WRITE_PERMISSION) {
      return '无写入权限';
    }
    return '未知错误';
  }

  private static taskStatusText(task: DownloadTaskInfo): string {
    if (task.status === DownloadStatus.Pending) {
      return '等待下载';
    }
    if (task.status === DownloadStatus.Preparing) {
      return '准备中...';
    }
    if (task.status === DownloadStatus.Downloading) {
      if (task.fileSize > 0) {
        return '下载中 ' + DownloadPage.taskPercent(task).toString() + '%';
      }
      return '下载中...';
    }
    if (task.status === DownloadStatus.Completed) {
      return '下载完成';
    }
    return '下载失败：' + DownloadPage.failReasonText(task.errorReason);
  }

  /** 取消下载任务（仅等待/失败状态可取消） */
  private removeTask(task: DownloadTaskInfo): void {
    if (downloader.remove(task.musicItem)) {
      this.showToast('已取消下载');
    } else {
      this.showToast('正在下载中，无法取消');
    }
    this.refreshTasks();
  }

  /** 播放已下载歌曲（用整个已下载列表作为播放队列） */
  private playDownloaded(item: MusicItem): void {
    const playList = this.dataSource.getItems();
    if (playList.length === 0) {
      return;
    }
    trackPlayer.playWithReplacePlayList(item, playList).catch((_e: Object): void => {
      this.showToast('播放失败');
    });
  }

  private playNext(): void {
    trackPlayer.addNext(this.optionsItem);
    this.showToast('将在下一首播放');
  }

  /** 分享歌曲信息（复制到剪贴板） */
  private shareCurrent(): void {
    const text = '「' + this.optionsItem.title + '」 - ' + this.optionsItem.artist +
      '（来自 ' + this.optionsItem.platform + '）';
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      this.showToast('已复制歌曲信息，可粘贴分享');
    }).catch((_e: Object): void => {
      this.showToast('复制失败');
    });
  }

  /** 移出已下载列表 */
  private removeFromSheet(): void {
    const target = this.optionsItem;
    this.showOptions = false;
    localMusicSheet.removeMusic(target, false).then((): void => {
      this.showToast('已移出下载列表');
    });
  }

  /** 移出已下载列表并删除本地文件 */
  private removeWithFile(): void {
    const target = this.optionsItem;
    this.showOptions = false;
    localMusicSheet.removeMusic(target, true).then((): void => {
      this.showToast('已删除歌曲与本地文件');
    });
  }

  private static formatDuration(sec: number): string {
    const s = Math.max(0, Math.floor(sec));
    const m = Math.floor(s / 60);
    const r = s % 60;
    const mStr = m < 10 ? '0' + m.toString() : m.toString();
    const rStr = r < 10 ? '0' + r.toString() : r.toString();
    return mStr + ':' + rStr;
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf($r('app.string.tab_download'), undefined, undefined),
      isHideBackButton: true
    }) {
      List({ scroller: this.scroller }) {
        // 下载任务分组
        if (this.taskRows.length > 0) {
          ListItem() {
            Text('下载中 · ' + this.taskRows.length.toString())
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
              .margin({ top: 12, bottom: 4 })
          }
          ForEach(this.taskRows, (task: DownloadTaskInfo, index: number) => {
            ListItem() {
              this.TaskRowBuilder(task, index)
            }
          }, (task: DownloadTaskInfo, _index: number) =>
            task.musicItem.platform + '_' + task.musicItem.id + '_' +
            task.status.toString() + '_' + task.downloadedSize.toString())
        }

        // 已下载分组
        if (this.downloadedCount > 0) {
          ListItem() {
            Text('已下载 · ' + this.downloadedCount.toString())
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
              .margin({ top: 12, bottom: 4 })
          }
          LazyForEach(this.dataSource, (item: MusicItem, index: number) => {
            ListItem() {
              this.DownloadedRowBuilder(item, index)
            }
          }, (item: MusicItem, _index: number) => item.platform + '_' + item.id)
        }

        // 空态
        if (this.taskRows.length === 0 && this.downloadedCount === 0) {
          ListItem() {
            Column({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.download'))
                .fontSize(44)
                .fontColor([$r('sys.color.icon_tertiary')])
              Text('暂无下载任务')
                .fontSize(14)
                .fontColor($r('sys.color.font_secondary'))
              Text('在歌曲操作中选择「下载」，下载完成后会出现在这里')
                .fontSize(12)
                .fontColor($r('sys.color.font_tertiary'))
                .textAlign(TextAlign.Center)
                .padding({ left: 32, right: 32 })
            }
            .width('100%')
            .margin({ top: 48 })
            .alignItems(HorizontalAlign.Center)
          }
        }
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .contentStartOffset(appState.topRect + 66)
      .contentEndOffset(appState.bottomRect + 60)
      .padding({ left: 16, right: 16 })
      .bindSheet(!!this.showOptions, this.OptionsSheetBuilder(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        dragBar: true,
        onWillDisappear: () => {
          this.showOptions = false;
          appState.isForegroundBlur = false
        },
        onWillAppear: () => {
          appState.isForegroundBlur = true
        }
      })
    }
  }

  /** 下载任务行：状态图标 + 标题/状态文本 + 进度条 + 取消 */
  @Builder
  TaskRowBuilder(task: DownloadTaskInfo, index: number) {
    Column() {
      Row({ space: 12 }) {
        Column() {
          if (task.status === DownloadStatus.Preparing || task.status === DownloadStatus.Downloading) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color($r('sys.color.icon_emphasize'))
          } else if (task.status === DownloadStatus.Error) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(20)
              .fontColor([$r('sys.color.icon_secondary')])
          } else {
            SymbolGlyph($r('sys.symbol.clock'))
              .fontSize(20)
              .fontColor([$r('sys.color.icon_secondary')])
          }
        }
        .width(40)
        .height(40)
        .borderRadius(10)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .justifyContent(FlexAlign.Center)

        Column({ space: 4 }) {
          Text(task.musicItem.title)
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(DownloadPage.taskStatusText(task))
            .fontSize(12)
            .fontColor(task.status === DownloadStatus.Error ?
              $r('sys.color.font_secondary') : $r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (task.status === DownloadStatus.Downloading && task.fileSize > 0) {
            Progress({ value: DownloadPage.taskPercent(task), total: 100, type: ProgressType.Linear })
              .width('100%')
              .height(3)
              .color($r('sys.color.icon_emphasize'))
              .backgroundColor($r('sys.color.comp_background_tertiary'))
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([$r('sys.color.icon_secondary')])
          .onClick(() => {
            this.removeTask(task);
          })
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })

      // 条目间分割线
      if (index < this.taskRows.length - 1) {
        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.comp_divider'))
          .margin({ left: 52, right: 4 })
      }
    }
    .width('100%')
  }

  /** 已下载歌曲行（风格同搜索结果行）：点击播放，更多操作进半模态 */
  @Builder
  DownloadedRowBuilder(item: MusicItem, index: number) {
    Column() {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.music_note_list'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
        }
        .width(40)
        .height(40)
        .borderRadius(10)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .justifyContent(FlexAlign.Center)

        Column({ space: 2 }) {
          Text(item.title)
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.artist + (item.album.length > 0 ? ' · ' + item.album : ''))
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(DownloadPage.formatDuration(item.duration))
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
        SymbolGlyph($r('sys.symbol.ellipsis_circle'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
          .onClick(() => {
            this.optionsItem = item.clone();
            this.showOptions = true;
          })
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })
      .onClick(() => {
        this.playDownloaded(item);
      })

      // 条目间分割线
      if (index < this.dataSource.totalCount() - 1) {
        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.comp_divider'))
          .margin({ left: 52, right: 4 })
      }
    }
    .width('100%')
  }

  /** 已下载歌曲操作半模态（UI 参考插件详情的操作分组） */
  @Builder
  OptionsSheetBuilder() {
    Column() {
      // 头部：图标 + 标题 + 歌手 + 专辑
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.music_note_list'))
            .fontSize(28)
            .fontColor([$r('sys.color.icon_tertiary')])
        }
        .width(64)
        .height(64)
        .borderRadius(10)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .justifyContent(FlexAlign.Center)

        Column({ space: 3 }) {
          Text(this.optionsItem.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.optionsItem.artist)
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.optionsItem.album.length > 0 ? this.optionsItem.album : '未知专辑')
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 操作分组：播放 / 下一首播放 / 分享 / 移出列表 / 删除歌曲文件
      Text('操作')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .margin({ top: 20, bottom: 6 })
      Column() {
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
          Text('播放')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          const target = this.optionsItem;
          this.showOptions = false;
          this.playDownloaded(target);
        })

        Divider().DividerStyle()
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.forward_end_fill'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
          Text('下一首播放')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.playNext();
        })

        Divider().DividerStyle()
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.share'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
          Text('分享')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.shareCurrent();
        })

        Divider().DividerStyle()
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
          Text('移出下载列表')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.removeFromSheet();
        })

        Divider().DividerStyle()
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
          Text('删除歌曲文件')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.removeWithFile();
        })
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor($r('sys.color.comp_background_list_card'))
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }
}

@Extend(Divider)
function DividerStyle(){
  .strokeWidth(0.5)
  .color($r('sys.color.comp_divider'))
  .margin({ left: 48, right: 12 })
}
