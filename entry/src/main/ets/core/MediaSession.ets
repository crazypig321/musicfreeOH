import avSession from '@ohos.multimedia.avsession';
import { ContextHolder } from '../common/ContextHolder';
import { MusicItem } from '../model/MediaTypes';
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
  private lastMusic: MusicItem | null = null;
  private lastPosition: number = 0;
  private lastDuration: number = 0;
  private lastState: PlayState = PlayState.Idle;
  private syncedDuration: number = 0;
  private lastPositionSyncAt: number = 0;

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
    const meta: avSession.AVMetadata = {
      assetId: `${music.platform}_${music.id}`,
      title: music.title,
      artist: music.artist,
      album: music.album,
      duration: Math.round(this.syncedDuration * 1000)
    };
    session.setAVMetadata(meta).catch(() => {
    });
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
