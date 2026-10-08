import { pasteboard } from '@kit.BasicServicesKit';
import { ArtworkCache } from '../utils/ArtworkCache';
import { ShareUtils } from '../utils/ShareUtils';
import { MusicItem, LyricSource } from '../common/model/MediaTypes';
import { SheetItem } from '../common/model/SheetTypes';
import { pluginManager } from '../plugin/PluginManager';
import { trackPlayer } from '../core/TrackPlayer';
import { musicSheet } from '../core/MusicSheet';
import { localMusicSheet, downloadedSheet } from '../core/LocalMusicSheet';
import { LocalMusicExclusion } from '../core/LocalMusicExclusion';
import { downloader, Downloader } from '../core/Downloader';
import { appConfig } from '../core/AppConfig';
import { ScheduleClose } from '../utils/ScheduleClose';
import { MediaUtils } from '../utils/MediaUtils';
import { FileUtils } from '../utils/FileUtils';
import { CoverSearch } from '../utils/CoverSearch';
import { TagEditor } from '../utils/TagEditor';
import { TagEditFields } from '../utils/TagEditor';
import { appState } from '../entryability/AppState';
import { sheetPreferType, sheetTopAvoidVp } from '../utils/BreakpointUtils';
  import { DialogManager, MetaEditFieldDesc } from '../utils/DialogUtils';
  import { LyricSearch } from '../utils/LyricSearch';
  import { lyricManager } from '../core/LyricManager';
import { LOCAL_PLUGIN_PLATFORM } from '../common/Consts';
import { showUiToast } from '../utils/UiUtils';

/** 快捷操作按钮数据（ForEach 数据源） */
class QuickActionSpec {
  icon: Resource;
  label: string;
  isHighlight: boolean;
  onTap: () => void;

  constructor(icon: Resource, label: string, onTap: () => void, isHighlight: boolean = false) {
    this.icon = icon;
    this.label = label;
    this.onTap = onTap;
    this.isHighlight = isHighlight;
  }
}

/** 操作/详情行数据（ForEach 数据源；isDetail 为 true 时用可复制的信息行样式） */
class OptionEntry {
  icon: Resource;
  label: string;
  value: string;
  isDetail: boolean;
  onTap: () => void;

  constructor(icon: Resource, label: string, onTap: () => void,
    value: string = '', isDetail: boolean = false) {
    this.icon = icon;
    this.label = label;
    this.onTap = onTap;
    this.value = value;
    this.isDetail = isDetail;
  }
}

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
        .fontColor(this.isHighlight ? appState.accentColor : $r('sys.color.font_secondary'))
        .maxLines(1)
    }
    .width(64)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.onTap();
    })
  }
}

