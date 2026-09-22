import { PiPWindow } from '@kit.ArkUI';
import { appConfig, ConfigKeys } from './AppConfig';
import { ContextHolder } from '../common/ContextHolder';
import { trackPlayer } from './TrackPlayer';
import { lyricManager } from './LyricManager';
import { ParsedLrcItem } from '../utils/LyricParser';
import { MusicItem } from '../common/model/MediaTypes';
import { FloatLyricNodeController, FloatLyricData } from '../common/FloatLyricNodeController';

/**
 * 悬浮歌词（桌面歌词）管理器 —— 画中画方案
 * 使用 PiPWindow 创建系统级画中画窗口，无需 ACL 权限。
 * 歌词 UI 通过 FloatLyricNodeController（customUIController）渲染。
 * PiP 窗口位置/大小由系统管理，支持拖动到四角。
 */
@ObservedV2
export class FloatLyricManager {
  /** 开关状态（PiP 窗口存活期间为 true；持久化到 floatLyric.enabled） */
  @Trace enabled: boolean = false;
  /** 主行字号（fp，12-32） */
  @Trace fontSize: number = 18;
  /** 字体颜色（#AARRGGBB） */
  @Trace color: string = '#FFFFFFFF';
  /** 背景样式：dark / light / cover */
  @Trace bg: string = 'dark';
  /** 翻译行开关 */
  @Trace showTranslation: boolean = true;
  /** 画中画窗口高度（px，60-200） */
  @Trace windowSize: number = 80;

  private pipController: PiPWindow.PiPController | null = null;
  private nodeController: FloatLyricNodeController | null = null;
  private xComponentController: XComponentController | null = null;
  private creating: boolean = false;
  private lyricUnsub: (() => void) | null = null;
  private musicUnsub: (() => void) | null = null;

  /** 设置 XComponentController（PlayerPage 创建 XComponent 后调用） */
  setXComponentController(controller: XComponentController): void {
    this.xComponentController = controller;
  }

  /** 启动恢复：读取样式配置（PiP 启动需 XComponent，延迟到用户主动开启） */
  setup(): void {
    this.fontSize = appConfig.getFloatLyricFontSize();
    this.color = appConfig.getFloatLyricColor();
    this.bg = appConfig.getFloatLyricBg();
    this.showTranslation = appConfig.getFloatLyricShowTranslation();
    this.windowSize = appConfig.getFloatLyricWindowSize();
  }

  /** 用户入口：切换开/关；返回是否成功开启 */
  async toggle(): Promise<boolean> {
    if (this.enabled) {
      await this.close();
      return false;
    }
    return this.open();
  }

  /** 开启画中画；返回是否成功 */
  async open(): Promise<boolean> {
    if (this.pipController !== null) {
      return true;
    }
    if (this.creating) {
      return false;
    }
    if (this.xComponentController === null) {
      return false;
    }
    if (!PiPWindow.isPiPEnabled()) {
      return false;
    }
    this.creating = true;
    try {
      this.nodeController = new FloatLyricNodeController();
      this.subscribeLyricUpdates();
      const config: PiPWindow.PiPConfiguration = {
        context: ContextHolder.get(),
        componentController: this.xComponentController,
        customUIController: this.nodeController,
        templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY,
        contentWidth: 300,
        contentHeight: this.windowSize
      };
      this.pipController = await PiPWindow.create(config);
      this.pipController.on('stateChange', (state: PiPWindow.PiPState, _reason: string): void => {
        if (state === PiPWindow.PiPState.STOPPED) {
          this.onPiPClosed();
        }
      });
      await this.pipController.startPiP();
      this.enabled = true;
      appConfig.setConfig(ConfigKeys.FLOAT_LYRIC_ENABLED, true);
      return true;
    } catch (e) {
      this.cleanup();
      return false;
    } finally {
      this.creating = false;
    }
  }

  /** 关闭画中画 */
  async close(): Promise<void> {
    const controller = this.pipController;
    if (controller !== null) {
      try {
        await controller.stopPiP();
      } catch (e) {
        // 窗口已失效时忽略
      }
    }
    this.onPiPClosed();
  }

  /** PiP 窗口被系统/用户关闭时的清理 */
  private onPiPClosed(): void {
    this.cleanup();
    this.enabled = false;
    appConfig.setConfig(ConfigKeys.FLOAT_LYRIC_ENABLED, false);
  }

  /** 释放控制器和订阅 */
  private cleanup(): void {
    if (this.lyricUnsub !== null) {
      this.lyricUnsub();
      this.lyricUnsub = null;
    }
    if (this.musicUnsub !== null) {
      this.musicUnsub();
      this.musicUnsub = null;
    }
    this.pipController = null;
    this.nodeController = null;
  }

  /** 订阅歌词/曲目变化，实时更新画中画内容 */
  private subscribeLyricUpdates(): void {
    this.updateNodeData();
    this.lyricUnsub = lyricManager.onCurrentLyricChanged((_item: ParsedLrcItem | null): void => {
      this.updateNodeData();
    });
    this.musicUnsub = trackPlayer.onCurrentMusicChanged((_music: MusicItem | null): void => {
      this.updateNodeData();
    });
  }

  /** 组装当前歌词数据并刷新 NodeController */
  private updateNodeData(): void {
    if (this.nodeController === null) {
      return;
    }
    const data = new FloatLyricData();
    data.fontSize = this.fontSize;
    data.color = this.color;
    data.bg = this.bg;
    data.artwork = trackPlayer.currentMusic !== null ? trackPlayer.currentMusic.artwork : '';

    const item = lyricManager.currentLyricItem;
    if (item !== null && item.lrc.length > 0) {
      data.mainText = item.lrc;
    } else {
      const music = trackPlayer.currentMusic;
      if (music !== null) {
        data.mainText = music.artist.length > 0 ? music.title + ' - ' + music.artist : music.title;
      } else {
        data.mainText = '未在播放';
      }
    }

    if (this.showTranslation && item !== null && item.translation.length > 0) {
      data.transText = item.translation;
    }

    this.nodeController.updateData(data);
  }

  // ---------- 样式设置（设置页调用，实时生效并持久化） ----------

  setFontSize(v: number): void {
    this.fontSize = v;
    appConfig.setConfig(ConfigKeys.FLOAT_LYRIC_FONT_SIZE, v);
    this.updateNodeData();
  }

  setColor(v: string): void {
    this.color = v;
    appConfig.setConfig(ConfigKeys.FLOAT_LYRIC_COLOR, v);
    this.updateNodeData();
  }

  setBg(v: string): void {
    this.bg = v;
    appConfig.setConfig(ConfigKeys.FLOAT_LYRIC_BG, v);
    this.updateNodeData();
  }

  setShowTranslation(v: boolean): void {
    this.showTranslation = v;
    appConfig.setConfig(ConfigKeys.FLOAT_LYRIC_SHOW_TRANSLATION, v);
    this.updateNodeData();
  }

  setWindowSize(v: number): void {
    this.windowSize = v;
    appConfig.setConfig(ConfigKeys.FLOAT_LYRIC_WINDOW_SIZE, v);
    if (this.pipController !== null) {
      try {
        this.pipController.updateContentSize(300, v);
      } catch (e) {
        // 窗口未就绪时忽略
      }
    }
  }
}

export const floatLyricManager = new FloatLyricManager();
