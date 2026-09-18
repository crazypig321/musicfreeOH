import avSession from '@ohos.multimedia.avsession';
import image from '@ohos.multimedia.image';
import { ContextHolder } from '../common/ContextHolder';
import { MusicItem } from '../common/model/MediaTypes';
import { ArtworkCache } from '../utils/ArtworkCache';
import { Log } from '../utils/Log';
import { trackPlayer } from './TrackPlayer';
import { PlayState } from './PlayerEngine';

/**
 * 媒体会话（AVSession）
 * 将 trackPlayer 的播放状态/元数据同步到系统媒体中心（通知栏/锁屏/播控中心），
 * 并接收系统播控命令（播放/暂停/上下曲/进度拖动）。
 * 对应 RN 侧 react-native-track-player 的通知栏能力。
 */
export class MediaSession {
  private static readonly POSITION_SYNC_INTERVAL_MS = 1000;

  private session: avSession.AVSession | null = null;
  private listenersRegistered: boolean = false;
  private lastMusic: MusicItem | null = null;
  private lastPosition: number = 0;
  private lastDuration: number = 0;
  private lastState: PlayState = PlayState.Idle;
  private syncedDuration: number = 0;
  private lastPositionSyncAt: number = 0;
  /** 当前封面对应的 artwork 地址 */
  private artworkUrl: string = '';
  /** 当前封面（已解码，供 mediaImage 使用） */
  private artworkPixel: image.PixelMap | null = null;
  /** 封面是否已加载完成（含失败回退，避免空 artwork 反复触发） */
  private artworkReady: boolean = false;
  /** 封面加载代次：切歌后丢弃过期结果 */
  private artworkGen: number = 0;
  /** 兜底封面（资源 media/altImage.jpg，仅解码一次） */
  private fallbackPixel: image.PixelMap | null = null;

  /** 初始化会话并绑定 trackPlayer 事件（幂等） */
  async setup(): Promise<void> {
    if (this.session !== null) {
      return;
    }
    try {
      const session = await avSession.createAVSession(ContextHolder.get(), 'MusicFreePlayer', 'audio');
      this.session = session;

      session.on('play', () => {
        trackPlayer.play().catch(() => {
        });
      });
      session.on('pause', () => {
        trackPlayer.pause().catch(() => {
        });
      });
      session.on('playNext', () => {
        trackPlayer.skipToNext().catch(() => {
        });
      });
      session.on('playPrevious', () => {
        trackPlayer.skipToPrevious().catch(() => {
        });
      });
      session.on('stop', () => {
        trackPlayer.reset().catch(() => {
        });
      });
      session.on('seek', (time: number) => {
        trackPlayer.seekTo(time / 1000);
      });

      await session.activate();

      // trackPlayer 事件监听只需注册一次（setup 可能因 Ability 重建被再次调用）
      if (!this.listenersRegistered) {
        this.listenersRegistered = true;
        trackPlayer.onCurrentMusicChanged((music: MusicItem | null) => {
          this.updateMetadata(music);
        });
        trackPlayer.onProgressChanged((position: number, duration: number) => {
          this.lastPosition = position;
          this.lastDuration = duration;
          if (this.lastMusic !== null && duration > 0 && this.syncedDuration !== duration) {
            // 流式音源的真实时长在播放后才可知，补写元数据
            this.updateMetadata(this.lastMusic);
          }
          this.updatePlaybackState(false);
        });
        trackPlayer.onPlayStateChanged((state: PlayState) => {
          this.lastState = state;
          this.updatePlaybackState(true);
        });

        // 启动时恢复的当前歌曲不会触发 onCurrentMusicChanged，主动补同步元数据，
        // 否则播控中心拿不到元数据、不显示媒体卡片，仅有长时任务的普通通知
        const restored = trackPlayer.currentMusic;
        if (restored !== null) {
          this.lastState = trackPlayer.playState;
          this.updateMetadata(restored);
          this.updatePlaybackState(true);
        }
      }
    } catch (e) {
      Log.error('AVSession 初始化失败', e);
    }
  }

  /** 同步当前歌曲元数据到媒体中心 */
  private updateMetadata(music: MusicItem | null): void {
    const session = this.session;
    if (session === null) {
      return;
    }
    this.lastMusic = music;
    if (music === null) {
      return;
    }
    this.syncedDuration = this.lastDuration > 0 ? this.lastDuration : music.duration;
    session.setAVMetadata(this.buildMetadata(music)).catch(() => {
    });
    if (!this.artworkReady || this.artworkUrl !== music.artwork) {
      this.refreshArtwork(music.artwork).catch(() => {
      });
    }
  }

