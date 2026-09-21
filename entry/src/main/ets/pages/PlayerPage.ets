import { pasteboard } from '@kit.BasicServicesKit';
import { ArtworkCache } from '../utils/ArtworkCache';
import { AVCastPicker } from '@kit.AVSessionKit';
import { MusicItem, QualityKey, QUALITY_KEYS } from '../common/model/MediaTypes';
import { CommentItem, CommentsResult } from '../common/model/SheetTypes';
import { CommentDataSource } from '../common/model/CommentDataSource';
import { PlayState, playerEngine } from '../core/PlayerEngine';
import { MusicRepeatMode } from '../common/Consts';
import { musicSheet } from '../core/MusicSheet';
import { trackPlayer } from '../core/TrackPlayer';
import { lyricManager, LyricState } from '../core/LyricManager';
import { ParsedLrcItem } from '../utils/LyricParser';
import { MediaUtils } from '../utils/MediaUtils';
import { appState } from '../entryability/AppState';
import { playerAnim, PlayerExpandAnimController } from '../view/PlayerExpandAnim';
import { QueueSheet } from '../view/QueueSheet';
import { MusicOptionsSheet } from '../view/MusicOptionsSheet';
import { pluginManager } from '../plugin/PluginManager';
import { downloader } from '../core/Downloader';
import { appConfig } from '../core/AppConfig';
import { localMusicSheet, downloadedSheet } from '../core/LocalMusicSheet';
import { DialogManager } from '../utils/DialogUtils';
import { contentMaxWidthVp, isLandscapeLayout as isLandscapeBreakpoint, sheetTopAvoidVp, useSidebarLayout } from '../utils/BreakpointUtils';

/**
 * 全屏播放页（结构参考官方多设备音乐最佳实践）：
 * 顶部栏（收起/分享）+ 封面区（左滑/点击进歌词）+ 当前行歌词 + 进度条
 * + 播放控制（循环/上一首/播放/下一首/队列）+ 底部功能（收藏/下载/评论/音质/音效/更多）
 * 背景为当前封面高斯模糊 + 主题色蒙层
 */
@ComponentV2
export struct PlayerPage {
  @Local currentMusic: MusicItem | null = null;
  @Local isPlaying: boolean = false;
  @Local currentPosition: number = 0;
  @Local duration: number = 0;
  @Local repeatMode: MusicRepeatMode = MusicRepeatMode.QUEUE;
  @Local isFavorited: boolean = false;
  @Local lyricLoading: boolean = true;
  @Local currentLyric: ParsedLrcItem | null = null;
  /** 完整歌词列表（歌词模式下滚动展示） */
  @Local lyrics: Array<ParsedLrcItem> = [];
  /** 是否含翻译 */
  @Local hasTranslation: boolean = false;
  /** 歌词模式（点击封面或左滑进入，歌词区右滑返回封面） */
  @Local showLyric: boolean = false;
  /** 播放队列半模态 */
  @Local showQueue: boolean = false;
  /** 「更多」歌曲操作半模态（复用搜索页组件） */
  @Local showMore: boolean = false;
  /** 评论半模态 */
  @Local showComments: boolean = false;
  @Local comments: Array<CommentItem> = [];
  @Local commentsLoading: boolean = false;
  @Local commentsEnded: boolean = false;
  /** 评论懒加载数据源（与 comments 同步） */
  private commentSource: CommentDataSource = new CommentDataSource();
  /** 音效开关 */
  @Local audioEffectOn: boolean = true;
  /** 用户拖动进度条期间不回写进度事件 */
  private isSeeking: boolean = false;
  /** 用户手动滚动歌词期间暂停自动居中；松手 3 秒后恢复 */
  private userScrolling: boolean = false;
  private userScrollTimer: number = -1;
  private lyricScroller: Scroller = new Scroller();
  private commentsPage: number = 1;
  /** 评论请求序号：仅采纳最新一次请求的结果 */
  private commentsReqId: number = 0;
  private offCurrent: () => void = (): void => {
  };
  private offState: () => void = (): void => {
  };
  private offProgress: () => void = (): void => {
  };
  private offLyricState: () => void = (): void => {
  };
  private offCurrentLyric: () => void = (): void => {
  };

  aboutToAppear(): void {
    this.currentMusic = trackPlayer.currentMusic;
    this.isPlaying = trackPlayer.playState === PlayState.Playing;
    const progress = trackPlayer.getProgress();
    this.currentPosition = progress.position;
    this.duration = progress.duration;
    this.repeatMode = trackPlayer.repeatMode;
    this.audioEffectOn = playerEngine.audioEffectEnabled;
    this.refreshFavorite();
    this.syncLyricState(lyricManager.lyricState);
    this.currentLyric = lyricManager.currentLyricItem;

    this.offCurrent = trackPlayer.onCurrentMusicChanged((music: MusicItem | null) => {
      this.currentMusic = music;
      this.currentPosition = 0;
      this.refreshFavorite();
    });
    this.offState = trackPlayer.onPlayStateChanged((state: PlayState) => {
      this.isPlaying = state === PlayState.Playing;
    });
    this.offProgress = trackPlayer.onProgressChanged((position: number, duration: number) => {
      if (duration > 0) {
        this.duration = duration;
      }
      if (!this.isSeeking) {
        this.currentPosition = position;
      }
    });
    this.offLyricState = lyricManager.onLyricStateChanged((state: LyricState) => {
      this.syncLyricState(state);
    });
    this.offCurrentLyric = lyricManager.onCurrentLyricChanged((item: ParsedLrcItem | null) => {
      this.currentLyric = item;
      this.autoScrollToCurrentLyric();
    });
    // 收起完成时重置歌词态，保证下次展开时封面占位可测量
    playerAnim.onCollapsed = (): void => {
      this.showLyric = false;
    };
  }

