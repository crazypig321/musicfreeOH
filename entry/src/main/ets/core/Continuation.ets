import { Want } from '@kit.AbilityKit';
import { JsonUtil } from '../utils/JsonUtil';
import { MusicItem, MusicItemSerializer } from '../common/model/MediaTypes';
import { MusicRepeatMode, MAX_PLAYLIST_SIZE } from '../common/Consts';
import { trackPlayer } from './TrackPlayer';
import { PlayState } from './PlayerEngine';
import { PersistStatus } from './PersistStatus';

/**
 * 应用接续（车机流转）数据载体
 * - 源端：buildPayload 从 trackPlayer 打包播放现场写入 onContinue 的 wantParam
 * - 目标端：parseFromWant 从 want.parameters 解析接续数据
 * - 系统限制 wantParam 数据 < 100KB：队列 JSON 超限时自动降级为仅传当前歌曲
 */
export class ContinuationKeys {
  static readonly QUEUE = 'musicfree.queue';
  static readonly CURRENT = 'musicfree.current';
  static readonly PROGRESS = 'musicfree.progress';
  static readonly PLAYING = 'musicfree.playing';
  static readonly REPEAT_MODE = 'musicfree.repeatMode';
}

/** 接续传输的数据上限守卫（系统硬限制 100KB，预留余量） */
const CONTINUATION_PAYLOAD_LIMIT = 90000;

/** 解析后的接续数据 */
export class ContinuationData {
  queue: Array<MusicItem> = [];
  current: MusicItem | null = null;
  progress: number = 0;
  playing: boolean = false;
  repeatMode: MusicRepeatMode = MusicRepeatMode.QUEUE;
}

export class Continuation {
  /**
   * 进程级接续数据暂存：接续拉起存活进程中被销毁的 Ability 时，系统可能不创建
   * WindowStage（卡启动页），EntryAbility 修复窗口/重新拉起后由此热应用播放现场
   */
  static pendingRepair: ContinuationData | null = null;

  /**
   * 源端打包播放现场（同步纯读，不发起网络请求，不中断当前播放）
   * 返回 null 表示当前无可接续内容
   */
  static buildPayload(): Record<string, Object> | null {
    const current = trackPlayer.currentMusic;
    if (current === null) {
      return null;
    }
    const payload: Record<string, Object> = {};
    try {
      const currentJson = JsonUtil.safeStringify(current.toPersistRecord());
      if (currentJson.length === 0) {
        return null;
      }
      payload[ContinuationKeys.CURRENT] = currentJson;
      // 大小守卫：总 payload 控制在系统 100KB 限制内，超限降级为仅传当前歌曲
      const queueJson = MusicItemSerializer.serialize(trackPlayer.playList);
      if (currentJson.length + queueJson.length < CONTINUATION_PAYLOAD_LIMIT) {
        payload[ContinuationKeys.QUEUE] = queueJson;
      }
      const progressInfo = trackPlayer.getProgress();
      let progress = progressInfo.position;
      if (progress < 0) {
        progress = 0;
      }
      payload[ContinuationKeys.PROGRESS] = progress;
      payload[ContinuationKeys.PLAYING] = trackPlayer.playState === PlayState.Playing;
      payload[ContinuationKeys.REPEAT_MODE] = trackPlayer.repeatMode;
      return payload;
    } catch (e) {
      return null;
    }
  }

  /**
   * 目标端从接续 want 中解析数据；非接续启动或数据非法时返回 null
   */
  static parseFromWant(want: Want): ContinuationData | null {
    const params = want.parameters;
    if (params === undefined || params === null) {
      return null;
    }
    try {
      const currentRaw = params[ContinuationKeys.CURRENT];
      if (typeof currentRaw !== 'string' || currentRaw.length === 0) {
        return null;
      }
      const currentRec = JsonUtil.parseRecord(currentRaw);
      if (currentRec === null) {
        return null;
      }
      const data = new ContinuationData();
      data.current = MusicItem.fromRecord(currentRec);

      // 队列可选（源端超限降级时不传）
      const queueRaw = params[ContinuationKeys.QUEUE];
      if (typeof queueRaw === 'string' && queueRaw.length > 0) {
        data.queue = MusicItemSerializer.deserialize(queueRaw).slice(0, MAX_PLAYLIST_SIZE);
      }

      const progressRaw = params[ContinuationKeys.PROGRESS];
      if (typeof progressRaw === 'number' && progressRaw > 0) {
        data.progress = progressRaw;
      }

      const playingRaw = params[ContinuationKeys.PLAYING];
      if (typeof playingRaw === 'boolean') {
        data.playing = playingRaw;
      }

      const modeRaw = params[ContinuationKeys.REPEAT_MODE];
      if (typeof modeRaw === 'string' &&
        (modeRaw === MusicRepeatMode.SHUFFLE || modeRaw === MusicRepeatMode.QUEUE ||
          modeRaw === MusicRepeatMode.SINGLE)) {
        data.repeatMode = modeRaw;
      }
      return data;
    } catch (e) {
      return null;
    }
  }

  /** 日志用的安全描述（不输出大体量数据） */
  static describe(data: ContinuationData): string {
    const current = data.current;
    const title = current !== null ? current.title : '';
    return `queue=${data.queue.length}, current=${title}, progress=${data.progress}, playing=${data.playing}`;
  }

  /** 冷启动接续：把接续数据覆写进本地持久化（须在 Bootstrap.setup 之前调用，恢复链随后自然生效） */
  static writeToPersistStatus(data: ContinuationData): void {
    const current = data.current;
    if (current === null) {
      return;
    }
    const queue = data.queue.length > 0 ? data.queue : [current];
    PersistStatus.setPlayList(queue);
    PersistStatus.setMusicItem(current);
    PersistStatus.setProgress(data.progress);
    PersistStatus.setRepeatMode(data.repeatMode);
  }
}
