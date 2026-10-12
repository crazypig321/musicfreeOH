import media from '@ohos.multimedia.media';
import audio from '@ohos.multimedia.audio';
import fs from '@ohos.file.fs';
import { BusinessError } from '@ohos.base';
import { Log } from '../utils/Log';
import { Delay } from '../utils/Delay';
import { PcmDecoderTool, AudioRendererPlayer } from '@ospark/free-pcm';
import type {
  PcmStreamDecoder,
  PcmStreamInfo,
  PcmStreamDecoderOptions,
  PcmStreamDecoderCallbacks
} from '@ospark/free-pcm';
import { EqualizerManager } from './EqualizerManager';
import { audioCacheProxy } from './AudioCacheProxy';

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
  /** 等待音频会话激活完成的时限（超时放弃等待，不阻塞起播） */
  private static readonly SESSION_ACTIVATE_TIMEOUT_MS = 2000;
  private player: media.AVPlayer | null = null;
  private createPromise: Promise<media.AVPlayer> | null = null;
  private stateInternal: PlayState = PlayState.Idle;
  private rate: number = 1;
  private playingBeforeInterrupt: boolean = false;
  /** 音频会话管理器（「被打断转暂停」策略用；低版本设备获取失败为 null） */
  private sessionManager: audio.AudioSessionManager | null = null;
  /** 会话行为（PAUSE_WHEN_INTERRUPTED）已设置 */
  private sessionBehaviorSet: boolean = false;
  /** 会话焦点状态监听已注册 */
  private sessionStateHooked: boolean = false;
  /** 会话激活请求进行中（防重复激活；null 表示无进行中的激活） */
  private sessionActivateTask: Promise<void> | null = null;
  /** 本地播放文件句柄（fd:// 播放期间需保持打开） */
  private localFile: fs.File | null = null;
  /** 音效开关（true=系统默认音效 EFFECT_DEFAULT / false=关闭音效 EFFECT_NONE） */
  private audioEffectOn: boolean = true;

  // ==================== free-pcm 均衡器引擎 ====================
  /** 当前 load 是否走 free-pcm PCM 管线（均衡器开启时） */
  private pcmMode: boolean = false;
  private pcmDecoder: PcmStreamDecoder | null = null;
  private pcmPlayer: AudioRendererPlayer | null = null;
  private pcmInfo: PcmStreamInfo | null = null;
  /** PCM 播放完成检测定时器 */
  private pcmEndTimer: number = -1;
  /** 最近一次加载的音源（EQ 开关切换引擎时原位重载用） */
  private lastUrl: string = '';
  private lastHeaders: Record<string, string> | null = null;
  private offEqEnabled: () => void = (): void => {
  };
  private offEqGains: () => void = (): void => {
  };

  /** EQ 监听注册标记（模块加载期 ContextHolder 未就绪，须延迟到首次 load 时注册） */
  private eqSynced: boolean = false;

  private syncEqListenersOnce(): void {
    if (this.eqSynced) {
      return;
    }
    this.eqSynced = true;
    const mgr = EqualizerManager.getInstance();
    // EQ 开关 → 切换播放引擎（AVPlayer ↔ free-pcm PCM），原位重载
    this.offEqEnabled = mgr.onEnabledChanged((enabled: boolean): void => {
      this.handleEqEngineToggle(enabled);
    });
    // EQ 增益变化 → 实时下发当前 PCM 解码器（拖动滑杆即时生效）
    this.offEqGains = mgr.onGainsChanged((gains: Array<number>): void => {
      const decoder = this.pcmDecoder;
      if (decoder !== null) {
        decoder.setEqGains(gains);
      }
    });
  }

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
    if (this.pcmMode) {
      const decoder = this.pcmDecoder;
      return decoder === null ? 0 : decoder.getPosition() / 1000;
    }
    if (this.player === null) {
      return 0;
    }
    return this.player.currentTime / 1000;
  }

  /** 总时长（秒；未知为 0） */
  get duration(): number {
    if (this.pcmMode) {
      const info = this.pcmInfo;
      return info === null ? 0 : (info.durationMs > 0 ? info.durationMs / 1000 : 0);
    }
    if (this.player === null) {
      return 0;
    }
    const d = this.player.duration;
    return d > 0 ? d / 1000 : 0;
  }

  get currentRate(): number {
    return this.rate;
  }

  /** 当前已加载音源地址（裸路径或网络地址；用于识别音频格式） */
  get loadedUrl(): string {
    return this.lastUrl;
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
      if (state === 'prepared') {
        // 换源后音效模式恢复为默认值，需重新应用
        this.applyAudioEffectMode();
      }
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
    Log.debug('audioInterrupt 提示: hint=' + info.hintType.toString() + ', force=' + info.forceType.toString());
    if (info.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
      this.playingBeforeInterrupt = this.stateInternal === PlayState.Playing;
      this.pause().catch(() => {
      });
    } else if (info.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
      // 系统默认策略下音乐类应用互打为 STOP（永久失焦，对方结束后不恢复）：
      // 仅转为暂停以保留进度（stop 会清进度，手动续播将从头开始）；
      // 已启用 PAUSE_WHEN_INTERRUPTED 时一般收到的是 PAUSE 而非 STOP
      this.playingBeforeInterrupt = this.stateInternal === PlayState.Playing;
      this.pause().catch(() => {
      });
    } else if (info.hintType === audio.InterruptHint.INTERRUPT_HINT_RESUME) {
      if (this.playingBeforeInterrupt && this.resumeAfterInterrupt) {
        this.playingBeforeInterrupt = false;
        this.play().catch(() => {
        });
      }
    }
  }

  /**
   * 启用「被其他应用打断时转暂停」的音频会话策略（API 24+，低版本设备静默跳过）。
   * 默认焦点策略下音乐类应用互打为 STOP：被抢占后永久失焦，对方停止播放后
   * 系统不会下发 RESUME，应用无法自动恢复；设置 PAUSE_WHEN_INTERRUPTED 后，
   * 被抢占转为暂停并保留进度，对方释放焦点后收到 RESUME 提示可自动续播。
   * 注意：会话必须在起流前完成激活，否则策略对本流不生效（文档明确要求），
   * 故本方法返回 Promise，由 load/play 在起流前 await（awaitSessionReady）。
   * 仅在即将播放时调用：会话激活本身会申请焦点，冷启动预热会打断其他应用。
   */
  ensurePauseOnInterruptSession(): Promise<void> {
    const mgr = this.getSessionManager();
    if (mgr === null) {
      return Promise.resolve();
    }
    if (!this.sessionBehaviorSet) {
      try {
        mgr.setAudioSessionScene(audio.AudioSessionScene.AUDIO_SESSION_SCENE_MEDIA);
        mgr.setAudioSessionBehavior(audio.AudioSessionBehaviorFlags.PAUSE_WHEN_INTERRUPTED);
        this.sessionBehaviorSet = true;
        Log.debug('已设置音频会话行为: PAUSE_WHEN_INTERRUPTED');
      } catch (e) {
        // 低版本设备无此接口：保持系统默认打断策略（STOP 后不自动恢复）
        return Promise.resolve();
      }
    }
    if (!this.sessionStateHooked) {
      this.sessionStateHooked = true;
      try {
        mgr.on('audioSessionStateChanged', (event: audio.AudioSessionStateChangedEvent) => {
          Log.debug('音频会话焦点提示: ' + event.stateChangeHint.toString());
          this.handleSessionStateChange(event);
        });
      } catch (e) {
        // 监听注册失败忽略：AVPlayer 的 audioInterrupt 仍可用
      }
    }
    let activated = false;
    try {
      activated = mgr.isAudioSessionActivated();
    } catch (e) {
      activated = false;
    }
    if (activated) {
      return Promise.resolve();
    }
    if (this.sessionActivateTask !== null) {
      // 已有激活在途：等待其落定，避免并发重复激活
      return this.sessionActivateTask;
    }
    const strategy: audio.AudioSessionStrategy = {
      concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_DEFAULT
    };
    const raw: Promise<void> = mgr.activateAudioSession(strategy).then((): void => {
      Log.debug('音频会话已激活，被打断转暂停策略生效');
    }).catch((e: BusinessError): void => {
      Log.warn('音频会话激活失败: ' + e.message);
    });
    const wrapped: Promise<void> = raw.finally((): void => {
      if (this.sessionActivateTask === wrapped) {
        // 失败也清空以允许下次播放重试
        this.sessionActivateTask = null;
      }
    });
    this.sessionActivateTask = wrapped;
    return wrapped;
  }

  /** 等待「被打断转暂停」会话就绪（限时兜底，防激活异常时阻塞起播） */
  private async awaitSessionReady(): Promise<void> {
    const racers: Array<Promise<void>> = [
      this.ensurePauseOnInterruptSession(),
      Delay.wait(PlayerEngine.SESSION_ACTIVATE_TIMEOUT_MS)
    ];
    await Promise.race(racers);
  }

  /** 获取音频会话管理器（懒加载） */
  private getSessionManager(): audio.AudioSessionManager | null {
    if (this.sessionManager !== null) {
      return this.sessionManager;
    }
    try {
      this.sessionManager = audio.getAudioManager().getSessionManager();
    } catch (e) {
      this.sessionManager = null;
    }
    return this.sessionManager;
  }

  /** 会话焦点状态回调（会话级「被打断转暂停」的提示经由此事件送达） */
  private handleSessionStateChange(event: audio.AudioSessionStateChangedEvent): void {
    const hint = event.stateChangeHint;
    if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_PAUSE ||
      hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_STOP) {
      // 系统已暂停/停止音频流：主动同步引擎状态以保留进度
      this.playingBeforeInterrupt = this.stateInternal === PlayState.Playing;
      this.pause().catch(() => {
      });
    } else if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_RESUME) {
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
    * 均衡器开启时走 free-pcm PCM 管线（解码 + AudioRenderer 渲染，EQ 生效）；
    * 加载失败自动回退 AVPlayer（EQ 不生效但不断播）
   * @param url 网络地址或本地路径（支持 file:// 前缀；本地文件以 fd:// 方式播放）
   * @param headers 自定义 HTTP 头（网络源生效；PCM 管线暂不支持请求头）
   * @param mediaId 歌曲唯一标识（platform@id），用于稳定缓存键
   */
  async load(url: string, headers: Record<string, string> | null, mediaId?: string): Promise<void> {
    this.syncEqListenersOnce();
    // 会话必须在起流前激活完成，「被打断转暂停」策略才对本流生效（异步竞态会导致策略失效）
    await this.awaitSessionReady();
    // 音频缓存代理改写（对齐 RN react-native-track-player SimpleCache 行为）
    // 仅 http/https 且非 m3u8 时改写；降级时返回原始 URL，不影响播放
    // 代理 URL 已将 headers 编码进查询参数，无需再传给播放器
    // mediaId 传入时 cacheKey 基于 SHA1(mediaId)，同一首歌 CDN 签名变化也命中同一缓存
    const proxyUrl = await audioCacheProxy.getProxyUrl(url, headers ?? undefined, mediaId);
    const usingProxy = proxyUrl !== url;
    const playUrl = proxyUrl;
    const playHeaders = usingProxy ? null : headers;
    this.lastUrl = url;
    this.lastHeaders = headers;
    await this.teardownPcm();
    if (EqualizerManager.getInstance().shouldUsePcmEngine()) {
      // 停掉 AVPlayer 旧源，避免 PCM 与 AVPlayer 双路输出
      await this.silenceAVPlayer();
      try {
        await this.loadPcm(playUrl);
        return;
      } catch (e) {
        Log.warn('PCM 引擎加载失败，回退 AVPlayer: ' + (e instanceof Error ? e.message : ''));
        await this.teardownPcm();
      }
    }
    this.pcmMode = false;
    const p = await this.recycle();
    // 播放器已回收，上一首本地文件句柄不再被占用
    this.closeLocalFile();
    const isHttp = playUrl.startsWith('http://') || playUrl.startsWith('https://');
    let sourceSet = false;
    if (isHttp && playHeaders !== null && Object.keys(playHeaders).length > 0) {
      try {
        await p.setMediaSource(media.createMediaSourceWithUrl(playUrl, playHeaders));
        sourceSet = true;
      } catch (e) {
        Log.warn('setMediaSource 失败，回退无请求头播放');
      }
    }
    if (!sourceSet) {
      if (isHttp) {
        p.url = playUrl;
      } else {
        // AVPlayer 不支持裸磁盘路径，本地文件需打开为 fd://
        const path = playUrl.startsWith('file://') ? playUrl.substring('file://'.length) : playUrl;
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

  // ==================== free-pcm PCM 引擎 ====================

  /** 将 AVPlayer 静音回收到 idle（切换到 PCM 管线前调用，避免双路输出） */
  private async silenceAVPlayer(): Promise<void> {
    const p = this.player;
    if (p === null) {
      return;
    }
    const st = p.state;
    if (st === 'idle' || st === 'released' || st === 'error') {
      return;
    }
    try {
      await p.reset();
    } catch (e) {
      // 忽略
    }
    this.closeLocalFile();
    this.stateInternal = PlayState.Idle;
    this.onStateChanged(this.stateInternal);
  }

  /** free-pcm 管线加载：创建流式解码器并等待就绪（EQ 增益即时应用） */
  private async loadPcm(url: string): Promise<void> {
    const path = url.startsWith('file://') ? url.substring('file://'.length) : url;
    const options: PcmStreamDecoderOptions = { eqEnabled: true };
    const callbacks: PcmStreamDecoderCallbacks = {
      onError: (e: Error): void => {
        Log.error('PCM 解码错误: ' + e.message);
      }
    };
    const tool = new PcmDecoderTool();
    const decoder = tool.createStreamDecoder(path, options, callbacks);
    this.pcmDecoder = decoder;
    // 网络/解码就绪限时，超时回退 AVPlayer
    const info = await PlayerEngine.withTimeout(decoder.ready, 12000);
    this.pcmInfo = info;
    decoder.setEqGains(EqualizerManager.getInstance().getGains());
    this.pcmMode = true;
    this.stateInternal = PlayState.Prepared;
    this.onStateChanged(this.stateInternal);
  }

  private static withTimeout(p: Promise<PcmStreamInfo>, timeoutMs: number): Promise<PcmStreamInfo> {
    return new Promise<PcmStreamInfo>((resolve: (v: PcmStreamInfo) => void,
      reject: (r: Object) => void): void => {
      const timer = setTimeout((): void => {
        reject(new Error('PCM 解码就绪超时'));
      }, timeoutMs);
      p.then((v: PcmStreamInfo): void => {
        clearTimeout(timer);
        resolve(v);
      }).catch((e: Object): void => {
        clearTimeout(timer);
        reject(e);
      });
    });
  }

  /** 拆除 PCM 管线（换曲/停播/回退 AVPlayer 时调用） */
  private async teardownPcm(): Promise<void> {
    this.stopPcmEndWatch();
    const player = this.pcmPlayer;
    const decoder = this.pcmDecoder;
    this.pcmPlayer = null;
    this.pcmDecoder = null;
    this.pcmInfo = null;
    this.pcmMode = false;
    if (player !== null) {
      try {
        await player.stop();
      } catch (e) {
        // 忽略
      }
    }
    if (decoder !== null) {
      try {
        decoder.close();
      } catch (e) {
        // 忽略
      }
    }
  }

  /** PCM 渲染器创建后注册打断监听、恢复倍速 */
  private setupPcmRenderer(renderer: audio.AudioRenderer): void {
    try {
      renderer.on('audioInterrupt', (info: audio.InterruptEvent) => {
        this.handleInterrupt(info);
      });
    } catch (e) {
      // 忽略监听注册失败
    }
    const player = this.pcmPlayer;
    if (player !== null && this.rate !== 1) {
      player.setSpeed(this.rate);
    }
  }

  /** PCM 管线播放（已完成状态下重播；解码器退出时原位重建） */
  private async playPcm(): Promise<void> {
    if (this.stateInternal === PlayState.Completed) {
      // 播完重播：重建解码器从头播放
      await this.load(this.lastUrl, this.lastHeaders);
    }
    const decoder = this.pcmDecoder;
    const info = this.pcmInfo;
    if (decoder === null || info === null) {
      throw new Error('player is not prepared');
    }
    if (this.pcmPlayer === null) {
      this.pcmPlayer = this.createPcmPlayer();
      await this.pcmPlayer.play(decoder, info);
    } else {
      try {
        await this.pcmPlayer.resume();
      } catch (e) {
        // 解码器已退出（如长暂停后网络断开）：从当前位置重建管线
        const resumePosMs = Math.max(0, decoder.getPosition());
        await this.load(this.lastUrl, this.lastHeaders);
        const fresh = this.pcmDecoder;
        const freshInfo = this.pcmInfo;
        if (fresh === null || freshInfo === null) {
          throw new Error('PCM 管线重建失败');
        }
        try {
          fresh.seekTo(resumePosMs);
        } catch (e) {
          Log.error('PCM 重建后 seek 失败: ' + (e as Error).message);
        }
        this.pcmPlayer = this.createPcmPlayer();
        await this.pcmPlayer.play(fresh, freshInfo);
      }
    }
    this.stateInternal = PlayState.Playing;
    this.onStateChanged(this.stateInternal);
    this.startPcmEndWatch();
  }

  private createPcmPlayer(): AudioRendererPlayer {
    const player = new AudioRendererPlayer();
    player.setOnCreated((renderer: audio.AudioRenderer): void => {
      this.setupPcmRenderer(renderer);
    });
    return player;
  }

  /** PCM 播放完成检测（解码位置到达时长即视为播完，与 AVPlayer completed 语义对齐） */
  private startPcmEndWatch(): void {
    this.stopPcmEndWatch();
    this.pcmEndTimer = setInterval((): void => {
      if (!this.pcmMode || this.stateInternal !== PlayState.Playing) {
        return;
      }
      const decoder = this.pcmDecoder;
      const info = this.pcmInfo;
      if (decoder === null || info === null || info.durationMs <= 0) {
        return;
      }
      if (decoder.getPosition() >= info.durationMs - 200) {
        this.stopPcmEndWatch();
        this.stateInternal = PlayState.Completed;
        this.onEndReached();
        this.onStateChanged(this.stateInternal);
      }
    }, 250);
  }

  private stopPcmEndWatch(): void {
    if (this.pcmEndTimer !== -1) {
      clearInterval(this.pcmEndTimer);
      this.pcmEndTimer = -1;
    }
  }

  /** EQ 开关切换引擎：已加载音源原位重载（保持进度与播放状态） */
  private handleEqEngineToggle(_enabled: boolean): void {
    if (this.lastUrl.length === 0) {
      return;
    }
    const st = this.stateInternal;
    if (st !== PlayState.Prepared && st !== PlayState.Playing &&
      st !== PlayState.Paused && st !== PlayState.Completed) {
      // 未加载音源：下次 load 按新引擎执行
      return;
    }
    const wasPlaying = st === PlayState.Playing;
    const pos = this.position;
    this.load(this.lastUrl, this.lastHeaders).then((): void => {
      if (pos > 0.2) {
        this.seek(pos);
      }
      if (wasPlaying) {
        this.play().catch((): void => {
        });
      }
    }).catch((): void => {
      this.stateInternal = PlayState.Error;
      this.onError('均衡器切换失败');
    });
  }

  async play(): Promise<void> {
    // 恢复播放/起流前确保会话就绪：会话可能因超时/被抢占停用，需重新激活
    await this.awaitSessionReady();
    if (this.pcmMode) {
      if (this.stateInternal === PlayState.Playing) {
        return;
      }
      await this.playPcm();
      return;
    }
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
    if (this.pcmMode) {
      if (this.stateInternal !== PlayState.Playing) {
        return;
      }
      const player = this.pcmPlayer;
      if (player !== null) {
        await player.pause();
      }
      this.stopPcmEndWatch();
      this.stateInternal = PlayState.Paused;
      this.onStateChanged(this.stateInternal);
      return;
    }
    const p = await this.ensurePlayer();
    if (p.state === 'paused' || p.state === 'idle' || p.state === 'initialized' ||
      p.state === 'stopped' || p.state === 'released' || p.state === 'error') {
      return;
    }
    await p.pause();
  }

  async stop(): Promise<void> {
    if (this.pcmMode) {
      await this.teardownPcm();
      this.stateInternal = PlayState.Stopped;
      this.onStateChanged(this.stateInternal);
      return;
    }
    const p = await this.ensurePlayer();
    if (p.state === 'stopped' || p.state === 'idle' || p.state === 'initialized' ||
      p.state === 'released' || p.state === 'error') {
      return;
    }
    await p.stop();
  }

  /** 跳转（秒） */
  seek(positionSec: number): void {
    // Slider 等来源可能回调 NaN/负数（动画期间越界）；native seekTo 对负数同步抛错，必须钳位
    if (!(positionSec > 0)) {
      positionSec = 0;
    }
    let ms = Math.floor(positionSec * 1000);
    if (ms < 0) {
      ms = 0;
    }
    if (this.pcmMode) {
      const decoder = this.pcmDecoder;
      if (decoder === null) {
        return;
      }
      const info = this.pcmInfo;
      if (info !== null && info.durationMs > 0 && ms > info.durationMs) {
        ms = info.durationMs;
      }
      const player = this.pcmPlayer;
      if (player !== null && this.stateInternal === PlayState.Playing) {
        try {
          player.seekTo(ms).then((): void => {
            this.onSeekDone(positionSec);
          }).catch((): void => {
          });
        } catch (e) {
          Log.error('PCM seek 失败: ' + (e as Error).message);
        }
      } else {
        // 未开始渲染（prepared/paused）：直接对解码器跳转（native 对非法值同步抛错，需捕获）
        try {
          decoder.seekTo(ms);
          this.onSeekDone(positionSec);
        } catch (e) {
          Log.error('PCM 解码器 seek 失败: ' + (e as Error).message);
        }
      }
      return;
    }
    const p = this.player;
    if (p === null) {
      return;
    }
    if (p.state === 'prepared' || p.state === 'playing' || p.state === 'paused' ||
      p.state === 'completed') {
      p.seek(ms);
    }
  }

  /** 倍速（0.125 ~ 3） */
  setRate(rate: number): void {
    this.rate = rate;
    if (this.pcmMode) {
      const player = this.pcmPlayer;
      if (player !== null) {
        player.setSpeed(rate);
      }
      return;
    }
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
    if (this.pcmMode) {
      const player = this.pcmPlayer;
      if (player !== null) {
        player.setVolume(volume).catch((): void => {
        });
      }
      return;
    }
    const p = this.player;
    if (p === null) {
      return;
    }
    if (p.state === 'prepared' || p.state === 'playing' || p.state === 'paused' ||
      p.state === 'completed') {
      p.setVolume(volume);
    }
  }

  get audioEffectEnabled(): boolean {
    return this.audioEffectOn;
  }

  /** 开关系统音效（立即应用到当前实例，换源后自动重应用） */
  setAudioEffectEnabled(enabled: boolean): void {
    this.audioEffectOn = enabled;
    this.applyAudioEffectMode();
  }

  /** 应用音效模式（仅在 prepared/playing/paused/completed 状态可设置，否则忽略） */
  private applyAudioEffectMode(): void {
    const p = this.player;
    if (p === null) {
      return;
    }
    try {
      p.audioEffectMode = this.audioEffectOn
        ? audio.AudioEffectMode.EFFECT_DEFAULT
        : audio.AudioEffectMode.EFFECT_NONE;
    } catch (e) {
      // 状态不允许设置时忽略，prepared 后会重新应用
    }
  }

  async release(): Promise<void> {
    this.offEqEnabled();
    this.offEqGains();
    await this.teardownPcm();
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
