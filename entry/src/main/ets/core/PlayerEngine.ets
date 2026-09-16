import media from '@ohos.multimedia.media';
import audio from '@ohos.multimedia.audio';
import fs from '@ohos.file.fs';
import { BusinessError } from '@ohos.base';
import { Log } from '../utils/Log';
import { Delay } from '../utils/Delay';

/**
 * 播放器引擎状态（对应 avPlayer 状态）
 */
export enum PlayState {
  Idle = 'idle',
  Initialized = 'initialized',
  Prepared = 'prepared',
  Playing = 'playing',
  Paused = 'paused',
  Completed = 'completed',
  Stopped = 'stopped',
  Error = 'error',
  Released = 'released',
}

/**
 * 底层播放器引擎（替代 react-native-track-player 的播放能力）
 * 基于 @ohos.multimedia.avPlayer；对外时间单位为秒（与 RN TrackPlayer 一致）
 */
export class PlayerEngine {
  private player: media.AVPlayer | null = null;
  private createPromise: Promise<media.AVPlayer> | null = null;
  private stateInternal: PlayState = PlayState.Idle;
  private rate: number = 1;
  private playingBeforeInterrupt: boolean = false;
  /** 本地播放文件句柄（fd:// 播放期间需保持打开） */
  private localFile: fs.File | null = null;

  /** 被其他应用打断后是否自动恢复播放（basic.notInterrupt 取反） */
  resumeAfterInterrupt: boolean = true;

  onStateChanged: (state: PlayState) => void = () => {
  };
  /** 播放到末尾（对应 RN 队列 fake-audio 触发 PlayEnd） */
  onEndReached: () => void = () => {
  };
  onError: (message: string) => void = () => {
  };
  onSeekDone: (positionSec: number) => void = () => {
  };

  get state(): PlayState {
    return this.stateInternal;
  }

  /** 当前播放位置（秒） */
  get position(): number {
    if (this.player === null) {
      return 0;
    }
    return this.player.currentTime / 1000;
  }

  /** 总时长（秒；未知为 0） */
  get duration(): number {
    if (this.player === null) {
      return 0;
    }
    const d = this.player.duration;
    return d > 0 ? d / 1000 : 0;
  }

  get currentRate(): number {
    return this.rate;
  }

  get isPlaying(): boolean {
    return this.stateInternal === PlayState.Playing;
  }

  private ensurePlayer(): Promise<media.AVPlayer> {
    if (this.player !== null) {
      return Promise.resolve(this.player);
    }
    if (this.createPromise === null) {
      this.createPromise = media.createAVPlayer().then((p: media.AVPlayer) => {
        this.player = p;
        this.setupListeners(p);
        this.createPromise = null;
        return p;
      });
    }
    return this.createPromise;
  }

  private setupListeners(p: media.AVPlayer): void {
    p.on('stateChange', (state: media.AVPlayerState, _reason: media.StateChangeReason) => {
      this.stateInternal = PlayerEngine.mapState(state);
      if (state === 'completed') {
        this.onEndReached();
      }
      this.onStateChanged(this.stateInternal);
    });
    p.on('error', (err: BusinessError) => {
      this.stateInternal = PlayState.Error;
      Log.error('PlayerEngine 播放错误: ' + err.message);
      this.onError(err.message);
    });
    p.on('seekDone', (ms: number) => {
      this.onSeekDone(ms / 1000);
    });
    p.on('audioInterrupt', (info: audio.InterruptEvent) => {
      this.handleInterrupt(info);
    });
  }

  private handleInterrupt(info: audio.InterruptEvent): void {
    if (info.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
      this.playingBeforeInterrupt = this.stateInternal === PlayState.Playing;
      this.pause().catch(() => {
      });
    } else if (info.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
      this.playingBeforeInterrupt = false;
      this.stop().catch(() => {
      });
    } else if (info.hintType === audio.InterruptHint.INTERRUPT_HINT_RESUME) {
      if (this.playingBeforeInterrupt && this.resumeAfterInterrupt) {
        this.playingBeforeInterrupt = false;
        this.play().catch(() => {
        });
      }
    }
  }

  private static mapState(state: media.AVPlayerState): PlayState {
    if (state === 'idle') {
      return PlayState.Idle;
    }
    if (state === 'initialized') {
      return PlayState.Initialized;
    }
    if (state === 'prepared') {
      return PlayState.Prepared;
    }
    if (state === 'playing') {
      return PlayState.Playing;
    }
    if (state === 'paused') {
      return PlayState.Paused;
    }
    if (state === 'completed') {
      return PlayState.Completed;
    }
    if (state === 'stopped') {
      return PlayState.Stopped;
    }
    if (state === 'released') {
      return PlayState.Released;
    }
    return PlayState.Error;
  }

  /** 将播放器回收到 idle 状态（必要时重建实例） */
  private async recycle(): Promise<media.AVPlayer> {
    const p = await this.ensurePlayer();
    const st = p.state;
    if (st === 'idle') {
      return p;
    }
    if (st === 'error' || st === 'released') {
      try {
        p.release();
      } catch (e) {
        // 忽略释放失败
      }
      this.player = null;
      this.stateInternal = PlayState.Idle;
      return this.ensurePlayer();
    }
    await p.reset();
    this.stateInternal = PlayState.Idle;
    return p;
  }

