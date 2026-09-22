import { EventEmitter, EventListenerFn } from '../common/EventBus';
import { PathConst } from '../common/PathConst';
import { JsonRecord } from '../common/JsonUtil';
import { MusicItem, LyricSource } from '../common/model/MediaTypes';
import { SupportMediaType, SearchResult } from '../common/model/SheetTypes';
import { LyricParser, ParsedLrcItem } from '../utils/LyricParser';
import { MediaUtils } from '../utils/MediaUtils';
import { FileUtils } from '../utils/FileUtils';
import { CryptoUtil } from '../utils/CryptoUtil';
import { MinDistance } from '../utils/MinDistance';
import { Log } from '../utils/Log';
import { appConfig } from './AppConfig';
import { MediaExtra, MediaExtraProperties } from './MediaExtra';
import { trackPlayer } from './TrackPlayer';
import { pluginManager } from '../plugin/PluginManager';
import { Plugin } from '../plugin/Plugin';

/** 歌词状态 */
export class LyricState {
  loading: boolean = true;
  lyrics: Array<ParsedLrcItem> = [];
  hasTranslation: boolean = false;
  meta: JsonRecord = {};
  /** 歌词原文（复制/编辑歌词用） */
  rawLrc: string = '';
}

/** 歌词状态变化事件 */
export class LyricStateChangedEvent {
  state: LyricState = new LyricState();
}

/** 当前歌词项变化事件 */
export class CurrentLyricChangedEvent {
  item: ParsedLrcItem | null = null;
}

/**
 * 歌词管理（移植自 core/lyricManager.ts）
 * RN 的状态栏歌词（LyricUtil）在鸿蒙无对应能力，整体省略
 */
export class LyricManager {
  private ee: EventEmitter = new EventEmitter();
  private lyricParser: LyricParser | null = null;
  private lyricStateInternal: LyricState = new LyricState();
  private currentLyricItemInternal: ParsedLrcItem | null = null;
  private setupDone: boolean = false;

  get lyricState(): LyricState {
    return this.lyricStateInternal;
  }

  get currentLyricItem(): ParsedLrcItem | null {
    return this.currentLyricItemInternal;
  }

  /** 当前歌词时间偏移（秒） */
  get offset(): number {
    return this.lyricParser !== null ? this.lyricParser.offset : 0;
  }

  setup(): void {
    if (this.setupDone) {
      return;
    }
    this.setupDone = true;

    trackPlayer.onCurrentMusicChanged((_music: MusicItem | null) => {
      this.refreshLyric(true, true);
    });

    trackPlayer.onProgressChanged((position: number, _duration: number) => {
      const parser = this.lyricParser;
      if (parser === null || !trackPlayer.isCurrentMusic(parser.musicItem)) {
        return;
      }
      const newLyricItem = parser.getPosition(position);
      const current = this.currentLyricItemInternal;
      if (current === null) {
        if (newLyricItem !== null) {
          this.setCurrentLyric(newLyricItem);
        }
      } else {
        if (newLyricItem === null || current.lrc !== newLyricItem.lrc) {
          this.setCurrentLyric(newLyricItem);
        }
      }
    });

    this.refreshLyric(true);
  }

  /** 关联歌词 */
  associateLyric(musicItem: MusicItem, linkToMusicItem: MusicItem): boolean {
    if (musicItem.platform.length === 0 || linkToMusicItem.platform.length === 0) {
      return false;
    }

    if (MediaUtils.isSameMediaItem(musicItem, linkToMusicItem)) {
      MediaExtra.removeMediaExtraProperty(musicItem, 'associatedLrc');
      return false;
    }
    const patch = new MediaExtraProperties();
    patch.associatedLrc = linkToMusicItem.toPersistRecord();
    MediaExtra.patchMediaExtra(musicItem, patch);
    if (trackPlayer.isCurrentMusic(musicItem)) {
      this.refreshLyric(false, false);
    }
    return true;
  }

  /** 取消关联歌词 */
  unassociateLyric(musicItem: MusicItem): void {
    if (musicItem.platform.length === 0) {
      return;
    }
    MediaExtra.removeMediaExtraProperty(musicItem, 'associatedLrc');
    if (trackPlayer.isCurrentMusic(musicItem)) {
      this.refreshLyric(false, false);
    }
  }