  aboutToDisappear(): void {
    playerAnim.onCollapsed = null;
    this.offCurrent();
    this.offState();
    this.offProgress();
    this.offLyricState();
    this.offCurrentLyric();
    if (this.userScrollTimer !== -1) {
      clearTimeout(this.userScrollTimer);
      this.userScrollTimer = -1;
    }
  }

  private syncLyricState(state: LyricState): void {
    this.lyricLoading = state.loading;
    this.lyrics = state.lyrics;
    this.hasTranslation = state.hasTranslation;
  }

  /** 歌词行变化时自动居中滚动（歌词可见（歌词模式或分栏常驻）且用户未在手动滚动时） */
  private autoScrollToCurrentLyric(): void {
    if ((!this.showLyric && !this.useSplitLayout()) || this.userScrolling) {
      return;
    }
    this.scrollToCurrentLyric(true);
  }

  /** 滚动到当前歌词行（居中对齐，参考官方 FAQ 列表定位方案；下标 +1 跳过顶部占位项） */
  private scrollToCurrentLyric(animated: boolean): void {
    const current = this.currentLyric;
    if (current === null || current.index < 0 || current.index >= this.lyrics.length) {
      return;
    }
    try {
      this.lyricScroller.scrollToIndex(current.index + 1, animated, ScrollAlign.CENTER);
    } catch (error) {
      // 列表尚未布局完成时忽略
    }
  }

  /** 进入歌词模式：定位到当前行 */
  private enterLyricMode(): void {
    this.setLyricMode(true);
  }

