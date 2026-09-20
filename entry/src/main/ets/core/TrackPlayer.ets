import { EventEmitter, EventListenerFn } from '../common/EventBus';
import { JsonUtil, JsonRecord } from '../common/JsonUtil';
import { MusicRepeatMode, MAX_PLAYLIST_SIZE } from '../common/Consts';
import { MusicItem, MediaSource, QualityKey } from '../common/model/MediaTypes';
import { MediaUtils } from '../utils/MediaUtils';
import { MediaIndexMap } from '../utils/MediaIndexMap';
import { Qualities } from '../utils/Qualities';
import { MinDistance } from '../utils/MinDistance';
import { Delay } from '../utils/Delay';
import { Log } from '../utils/Log';
import { BackgroundTask } from '../utils/BackgroundTask';
import { PersistStatus } from './PersistStatus';
import { appConfig } from './AppConfig';
import { musicHistory } from './MusicHistory';
import { localMusicSheet, downloadedSheet } from './LocalMusicSheet';
import { pluginManager } from '../plugin/PluginManager';
import { Plugin } from '../plugin/Plugin';
import { SupportMediaType, SearchResult } from '../common/model/SheetTypes';
import { Network } from '../infra/Network';
import { playerEngine, PlayState } from './PlayerEngine';

/** 播放失败原因 */
export class PlayFailReason {
  static readonly FORBID_CELLUAR_NETWORK_PLAY = 'FORBID_CELLUAR_NETWORK_PLAY';
  static readonly PLAY_LIST_IS_EMPTY = 'PLAY_LIST_IS_EMPTY';
  static readonly INVALID_SOURCE = 'INVALID_SOURCE';
}

/** 播放进度（秒） */
export class ProgressInfo {
  position: number = 0;
  duration: number = 0;
}

/** 播放结束事件 */
export class PlayEndEvent {
}

/** 当前歌曲变化事件 */
export class CurrentMusicChangedEvent {
  music: MusicItem | null = null;
}

/** 进度变化事件 */
export class ProgressChangedEvent {
  position: number = 0;
  duration: number = 0;
}

/** 播放器状态变化事件 */
export class PlayStateChangedEvent {
  state: PlayState = PlayState.Idle;
}

/** 播放列表变化事件 */
export class PlayListChangedEvent {
}

/** 移动网络播放被禁止事件（UI 弹提示用） */
export class CellularForbiddenEvent {
}

/**
 * 播放器（移植自 trackPlayer/index.ts）
 * 底层由 PlayerEngine（avPlayer）承担，替代 react-native-track-player
 */
export class TrackPlayer {
  private static readonly HALF_MAX_PLAYLIST_SIZE = 5000;
  /** 播放中进度落盘节流间隔（ms） */
  private static readonly PROGRESS_PERSIST_INTERVAL_MS = 10000;
  private ee: EventEmitter = new EventEmitter();

  private currentMusicItem: MusicItem | null = null;
  private repeatModeValue: MusicRepeatMode = MusicRepeatMode.QUEUE;
  private qualityValue: QualityKey = 'standard';
  private playListItems: Array<MusicItem> = [];
  private currentIndex: number = -1;
  private playListIndexMap: MediaIndexMap = new MediaIndexMap();
  private serviceInited: boolean = false;
  /** 恢复期标记（对应 RN track.isInit，播放失败时不跳下一首） */
  private initRestoring: boolean = false;
  /** 已加载到引擎的源（对应 RNTP queue[0] 的 track） */
  private loadedMusic: MusicItem | null = null;
  /** 防止连续播放失败时重复跳曲 */
  private handlingPlayFail: boolean = false;
  private progressTimer: number = -1;
  /** 上次进度落盘时间（节流用） */
  private lastProgressPersistAt: number = 0;

  constructor() {
  }

  // ---------------- 状态 ----------------

  get currentMusic(): MusicItem | null {
    return this.currentMusicItem;
  }

  get previousMusic(): MusicItem | null {
    const currentMusic = this.currentMusicItem;
    if (currentMusic === null) {
      return null;
    }
    return this.getPlayListMusicAt(this.currentIndex - 1);
  }

  get nextMusic(): MusicItem | null {
    const currentMusic = this.currentMusicItem;
    if (currentMusic === null) {
      return null;
    }
    return this.getPlayListMusicAt(this.currentIndex + 1);
  }

  get repeatMode(): MusicRepeatMode {
    return this.repeatModeValue;
  }

  get quality(): QualityKey {
    return this.qualityValue;
  }

  get playList(): Array<MusicItem> {
    return this.playListItems;
  }

  get playState(): PlayState {
    return playerEngine.state;
  }

  // ---------------- 初始化 ----------------