  /** 关闭本地播放文件句柄（需在播放器 reset/release 之后调用） */
  private closeLocalFile(): void {
    if (this.localFile !== null) {
      try {
        fs.closeSync(this.localFile);
      } catch (e) {
        // 忽略关闭失败
      }
      this.localFile = null;
    }
  }

  /**
   * 加载音源并 prepare 完成
   * @param url 网络地址或本地路径（支持 file:// 前缀；本地文件以 fd:// 方式播放）
   * @param headers 自定义 HTTP 头（网络源生效）
   */
  async load(url: string, headers: Record<string, string> | null): Promise<void> {
    const p = await this.recycle();
    // 播放器已回收，上一首本地文件句柄不再被占用
    this.closeLocalFile();
    const isHttp = url.startsWith('http://') || url.startsWith('https://');
    let sourceSet = false;
    if (isHttp && headers !== null && Object.keys(headers).length > 0) {
      try {
        await p.setMediaSource(media.createMediaSourceWithUrl(url, headers));
        sourceSet = true;
      } catch (e) {
        Log.warn('setMediaSource 失败，回退无请求头播放');
      }
    }
    if (!sourceSet) {
      if (isHttp) {
        p.url = url;
      } else {
        // AVPlayer 不支持裸磁盘路径，本地文件需打开为 fd://
        const path = url.startsWith('file://') ? url.substring('file://'.length) : url;
        const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
        this.localFile = file;
        p.url = 'fd://' + file.fd.toString();
      }
    }
    // url 赋值/setMediaSource 后播放器异步迁移 idle → initialized，
    // 必须等待迁移完成才能 prepare，否则报 "Prepare operation only supports stopped/initialized"
    await PlayerEngine.waitInitialized(p, 5000);
    await p.prepare();
    // 恢复倍速
    if (this.rate !== 1) {
      p.setSpeed(PlayerEngine.speedToEnum(this.rate));
    }
  }

  /** 等待播放器完成到 initialized 的异步迁移（轮询；超时抛错） */
  private static async waitInitialized(p: media.AVPlayer, timeoutMs: number): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const st = PlayerEngine.readState(p);
      if (st === 'initialized' || st === 'prepared') {
        return;
      }
      await Delay.wait(20);
    }
    const st = PlayerEngine.readState(p);
    if (st !== 'initialized' && st !== 'prepared') {
      throw new Error('播放器加载源超时（state=' + st + '）');
    }
  }

  /** 独立读取播放器状态（避免类型窄化误判） */
  private static readState(p: media.AVPlayer): media.AVPlayerState {
    return p.state;
  }

  async play(): Promise<void> {
    const p = await this.ensurePlayer();
    if (p.state === 'playing') {
      return;
    }
    if (p.state === 'idle' || p.state === 'initialized' || p.state === 'stopped' ||
      p.state === 'released' || p.state === 'error') {
      throw new Error('player is not prepared');
    }
    await p.play();
  }

  async pause(): Promise<void> {
    const p = await this.ensurePlayer();
    if (p.state === 'paused' || p.state === 'idle' || p.state === 'initialized' ||
      p.state === 'stopped' || p.state === 'released' || p.state === 'error') {
      return;
    }
    await p.pause();
  }

  async stop(): Promise<void> {
    const p = await this.ensurePlayer();
    if (p.state === 'stopped' || p.state === 'idle' || p.state === 'initialized' ||
      p.state === 'released' || p.state === 'error') {
      return;
    }
    await p.stop();
  }

  /** 跳转（秒） */
  seek(positionSec: number): void {
    const p = this.player;
    if (p === null) {
      return;
    }
    if (p.state === 'prepared' || p.state === 'playing' || p.state === 'paused' ||
      p.state === 'completed') {
      p.seek(Math.floor(positionSec * 1000));
    }
  }

  /** 倍速（0.125 ~ 3） */
  setRate(rate: number): void {
    this.rate = rate;
    const p = this.player;
    if (p === null) {
      return;
    }
    if (p.state === 'prepared' || p.state === 'playing' || p.state === 'paused' ||
      p.state === 'completed') {
      p.setSpeed(PlayerEngine.speedToEnum(rate));
    }
  }

  setVolume(volume: number): void {
    const p = this.player;
    if (p === null) {
      return;
    }
    if (p.state === 'prepared' || p.state === 'playing' || p.state === 'paused' ||
      p.state === 'completed') {
      p.setVolume(volume);
    }
  }

  async release(): Promise<void> {
    const p = this.player;
    this.player = null;
    this.stateInternal = PlayState.Released;
    this.closeLocalFile();
    if (p !== null) {
      try {
        await p.release();
      } catch (e) {
        // 忽略
      }
    }
  }

  private static speedToEnum(rate: number): media.PlaybackSpeed {
    if (rate < 0.1875) {
      return media.PlaybackSpeed.SPEED_FORWARD_0_125_X;
    }
    if (rate < 0.375) {
      return media.PlaybackSpeed.SPEED_FORWARD_0_25_X;
    }
    if (rate < 0.625) {
      return media.PlaybackSpeed.SPEED_FORWARD_0_50_X;
    }
    if (rate < 0.875) {
      return media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
    }
    if (rate < 1.125) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    }
    if (rate < 1.375) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
    }
    if (rate < 1.625) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_50_X;
    }
    if (rate < 1.875) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_75_X;
    }
    if (rate < 2.5) {
      return media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
    }
    return media.PlaybackSpeed.SPEED_FORWARD_3_00_X;
  }
}

export const playerEngine = new PlayerEngine();