  /** 切换封面/歌词模式（显式动画包裹挂载/卸载渐隐） */
  private setLyricMode(on: boolean): void {
    if (this.showLyric === on) {
      return;
    }
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      this.showLyric = on;
    });
    if (on) {
      this.scrollToCurrentLyric(false);
    }
  }

  /** 用户触摸歌词列表：按下暂停自动滚动，松手 3 秒后恢复 */
  private handleLyricTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.userScrolling = true;
      if (this.userScrollTimer !== -1) {
        clearTimeout(this.userScrollTimer);
        this.userScrollTimer = -1;
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.userScrollTimer !== -1) {
        clearTimeout(this.userScrollTimer);
      }
      this.userScrollTimer = setTimeout((): void => {
        this.userScrolling = false;
        this.userScrollTimer = -1;
      }, 3000);
    }
  }

  /** 判断是否为当前歌词行 */
  private isCurrentLyric(item: ParsedLrcItem): boolean {
    const current = this.currentLyric;
    return current !== null && current.index === item.index && current.time === item.time;
  }

  private refreshFavorite(): void {
    const current = this.currentMusic;
    if (current === null) {
      this.isFavorited = false;
      return;
    }
    const favList = musicSheet.getMusicList(musicSheet.defaultSheet.id);
    for (const it of favList) {
      if (MediaUtils.isSameMediaItem(it, current)) {
        this.isFavorited = true;
        return;
      }
    }
    this.isFavorited = false;
  }

  private toggleFavorite(): void {
    const current = this.currentMusic;
    if (current === null) {
      return;
    }
    if (this.isFavorited) {
      musicSheet.removeMusic(musicSheet.defaultSheet.id, [current]).then((): void => {
        this.isFavorited = false;
        this.showToast('已取消收藏');
      });
    } else {
      musicSheet.addMusic(musicSheet.defaultSheet.id, current).then((): void => {
        this.isFavorited = true;
        this.showToast('已收藏到「我的收藏」');
      });
    }
  }

  /** 下载当前歌曲（本地/已下载音乐除外；已在下载列表中则提示） */
  private downloadCurrent(): void {
    const current = this.currentMusic;
    if (current === null) {
      return;
    }
    if (localMusicSheet.isLocalMusic(current) !== null || downloadedSheet.isLocalMusic(current) !== null) {
      this.showToast('本地音乐无需下载');
      return;
    }
    if (downloader.getDownloadTask(current) !== null) {
      this.showToast('已在下载列表中');
      return;
    }
    // 弹窗填写目标子文件夹（留空 = 默认下载目录），与歌曲操作面板一致
    DialogManager.downloadFolderValue = '';
    DialogManager.downloadFolderConfirm = (folder: string): void => {
      downloader.download(current, appConfig.getDefaultDownloadQuality(), folder);
      this.showToast('已加入下载队列');
    };
    DialogManager.OpenDialog('下载到文件夹');
  }

  /** 当前歌曲的插件是否支持获取评论 */
  private canComment(): boolean {
    const current = this.currentMusic;
    if (current === null) {
      return false;
    }
    const plugin = pluginManager.getByMedia(current);
    return plugin !== null && plugin.hasMethod('getMusicComments');
  }

  private openComments(): void {
    if (!this.canComment()) {
      this.showToast('当前歌曲不支持评论');
      return;
    }
    this.comments = [];
    this.commentSource.reload(this.comments);
    this.commentsEnded = false;
    this.commentsLoading = true;
    this.commentsPage = 1;
    this.showComments = true;
    this.loadComments(1);
  }

  private loadComments(page: number): void {
    const current = this.currentMusic;
    const plugin = current === null ? null : pluginManager.getByMedia(current);
    if (current === null || plugin === null) {
      this.commentsLoading = false;
      return;
    }
    this.commentsReqId += 1;
    const reqId = this.commentsReqId;
    plugin.methods.getMusicComments(current, page).then((result: CommentsResult): void => {
      if (reqId !== this.commentsReqId) {
        return;
      }
      if (page === 1) {
        this.comments = result.data;
      } else {
        this.comments = this.comments.concat(result.data);
      }
      this.commentSource.reload(this.comments);
      this.commentsEnded = result.isEnd;
      this.commentsPage = page;
      this.commentsLoading = false;
    }).catch((_e: Object): void => {
      if (reqId !== this.commentsReqId) {
        return;
      }
      this.commentsLoading = false;
      if (page === 1) {
        this.showToast('评论获取失败');
      }
    });
  }

  private loadMoreComments(): void {
    if (this.commentsLoading || this.commentsEnded) {
      return;
    }
    this.commentsLoading = true;
    this.loadComments(this.commentsPage + 1);
  }

  /** 音质选择：TextPicker 滚轮（当前档标注），确定生效，取消/关闭弹窗不更改 */
  private showQualityMenu(): void {
    const options: Array<string> = [];
    for (const q of QUALITY_KEYS) {
      options.push(PlayerPage.qualityLabel(q) + (q === trackPlayer.quality ? '（当前）' : ''));
    }
    DialogManager.pickerTitle = '切换音质';
    DialogManager.pickerOptions = options;
    DialogManager.pickerIndex = QUALITY_KEYS.indexOf(trackPlayer.quality);
    DialogManager.pickerConfirm = (index: number): void => {
      if (index < 0 || index >= QUALITY_KEYS.length) {
        return;
      }
      const quality = QUALITY_KEYS[index];
      if (quality === trackPlayer.quality) {
        return;
      }
      trackPlayer.changeQuality(quality).then((ok: boolean): void => {
        this.showToast(ok ? '已切换为' + PlayerPage.qualityLabel(quality) + '音质' : '音质切换失败');
      });
    };
    DialogManager.OpenDialog('选择器');
  }

  /** 切换系统音效开关 */
  private toggleAudioEffect(): void {
    const next = !this.audioEffectOn;
    playerEngine.setAudioEffectEnabled(next);
    this.audioEffectOn = next;
    this.showToast(next ? '音效已开启' : '音效已关闭');
  }

  /** 切换循环模式 */
  private toggleRepeatMode(): void {
    trackPlayer.toggleRepeatMode();
    this.repeatMode = trackPlayer.repeatMode;
    this.showToast(this.repeatMode === MusicRepeatMode.SHUFFLE ? '随机播放' :
      (this.repeatMode === MusicRepeatMode.SINGLE ? '单曲循环' : '列表循环'));
  }

  private togglePlay(): void {
    if (this.isPlaying) {
      trackPlayer.pause().catch((): void => {
      });
    } else {
      trackPlayer.play().catch((): void => {
      });
    }
  }

  private skipToPrevious(): void {
    trackPlayer.skipToPrevious().catch((): void => {
    });
  }

  private skipToNext(): void {
    trackPlayer.skipToNext().catch((): void => {
    });
  }

  /** 分享：复制歌曲信息 */
  private shareCurrent(): void {
    const current = this.currentMusic;
    if (current === null) {
      return;
    }
    const text = '「' + current.title + '」 - ' + current.artist + '（来自 ' + current.platform + '）';
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      this.showToast('已复制歌曲信息，可粘贴分享');
    }).catch((_e: Object): void => {
      this.showToast('复制失败');
    });
  }

  /** 循环模式图标：随机 / 单曲循环 / 列表循环 */
  private repeatIcon(): Resource {
    if (this.repeatMode === MusicRepeatMode.SHUFFLE) {
      return $r('sys.symbol.shuffle');
    }
    if (this.repeatMode === MusicRepeatMode.SINGLE) {
      return $r('sys.symbol.repeat_1');
    }
    return $r('sys.symbol.repeat');
  }

  /** 进度条最大值（时长未知时保持 1 避免除零） */
  private sliderMax(): number {
    return this.duration > 0 ? this.duration : 1;
  }

  private static qualityLabel(q: QualityKey): string {
    if (q === 'low') {
      return '低';
    }
    if (q === 'high') {
      return '高';
    }
    if (q === 'super') {
      return '超高';
    }
    return '标准';
  }

  /** 评论时间（兼容秒/毫秒两种时间戳；无效时返回空） */
  private static formatCommentTime(createAt: number): string {
    if (createAt <= 0) {
      return '';
    }
    const ms = createAt > 1000000000000 ? createAt : createAt * 1000;
    const d = new Date(ms);
    const y = d.getFullYear();
    const mo = d.getMonth() + 1;
    const day = d.getDate();
    return y.toString() + '-' + (mo < 10 ? '0' + mo.toString() : mo.toString()) + '-' +
      (day < 10 ? '0' + day.toString() : day.toString());
  }

  private static formatDuration(sec: number): string {
    const s = Math.max(0, Math.floor(sec));
    const m = Math.floor(s / 60);
    const r = s % 60;
    const mStr = m < 10 ? '0' + m.toString() : m.toString();
    const rStr = r < 10 ? '0' + r.toString() : r.toString();
    return mStr + ':' + rStr;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  // ==================== 断点适配 ====================

  /** 分栏布局（PC/窗口侧边栏模式、横屏/矮窗口，或宽度 lg 的宽屏）：左侧封面+控制组件纵向堆叠，右侧歌词常驻，无需封面/歌词切换 */
  private useSplitLayout(): boolean {
    return useSidebarLayout(appState.WidthBp, appState.screenWidth, appState.displayWidth) ||
      isLandscapeBreakpoint(appState.WidthBp, appState.HeightBp) || appState.WidthBp >= 2;
  }

  /** 分栏控件尺寸缩放：随窗口可用高度连续缩放（约 420vp 最紧凑 0.72，约 680vp 以上完整 1），
   *  避免按断点离散切换导致窗口尺寸变化时组件尺寸瞬间跳变 */
  private uiScale(): number {
    const h = (appState.screenHeight > 0 ? appState.screenHeight : playerAnim.screenHeight) -
      appState.topRect - appState.bottomRect;
    if (h <= 0) {
      return 1;
    }
    return Math.max(0.72, Math.min(1, (h - 420) / 260));
  }

  /** 大屏（lg）限宽居中，避免内容被拉满全屏；其余断点不限 */
  private bodyMaxWidth(): number {
    return contentMaxWidthVp(appState.WidthBp);
  }

  /** 分栏布局时压缩纵向间距，保证各组件完整展示不叠加 */
  private compactGap(vp: number): number {
    return this.useSplitLayout() ? Math.round(vp / 2) : vp;
  }

  build() {
    Stack() {
      // 背景：封面高斯模糊 + 主题色蒙层
      if (this.currentMusic !== null && this.currentMusic.artwork.length > 0) {
        Image(ArtworkCache.resolve(this.currentMusic.artwork))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(80)
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('sys.color.background_secondary'))
          .opacity(0.82)
        }

        if (this.currentMusic === null) {
          // 空态
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.music_note_list'))
              .fontSize(48)
              .fontColor([$r('sys.color.icon_tertiary')])
            Text('还没有正在播放的歌曲')
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.useSplitLayout()) {
          this.SplitBody()
        } else {
          this.PortraitBody()
        }



        // 「更多」歌曲操作面板（复用搜索页组件，内部自带 bindSheet）
        if (this.currentMusic !== null) {
          MusicOptionsSheet({
            show: this.showMore,
            optionsItem: this.currentMusic,
            onClose: (): void => {
              this.showMore = false;
            }
          })
        }

        // 评论半模态挂载点（独立锚点，避免与队列 bindSheet 冲突）
        Column()
          .width(0)
          .height(0)
          .bindSheet(!!this.showComments, this.CommentsSheetBuilder(), {
            scrollSizeMode: ScrollSizeMode.CONTINUOUS, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
            dragBar: true,
            backgroundColor: $r('sys.color.background_secondary'),
            onWillDisappear: () => {
              this.showComments = false;
              appState.isForegroundBlur = false;
            },
            onWillAppear: () => {
              appState.isForegroundBlur = true;
            }
          })
      }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_secondary'))
    .foregroundBlurStyle(appState.isForegroundBlur ? BlurStyle.Thin : BlurStyle.NONE,
      { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT, scale: 0.3 })
    // 展开态下拉收起：跟手 → 松手半屏判定回弹/收起（distance 20 防误触）
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 20 })
        .onActionUpdate((event: GestureEvent): void => {
          PlayerExpandAnimController.updateDrag(event.offsetY);
        })
        .onActionEnd((): void => {
          PlayerExpandAnimController.endDrag();
        })
    )
    .bindSheet(!!this.showQueue, this.QueueSheetBuilder(), {
      scrollSizeMode: ScrollSizeMode.CONTINUOUS, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      backgroundColor: $r('sys.color.background_secondary'),
      onWillDisappear: () => {
        this.showQueue = false;
        appState.isForegroundBlur = false;
      },
      onWillAppear: () => {
        appState.isForegroundBlur = true;
      }
    })
  }

  /** 竖屏布局（保持原样式）：顶部栏 + 封面/歌词 + 信息 + 当前行歌词 + 进度 + 控制 + 底部功能 */
  @Builder
  PortraitBody() {
    Column() {
      this.PlayerTopBar(true)
      if (!this.showLyric) {
        this.CoverArea()
      } else {
        this.LyricArea()
      }
      this.SongInfo(1)
      if (!this.showLyric) {
        this.CurrentLyricPreview()
      }
      this.ProgressArea(1)
      this.ControlsRow(1)
      this.BottomActions(1)
    }
    .width('100%')
    .height('100%')
    .constraintSize({ maxWidth: this.bodyMaxWidth() })
    .padding({
      left: 24,
      right: 24,
      top: appState.topRect + 8,
      bottom: appState.bottomRect + 20
    })
  }

  /** 分栏布局：左侧从上到下依次为封面 + 名称/副文本 + 进度条和时间 + 播控按钮排 + 其他功能按钮排，右侧歌词常驻滚动 */
  @Builder
  SplitBody() {
    Column() {
      this.PlayerTopBar(false)
      Row({ space: 36 }) {
        // 左右两列各占 50%：封面（自动缩小，杜绝与下方组件叠加）+ 信息 + 进度 + 播控 + 功能键
        Column() {
          this.SplitCoverSlot()
          this.SongInfo(this.uiScale())
          this.ProgressArea(this.uiScale())
          this.ControlsRow(this.uiScale())
          this.BottomActions(this.uiScale())
        }
        .layoutWeight(1)
        .height('100%')

        // 右侧：歌词常驻滚动（当前行自动居中）
        Column() {
          this.LyricArea()
        }
        .layoutWeight(1)
        .height('100%')
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: 32,
      right: 32,
      top: appState.topRect + 4,
      bottom: appState.bottomRect + 12
    })
  }

  /** 分栏封面位：占左侧剩余高度并保持正方形居中（上限 340），高度不足时自动缩小避免叠加 */
  @Builder
  SplitCoverSlot() {
    Column() {
      if (this.currentMusic !== null && this.currentMusic.artwork.length > 0) {
        Image(ArtworkCache.resolve(this.currentMusic.artwork))
          .height('100%')
          .aspectRatio(1)
          .constraintSize({ maxWidth: 340, maxHeight: 340 })
          .borderRadius(24)
          .objectFit(ImageFit.Cover)
          .shadow({
            radius: 80,
            color: ColoringStrategy.PRIMARY,
            offsetX: 0,
            offsetY: 0
          })
          .id('player_page_cover')
          .opacity(playerAnim.bigCoverHidden ? 0 : 1)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.music'))
            .fontSize(64)
            .fontColor([$r('sys.color.icon_secondary')])
        }
        .height('100%')
        .aspectRatio(1)
        .constraintSize({ maxWidth: 340, maxHeight: 340 })
        .borderRadius(24)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .id('player_page_cover')
        .opacity(playerAnim.bigCoverHidden ? 0 : 1)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .margin({ top: 4, bottom: 4 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /** 顶部栏：收起 + 封面/歌词切换（居中，宽屏分栏时常驻歌词无需切换） + 分享 */
  @Builder
  PlayerTopBar(showToggle: boolean) {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(26)
          .fontColor([$r('sys.color.icon_primary')])
          .onClick(() => {
            // 一镜到底收起回迷你条
            PlayerExpandAnimController.collapse();
          })
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)

      // 封面 | 歌词 分段切换（宽屏分栏下歌词常驻，隐藏切换）
      if (showToggle) {
        Row({ space: 2 }) {
          Text('封面')
            .fontSize(12)
            .fontWeight(this.showLyric ? FontWeight.Normal : FontWeight.Medium)
            .fontColor(this.showLyric ?
              $r('sys.color.font_secondary') : appState.accentColor)
            .height(26)
            .padding({ left: 12, right: 12 })
            .borderRadius(13)
            .textAlign(TextAlign.Center)
            .backgroundColor(this.showLyric ?
              Color.Transparent : $r('sys.color.comp_background_primary'))
            .onClick(() => {
              this.setLyricMode(false);
            })
          Text('歌词')
            .fontSize(12)
            .fontWeight(this.showLyric ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.showLyric ?
              appState.accentColor : $r('sys.color.font_secondary'))
            .height(26)
            .padding({ left: 12, right: 12 })
            .borderRadius(13)
            .textAlign(TextAlign.Center)
            .backgroundColor(this.showLyric ?
              $r('sys.color.comp_background_primary') : Color.Transparent)
            .onClick(() => {
              this.enterLyricMode();
            })
        }
        .height(30)
        .borderRadius(15)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .padding(2)
        .alignItems(VerticalAlign.Center)
      }

      Row() {
        SymbolGlyph($r('sys.symbol.share'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_primary')])
          .onClick(() => {
            this.shareCurrent();
          })
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(32)
    .opacity(playerAnim.topBarOpacity)
    .padding({ bottom: this.useSplitLayout() ? 4 : 16 })
  }

  /** 封面区（竖屏专用：点击/左滑进入歌词模式，撑满剩余高度） */
  @Builder
  CoverArea() {
    Stack(){
      // 封面（点击/左滑进入歌词模式）
      Column() {
        if (this.currentMusic !== null && this.currentMusic.artwork.length > 0) {
          Image(ArtworkCache.resolve(this.currentMusic.artwork))
            .width(280)
            .height(280)
            .borderRadius(24)
            .objectFit(ImageFit.Cover)
            // 光晕：阴影颜色取封面主色（ColoringStrategy.PRIMARY）
            .shadow({
              radius: 80,
              color: ColoringStrategy.PRIMARY,
              offsetX: 0,
              offsetY: 0
            })
            // 一镜到底落点：动画期间作为隐形占位，由顶层飞行封面代替
            .id('player_page_cover')
            .opacity(playerAnim.bigCoverHidden ? 0 : 1)
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.music'))
              .fontSize(64)
              .fontColor([$r('sys.color.icon_secondary')])
          }
          .width(280)
          .height(280)
          .borderRadius(24)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .id('player_page_cover')
          .opacity(playerAnim.bigCoverHidden ? 0 : 1)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.enterLyricMode();
      })
      .gesture(
        SwipeGesture({ direction: SwipeDirection.Horizontal })
          .onAction(() => {
            this.enterLyricMode();
          })
      )
    }.layoutWeight(1)
    .transition(TransitionEffect.OPACITY)
  }

  /** 歌词区（横向滑动返回封面） */
  @Builder
  LyricArea() {
    // 歌词区：横向滑动返回封面
    Column() {
      if (this.lyricLoading) {
        Column({ space: 8 }) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color($r('sys.color.icon_tertiary'))
          Text('歌词加载中…')
            .fontSize(13)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.lyrics.length === 0) {
        Column() {
          Text('暂无歌词')
            .fontSize(14)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        // 歌词列表：当前行居中高亮，点击行跳转进度，拖动时暂停自动滚动
        List({ scroller: this.lyricScroller }) {
          // 顶部占位：保证首行也能居中
          ListItem() {
            Column().width('100%').height(120)
          }
          ForEach(this.lyrics, (item: ParsedLrcItem) => {
            ListItem() {
              Column({ space: 4 }) {
                Text(item.lrc)
                  .fontSize(this.isCurrentLyric(item) ? 18 : 16)
                  .fontWeight(this.isCurrentLyric(item) ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.isCurrentLyric(item) ?
                    appState.accentColor : $r('sys.color.font_secondary'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.hasTranslation && item.translation.length > 0) {
                  Text(item.translation)
                    .fontSize(this.isCurrentLyric(item) ? 14 : 12)
                    .fontColor(this.isCurrentLyric(item) ?
                      $r('sys.color.font_secondary') : $r('sys.color.font_tertiary'))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 10, bottom: 10 })
              .onClick(() => {
                trackPlayer.seekTo(item.time);
              })
            }
          }, (item: ParsedLrcItem) => item.index.toString() + '_' + item.time.toString())
          // 底部占位：保证末行也能居中
          ListItem() {
            Column().width('100%').height(120)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .alignListItem(ListItemAlign.Center)
        .onAppear(() => {
          // 首次挂载（含宽屏常驻歌词）定位到当前行
          this.scrollToCurrentLyric(false);
        })
        .onTouch((event: TouchEvent): void => {
          this.handleLyricTouch(event);
        })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .gesture(
      SwipeGesture({ direction: SwipeDirection.Horizontal })
        .onAction(() => {
          this.setLyricMode(false);
        })
    )
    .transition(TransitionEffect.OPACITY)
  }

  /** 歌曲信息（s：分栏缩放系数，竖屏传 1 保持原样式） */
  @Builder
  SongInfo(s: number) {
    // 歌曲信息
    if (this.currentMusic !== null) {
      Column({ space: Math.max(4, Math.round(6 * s)) }) {
        Text(this.currentMusic.title)
          .fontSize(Math.max(18, Math.round(22 * s)))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.currentMusic.artist +
          (this.currentMusic.album.length > 0 ? ' · ' + this.currentMusic.album : ''))
          .fontSize(Math.max(12, Math.round(13 * s)))
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: this.compactGap(20) })
    }
  }

  /** 当前行歌词（仅封面模式显示；横屏分栏空间紧凑不展示） */
  @Builder
  CurrentLyricPreview() {
    Column({ space: 3 }) {
      if (this.lyricLoading) {
        Text('歌词加载中…')
          .fontSize(13)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      } else if (this.currentLyric === null) {
        Text('暂无歌词')
          .fontSize(13)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      } else {
        Text(this.currentLyric.lrc)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.currentLyric.translation.length > 0) {
          Text(this.currentLyric.translation)
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
    }
    .width('100%')
    .height(42)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .margin({ top: this.compactGap(10) })
    .transition(TransitionEffect.OPACITY)
  }

  /** 进度条（s：分栏缩放系数，竖屏传 1 保持原样式） */
  @Builder
  ProgressArea(s: number) {
    // 进度条
    Column({ space: 0 }) {
      Slider({
        value: Math.min(this.currentPosition, this.sliderMax()),
        min: 0,
        max: this.sliderMax(),
        style: SliderStyle.NONE
      })
        .height(Math.max(30, Math.round(40 * s)))
        .selectedColor($r('sys.color.icon'))
        .trackColor($r('sys.color.comp_background_tertiary'))
        .blockColor($r('sys.color.icon'))
        .trackThickness(this.isSeeking ? 8 : 5)
        .width('100%')
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
            this.isSeeking = true;
            this.currentPosition = value;
          } else {
            // End（拖动结束）/ Click（点按）：提交进度
            this.isSeeking = false;
            this.currentPosition = value;
            trackPlayer.seekTo(value);
          }
        })
      Row() {
        Text(PlayerPage.formatDuration(this.currentPosition))
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
        Text(this.duration > 0 ? PlayerPage.formatDuration(this.duration) : '--:--')
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ top: 2 })
    }
    .width('100%')
    .margin({ top: this.compactGap(6) })
  }

  /** 播放控制：循环模式 | 上一首 | 播放/暂停 | 下一首 | 播放队列（s：分栏缩放系数，竖屏传 1 保持原样式） */
  @Builder
  ControlsRow(s: number) {
    // 播放控制：循环模式 | 上一首 | 播放/暂停 | 下一首 | 播放队列
    Row() {
      SymbolGlyph(this.repeatIcon())
        .fontSize(Math.max(20, Math.round(24 * s)))
        .fontColor([$r('sys.color.icon_secondary')])
        .padding(Math.max(2, Math.round(4 * s)))
        .onClick(() => {
          this.toggleRepeatMode();
        })

      SymbolGlyph($r('sys.symbol.backward_end_fill'))
        .fontSize(Math.max(26, Math.round(36 * s)))
        .fontColor([$r('sys.color.icon_primary')])
        .padding(Math.max(2, Math.round(8 * s)))
        .onClick(() => {
          this.skipToPrevious();
        })

      SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_circle_fill') : $r('sys.symbol.play_circle_fill'))
        .fontSize(Math.max(42, Math.round(58 * s)))
        .fontColor([$r('sys.color.icon_primary')])
        .onClick(() => {
          this.togglePlay();
        })

      SymbolGlyph($r('sys.symbol.forward_end_fill'))
        .fontSize(Math.max(26, Math.round(36 * s)))
        .fontColor([$r('sys.color.icon_primary')])
        .padding(Math.max(2, Math.round(8 * s)))
        .onClick(() => {
          this.skipToNext();
        })

      SymbolGlyph($r('sys.symbol.music_note_list'))
        .fontSize(Math.max(20, Math.round(24 * s)))
        .fontColor([$r('sys.color.icon_secondary')])
        .padding(Math.max(2, Math.round(4 * s)))
        .onClick(() => {
          this.showQueue = true;
        })
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 8, right: 8 })
    .margin({ top: this.compactGap(16) })
  }

  /** 底部功能：投播 / 收藏 / 下载 / 评论 / 音质 / 更多（s：分栏缩放系数，竖屏传 1 保持原样式） */
  @Builder
  BottomActions(s: number) {
    // 底部功能：投播 / 收藏 / 下载 / 评论 / 音质 / 更多
    Row() {
      // 投播：系统 AVCastPicker 组件（点击拉起设备选择面板）
      Column({ space: Math.max(3, Math.round(5 * s)) }) {
        AVCastPicker({
          customPicker: (): void => {
            this.CastPickerIcon();
          }
        })
          .width(Math.max(20, Math.round(24 * s)))
          .height(Math.max(20, Math.round(24 * s)))
        Text('投播')
          .fontSize(Math.max(9, Math.round(10 * s)))
          .fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Center)

      Column({ space: Math.max(3, Math.round(5 * s)) }) {
        SymbolGlyph(this.isFavorited ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
          .fontSize(Math.max(20, Math.round(24 * s)))
          .fontColor([this.isFavorited ?
            '#E84026' : $r('sys.color.icon_secondary')])
        Text('收藏')
          .fontSize(Math.max(9, Math.round(10 * s)))
          .fontColor(this.isFavorited ?
            '#E84026' : $r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.toggleFavorite();
      })

      Column({ space: Math.max(3, Math.round(5 * s)) }) {
        SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
          .fontSize(Math.max(20, Math.round(24 * s)))
          .fontColor([$r('sys.color.icon_secondary')])
        Text('下载')
          .fontSize(Math.max(9, Math.round(10 * s)))
          .fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.downloadCurrent();
      })

      Column({ space: Math.max(3, Math.round(5 * s)) }) {
        SymbolGlyph($r('sys.symbol.message'))
          .fontSize(Math.max(20, Math.round(24 * s)))
          .fontColor([this.canComment() ?
            $r('sys.color.icon_secondary') : $r('sys.color.icon_tertiary')])
        Text('评论')
          .fontSize(Math.max(9, Math.round(10 * s)))
          .fontColor(this.canComment() ?
            $r('sys.color.font_secondary') : $r('sys.color.font_tertiary'))
      }
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.openComments();
      })

      Column({ space: Math.max(3, Math.round(5 * s)) }) {
        SymbolGlyph($r('sys.symbol.hi_waveform_2'))
          .fontSize(Math.max(20, Math.round(24 * s)))
          .fontColor([$r('sys.color.icon_secondary')])
        Text('音质')
          .fontSize(Math.max(9, Math.round(10 * s)))
          .fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.showQualityMenu();
      })

      // TODO: 系统音效开关对插件音源无明显效果，原版音效为均衡器调音，后续再做
      // Column({ space: 5 }) {
      //   SymbolGlyph($r('sys.symbol.waveform_headphones'))
      //     .fontSize(24)
      //     .fontColor([this.audioEffectOn ?
      //       $r('sys.color.icon_emphasize') : $r('sys.color.icon_secondary')])
      //   Text('音效')
      //     .fontSize(10)
      //     .fontColor(this.audioEffectOn ?
      //       appState.accentColor : $r('sys.color.font_secondary'))
      // }
      // .alignItems(HorizontalAlign.Center)
      // .onClick(() => {
      //   this.toggleAudioEffect();
      // })

      Column({ space: Math.max(3, Math.round(5 * s)) }) {
        SymbolGlyph($r('sys.symbol.ellipsis_circle'))
          .fontSize(Math.max(20, Math.round(24 * s)))
          .fontColor([$r('sys.color.icon_secondary')])
        Text('更多')
          .fontSize(Math.max(9, Math.round(10 * s)))
          .fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.showMore = true;
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 4, right: 4 })
    .margin({ top: this.compactGap(25) })
  }

  @Builder
  QueueSheetBuilder() {
    QueueSheet()
  }

  /** 投播组件自定义图标 */
  @Builder
  CastPickerIcon() {
    SymbolGlyph($r('sys.symbol.airplayaudio'))
      .fontSize(24)
      .fontColor([$r('sys.color.icon_secondary')])
  }

  /** 评论面板：列表分页加载，触底续拉 */
  @Builder
  CommentsSheetBuilder() {
    Column() {
      Text('评论')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 4, bottom: 4 })

      if (this.commentsLoading && this.comments.length === 0) {
        Column({ space: 8 }) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color($r('sys.color.icon_tertiary'))
          Text('评论加载中…')
            .fontSize(13)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.comments.length === 0) {
        Column() {
          Text('暂无评论')
            .fontSize(14)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
          LazyForEach(this.commentSource, (item: CommentItem) => {
            ListItem() {
              Column({ space: 8 }) {
                Row({ space: 10 }) {
                  if (item.avatar.length > 0) {
                    Image(item.avatar)
                      .width(36)
                      .height(36)
                      .borderRadius(18)
                      .objectFit(ImageFit.Cover)
                      .alt($r('app.media.altImage'))
                  } else {
                    Column() {
                      SymbolGlyph($r('sys.symbol.person'))
                        .fontSize(18)
                        .fontColor([$r('sys.color.icon_secondary')])
                    }
                    .width(36)
                    .height(36)
                    .borderRadius(18)
                    .backgroundColor($r('sys.color.comp_background_tertiary'))
                    .justifyContent(FlexAlign.Center)
                    .alignItems(HorizontalAlign.Center)
                  }
                  Column({ space: 2 }) {
                    Text(item.nickName.length > 0 ? item.nickName : '匿名用户')
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('sys.color.font_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text((item.location.length > 0 ? item.location + ' · ' : '') +
                      PlayerPage.formatCommentTime(item.createAt))
                      .fontSize(11)
                      .fontColor($r('sys.color.font_tertiary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  Row({ space: 3 }) {
                    SymbolGlyph($r('sys.symbol.heart'))
                      .fontSize(13)
                      .fontColor([$r('sys.color.icon_tertiary')])
                    if (item.likeCount > 0) {
                      Text(item.likeCount.toString())
                        .fontSize(11)
                        .fontColor($r('sys.color.font_tertiary'))
                    }
                  }
                  .alignItems(VerticalAlign.Center)
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)

                Text(item.comment)
                  .fontSize(14)
                  .fontColor($r('sys.color.font_primary'))
                  .lineHeight(20)
                  .width('100%')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ top: 12, bottom: 12 })
            }
          }, (item: CommentItem, index: number) => item.id + '_' + index.toString())

          if (!this.commentsEnded) {
            ListItem() {
              Column() {
                if (this.commentsLoading) {
                  LoadingProgress()
                    .width(22)
                    .height(22)
                    .color($r('sys.color.icon_tertiary'))
                } else {
                  Text('上拉加载更多')
                    .fontSize(12)
                    .fontColor($r('sys.color.font_tertiary'))
                }
              }
              .width('100%')
              .height(48)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .divider({
          strokeWidth: 0.5,
          color: $r('sys.color.comp_divider'),
          startMargin: 0,
          endMargin: 0
        })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onReachEnd(() => {
          this.loadMoreComments();
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 12 + sheetTopAvoidVp(), bottom: 24 })
  }
}