  setupTrackPlayer(): Promise<void> {
    const rate = PersistStatus.getRate();
    this.repeatModeValue = PersistStatus.getRepeatMode();
    if (rate !== 1) {
      playerEngine.setRate(rate);
    }

    const musicQueue = PersistStatus.getPlayList();
    if (musicQueue.length > 0) {
      this.addAll(musicQueue, undefined, this.repeatModeValue === MusicRepeatMode.SHUFFLE);
    }

    const track = PersistStatus.getMusicItem();
    if (track !== null && this.isInPlayList(track)) {
      const progress = PersistStatus.getProgress();
      if (!appConfig.getAutoPlayWhenAppStart()) {
        this.initRestoring = true;
      }
      const plugin = pluginManager.getByMedia(track);
      if (plugin !== null) {
        const quality = PersistStatus.getQuality();
        plugin.methods.getMediaSource(track, quality)
          .then((newSource: MediaSource | null) => {
            if (newSource !== null && newSource.url.length > 0) {
              track.url = newSource.url;
            }
            if (this.isCurrentMusic(track)) {
              const merged = newSource !== null ? this.mergeTrackSource(track, newSource) : track;
              this.setTrackSource(merged, false).then(() => {
                this.initRestoring = false;
                if (progress > 0) {
                  this.seekTo(progress);
                }
                // 启动自动续播：进度恢复完成后再播放（提前 play 会重新拉源并重置进度）
                if (appConfig.getAutoPlayWhenAppStart() && this.isCurrentMusic(track)) {
                  Log.debug('启动自动续播');
                  this.play().catch(() => {
                  });
                }
              }).catch(() => {
                this.initRestoring = false;
              });
            } else {
              this.initRestoring = false;
            }
          })
          .catch(() => {
            this.initRestoring = false;
          });
      } else {
        this.initRestoring = false;
      }
      this.setCurrentMusic(track);
    }

    if (!this.serviceInited) {
      playerEngine.onEndReached = () => {
        Log.debug('队列末尾，播放下一首');
        this.ee.emit('play-end', new PlayEndEvent());
        if (this.repeatModeValue === MusicRepeatMode.SINGLE) {
          this.play(null, true).catch(() => {
          });
        } else {
          this.skipToNext().catch(() => {
          });
        }
      };
      playerEngine.onError = (message: string) => {
        Log.error('播放出错', message);
        if (this.initRestoring) {
          this.initRestoring = false;
          return;
        }
        this.handlePlayFail().catch(() => {
        });
      };
      playerEngine.onStateChanged = (state: PlayState) => {
        this.handleStateChanged(state);
      };
      playerEngine.onSeekDone = (_positionSec: number) => {
        this.emitProgress();
      };
      this.serviceInited = true;
    }
    return Promise.resolve();
  }

  private handleStateChanged(state: PlayState): void {
    const ev = new PlayStateChangedEvent();
    ev.state = state;
    this.ee.emit('play-state-changed', ev);
    if (state === PlayState.Playing) {
      // 播放中申请音频长时任务，避免退后台后被系统挂起
      BackgroundTask.startAudio();
      this.startProgressTimer();
    } else {
      this.stopProgressTimer();
      // 暂停/播完时立即落盘进度，保证应用被杀后重启可续播
      if (state === PlayState.Paused || state === PlayState.Completed) {
        this.saveProgress();
      }
      // 暂停/停止/出错/释放时取消长时任务；
      // 换曲期间的 completed→idle→playing 不经过这些状态，任务不会抖动
      if (state === PlayState.Paused || state === PlayState.Stopped ||
        state === PlayState.Completed || state === PlayState.Error ||
        state === PlayState.Released) {
        BackgroundTask.stopAudio();
      }
    }
  }

  private startProgressTimer(): void {
    if (this.progressTimer !== -1) {
      return;
    }
    this.progressTimer = setInterval(() => {
      this.emitProgress();
      this.persistProgressIfNeeded();
    }, 500);
  }

  private stopProgressTimer(): void {
    if (this.progressTimer !== -1) {
      clearInterval(this.progressTimer);
      this.progressTimer = -1;
    }
  }

  private emitProgress(): void {
    const ev = new ProgressChangedEvent();
    ev.position = playerEngine.position;
    ev.duration = playerEngine.duration;
    this.ee.emit('progress-changed', ev);
  }

  /** 播放中周期性落盘进度（节流，避免高频写 preferences） */
  private persistProgressIfNeeded(): void {
    const now = Date.now();
    if (now - this.lastProgressPersistAt < TrackPlayer.PROGRESS_PERSIST_INTERVAL_MS) {
      return;
    }
    this.lastProgressPersistAt = now;
    this.saveProgress();
  }

