import { ArtworkCache } from '../utils/ArtworkCache';
import { CoverColorUtils, DominantColor } from '../utils/CoverColorUtils';
import { MusicItem } from '../common/model/MediaTypes';
import { MusicRepeatMode } from '../common/Consts';
import { PlayState } from '../core/PlayerEngine';
import { trackPlayer } from '../core/TrackPlayer';
import { lyricManager, LyricState } from '../core/LyricManager';
import { musicSheet } from '../core/MusicSheet';
import { mediaSession } from '../core/MediaSession';
import { MediaUtils } from '../utils/MediaUtils';
import { ParsedLrcItem } from '../utils/LyricParser';
import { appConfig } from '../core/AppConfig';
import { appState } from '../entryability/AppState';
import { LyricView } from './LyricView';

/** 封面主色染色层透明度（两位十六进制，'40' ≈ 25%） */
const CAR_BG_TINT_ALPHA_HEX = '40';

/**
 * 驾驶模式界面（HiCar/超级桌面车机屏 & 手动车载模式）
 * 横屏：左侧 封面/歌名/歌手名/控制排（循环+上一曲+播放+下一曲+收藏），右侧歌词（复用 LyricView）
 * 竖屏：同结构纵向排列，歌词占底部剩余区域
 * 背景：系统底色上叠加当前封面提取主色的半透明染色层
 */
@ComponentV2
export struct CarModeView {
  @Local currentMusic: MusicItem | null = null;
  @Local isPlaying: boolean = false;
  @Local repeatMode: MusicRepeatMode = MusicRepeatMode.QUEUE;
  @Local isFavorited: boolean = false;
  @Local lyrics: Array<ParsedLrcItem> = [];
  @Local hasTranslation: boolean = false;
  @Local showTranslation: boolean = appConfig.getLyricShowTranslation();
  /** 封面主色染色（'#AARRGGBB'；空串 = 未提取/无封面，保持系统背景） */
  @Local coverTint: string = '';
  /** 染色提取序号：切歌后丢弃过期异步结果 */
  private tintSeq: number = 0;
  private offCurrent: () => void = (): void => {
  };
  private offState: () => void = (): void => {
  };
  private offRepeatMode: () => void = (): void => {
  };
  private offFavorite: () => void = (): void => {
  };
  private offLyricState: () => void = (): void => {
  };

  aboutToAppear(): void {
    this.currentMusic = trackPlayer.currentMusic;
    this.isPlaying = trackPlayer.playState === PlayState.Playing;
    this.repeatMode = trackPlayer.repeatMode;
    this.refreshFavorite();
    this.syncLyricState(lyricManager.lyricState);
    this.refreshCoverTint();
    this.offCurrent = trackPlayer.onCurrentMusicChanged((music: MusicItem | null) => {
      this.currentMusic = music;
      this.refreshFavorite();
      this.refreshCoverTint();
    });
    this.offState = trackPlayer.onPlayStateChanged((state: PlayState) => {
      this.isPlaying = state === PlayState.Playing;
    });
    this.offRepeatMode = trackPlayer.onRepeatModeChanged((mode: MusicRepeatMode) => {
      this.repeatMode = mode;
    });
    this.offFavorite = mediaSession.onFavoriteChanged(() => {
      this.refreshFavorite();
    });
    this.offLyricState = lyricManager.onLyricStateChanged((state: LyricState) => {
      this.syncLyricState(state);
    });
  }

  aboutToDisappear(): void {
    this.offCurrent();
    this.offState();
    this.offRepeatMode();
    this.offFavorite();
    this.offLyricState();
  }

  private isLandscape(): boolean {
    return appState.screenWidth > appState.screenHeight && appState.screenHeight > 0;
  }

