import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { MusicItem, LyricSource } from '../common/model/MediaTypes';
import { SheetItem } from '../common/model/SheetTypes';
import { pluginManager } from '../plugin/PluginManager';
import { trackPlayer } from '../core/TrackPlayer';
import { musicSheet } from '../core/MusicSheet';
import { downloader } from '../core/Downloader';
import { appConfig } from '../core/AppConfig';
import { ScheduleClose } from '../utils/ScheduleClose';
import { MediaUtils } from '../utils/MediaUtils';
import { appState } from '../entryability/AppState';

/** 快捷操作按钮（横向） */
@ComponentV2
struct QuickActionItem {
  @Require @Param icon: Resource;
  @Require @Param label: string;
  @Param isHighlight: boolean = false;
  @Event onTap: () => void = (): void => {};

  build() {
    Column({ space: 6 }) {
      Column() {
        SymbolGlyph(this.icon)
          .fontSize(22)
          .fontColor([$r('sys.color.icon_secondary')])
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.onTap();
      })
      Text(this.label)
        .fontSize(11)
        .fontColor(this.isHighlight ? $r('sys.color.font_emphasize') : $r('sys.color.font_secondary'))
        .maxLines(1)
    }
    .width(64)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.onTap();
    })
  }
}

/** 信息展示行（来源/ID/歌手/专辑） */
@ComponentV2
struct DetailRowItem {
  @Require @Param icon: Resource;
  @Require @Param label: string;
  @Require @Param value: string;

  build() {
    Row({ space: 12 }) {
      SymbolGlyph(this.icon)
        .fontSize(20)
        .fontColor([$r('sys.color.icon_secondary')])
      Text(this.label)
        .fontSize(15)
        .fontColor($r('sys.color.font_primary'))
      Blank()
      Text(this.value.length > 0 ? this.value : '-')
        .fontSize(12)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '60%' })
    }
    .width('100%')
    .height(48)
  }
}

/** 操作行（下载/定时关闭/搜索歌词/加入播放队列） */
@ComponentV2
struct ActionRowItem {
  @Require @Param icon: Resource;
  @Require @Param label: string;
  @Param value: string = '';
  @Event onTap: () => void = (): void => {};

  build() {
    Row({ space: 12 }) {
      SymbolGlyph(this.icon)
        .fontSize(20)
        .fontColor([$r('sys.color.icon_secondary')])
      Text(this.label)
        .fontSize(15)
        .fontColor($r('sys.color.font_primary'))
      Blank()
      if (this.value.length > 0) {
        Text(this.value)
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
      }
    }
    .width('100%')
    .height(48)
    .onClick(() => {
      this.onTap();
    })
  }
}

/**
 * 歌曲操作半模态（搜索结果 / 首页本地音乐共用）
 * 页面通过 show + optionsItem 控制显示；内部包含操作面板与「添加到歌单」二级半模态
 */
@ComponentV2
export struct MusicOptionsSheet {
  @Require @Param optionsItem: MusicItem;
  /** 是否显示操作面板 */
  @Param show: boolean = false;
  /** 面板消失回调（页面将 show 置回 false） */
  @Event onClose: () => void = (): void => {};

  @Local isFavorited: boolean = false;
  @Local showSheetPicker: boolean = false;
  @Local pickerInCreateMode: boolean = false;
  @Local newSheetTitle: string = '';