  /** 上传本地歌词（raw / translation） */
  async uploadLocalLyric(musicItem: MusicItem, lyricContent: string, type: string = 'raw'): Promise<void> {
    if (musicItem.platform.length === 0) {
      return;
    }
    const platformHash = await CryptoUtil.md5(musicItem.platform);
    const idHash = await CryptoUtil.md5(musicItem.id);

    FileUtils.checkAndCreateDir(PathConst.localLrcPath + platformHash);
    FileUtils.writeFileText(PathConst.localLrcPath + platformHash + '/' + idHash +
      (type === 'raw' ? '' : '.tran') + '.lrc', lyricContent);

    if (trackPlayer.isCurrentMusic(musicItem)) {
      this.refreshLyric(false, false);
    }
  }

  /** 移除本地歌词 */
  async removeLocalLyric(musicItem: MusicItem): Promise<void> {
    if (musicItem.platform.length === 0) {
      return;
    }
    const platformHash = await CryptoUtil.md5(musicItem.platform);
    const idHash = await CryptoUtil.md5(musicItem.id);

    const basePath = PathConst.localLrcPath + platformHash + '/' + idHash;
    FileUtils.unlink(basePath + '.lrc');
    FileUtils.unlink(basePath + '.tran.lrc');

    if (trackPlayer.isCurrentMusic(musicItem)) {
      this.refreshLyric(false, false);
    }
  }

  /** 更新歌词偏移 */
  updateLyricOffset(musicItem: MusicItem, offset: number): void {
    if (musicItem.platform.length === 0) {
      return;
    }
    const patch = new MediaExtraProperties();
    patch.lyricOffset = offset;
    MediaExtra.patchMediaExtra(musicItem, patch);

    if (trackPlayer.isCurrentMusic(musicItem)) {
      this.refreshLyric(true, false);
    }
  }

  /** 强制重新加载当前歌曲歌词（搜索歌词/编辑歌词/偏移调整后调用） */
  reloadLyric(): void {
    this.refreshLyric(false, false);
  }

  private setLyricState(state: LyricState): void {
    this.lyricStateInternal = state;
    const ev = new LyricStateChangedEvent();
    ev.state = state;
    this.ee.emit('lyric-state-changed', ev);
  }

  private setCurrentLyric(item: ParsedLrcItem | null): void {
    this.currentLyricItemInternal = item;
    const ev = new CurrentLyricChangedEvent();
    ev.item = item;
    this.ee.emit('current-lyric-changed', ev);
  }

  private setLyricAsLoadingState(): void {
    const state = new LyricState();
    state.loading = true;
    this.setLyricState(state);
    this.setCurrentLyric(null);
  }

  private setLyricAsNoLyricState(): void {
    const state = new LyricState();
    state.loading = false;
    this.setLyricState(state);
    this.setCurrentLyric(null);
  }