  /** 持久化当前播放进度（供定时器/暂停/退后台/销毁时调用） */
  saveProgress(): void {
    if (this.currentMusicItem === null) {
      return;
    }
    const st = playerEngine.state;
    if (st !== PlayState.Prepared && st !== PlayState.Playing &&
      st !== PlayState.Paused && st !== PlayState.Completed) {
      return;
    }
    PersistStatus.setProgress(playerEngine.position);
  }

  // ---------------- 播放队列 ----------------

  getMusicIndexInPlayList(musicItem: MusicItem | null | undefined): number {
    if (musicItem === null || musicItem === undefined) {
      return -1;
    }
    return this.playListIndexMap.getIndex(musicItem);
  }

  isInPlayList(musicItem: MusicItem | null | undefined): boolean {
    if (musicItem === null || musicItem === undefined) {
      return false;
    }
    return this.playListIndexMap.has(musicItem);
  }

  getPlayListMusicAt(index: number): MusicItem | null {
    const playList = this.playListItems;
    const len = playList.length;
    if (len === 0) {
      return null;
    }
    return playList[(index + len) % len];
  }

  isPlayListEmpty(): boolean {
    return this.playListItems.length === 0;
  }

  addAll(musicItems: Array<MusicItem>, beforeIndex?: number, shouldShuffle?: boolean): void {
    const now = Date.now();
    let newPlayList: Array<MusicItem> = [];
    const currentPlayList = this.playListItems;
    musicItems.forEach((item: MusicItem, index: number) => {
      item.timeStamp = now;
      item.sortIndex = index;
    });

    if (beforeIndex === undefined || beforeIndex < 0) {
      // 1.1. 添加到列表末尾，并过滤掉已有的歌曲
      const filtered: Array<MusicItem> = [];
      for (const item of musicItems) {
        if (!this.isInPlayList(item)) {
          filtered.push(item);
        }
      }
      newPlayList = currentPlayList.concat(filtered);
    } else {
      // 1.2. 插入
      const indexMap = new MediaIndexMap(musicItems);
      const beforeDraft: Array<MusicItem> = [];
      for (const item of currentPlayList.slice(0, beforeIndex)) {
        if (!indexMap.has(item)) {
          beforeDraft.push(item);
        }
      }
      const afterDraft: Array<MusicItem> = [];
      for (const item of currentPlayList.slice(beforeIndex)) {
        if (!indexMap.has(item)) {
          afterDraft.push(item);
        }
      }
      newPlayList = beforeDraft.concat(musicItems).concat(afterDraft);
    }

    // 2. 列表过长时收缩
    if (newPlayList.length > MAX_PLAYLIST_SIZE) {
      newPlayList = this.shrinkPlayListToSize(
        newPlayList,
        beforeIndex !== undefined ? beforeIndex : newPlayList.length - 1,
      );
    }

    // 3. 随机
    if (shouldShuffle === true) {
      newPlayList = TrackPlayer.shuffle(newPlayList);
    }
    // 4. 设置播放列表
    this.setPlayList(newPlayList);
  }

  add(musicItem: MusicItem | Array<MusicItem>, beforeIndex?: number): void {
    this.addAll(
      Array.isArray(musicItem) ? musicItem : [musicItem],
      beforeIndex,
    );
  }

  addNext(musicItem: MusicItem | Array<MusicItem>): void {
    const shouldAutoPlay = this.isPlayListEmpty() || this.currentMusicItem === null;
    this.add(musicItem, this.currentIndex + 1);
    if (shouldAutoPlay) {
      const first = Array.isArray(musicItem) ? musicItem[0] : musicItem;
      this.play(first).catch(() => {
      });
    }
  }

  async remove(musicItem: MusicItem): Promise<void> {
    const playList = this.playListItems;
    let newPlayList: Array<MusicItem> = playList.slice();
    let currentMusic: MusicItem | null = this.currentMusicItem;
    const targetIndex = this.getMusicIndexInPlayList(musicItem);
    let shouldPlayCurrent: boolean | null = null;
    if (targetIndex === -1) {
      return;
    }
    if (this.currentIndex === targetIndex) {
      // 移除的是当前项
      newPlayList.splice(targetIndex, 1);
      if (newPlayList.length === 0) {
        currentMusic = null;
        shouldPlayCurrent = false;
      } else {
        currentMusic = newPlayList[this.currentIndex % newPlayList.length];
        shouldPlayCurrent = !TrackPlayer.musicIsPaused(playerEngine.state);
      }
      this.setCurrentMusic(currentMusic);
    } else {
      newPlayList.splice(targetIndex, 1);
    }
    this.setPlayList(newPlayList);
    if (shouldPlayCurrent === true) {
      await this.play(currentMusic, true);
    } else if (shouldPlayCurrent === false) {
      await playerEngine.stop();
    }
  }