  @Monitor('show')
  onShowChange(): void {
    if (this.show) {
      this.isFavorited = this.checkFavorited(this.optionsItem);
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  private checkFavorited(item: MusicItem): boolean {
    const favList = musicSheet.getMusicList(musicSheet.defaultSheet.id);
    for (const it of favList) {
      if (MediaUtils.isSameMediaItem(it, item)) {
        return true;
      }
    }
    return false;
  }

  private toggleFavorite(): void {
    const target = this.optionsItem;
    if (this.isFavorited) {
      musicSheet.removeMusic(musicSheet.defaultSheet.id, [target]).then((): void => {
        this.isFavorited = false;
        this.showToast('已取消收藏');
      });
    } else {
      musicSheet.addMusic(musicSheet.defaultSheet.id, target).then((): void => {
        this.isFavorited = true;
        this.showToast('已收藏到我喜欢的音乐');
      });
    }
  }

  private openSheetPicker(): void {
    this.pickerInCreateMode = false;
    this.newSheetTitle = '';
    this.showSheetPicker = true;
  }

  private getUserSheets(): Array<SheetItem> {
    const result: Array<SheetItem> = [];
    for (const sheet of musicSheet.sheets) {
      if (sheet.id === musicSheet.defaultSheet.id) {
        continue;
      }
      result.push(sheet);
    }
    return result;
  }

  private addToSheet(sheet: SheetItem): void {
    const target = this.optionsItem;
    const existing = musicSheet.getMusicList(sheet.id);
    for (const it of existing) {
      if (MediaUtils.isSameMediaItem(it, target)) {
        this.showToast('歌曲已在歌单中');
        this.showSheetPicker = false;
        return;
      }
    }
    musicSheet.addMusic(sheet.id, target).then((): void => {
      this.showSheetPicker = false;
      this.showToast('已添加到「' + sheet.title + '」');
    });
  }

  private confirmCreateSheet(): void {
    const title = this.newSheetTitle.trim();
    if (title.length === 0) {
      this.showToast('请输入歌单名称');
      return;
    }
    musicSheet.addSheet(title).then((sheetId: string): Promise<void> => {
      this.newSheetTitle = '';
      this.pickerInCreateMode = false;
      return musicSheet.addMusic(sheetId, this.optionsItem);
    }).then((): void => {
      this.showSheetPicker = false;
      this.showToast('已创建歌单并添加');
    });
  }

  private playNext(): void {
    trackPlayer.addNext(this.optionsItem);
    this.showToast('将在下一首播放');
  }

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

  private downloadCurrent(): void {
    if (downloader.getDownloadTask(this.optionsItem) !== null) {
      this.showToast('已在下载列表中');
      return;
    }
    downloader.download(this.optionsItem, appConfig.getDefaultDownloadQuality());
    this.showToast('已加入下载队列');
  }

  private showSleepMenu(): void {
    try {
      this.getUIContext().getPromptAction().showActionMenu({
        title: '定时关闭',
        buttons: [
          { text: '关闭定时', color: $r('sys.color.font_primary') },
          { text: '播完当前歌曲', color: $r('sys.color.font_primary') },
          { text: '15分钟', color: $r('sys.color.font_primary') },
          { text: '30分钟', color: $r('sys.color.font_primary') },
          { text: '60分钟', color: $r('sys.color.font_primary') }
        ]
      }).then((resp: promptAction.ActionMenuSuccessResponse): void => {
        this.applySleepChoice(resp.index);
      }).catch((_e: Object): void => {
      });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  private applySleepChoice(index: number): void {
    if (index === 0) {
      ScheduleClose.setCloseAfterPlayEnd(false);
      ScheduleClose.setScheduleClose(null);
      this.showToast('已关闭定时');
    } else if (index === 1) {
      ScheduleClose.setCloseAfterPlayEnd(true);
      ScheduleClose.setScheduleClose(Date.now() + 1000);
      this.showToast('将在播完当前歌曲后关闭');
    } else if (index === 2) {
      ScheduleClose.setCloseAfterPlayEnd(false);
      ScheduleClose.setScheduleClose(Date.now() + 15 * 60 * 1000);
      this.showToast('将在15分钟后关闭');
    } else if (index === 3) {
      ScheduleClose.setCloseAfterPlayEnd(false);
      ScheduleClose.setScheduleClose(Date.now() + 30 * 60 * 1000);
      this.showToast('将在30分钟后关闭');
    } else if (index === 4) {
      ScheduleClose.setCloseAfterPlayEnd(false);
      ScheduleClose.setScheduleClose(Date.now() + 60 * 60 * 1000);
      this.showToast('将在60分钟后关闭');
    }
  }

  private sleepStatusText(): string {
    if (ScheduleClose.getDeadline() !== null) {
      return '已开启';
    }
    return '';
  }

  private searchLyric(): void {
    const target = this.optionsItem;
    const plugin = pluginManager.getByMedia(target);
    if (plugin === null) {
      this.showToast('无可用插件');
      return;
    }
    plugin.methods.getLyric(target).then((lyric: LyricSource | null): void => {
      if (lyric !== null && !lyric.isEmpty()) {
        this.showToast('歌词已缓存');
      } else {
        this.showToast('未找到歌词');
      }
    }).catch((_e: Object): void => {
      this.showToast('歌词获取失败');
    });
  }

  private addToPlayQueue(): void {
    trackPlayer.add(this.optionsItem);
    this.showToast('已加入播放队列');
  }

  build() {
    // 两个空节点分别挂载操作面板与歌单选择器（二级半模态），互不影响
    Column() {
      Column()
        .bindSheet(!!this.showSheetPicker, this.SheetPickerBuilder(), {
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          dragBar: true,
          onDisappear: () => {
            this.showSheetPicker = false;
            this.pickerInCreateMode = false;
          }
        })
    }
    .width('100%')
    .height(0)
    .bindSheet(!!this.show, this.OptionsSheetBuilder(), {
      detents: [600, SheetSize.LARGE],
      dragBar: true,
      preferType: SheetType.CENTER,
      onWillDisappear: () => {
        this.onClose();
        appState.isForegroundBlur = false;
      },
      onWillAppear: () => {
        appState.isForegroundBlur = true;
      }
    })
  }

  /** 歌曲操作面板：头部 + 快捷操作 + 详情/操作列表 */
  @Builder
  OptionsSheetBuilder() {
    Column() {
      Row({ space: 12 }) {
        if (this.optionsItem.artwork.length > 0) {
          Image(this.optionsItem.artwork)
            .width(64)
            .height(64)
            .borderRadius(10)
            .objectFit(ImageFit.Cover)
            .alt($r('app.media.startIcon'))
        } else {
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
        }
        Column({ space: 3 }) {
          Text(this.optionsItem.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .width('70%')
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

      Row({ space: 4 }) {
        QuickActionItem({
          icon: this.isFavorited ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
          label: this.isFavorited ? '取消收藏' : '收藏',
          isHighlight: this.isFavorited,
          onTap: (): void => {
            this.toggleFavorite();
          }
        })
        QuickActionItem({
          icon: $r('sys.symbol.plus_square_on_square'),
          label: '添加到歌单',
          onTap: (): void => {
            this.openSheetPicker();
          }
        })
        QuickActionItem({
          icon: $r('sys.symbol.forward_end_fill'),
          label: '下一首播放',
          onTap: (): void => {
            this.playNext();
          }
        })
        QuickActionItem({
          icon: $r('sys.symbol.share'),
          label: '分享',
          onTap: (): void => {
            this.shareCurrent();
          }
        })
      }
      .width('100%')
      .margin({ top: 20 })
      .justifyContent(FlexAlign.SpaceBetween)

      Divider()
        .width('100%')
        .margin({ top: 12, bottom: 4 })

      List() {
        ListItem() {
          DetailRowItem({
            icon: $r('sys.symbol.link'),
            label: '来源',
            value: this.optionsItem.platform
          })
        }
        ListItem() {
          DetailRowItem({
            icon: $r('sys.symbol.hash'),
            label: 'ID',
            value: this.optionsItem.id
          })
        }
        ListItem() {
          DetailRowItem({
            icon: $r('sys.symbol.person'),
            label: '歌手',
            value: this.optionsItem.artist
          })
        }
        ListItem() {
          DetailRowItem({
            icon: $r('sys.symbol.opticaldisc'),
            label: '专辑',
            value: this.optionsItem.album
          })
        }
        ListItem() {
          ActionRowItem({
            icon: $r('sys.symbol.square_and_arrow_down'),
            label: '下载',
            onTap: (): void => {
              this.downloadCurrent();
            }
          })
        }
        ListItem() {
          ActionRowItem({
            icon: $r('sys.symbol.moon_z'),
            label: '定时关闭',
            value: this.sleepStatusText(),
            onTap: (): void => {
              this.showSleepMenu();
            }
          })
        }
        ListItem() {
          ActionRowItem({
            icon: $r('sys.symbol.doc_plaintext'),
            label: '搜索歌词',
            onTap: (): void => {
              this.searchLyric();
            }
          })
        }
        ListItem() {
          ActionRowItem({
            icon: $r('sys.symbol.list_bullet'),
            label: '加入播放队列',
            onTap: (): void => {
              this.addToPlayQueue();
            }
          })
        }
      }
      .width('100%')
      .nestedScroll({
        scrollForward: NestedScrollMode.PARENT_FIRST,
        scrollBackward: NestedScrollMode.SELF_FIRST
      })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 添加到歌单（含新建歌单） */
  @Builder
  SheetPickerBuilder() {
    Column() {
      if (this.pickerInCreateMode) {
        Text('新建歌单')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .margin({ top: 4, bottom: 16 })
        TextInput({ placeholder: '歌单名称', text: this.newSheetTitle })
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
          .placeholderColor($r('sys.color.font_tertiary'))
          .placeholderFont({ size: 15 })
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .borderRadius(12)
          .onChange((v: string) => {
            this.newSheetTitle = v;
          })
          .onSubmit((_enterKey: EnterKeyType) => {
            this.confirmCreateSheet();
          })
        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .fontColor($r('sys.color.font_primary'))
            .onClick(() => {
              this.pickerInCreateMode = false;
              this.newSheetTitle = '';
            })
          Button('创建')
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .onClick(() => {
              this.confirmCreateSheet();
            })
        }
        .width('100%')
        .margin({ top: 20 })
      } else {
        Text('添加到歌单')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .margin({ top: 4, bottom: 4 })
        List() {
          ListItem() {
            Row({ space: 12 }) {
              Column() {
                SymbolGlyph($r('sys.symbol.plus'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
              }
              .width(40)
              .height(40)
              .borderRadius(10)
              .backgroundColor($r('sys.color.comp_background_tertiary'))
              .justifyContent(FlexAlign.Center)
              Text('新建歌单')
                .fontSize(15)
                .fontColor($r('sys.color.font_primary'))
            }
            .width('100%')
            .height(52)
            .onClick(() => {
              this.pickerInCreateMode = true;
            })
          }
          ForEach(this.getUserSheets(), (sheet: SheetItem, index: number) => {
            ListItem() {
              Row({ space: 12 }) {
                Text(sheet.title)
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(sheet.worksNum.toString() + ' 首')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.addToSheet(sheet);
              })
            }
          }, (sheet: SheetItem, index: number) => sheet.id + '_' + index.toString())
        }
        .width('100%')
        .margin({ top: 4 })
        .nestedScroll({
          scrollForward: NestedScrollMode.PARENT_FIRST,
          scrollBackward: NestedScrollMode.SELF_FIRST
        })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }
}