  private async refreshLyric(skipFetchLyricSourceIfSame: boolean = true, ignoreProgress: boolean = false): Promise<void> {
    const currentMusicItem = trackPlayer.currentMusic;

    if (currentMusicItem === null) {
      this.setLyricAsNoLyricState();
      return;
    }

    try {
      let lrcSource: LyricSource | null = null;

      if (skipFetchLyricSourceIfSame && this.lyricParser !== null &&
        trackPlayer.isCurrentMusic(this.lyricParser.musicItem)) {
        lrcSource = this.lyricParser.lyricSource;
      } else {
        this.setLyricAsLoadingState();
        const plugin = pluginManager.getByMedia(currentMusicItem);
        if (plugin !== null) {
          lrcSource = await plugin.methods.getLyric(currentMusicItem);
        }
      }

      if (!trackPlayer.isCurrentMusic(currentMusicItem)) {
        return;
      }

      if (lrcSource === null && appConfig.getLyricAutoSearchLyric()) {
        this.setLyricAsLoadingState();
        lrcSource = await this.searchSimilarLyric(currentMusicItem);
      }

      if (!trackPlayer.isCurrentMusic(currentMusicItem)) {
        return;
      }

      if (lrcSource === null) {
        this.setLyricAsNoLyricState();
        this.lyricParser = null;
        return;
      }

      const optionsExtra: Record<string, number> = {};
      const lyricOffsetProp = MediaExtra.getMediaExtraProperty(currentMusicItem, 'lyricOffset');
      optionsExtra['offset'] = (typeof lyricOffsetProp === 'number' ? lyricOffsetProp : 0) * -1;

      this.lyricParser = new LyricParser(lrcSource.rawLrc, {
        musicItem: currentMusicItem,
        lyricSource: lrcSource,
        translation: lrcSource.translation,
        extra: optionsExtra,
      });

      const state = new LyricState();
      state.loading = false;
      state.lyrics = this.lyricParser.getLyricItems();
      state.hasTranslation = lrcSource.translation.length > 0;
      state.meta = this.lyricParser.getMeta();
      state.rawLrc = lrcSource.rawLrc;
      this.setLyricState(state);

      const items = this.lyricParser.getLyricItems();
      const currentLyric = ignoreProgress
        ? (items.length > 0 ? items[0] : null)
        : this.lyricParser.getPosition(trackPlayer.getProgress().position);
      this.setCurrentLyric(currentLyric);
    } catch (err) {
      if (trackPlayer.isCurrentMusic(currentMusicItem)) {
        this.lyricParser = null;
        this.setLyricAsNoLyricState();
      }
      Log.warn('歌词加载失败');
    }
  }

  /** 检索最接近的歌词 */
  private async searchSimilarLyric(musicItem: MusicItem): Promise<LyricSource | null> {
    const keyword = musicItem.alias.length > 0 ? musicItem.alias : musicItem.title;
    const plugins = pluginManager.getSearchablePlugins(SupportMediaType.Lyric);

    let distance = Number.POSITIVE_INFINITY;
    let minDistanceMusicItem: MusicItem | null = null;
    let targetPlugin: Plugin | null = null;

    for (const plugin of plugins) {
      if (!trackPlayer.isCurrentMusic(musicItem)) {
        return null;
      }

      if (plugin.name === musicItem.platform) {
        continue;
      }

      let results: SearchResult | null = null;
      try {
        results = await plugin.methods.search(keyword, 1, SupportMediaType.Lyric);
      } catch (e) {
        results = null;
      }

      const firstTwo = results === null ? [] : results.lyricData.slice(0, 2);

      for (const item of firstTwo) {
        if (item.title === keyword && item.artist === musicItem.artist) {
          distance = 0;
          minDistanceMusicItem = item;
          targetPlugin = plugin;
          break;
        } else {
          const dist = MinDistance.compute(keyword, musicItem.title) +
            MinDistance.compute(item.artist, musicItem.artist);
          if (dist < distance) {
            distance = dist;
            minDistanceMusicItem = item;
            targetPlugin = plugin;
          }
        }
      }

      if (distance === 0) {
        break;
      }
    }

    if (minDistanceMusicItem !== null && targetPlugin !== null) {
      try {
        return await targetPlugin.methods.getLyric(minDistanceMusicItem);
      } catch (e) {
        return null;
      }
    }

    return null;
  }

  onLyricStateChanged(cb: (state: LyricState) => void): () => void {
    const wrapper: EventListenerFn = (payload?: Object) => {
      if (payload instanceof LyricStateChangedEvent) {
        cb(payload.state);
      }
    };
    this.ee.on('lyric-state-changed', wrapper);
    return (): void => {
      this.ee.off('lyric-state-changed', wrapper);
    };
  }

  onCurrentLyricChanged(cb: (item: ParsedLrcItem | null) => void): () => void {
    const wrapper: EventListenerFn = (payload?: Object) => {
      if (payload instanceof CurrentLyricChangedEvent) {
        cb(payload.item);
      }
    };
    this.ee.on('current-lyric-changed', wrapper);
    return (): void => {
      this.ee.off('current-lyric-changed', wrapper);
    };
  }
}

export const lyricManager = new LyricManager();