/** 信息展示行（ID/歌手/专辑：点击复制右侧文本） */
@ComponentV2
struct DetailRowItem {
  @Require @Param icon: Resource;
  @Require @Param label: string;
  @Require @Param value: string;
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
      Text(this.value.length > 0 ? this.value : '-')
        .fontSize(12)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '60%' })
      // 复制提示图标（无内容时隐藏）
      if (this.value.length > 0) {
        SymbolGlyph($r('sys.symbol.doc_filled_on_doc'))
          .fontSize(16)
          .fontColor([$r('sys.color.icon_tertiary')])
      }
    }
    .width('100%')
    .height(48)
    .onClick(() => {
      this.onTap();
    })
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
  /** 本地音乐列表面板（仅 DownloadPage 本地模式传 true）：追加移出/删除入口 */
  @Param localListMode: boolean = false;
  /** 从该歌单移除本曲（我的歌单进入的歌单详情页传入歌单 id）：显示「从当前歌单删除」入口 */
  @Param removeSheetId: string = '';
  @Param isGoalForegroundBlur: boolean = true;
  /** 面板消失回调（页面将 show 置回 false） */
  @Event onClose: () => void = (): void => {};
  @Event appear: () => void = (): void => {};

  @Local isFavorited: boolean = false;
  @Local showSheetPicker: boolean = false;
  @Local pickerInCreateMode: boolean = false;
  @Local newSheetTitle: string = '';
  /** 来源行展示的插件名（换源成功后更新为新插件） */
  @Local sourcePlatform: string = '';
  /** 头部/详情展示与后续操作共用的副本：面板打开时取自 optionsItem，
   *  保存标签/更新封面后替换实例即时刷新（父页面克隆 optionsItem 不会被动更新，故内部一律用本副本） */
  @Local displayItem: MusicItem = new MusicItem();

  @Monitor('show')
  onShowChange(): void {
    if (this.show) {
      this.isFavorited = this.checkFavorited(this.optionsItem);
      this.sourcePlatform = this.optionsItem.platform;
      this.displayItem = this.optionsItem.clone();
    }
  }

  private showToast(message: string): void {
    showUiToast(this.getUIContext(), message);
  }

  /** 快捷操作按钮列表（收藏状态实时计算） */
  private quickActionSpecs(): Array<QuickActionSpec> {
    const items: Array<QuickActionSpec> = [];
    items.push(new QuickActionSpec(
      this.isFavorited ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
      this.isFavorited ? '取消收藏' : '收藏',
      (): void => { this.toggleFavorite(); },
      this.isFavorited));
    items.push(new QuickActionSpec($r('sys.symbol.plus_square_on_square'), '添加到歌单',
      (): void => { this.openSheetPicker(); }));
    items.push(new QuickActionSpec($r('sys.symbol.forward_end_fill'), '下一首播放',
      (): void => { this.playNext(); }));
    items.push(new QuickActionSpec($r('sys.symbol.share'), '分享',
      (): void => { this.shareCurrent(); }));
    return items;
  }

  /** 操作/详情行列表（条件项按当前状态过滤；本地已有文件的条目不提供下载入口） */
  private optionEntries(): Array<OptionEntry> {
    const isLocalExisting = localMusicSheet.isLocalMusicExisting(this.displayItem) !== null ||
      downloadedSheet.isLocalMusicExisting(this.displayItem) !== null;
    const items: Array<OptionEntry> = [];
    items.push(new OptionEntry($r('sys.symbol.link'), '来源',
      (): void => { this.changeSource(); }, this.sourcePlatform));
    items.push(new OptionEntry($r('sys.symbol.hash'), 'ID',
      (): void => { this.copyText(this.displayItem.id, 'ID'); }, this.displayItem.id, true));
    items.push(new OptionEntry($r('sys.symbol.person'), '歌手',
      (): void => { this.copyText(this.displayItem.artist, '歌手'); }, this.displayItem.artist, true));
    items.push(new OptionEntry($r('sys.symbol.opticaldisc'), '专辑',
      (): void => { this.copyText(this.displayItem.album, '专辑'); }, this.displayItem.album, true));
    if (isLocalExisting) {
      // 本地音乐/已下载条目：显示实际文件名，点击弹窗确认后转换为简洁命名
      items.push(new OptionEntry($r('sys.symbol.save'), '本地文件名',
        (): void => { this.confirmSimpleRename(); }, this.localFileNameText()));
      // 文件可写（非媒体库条目）且未在播放：显示标签编辑入口，修改写回音频文件
      if (TagEditor.canEdit(this.displayItem)) {
        items.push(new OptionEntry($r('sys.symbol.square_and_pencil'), '编辑音频文件元数据',
          (): void => { this.openMetaEditor(); }));
      }
    } else {
      // 本地/已下载音乐已在设备上，不提供下载入口（文件被外部删除时恢复入口）
      items.push(new OptionEntry($r('sys.symbol.square_and_arrow_down'), '下载',
        (): void => { this.downloadCurrent(); }));
    }
    items.push(new OptionEntry($r('sys.symbol.moon_z'), '定时关闭',
      (): void => { this.showSleepMenu(); }, this.sleepStatusText()));
    items.push(new OptionEntry($r('sys.symbol.doc_plaintext'), '搜索歌词',
      (): void => { this.searchLyric(); }));
    items.push(new OptionEntry($r('sys.symbol.wand_and_stars'), '自动匹配封面',
      (): void => { this.searchCoverForCurrent(); }));
    items.push(new OptionEntry($r('sys.symbol.ohos_photo'), '手选匹配封面',
      (): void => { this.pickCoverForCurrent(); }));
    items.push(new OptionEntry($r('sys.symbol.list_bullet'), '加入播放队列',
      (): void => { this.addToPlayQueue(); }));
    // 我的歌单进入的歌单详情页：从当前歌单删除本曲
    if (this.removeSheetId.length > 0) {
      items.push(new OptionEntry($r('sys.symbol.trash'), '从当前歌单删除',
        (): void => { this.removeFromCurrentSheet(); }));
    }
    // 仅本地音乐列表的详情面板：移出本地音乐列表 / 删除歌曲文件
    if (this.localListMode) {
      items.push(new OptionEntry($r('sys.symbol.trash'), '移出本地音乐列表',
        (): void => { this.removeFromLocalMusic(); }));
      items.push(new OptionEntry($r('sys.symbol.trash'), '删除歌曲文件',
        (): void => { this.deleteLocalMusicFile(); }));
    }
    return items;
  }

  /** 复制文本到剪贴板（详情行 ID/歌手/专辑） */
  private copyText(text: string, label: string): void {
    if (text.length === 0) {
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setData(data).then((): void => {
        this.showToast('已复制' + label);
      }).catch((_e: Object): void => {
        this.showToast('复制失败');
      });
    } catch (error) {
      this.showToast('复制失败');
    }
  }

  /** 本地文件名（本地音乐/已下载条目详情行展示；无本地文件时为空） */
  private localFileNameText(): string {
    const lp = MediaUtils.getLocalPath(this.displayItem);
    if (lp === null || lp.length === 0 || lp.startsWith('content://')) {
      return '';
    }
    return FileUtils.getFileName(FileUtils.normalizePath(lp));
  }

  /** 转换为简洁命名：先校验（正在播放/媒体库歌曲/已是简洁命名直接提示），再弹窗确认 */
  private confirmSimpleRename(): void {
    if (trackPlayer.isCurrentMusic(this.displayItem)) {
      this.showToast('正在播放的歌曲无法转换');
      return;
    }
    const lp = MediaUtils.getLocalPath(this.displayItem);
    if (lp === null || lp.length === 0) {
      this.showToast('未找到本地文件');
      return;
    }
    if (lp.startsWith('content://')) {
      this.showToast('媒体库歌曲不支持转换');
      return;
    }
    const src = FileUtils.normalizePath(lp);
    // 已是简洁命名（无冲突后缀）则直接提示
    if (FileUtils.getFileName(src, true) === Downloader.simpleFilename(this.displayItem)) {
      this.showToast('当前已是简洁命名');
      return;
    }
    DialogManager.ConfirmSimpleRename(
      '是否将「' + FileUtils.getFileName(src) + '」转换为「歌曲名-歌手」简洁命名？',
      (): void => {
        this.doSimpleRename(this.displayItem);
      });
  }

  /** 执行转换为简洁命名：弹窗内显示 loading，完成后关闭弹窗并提示结果 */
  private async doSimpleRename(item: MusicItem): Promise<void> {
    // 显示 loading，让出主线程让 loading 渲染后再执行重命名
    appState.isDialogSaving = true;
    await new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, 300);
    });
    const result = Downloader.renameToSimpleFilename(item);
    appState.isDialogSaving = false;
    DialogManager.CloseDialog();
    if (result === 1) {
      this.showToast('已转换为「' + Downloader.simpleFilename(item) + '」');
    } else if (result === 0) {
      this.showToast('已是简洁命名或正在播放，已跳过');
    } else {
      this.showToast('转换失败');
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
    const target = this.displayItem;
    if (this.isFavorited) {
      musicSheet.removeMusic(musicSheet.defaultSheet.id, [target]).then((): void => {
        this.isFavorited = false;
        this.showToast('已取消收藏');
      });
    } else {
      musicSheet.addMusic(musicSheet.defaultSheet.id, target).then((): void => {
        this.isFavorited = true;
        this.showToast('已收藏到「我的收藏」');
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
    const target = this.displayItem;
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
      return musicSheet.addMusic(sheetId, this.displayItem);
    }).then((): void => {
      this.showSheetPicker = false;
      this.showToast('已创建歌单并添加');
    });
  }

  private playNext(): void {
    trackPlayer.addNext(this.displayItem);
    this.showToast('将在下一首播放');
  }

  /** 更换音源：打开弹窗并发搜索可用音源（弹窗内加载动画→插件选择列表），确认后替换并保存（队列/我的歌单） */
  private changeSource(): void {
    const item = this.displayItem;
    if (localMusicSheet.isLocalMusicExisting(item) !== null || downloadedSheet.isLocalMusicExisting(item) !== null ||
      item.platform === LOCAL_PLUGIN_PLATFORM) {
      this.showToast('本地音乐不支持更换音源');
      return;
    }
    DialogManager.changeSourceItem = item;
    DialogManager.changeSourceCandidates = [];
    DialogManager.changeSourceIndex = 0;
    DialogManager.changeSourceConfirm = (index: number): void => {
      const candidates = DialogManager.changeSourceCandidates;
      if (index < 0 || index >= candidates.length) {
        return;
      }
      const target = candidates[index];
      if (trackPlayer.isCurrentMusic(item)) {
        // 正在播放：替换队列并从新音源播放，同时保存到包含它的歌单
        trackPlayer.changeSource(target).then((ok: boolean): void => {
          if (ok) {
            musicSheet.replaceMusicEverywhere(item, target);
            this.sourcePlatform = target.platform;
            this.showToast('已更换为「' + target.platform + '」音源');
          } else {
            this.showToast('更换音源失败');
          }
        });
        return;
      }
      // 非播放中：替换队列中的同曲条目并保存到包含它的歌单
      const inQueue = trackPlayer.replaceInQueue(item, target);
      const saved = musicSheet.replaceMusicEverywhere(item, target);
      if (inQueue || saved > 0) {
        this.sourcePlatform = target.platform;
        this.showToast('已更换为「' + target.platform + '」音源');
      } else {
        this.showToast('该歌曲不在播放队列或我的歌单中');
      }
    };
    DialogManager.OpenDialog('更换音源');
  }

  private shareCurrent(): void {
    // 本地文件直接发文件；网络歌曲发带标记文本（接收端 MusicFreeOH 可导入/播放）
    ShareUtils.shareMusic(this.displayItem, (message: string): void => {
      this.showToast(message);
    });
  }

  private downloadCurrent(): void {
    if (downloader.getDownloadTask(this.displayItem) !== null) {
      this.showToast('已在下载列表中');
      return;
    }
    // 弹窗填写目标子文件夹（留空 = 默认下载目录）
    DialogManager.downloadFolderValue = '';
    DialogManager.downloadFolderConfirm = (folder: string): void => {
      downloader.download(this.displayItem, appConfig.getDefaultDownloadQuality(), folder);
      this.showToast('已加入下载队列');
    };
    DialogManager.OpenDialog('下载到文件夹');
  }

  private showSleepMenu(): void {
    // TextPicker 滚轮选择：确定生效，取消/关闭弹窗不更改
    DialogManager.pickerTitle = '定时关闭';
    DialogManager.pickerOptions = ['关闭定时', '播完当前歌曲', '15分钟', '30分钟', '60分钟'];
    DialogManager.pickerIndex = ScheduleClose.isCloseAfterPlayEnd() ? 1 : 0;
    DialogManager.pickerConfirm = (index: number): void => {
      this.applySleepChoice(index);
    };
    DialogManager.OpenDialog('选择器');
  }

  private applySleepChoice(index: number): void {
    // 可选分钟数（对应选项「15分钟 / 30分钟 / 60分钟」）
    const SLEEP_MINUTES: Array<number> = [15, 30, 60];
    if (index === 0) {
      ScheduleClose.setCloseAfterPlayEnd(false);
      ScheduleClose.setScheduleClose(null);
      this.showToast('已关闭定时');
    } else if (index === 1) {
      ScheduleClose.setCloseAfterPlayEnd(true);
      ScheduleClose.setScheduleClose(Date.now() + 1000);
      this.showToast('将在播完当前歌曲后关闭');
    } else if (index >= 2 && index <= 4) {
      const minutes = SLEEP_MINUTES[index - 2];
      ScheduleClose.setCloseAfterPlayEnd(false);
      ScheduleClose.setScheduleClose(Date.now() + minutes * 60 * 1000);
      this.showToast('将在' + minutes.toString() + '分钟后关闭');
    }
  }

  private sleepStatusText(): string {
    if (ScheduleClose.getDeadline() !== null) {
      return '已开启';
    }
    return '';
  }

  /** 搜索歌词：弹窗选择歌词音源插件，从该插件匹配歌词；若目标正在播放则同步刷新歌词 */
  private searchLyric(): void {
    const target = this.displayItem;
    const plugins = LyricSearch.lyricSourcePlugins();
    if (plugins.length === 0) {
      this.showToast('无可用插件');
      return;
    }
    const names: Array<string> = [LyricSearch.AUTO_SOURCE];
    for (const p of plugins) {
      names.push(p.name);
    }
    DialogManager.SelectLyricSource(target, names, (pluginName: string): void => {
      this.showToast('正在搜索歌词...');
      LyricSearch.searchLyric(target, pluginName).then((lyric: LyricSource | null): void => {
        if (lyric !== null && !lyric.isEmpty()) {
          if (trackPlayer.isCurrentMusic(target)) {
            lyricManager.reloadLyric();
          }
          this.showToast('歌词已缓存');
        } else {
          this.showToast('未找到歌词');
        }
      }).catch((_e: Object): void => {
        this.showToast('歌词获取失败');
      });
    });
  }

  private addToPlayQueue(): void {
    trackPlayer.add(this.displayItem);
    this.showToast('已加入播放队列');
  }

  /** 搜索封面（仅本地音乐显示）：来源插件详情优先，其次全插件按 标题+歌手 搜索；
   *  命中后写回本地条目，文件可写时同步写入音频文件内嵌封面 */
  private searchCoverForCurrent(): void {
    const target = this.displayItem;
    this.showToast('正在搜索封面...');
    CoverSearch.searchAndApply(target).then((artwork: string): void => {
      if (artwork.length === 0) {
        this.showToast('未找到封面');
        return;
      }
      this.syncDisplayArtwork(artwork);
      this.showToast('封面已更新');
      this.writeCoverToFileIfPossible(target, artwork);
    }).catch((_e: Object): void => {
      this.showToast('封面获取失败');
    });
  }

  /** 选择封面（仅本地音乐/已下载显示）：弹窗展示候选封面，点选后写回本地条目并刷新播放页；
   *  文件可写时同步写入音频文件内嵌封面 */
  private pickCoverForCurrent(): void {
    const target = this.displayItem;
    DialogManager.PickCover(target, (artwork: string): void => {
      if (artwork.length > 0) {
        CoverSearch.applyArtwork(target, artwork);
        this.syncDisplayArtwork(artwork);
        this.showToast('封面已更新');
        this.writeCoverToFileIfPossible(target, artwork);
      }
    });
  }

  /** 同步展示副本的封面（替换实例触发头部刷新） */
  private syncDisplayArtwork(artwork: string): void {
    const next = this.displayItem.clone();
    next.artwork = artwork;
    this.displayItem = next;
  }

  /** 封面写入音频文件（设置「匹配封面后写入音频文件」开启且文件可写时）：
   *  解码为 PixelMap 后写入内嵌封面标签 */
  private async writeCoverToFileIfPossible(target: MusicItem, artwork: string): Promise<void> {
    if (!appConfig.getCoverWriteToFile() || !TagEditor.canEdit(target)) {
      return;
    }
    const pixelMap = await ArtworkCache.loadPixelMap(artwork);
    if (pixelMap === null) {
      this.showToast('封面已更新，写入文件失败');
      return;
    }
    const outcome = await TagEditor.writeCover(target, pixelMap);
    this.showToast(outcome.ok ? '封面已写入音频文件' : '封面写入文件失败');
  }

  /** 打开标签编辑弹窗（仅本地音乐/已下载且文件可写时显示入口）：预填当前标题/歌手/专辑 */
  private openMetaEditor(): void {
    DialogManager.EditMeta(this.displayItem, (fields: Array<MetaEditFieldDesc>): void => {
      this.performMetaEdit(fields);
    });
  }

  /** 保存标签编辑：写入音频文件并同步应用内记录；校验失败或写入失败保持弹窗打开便于重试 */
  private async performMetaEdit(fields: Array<MetaEditFieldDesc>): Promise<void> {
    const title = fields[0].value.trim();
    if (title.length === 0) {
      DialogManager.Toast('标题不能为空');
      return;
    }
    appState.isDialogSaving = true;
    // 让出主线程让 loading 先渲染，再执行文件写入
    await new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, 300);
    });
    const editFields = new TagEditFields();
    editFields.title = title;
    editFields.artist = fields[1].value.trim();
    editFields.album = fields[2].value.trim();
    const outcome = await TagEditor.editLocalMusic(this.displayItem, editFields);
    appState.isDialogSaving = false;
    if (outcome.ok) {
      // 同步展示副本（替换实例触发头部/详情行刷新）
      const next = this.displayItem.clone();
      next.title = title;
      next.artist = fields[1].value.trim();
      next.album = fields[2].value.trim();
      this.displayItem = next;
      DialogManager.CloseDialog();
      this.showToast('已保存到音频文件');
    } else {
      DialogManager.Toast(outcome.message.length > 0 ? outcome.message : '保存失败');
    }
  }

  /** 从当前歌单删除本曲（仅歌单详情页本地歌单面板显示；弹窗确认，取消不删除）；
   * 列表随 onMusicListUpdated 自动刷新 */
  private removeFromCurrentSheet(): void {
    const target = this.displayItem;
    const sheetId = this.removeSheetId;
    this.onClose();
    DialogManager.ConfirmDelete('确定从当前歌单删除「' + target.title + '」吗？', (): void => {
      musicSheet.removeMusic(sheetId, [target]).then((): void => {
        this.showToast('已从歌单中删除');
      });
    });
  }

  /** 移出本地音乐列表（保留文件；写入排除名单防止扫描复活）；弹窗确认，取消不移出；
   *  仅本地音乐列表面板显示 */
  private removeFromLocalMusic(): void {
    const target = this.displayItem;
    this.onClose();
    DialogManager.ConfirmRemove('确定将「' + target.title + '」移出本地音乐列表吗？文件将保留在设备上，且不再被自动导入', (): void => {
      LocalMusicExclusion.excludeItem(target);
      localMusicSheet.removeMusic(target, false).then((): void => {
        this.showToast('已移出本地音乐');
      });
    });
  }

  /** 删除歌曲与本地文件（已下载列表同步移除记录；弹窗确认，取消不删除）；仅本地音乐列表面板显示 */
  private deleteLocalMusicFile(): void {
    const target = this.displayItem;
    this.onClose();
    DialogManager.ConfirmDelete('确定删除「' + target.title + '」及其本地文件吗？', (): void => {
      localMusicSheet.removeMusic(target, true).then((): void => {
        this.showToast('已删除歌曲与本地文件');
      });
    });
  }

  build() {
    // 两个空节点分别挂载操作面板与歌单选择器（二级半模态），互不影响
    Column() {
      Column()
        .bindSheet(!!this.showSheetPicker, this.SheetPickerBuilder(), {
          scrollSizeMode: ScrollSizeMode.CONTINUOUS, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          dragBar: true, preferType: sheetPreferType(),
          onDisappear: () => {
            this.showSheetPicker = false;
            this.pickerInCreateMode = false;
          }
        })
    }
    .width('100%')
    .height(0)
    .bindSheet(!!this.show, this.OptionsSheetBuilder(), {
      scrollSizeMode: ScrollSizeMode.CONTINUOUS, detents: [600, SheetSize.LARGE],
      dragBar: true,
      preferType: SheetType.CENTER,
      onWillDisappear: () => {
        this.onClose();
        if (this.isGoalForegroundBlur) {
          appState.isForegroundBlur = false;
        }
      },
      onWillAppear: () => {
        this.appear()
        if (this.isGoalForegroundBlur) {
          appState.isForegroundBlur = true;
        }
      }
    })
  }

  /** 歌曲操作面板：头部 + 快捷操作 + 详情/操作列表 */
  @Builder
  OptionsSheetBuilder() {
    Column() {
      Row({ space: 12 }) {
        if (this.displayItem.artwork.length > 0) {
          Image(ArtworkCache.resolve(this.displayItem.artwork))
            .width(64)
            .height(64)
            .borderRadius(10)
            .objectFit(ImageFit.Cover)
            .alt($r('app.media.altImage'))
            .draggable(false)
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
          Text(this.displayItem.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .width('70%')
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.displayItem.artist)
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.displayItem.album.length > 0 ? this.displayItem.album : '未知专辑')
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
        ForEach(this.quickActionSpecs(), (spec: QuickActionSpec) => {
          QuickActionItem({
            icon: spec.icon,
            label: spec.label,
            isHighlight: spec.isHighlight,
            onTap: spec.onTap
          })
        }, (spec: QuickActionSpec) => spec.label + (spec.isHighlight ? '_on' : '_off'))
      }
      .width('100%')
      .margin({ top: 20 })
      .justifyContent(FlexAlign.SpaceBetween)

      Divider()
        .width('100%')
        .margin({ top: 12, bottom: 4 })

      List() {
        ForEach(this.optionEntries(), (entry: OptionEntry) => {
          ListItem() {
            if (entry.isDetail) {
              DetailRowItem({
                icon: entry.icon,
                label: entry.label,
                value: entry.value,
                onTap: entry.onTap
              })
            } else {
              ActionRowItem({
                icon: entry.icon,
                label: entry.label,
                value: entry.value,
                onTap: entry.onTap
              })
            }
          }
        }, (entry: OptionEntry) => entry.label + '_' + entry.value)
      }
      .width('100%')
      .nestedScroll({
        scrollForward: NestedScrollMode.PARENT_FIRST,
        scrollBackward: NestedScrollMode.SELF_FIRST
      })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12 + sheetTopAvoidVp(), bottom: 32 })
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
        // 小标题「我的歌单」，右侧新建歌单图标
        Row() {
          Text('我的歌单')
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(18)
            .fontColor([$r('sys.color.icon_secondary')])
            .onClick(() => {
              this.pickerInCreateMode = true;
            })
        }
        .width('100%')
        .margin({ top: 8, bottom: 4 })
        List() {
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
        .divider({
          strokeWidth: 0.5,
          color: $r('sys.color.comp_divider'),
          startMargin: 0,
          endMargin: 0
        })
        .width('100%')
        .margin({ top: 4 })
        .nestedScroll({
          scrollForward: NestedScrollMode.PARENT_FIRST,
          scrollBackward: NestedScrollMode.SELF_FIRST
        })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12 + sheetTopAvoidVp(), bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }
}