  isCurrentMusic(musicItem: MusicItem | null | undefined): boolean {
    return MediaUtils.isSameMediaItem(musicItem, this.currentMusicItem);
  }

  // ---------------- 播放逻辑 ----------------

  async play(musicItem?: MusicItem | null, forcePlay?: boolean): Promise<void> {
    try {
      if (musicItem === undefined || musicItem === null) {
        musicItem = this.currentMusicItem;
      }
      if (musicItem === null) {
        throw new Error(PlayFailReason.PLAY_LIST_IS_EMPTY);
      }

      // 1. 移动网络禁止播放
      const localPath = MediaUtils.getLocalPath(musicItem);
      if (Network.getInstance().isCellular &&
        !appConfig.getUseCellularNetworkPlay() &&
        localMusicSheet.isLocalMusic(musicItem) === null &&
        downloadedSheet.isLocalMusic(musicItem) === null &&
        localPath === null) {
        await playerEngine.stop();
        throw new Error(PlayFailReason.FORBID_CELLUAR_NETWORK_PLAY);
      }

      // 2. 如果是当前正在播放的音频
      if (this.isCurrentMusic(musicItem)) {
        if (this.loadedMusic !== null &&
          MediaUtils.isSameMediaItem(this.loadedMusic, musicItem) &&
          this.loadedMusic.url.length > 0) {
          // 2.1 当前已有源
          const state = playerEngine.state;
          if (state === PlayState.Stopped || state === PlayState.Error) {
            await this.setTrackSource(this.loadedMusic, true);
          } else {
            if (forcePlay === true) {
              this.seekTo(0);
            }
            if (state !== PlayState.Playing &&
              (state === PlayState.Prepared || state === PlayState.Paused ||
                state === PlayState.Completed)) {
              await playerEngine.play();
            }
          }
          return;
        }
        // 2.2 其他情况：重新获取源
      }

      // 3. 不在播放列表中，添加到队尾
      if (!this.isInPlayList(musicItem)) {
        this.add(musicItem);
      }

      // 4. 更新当前音乐
      this.setCurrentMusic(musicItem);

      // 5. 获取音源
      const plugin = pluginManager.getByName(musicItem.platform);
      const qualityOrder = Qualities.getQualityOrder(
        appConfig.getDefaultPlayQuality(),
        appConfig.getPlayQualityOrder(),
      );
      let source: MediaSource | null = null;
      for (const quality of qualityOrder) {
        if (this.isCurrentMusic(musicItem)) {
          if (plugin !== null) {
            const s = await plugin.methods.getMediaSource(musicItem, quality);
            source = s === null ? null : s;
          } else {
            source = null;
          }
          if (source !== null) {
            this.setQualityInternal(quality);
            break;
          }
        } else {
          // 已切换到其他歌曲
          return;
        }
      }

      if (!this.isCurrentMusic(musicItem)) {
        return;
      }
      if (source === null) {
        // 5.1 使用缓存过的源
        if (Object.keys(musicItem.source).length > 0) {
          for (const quality of qualityOrder) {
            const cached = musicItem.source[quality];
            if (cached !== undefined && cached.url.length > 0) {
              source = cached;
              this.setQualityInternal(quality);
              break;
            }
          }
        }
        // 5.2 没有源
        if (source === null && musicItem.url.length === 0) {
          if (appConfig.getTryChangeSourceWhenPlayFail()) {
            const similarMusic = await this.getSimilarMusic(musicItem);
            if (similarMusic !== null) {
              const similarMusicPlugin = pluginManager.getByMedia(similarMusic);
              for (const quality of qualityOrder) {
                if (this.isCurrentMusic(musicItem)) {
                  if (similarMusicPlugin !== null) {
                    const s = await similarMusicPlugin.methods.getMediaSource(similarMusic, quality);
                    source = s === null ? null : s;
                  } else {
                    source = null;
                  }
                  if (source !== null) {
                    this.setQualityInternal(quality);
                    break;
                  }
                } else {
                  return;
                }
              }
            }
            if (source === null) {
              throw new Error(PlayFailReason.INVALID_SOURCE);
            }
          } else {
            throw new Error(PlayFailReason.INVALID_SOURCE);
          }
        } else if (source === null) {
          source = new MediaSource();
          source.url = musicItem.url;
          this.setQualityInternal('standard');
        }
      }

      // 6. 合并结果
      const track = this.mergeTrackSource(musicItem, source);

      // 7. 新增历史记录
      musicHistory.addMusic(musicItem).catch(() => {
      });

      Log.debug('获取音源成功: ' + track.title);
      // 8. 设置音源
      await this.setTrackSource(track);

      // 9. 获取补充信息
      let info: JsonRecord | null = null;
      try {
        info = plugin !== null ? await plugin.methods.getMusicInfo(musicItem) : null;
      } catch (e) {
        info = null;
      }

      // 10. 设置补充信息
      if (info !== null && this.isCurrentMusic(musicItem)) {
        const mergedTrack = this.mergeTrackInfo(track, info);
        this.currentMusicItem = mergedTrack;
        PersistStatus.setMusicItem(mergedTrack);
        const ev = new CurrentMusicChangedEvent();
        ev.music = mergedTrack;
        this.ee.emit('current-music-changed', ev);
      }
    } catch (e) {
      const message = e instanceof Error ? e.message : '';
      if (message === PlayFailReason.FORBID_CELLUAR_NETWORK_PLAY) {
        Log.warn('当前非WIFI环境，播放已停止');
        this.ee.emit('cellular-forbidden', new CellularForbiddenEvent());
      } else if (message === PlayFailReason.INVALID_SOURCE) {
        Log.debug('音源为空，播放失败');
        await this.handlePlayFail();
      } else if (message === PlayFailReason.PLAY_LIST_IS_EMPTY) {
        // 队列是空的
      } else {
        Log.error('播放失败: ' + message);
        await this.handlePlayFail();
      }
    }
  }