  /** 构造当前歌曲的媒体中心元数据 */
  private buildMetadata(music: MusicItem): avSession.AVMetadata {
    const meta: avSession.AVMetadata = {
      assetId: `${music.platform}_${music.id}`,
      title: music.title,
      artist: music.artist,
      album: music.album,
      duration: Math.round(this.syncedDuration * 1000)
    };
    if (this.artworkReady && this.artworkPixel !== null && this.artworkUrl === music.artwork) {
      meta.mediaImage = this.artworkPixel;
    }
    return meta;
  }

  /** 拉取封面并补写到媒体中心（无封面/失败时回退 altImage） */
  private async refreshArtwork(url: string): Promise<void> {
    const gen = ++this.artworkGen;
    const pixel = await this.loadArtwork(url);
    if (gen !== this.artworkGen) {
      // 已切歌，结果过期
      return;
    }
    this.artworkUrl = url;
    this.artworkPixel = pixel;
    this.artworkReady = true;
    const session = this.session;
    const music = this.lastMusic;
    if (session === null || music === null || music.artwork !== url) {
      return;
    }
    session.setAVMetadata(this.buildMetadata(music)).catch(() => {
    });
  }

  /** 下载并解码封面；失败返回兜底图 */
  private async loadArtwork(url: string): Promise<image.PixelMap | null> {
    if (url.length > 0) {
      const buf = await ArtworkCache.downloadBuffer(url);
      if (buf !== null) {
        try {
          const source = image.createImageSource(MediaSession.toArrayBuffer(buf));
          return await source.createPixelMap();
        } catch (e) {
          Log.warn('AVSession 封面解码失败');
        }
      }
    }
    return this.loadFallbackArtwork();
  }

  /** 兜底封面：资源 media/altImage.jpg（仅解码一次） */
  private async loadFallbackArtwork(): Promise<image.PixelMap | null> {
    if (this.fallbackPixel !== null) {
      return this.fallbackPixel;
    }
    try {
      const content = await ContextHolder.get().resourceManager.getMediaContent($r('app.media.altImage').id);
      const source = image.createImageSource(MediaSession.toArrayBuffer(content));
      this.fallbackPixel = await source.createPixelMap();
    } catch (e) {
      Log.warn('AVSession 兜底封面解码失败');
    }
    return this.fallbackPixel;
  }

  private static toArrayBuffer(data: Uint8Array): ArrayBuffer {
    return data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
  }

  /** 同步播放状态/进度到媒体中心（position 节流） */
  private updatePlaybackState(force: boolean): void {
    const session = this.session;
    if (session === null) {
      return;
    }
    const now = Date.now();
    if (!force && now - this.lastPositionSyncAt < MediaSession.POSITION_SYNC_INTERVAL_MS) {
      return;
    }
    this.lastPositionSyncAt = now;

    const state = this.mapPlayState(this.lastState);
    const playback: avSession.AVPlaybackState = {
      state: state,
      speed: trackPlayer.getRate(),
      position: {
        elapsedTime: Math.round(this.lastPosition * 1000),
        updateTime: now
      }
    };
    session.setAVPlaybackState(playback).catch(() => {
    });
  }

  /** PlayState -> AVSession PlaybackState */
  private mapPlayState(state: PlayState): avSession.PlaybackState {
    if (state === PlayState.Playing) {
      return avSession.PlaybackState.PLAYBACK_STATE_PLAY;
    }
    if (state === PlayState.Paused) {
      return avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
    }
    if (state === PlayState.Completed) {
      return avSession.PlaybackState.PLAYBACK_STATE_COMPLETED;
    }
    if (state === PlayState.Prepared) {
      return avSession.PlaybackState.PLAYBACK_STATE_PREPARE;
    }
    if (state === PlayState.Released) {
      return avSession.PlaybackState.PLAYBACK_STATE_RELEASED;
    }
    return avSession.PlaybackState.PLAYBACK_STATE_STOP;
  }

  /** 销毁会话（Ability onDestroy 时调用） */
  async destroy(): Promise<void> {
    const session = this.session;
    if (session === null) {
      return;
    }
    this.session = null;
    try {
      await session.deactivate();
      await session.destroy();
    } catch (e) {
      Log.warn('AVSession 销毁失败');
    }
  }
}

export const mediaSession = new MediaSession();