  private syncLyricState(state: LyricState): void {
    this.lyrics = state.lyrics;
    this.hasTranslation = state.hasTranslation;
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

  /** 退出驾驶模式：全局状态与持久化设置开关同步关闭 */
  private exitCarMode(): void {
    appConfig.setCarModeEnabled(false);
    appState.carModeManual = false;
    appState.refreshCarMode();
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
      });
    } else {
      musicSheet.addMusic(musicSheet.defaultSheet.id, current).then((): void => {
        this.isFavorited = true;
      });
    }
  }

  /** 切歌/进页时刷新封面主色染色（无封面/提取失败保持系统背景） */
  private refreshCoverTint(): void {
    const music = this.currentMusic;
    const seq = ++this.tintSeq;
    if (music === null || music.artwork.length === 0) {
      this.coverTint = '';
      return;
    }
    this.loadCoverTint(music.artwork, seq);
  }

  /** 解析封面本地路径 → 提取主色 → 半透明染色（过期结果丢弃，失败静默） */
  private async loadCoverTint(artwork: string, seq: number): Promise<void> {
    try {
      let path: string | null = null;
      if (artwork.startsWith('file://')) {
        path = artwork.substring('file://'.length);
      } else if (artwork.startsWith('http://') || artwork.startsWith('https://')) {
        path = await ArtworkCache.downloadToFile(artwork);
      }
      if (seq !== this.tintSeq || path === null) {
        return;
      }
      const color: DominantColor | null = await CoverColorUtils.extract(path);
      if (seq !== this.tintSeq || color === null) {
        return;
      }
      this.coverTint = CoverColorUtils.toHexWithAlpha(color, CAR_BG_TINT_ALPHA_HEX);
    } catch (e) {
      // 静默：保持系统背景
    }
  }

  @Builder
  CoverArea() {
    Column() {
      if (this.currentMusic !== null && this.currentMusic.artwork.length > 0) {
        Image(ArtworkCache.resolve(this.currentMusic.artwork))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(24)
          .draggable(false)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.music_note_list'))
            .fontSize(72)
            .fontColor([$r('sys.color.icon_tertiary')])
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor($r('sys.color.comp_background_secondary'))
        .borderRadius(24)
      }
    }
    .aspectRatio(1)
    .constraintSize({ maxWidth: '100%', maxHeight: '100%' })
  }

  /** 第二排歌名 + 第三排歌手名 */
  @Builder
  MusicInfo() {
    Column({ space: 8 }) {
      Text(this.currentMusic !== null ? this.currentMusic.title : '')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.currentMusic !== null ? this.currentMusic.artist : '')
        .fontSize(16)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 第四排控制：循环模式 + 上一曲 + 播放/暂停 + 下一曲 + 收藏 */
  @Builder
  ControlsRow() {
    Row({ space: 16 }) {
      SymbolGlyph(this.repeatIcon())
        .fontSize(34)
        .fontColor([$r('sys.color.icon_secondary')])
        .padding(6)
        .onClick(() => {
          trackPlayer.toggleRepeatMode();
        })
      SymbolGlyph($r('sys.symbol.backward_end_fill'))
        .fontSize(46)
        .fontColor([$r('sys.color.icon_primary')])
        .padding(6)
        .onClick(() => {
          trackPlayer.skipToPrevious().catch((): void => {
          });
        })
      SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_circle_fill') : $r('sys.symbol.play_circle_fill'))
        .fontSize(72)
        .fontColor([$r('sys.color.icon_primary')])
        .padding(2)
        .onClick(() => {
          this.togglePlay();
        })
      SymbolGlyph($r('sys.symbol.forward_end_fill'))
        .fontSize(46)
        .fontColor([$r('sys.color.icon_primary')])
        .padding(6)
        .onClick(() => {
          trackPlayer.skipToNext().catch((): void => {
          });
        })
      SymbolGlyph(this.isFavorited ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
        .fontSize(34)
        .fontColor([this.isFavorited ? appState.accentColor : $r('sys.color.icon_secondary')])
        .padding(6)
        .onClick(() => {
          this.toggleFavorite();
        })
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  /** 歌词区（直接复用 LyricView，支持逐字渐变/翻译/滑动 seek） */
  @Builder
  LyricArea() {
    if (this.lyrics.length > 0) {
      LyricView({
        lyrics: this.lyrics,
        positionProvider: (): number => trackPlayer.getProgress().position,
        isPlaying: this.isPlaying,
        fontScale: 1.2,
        highlightColor: appState.accentColor,
        showTranslation: this.showTranslation,
        hasTranslation: this.hasTranslation,
        lyricOffset: lyricManager.offset,
        onSeek: (time: number): void => {
          trackPlayer.seekTo(time);
        },
        onLyricLineChange: (_item: ParsedLrcItem | null): void => {
        }
      })
    } else {
      Column() {
        Text(this.currentMusic !== null ? '暂无歌词' : '')
          .fontSize(16)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder
  EmptyState() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.music_note_list'))
        .fontSize(64)
        .fontColor([$r('sys.color.icon_tertiary')])
      Text('还没有正在播放的歌曲')
        .fontSize(18)
        .fontColor($r('sys.color.font_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 封面主色染色层（叠于系统底色之上、内容之下；提取失败时不渲染）
      if (this.coverTint.length > 0) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.coverTint)
      }
      if (this.currentMusic === null) {
        this.EmptyState()
      } else if (this.isLandscape()) {
        Row({ space: 40 }) {
          // 左侧：封面 / 歌名 / 歌手名 / 控制排
          Column({ space: 20 }) {
            Column() {
              this.CoverArea()
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)

            this.MusicInfo()
            this.ControlsRow()
          }
          .width('42%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 48 })

          // 右侧：歌词
          Column() {
            this.LyricArea()
          }
          .layoutWeight(1)
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .height('100%')
        .alignItems(VerticalAlign.Center)
        .padding({
          left: 48,
          right: 48,
          top: appState.topRect,
          bottom: appState.bottomRect
        })
      } else {
        Column({ space: 16 }) {
          Column() {
            this.CoverArea()
          }
          .height('36%')
          .justifyContent(FlexAlign.Center)

          this.MusicInfo()
          this.ControlsRow()

          Column() {
            this.LyricArea()
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
        .width('86%')
        .height('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({
          top: appState.topRect,
          bottom: appState.bottomRect
        })
      }

      if (!appState.onCarScreen) {
        Text('退出')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_secondary'))
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .margin({ left: 16, top: appState.topRect + 8 })
          .onClick(() => {
            this.exitCarMode();
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_secondary'))
  }
}