  async pause(): Promise<void> {
    await playerEngine.pause();
  }

  toggleRepeatMode(): void {
    const next = this.repeatModeValue === MusicRepeatMode.SHUFFLE
      ? MusicRepeatMode.SINGLE
      : (this.repeatModeValue === MusicRepeatMode.SINGLE ? MusicRepeatMode.QUEUE : MusicRepeatMode.SHUFFLE);
    this.setRepeatModeInternal(next);
  }

  /** 清空播放队列 */
  async clearPlayList(): Promise<void> {
    this.setPlayList([]);
    this.setCurrentMusic(null);
    await playerEngine.stop();
    this.loadedMusic = null;
    PersistStatus.setMusicItem(null);
    PersistStatus.setProgress(0);
  }

  async skipToNext(): Promise<void> {
    if (this.isPlayListEmpty()) {
      this.setCurrentMusic(null);
      return;
    }
    await this.play(this.getPlayListMusicAt(this.currentIndex + 1), true);
  }

  async skipToPrevious(): Promise<void> {
    if (this.isPlayListEmpty()) {
      this.setCurrentMusic(null);
      return;
    }
    await this.play(
      this.getPlayListMusicAt(this.currentIndex === -1 ? 0 : this.currentIndex - 1),
      true,
    );
  }

  async changeQuality(newQuality: QualityKey): Promise<boolean> {
    if (newQuality === this.qualityValue) {
      return true;
    }
    const musicItem = this.currentMusicItem;
    if (musicItem === null) {
      return false;
    }
    try {
      const progress = playerEngine.position;
      const plugin = pluginManager.getByMedia(musicItem);
      const newSource = plugin !== null
        ? await plugin.methods.getMediaSource(musicItem, newQuality)
        : null;
      if (newSource === null || newSource.url.length === 0) {
        throw new Error(PlayFailReason.INVALID_SOURCE);
      }
      if (this.isCurrentMusic(musicItem)) {
        const playingState = playerEngine.state;
        const merged = this.mergeTrackSource(musicItem, newSource);
        await this.setTrackSource(merged, !TrackPlayer.musicIsPaused(playingState));
        this.seekTo(progress);
        this.setQualityInternal(newQuality);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  async playWithReplacePlayList(musicItem: MusicItem, newPlayList: Array<MusicItem>): Promise<void> {
    if (newPlayList.length === 0) {
      return;
    }
    const now = Date.now();
    if (newPlayList.length > MAX_PLAYLIST_SIZE) {
      newPlayList = this.shrinkPlayListToSize(newPlayList, this.findIndexSameItem(newPlayList, musicItem));
    }
    newPlayList.forEach((it: MusicItem, index: number) => {
      it.timeStamp = now;
      it.sortIndex = index;
    });
    this.setPlayList(
      this.repeatModeValue === MusicRepeatMode.SHUFFLE
        ? TrackPlayer.shuffle(newPlayList)
        : newPlayList,
    );
    await this.play(musicItem, true);
  }

  /**
   * 手动更换音源：用新条目替换队列中的当前项并播放
   * 返回是否成功（失败多为新音源不可用）
   */
  async changeSource(newItem: MusicItem): Promise<boolean> {
    const musicItem = this.currentMusicItem;
    if (musicItem === null) {
      return false;
    }
    const idx = this.getMusicIndexInPlayList(musicItem);
    if (idx !== -1) {
      const newPlayList = this.playListItems.slice();
      newPlayList[idx] = newItem;
      this.setPlayList(newPlayList);
    }
    await this.play(newItem, true);
    return true;
  }

  /**
   * 替换播放队列中的指定条目（非当前播放歌曲的换源，不打断播放）
   * 返回是否命中队列
   */
  replaceInQueue(oldItem: MusicItem, newItem: MusicItem): boolean {
    const idx = this.getMusicIndexInPlayList(oldItem);
    if (idx === -1) {
      return false;
    }
    const newPlayList = this.playListItems.slice();
    newPlayList[idx] = newItem;
    this.setPlayList(newPlayList);
    return true;
  }

  /**
   * 搜索其它插件上的同一首歌（每个插件取最优匹配），供手动换源选择
   * 并发搜索所有插件（单个插件超时 6s），总耗时约等于最慢的一个插件
   */
  async searchAlternateSources(musicItem: MusicItem): Promise<Array<MusicItem>> {
    const keyword = musicItem.alias.length > 0 ? musicItem.alias : musicItem.title;
    const plugins = pluginManager.getSearchablePlugins(SupportMediaType.Music);
    const tasks: Array<Promise<MusicItem | null>> = [];
    for (const plugin of plugins) {
      if (plugin.name === musicItem.platform) {
        continue;
      }
      tasks.push(TrackPlayer.searchBestFromPlugin(plugin, keyword, musicItem));
    }
    const results = await Promise.all(tasks);
    const candidates: Array<MusicItem> = [];
    for (const item of results) {
      if (item !== null) {
        candidates.push(item);
      }
    }
    return candidates;
  }

  /** 单插件搜索同一首歌并取最优匹配（超时/失败返回 null） */
  private static async searchBestFromPlugin(
    plugin: Plugin,
    keyword: string,
    musicItem: MusicItem
  ): Promise<MusicItem | null> {
    const searchTask: Promise<SearchResult | null> =
      plugin.methods.search(keyword, 1, SupportMediaType.Music)
        .catch((_e: Object): SearchResult | null => null);
    const timeoutTask: Promise<SearchResult | null> =
      new Promise<SearchResult | null>((resolve: (v: SearchResult | null) => void) => {
        setTimeout((): void => resolve(null), 6000);
      });
    const racers: Array<Promise<SearchResult | null>> = [searchTask, timeoutTask];
    const results = await Promise.race(racers);
    if (results === null) {
      return null;
    }
    let best: MusicItem | null = null;
    let bestDistance = Number.POSITIVE_INFINITY;
    for (const item of results.musicData.slice(0, 2)) {
      if (item.title === keyword && item.artist === musicItem.artist) {
        best = item;
        break;
      }
      const dist = MinDistance.compute(keyword, item.title) +
        MinDistance.compute(item.artist, musicItem.artist);
      if (dist < bestDistance) {
        bestDistance = dist;
        best = item;
      }
    }
    return best;
  }

  seekTo(progress: number): void {
    PersistStatus.setProgress(progress);
    playerEngine.seek(progress);
  }

  getProgress(): ProgressInfo {
    const info = new ProgressInfo();
    info.position = playerEngine.position;
    info.duration = playerEngine.duration;
    return info;
  }

  getRate(): number {
    return playerEngine.currentRate;
  }

  setRate(rate: number): void {
    playerEngine.setRate(rate);
    PersistStatus.setRate(rate);
  }

  async reset(): Promise<void> {
    await playerEngine.stop();
    this.loadedMusic = null;
  }

  // ---------------- 内部状态 ----------------

  private setCurrentMusic(musicItem: MusicItem | null): void {
    if (musicItem === null) {
      this.currentIndex = -1;
      this.currentMusicItem = null;
      PersistStatus.setMusicItem(null);
      PersistStatus.setProgress(0);
      const ev = new CurrentMusicChangedEvent();
      ev.music = null;
      this.ee.emit('current-music-changed', ev);
      return;
    }
    this.currentIndex = this.getMusicIndexInPlayList(musicItem);
    this.currentMusicItem = musicItem;
    const ev = new CurrentMusicChangedEvent();
    ev.music = musicItem;
    this.ee.emit('current-music-changed', ev);
  }

  private setRepeatModeInternal(mode: MusicRepeatMode): void {
    const playList = this.playListItems;
    const prevMode = this.repeatModeValue;
    if ((prevMode === MusicRepeatMode.SHUFFLE && mode !== MusicRepeatMode.SHUFFLE) ||
      (mode === MusicRepeatMode.SHUFFLE && prevMode !== MusicRepeatMode.SHUFFLE)) {
      let newPlayList: Array<MusicItem>;
      if (mode === MusicRepeatMode.SHUFFLE) {
        newPlayList = TrackPlayer.shuffle(playList);
      } else {
        newPlayList = this.sortByTimestampAndIndex(playList, true);
      }
      this.setPlayList(newPlayList);
    }
    this.repeatModeValue = mode;
    PersistStatus.setRepeatMode(mode);
  }

  private setQualityInternal(quality: QualityKey): void {
    this.qualityValue = quality;
    PersistStatus.setQuality(quality);
  }

  /** 设置音源 */
  private async setTrackSource(track: MusicItem, autoPlay: boolean = true): Promise<void> {
    const headers = TrackPlayer.collectHeaders(track);
    this.loadedMusic = track.clone();
    await playerEngine.load(track.url, headers);
    PersistStatus.setMusicItem(track);
    PersistStatus.setProgress(0);
    if (autoPlay) {
      await playerEngine.play();
    }
  }

  private setPlayList(newPlayList: Array<MusicItem>, persist: boolean = true): void {
    this.playListItems = newPlayList;
    this.playListIndexMap = new MediaIndexMap(newPlayList);
    if (persist) {
      PersistStatus.setPlayList(newPlayList);
    }
    this.currentIndex = this.getMusicIndexInPlayList(this.currentMusicItem);
    this.ee.emit('play-list-changed', new PlayListChangedEvent());
  }

  // ---------------- 工具方法 ----------------

  private findIndexSameItem(items: Array<MusicItem>, target: MusicItem): number {
    for (let i = 0; i < items.length; ++i) {
      if (MediaUtils.isSameMediaItem(items[i], target)) {
        return i;
      }
    }
    return -1;
  }

  private shrinkPlayListToSize(queue: Array<MusicItem>, targetIndex: number): Array<MusicItem> {
    if (queue.length > MAX_PLAYLIST_SIZE) {
      if (targetIndex < TrackPlayer.HALF_MAX_PLAYLIST_SIZE) {
        return queue.slice(0, MAX_PLAYLIST_SIZE);
      }
      const right = Math.min(queue.length, targetIndex + TrackPlayer.HALF_MAX_PLAYLIST_SIZE);
      const left = Math.max(0, right - MAX_PLAYLIST_SIZE);
      return queue.slice(left, right);
    }
    return queue;
  }

  /** 合并音源：{...mediaItem, ...props, id, platform} */
  private mergeTrackSource(mediaItem: MusicItem, source: MediaSource): MusicItem {
    const merged = mediaItem.clone();
    merged.url = source.url;
    const extras: JsonRecord = {};
    for (const k of Object.keys(merged.extras)) {
      if (k !== 'headers' && k !== 'userAgent') {
        extras[k] = merged.extras[k];
      }
    }
    if (Object.keys(source.headers).length > 0) {
      const headersRec: JsonRecord = {};
      for (const k of Object.keys(source.headers)) {
        headersRec[k] = source.headers[k];
      }
      extras['headers'] = headersRec;
    }
    if (source.userAgent.length > 0) {
      extras['userAgent'] = source.userAgent;
    }
    merged.extras = extras;
    return merged;
  }

  /** 合并补充信息 */
  private mergeTrackInfo(track: MusicItem, info: JsonRecord): MusicItem {
    const baseRec = track.toPersistRecord();
    const mergedRec: JsonRecord = {};
    for (const k of Object.keys(baseRec)) {
      mergedRec[k] = baseRec[k];
    }
    for (const k of Object.keys(info)) {
      if (k === 'id' || k === 'platform') {
        continue;
      }
      const v = info[k];
      // null/undefined/空字符串不覆盖已有非空字符串值（如插件对本地文件返回空 artwork/artist，避免清空已有封面）
      if (v === null || v === undefined || (typeof v === 'string' && v.length === 0)) {
        const baseVal = baseRec[k];
        if (typeof baseVal === 'string' && baseVal.length > 0) {
          continue;
        }
      }
      mergedRec[k] = v;
    }
    return MusicItem.fromRecord(mergedRec);
  }

  private sortByTimestampAndIndex(array: Array<MusicItem>, newArray: boolean): Array<MusicItem> {
    const arr = newArray ? array.slice() : array;
    arr.sort((a: MusicItem, b: MusicItem) => {
      const ts = a.timeStamp - b.timeStamp;
      if (ts !== 0) {
        return ts;
      }
      return a.sortIndex - b.sortIndex;
    });
    return arr;
  }

  private static musicIsPaused(state: PlayState): boolean {
    return state !== PlayState.Playing;
  }

  private static shuffle(items: Array<MusicItem>): Array<MusicItem> {
    const arr = items.slice();
    for (let i = arr.length - 1; i > 0; --i) {
      const j = Math.floor(Math.random() * (i + 1));
      const tmp = arr[i];
      arr[i] = arr[j];
      arr[j] = tmp;
    }
    return arr;
  }

  /** 从 track extras 中收集播放请求头 */
  private static collectHeaders(track: MusicItem): Record<string, string> {
    const headers: Record<string, string> = {};
    const headersRec = JsonUtil.objToRecord(track.extras['headers']);
    if (headersRec !== null) {
      for (const k of Object.keys(headersRec)) {
        const v = headersRec[k];
        if (typeof v === 'string' && v.length > 0) {
          headers[k] = v;
        }
      }
    }
    const ua = track.extras['userAgent'];
    if (typeof ua === 'string' && ua.length > 0) {
      let hasUa = false;
      for (const k of Object.keys(headers)) {
        if (k.toLowerCase() === 'user-agent') {
          hasUa = true;
          break;
        }
      }
      if (!hasUa) {
        headers['User-Agent'] = ua;
      }
    }
    return headers;
  }

  private async handlePlayFail(): Promise<void> {
    if (this.handlingPlayFail) {
      return;
    }
    if (!appConfig.getAutoStopWhenError()) {
      this.handlingPlayFail = true;
      await Delay.wait(500);
      this.handlingPlayFail = false;
      await this.skipToNext();
    }
  }

  /** 播放失败时搜索相似歌曲换源 */
  private async getSimilarMusic(musicItem: MusicItem): Promise<MusicItem | null> {
    const keyword = musicItem.alias.length > 0 ? musicItem.alias : musicItem.title;
    const plugins = pluginManager.getSearchablePlugins(SupportMediaType.Music);

    let distance = Number.POSITIVE_INFINITY;
    let minDistanceMusicItem: MusicItem | null = null;

    const startTime = Date.now();
    for (const plugin of plugins) {
      // 超时：8s
      if (Date.now() - startTime > 8000) {
        break;
      }
      if (plugin.name === musicItem.platform) {
        continue;
      }
      let results: SearchResult | null = null;
      try {
        results = await plugin.methods.search(keyword, 1, SupportMediaType.Music);
      } catch (e) {
        results = null;
      }
      const firstTwo: Array<MusicItem> = results !== null ? results.musicData.slice(0, 2) : [];
      for (const item of firstTwo) {
        if (item.title === keyword && item.artist === musicItem.artist) {
          distance = 0;
          minDistanceMusicItem = item;
          break;
        } else {
          const dist = MinDistance.compute(keyword, musicItem.title) +
            MinDistance.compute(item.artist, musicItem.artist);
          if (dist < distance) {
            distance = dist;
            minDistanceMusicItem = item;
          }
        }
      }
      if (distance === 0) {
        break;
      }
    }
    return minDistanceMusicItem;
  }

  // ---------------- 事件订阅 ----------------

  onPlayEnd(cb: () => void): void {
    const wrapper: EventListenerFn = (_payload?: Object) => {
      cb();
    };
    this.ee.on('play-end', wrapper);
  }

  onCurrentMusicChanged(cb: (music: MusicItem | null) => void): () => void {
    const wrapper: EventListenerFn = (payload?: Object) => {
      if (payload instanceof CurrentMusicChangedEvent) {
        cb(payload.music);
      }
    };
    this.ee.on('current-music-changed', wrapper);
    return (): void => {
      this.ee.off('current-music-changed', wrapper);
    };
  }

  onProgressChanged(cb: (position: number, duration: number) => void): () => void {
    const wrapper: EventListenerFn = (payload?: Object) => {
      if (payload instanceof ProgressChangedEvent) {
        cb(payload.position, payload.duration);
      }
    };
    this.ee.on('progress-changed', wrapper);
    return (): void => {
      this.ee.off('progress-changed', wrapper);
    };
  }

  onPlayStateChanged(cb: (state: PlayState) => void): () => void {
    const wrapper: EventListenerFn = (payload?: Object) => {
      if (payload instanceof PlayStateChangedEvent) {
        cb(payload.state);
      }
    };
    this.ee.on('play-state-changed', wrapper);
    return (): void => {
      this.ee.off('play-state-changed', wrapper);
    };
  }

  onPlayListChanged(cb: () => void): () => void {
    const wrapper: EventListenerFn = (_payload?: Object) => {
      cb();
    };
    this.ee.on('play-list-changed', wrapper);
    return (): void => {
      this.ee.off('play-list-changed', wrapper);
    };
  }

  onCellularForbidden(cb: () => void): void {
    const wrapper: EventListenerFn = (_payload?: Object) => {
      cb();
    };
    this.ee.on('cellular-forbidden', wrapper);
  }
}

export const trackPlayer = new TrackPlayer();
