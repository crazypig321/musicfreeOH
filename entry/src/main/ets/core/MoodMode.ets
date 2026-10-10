import { MusicItem } from '../common/model/MediaTypes';
import { MediaUtils } from '../utils/MediaUtils';
import { MinDistance } from '../utils/MinDistance';
import { SupportMediaType, SearchResult, ArtistItem } from '../common/model/SheetTypes';
import { Plugin } from '../plugin/Plugin';
import { pluginManager } from '../plugin/PluginManager';
import { musicHistory } from './MusicHistory';
import { musicSheet } from './MusicSheet';
import { localMusicSheet, downloadedSheet } from './LocalMusicSheet';
import { trackPlayer } from './TrackPlayer';
import { ContextHolder } from '../common/ContextHolder';
import { showUiToast } from '../utils/UiUtils';
import { Log } from '../utils/Log';

// ---------- 常量 ----------
const MOOD_MIN_HISTORY = 3;          // 发起心动模式所需的最少历史条数
const MOOD_SEED_COUNT = 30;          // 参与偏好加权的最近历史条数
const MOOD_RECENT_EXCLUDE = 20;      // 本地匹配时排除的最近已听条数
const MOOD_LOCAL_MAX = 40;           // 本地匹配结果上限
const MOOD_PER_ARTIST_CAP = 3;       // 单位歌手在本地结果中的最大贡献数（保证多样性）
const MOOD_ONLINE_ARTISTS = 3;       // 在线扩展的歌手数量上限
const MOOD_ONLINE_PER_ARTIST = 10;   // 每位歌手在线拉取的作品数上限
const MOOD_SEED_WEIGHT = 2;          // 指定种子歌曲的权重（高于任何历史条目的 1/(i+1)）
const MOOD_CALL_TIMEOUT = 4000;      // 单次插件调用超时（搜索歌手/拉取作品各一次）
const ARTIST_SPLIT_PATTERN = '[/&、,，;；]';

/** 偏好特征表（权重均为「历史位置衰减 × 播放次数」的累加） */
class MoodFeatures {
  /** 歌手权重（键为小写归一化歌手名） */
  artistWeights: Map<string, number> = new Map<string, number>();
  /** 小写歌手名 → 原始歌手名（在线搜索需用原始名） */
  artistNameByLower: Map<string, string> = new Map<string, string>();
  albumWeights: Map<string, number> = new Map<string, number>();
  platformWeights: Map<string, number> = new Map<string, number>();
}

/** 本地匹配候选（带得分） */
class MoodCandidate {
  item: MusicItem;
  score: number;

  constructor(item: MusicItem, score: number) {
    this.item = item;
    this.score = score;
  }
}

/** 歌手 → 解析插件的配对（在线扩展用） */
class ArtistPluginPair {
  artistName: string;
  plugin: Plugin;

  constructor(artistName: string, plugin: Plugin) {
    this.artistName = artistName;
    this.plugin = plugin;
  }
}

/**
 * 心动模式：基于最近播放的偏好特征，从本地语料（歌单/收藏/本地/已下载）
 * 匹配相似风格歌曲立即开播，再异步通过插件拉取常听歌手作品补充进队列。
 * （"风格相似"为启发式：歌手 > 专辑 > 平台 > 历史权重；项目无 genre 元数据）
 */
@ObservedV2
export class MoodMode {
  /** 心动模式激活中（播放页封面据此叠加心形动画） */
  @Trace isActive: boolean = false;
  /** 本次心动歌单的唯一键集合（队列被整体替换为非心动歌单时退出激活态） */
  private moodKeys: Set<string> = new Set<string>();

  constructor() {
    // 队列变更时检查心动歌单是否还在（换队列/清空队列 → 退出激活态）
    trackPlayer.onPlayListChanged((): void => {
      if (!this.isActive) {
        return;
      }
      let stillMood = false;
      for (const it of trackPlayer.playList) {
        if (this.moodKeys.has(MediaUtils.getMediaUniqueKey(it))) {
          stillMood = true;
          break;
        }
      }
      if (!stillMood) {
        this.isActive = false;
      }
    });
  }

  /** 首页入口：纯历史种子生成心动歌单并播放 */
  async startFromHistory(): Promise<void> {
    const history = musicHistory.history;
    if (history.length < MOOD_MIN_HISTORY) {
      this.toast('最近播放太少，先去听几首歌吧');
      return;
    }
    await this.startInternal(history, null);
  }

  /** 歌曲操作菜单入口：以指定歌曲为种子、历史为偏好背景生成并播放 */
  async startFromSong(seed: MusicItem): Promise<void> {
    const history = musicHistory.history;
    const seeds = history.length >= MOOD_MIN_HISTORY ? history : [];
    await this.startInternal(seeds, seed);
  }

  /** 生成流程：特征提取 → 本地匹配秒开播 → 在线扩展异步补充 */
  private async startInternal(history: Array<MusicItem>, seed: MusicItem | null): Promise<void> {
    const recent = history.slice(0, MOOD_SEED_COUNT);
    const features = this.buildFeatures(recent, seed);
    // 平台解析语料：种子 + 历史（种子歌曲的平台也参与在线扩展）
    const contextItems = seed !== null ? [seed].concat(recent) : recent;

    // 排除集：最近已听 + 种子本身（避免推荐刚听过的歌）
    const excludeKeys = new Set<string>();
    for (const it of history.slice(0, MOOD_RECENT_EXCLUDE)) {
      excludeKeys.add(MediaUtils.getMediaUniqueKey(it));
    }
    if (seed !== null) {
      excludeKeys.add(MediaUtils.getMediaUniqueKey(seed));
    }

    // 本地匹配（瞬时）
    const localMatched = this.matchLocal(features, excludeKeys);
    const initial: Array<MusicItem> = seed !== null ? [seed].concat(localMatched) : localMatched;

    if (initial.length > 0) {
      // 立即开播，随后在线补充
      this.beginMoodSession(initial);
      trackPlayer.playWithReplacePlayList(initial[0], initial.slice()).catch((_e: Object): void => {
        this.toast('播放失败');
      });
      this.toast('心动模式：已生成 ' + initial.length.toString() + ' 首开始播放');
      await this.enrichOnline(features, contextItems, excludeKeys, initial);
      return;
    }

    // 本地无可匹配：等待在线结果直接开播
    this.toast('正在生成心动歌单…');
    const online = await this.expandOnline(features, contextItems, excludeKeys);
    if (online.length === 0) {
      this.toast('心动模式：没有找到足够的相似歌曲');
      return;
    }
    this.beginMoodSession(online);
    trackPlayer.playWithReplacePlayList(online[0], online.slice()).catch((_e: Object): void => {
      this.toast('播放失败');
    });
    this.toast('心动模式：已生成 ' + online.length.toString() + ' 首开始播放');
  }

  /** 记录本次心动歌单并进入激活态（队列仍含心动条目期间保持激活） */
  private beginMoodSession(items: Array<MusicItem>): void {
    this.moodKeys = new Set<string>();
    for (const it of items) {
      this.moodKeys.add(MediaUtils.getMediaUniqueKey(it));
    }
    this.isActive = true;
  }

  /** 在线扩展并静默补充进当前队列（用户已切走队列时放弃） */
  private async enrichOnline(features: MoodFeatures, contextItems: Array<MusicItem>,
    excludeKeys: Set<string>, initial: Array<MusicItem>): Promise<void> {
    const online = await this.expandOnline(features, contextItems, excludeKeys);
    if (online.length === 0) {
      return;
    }
    // 去重：初始列表 + 当前播放队列
    const initialKeys = new Set<string>();
    const seen = new Set<string>();
    for (const it of initial) {
      const key = MediaUtils.getMediaUniqueKey(it);
      initialKeys.add(key);
      seen.add(key);
    }
    for (const it of trackPlayer.playList) {
      seen.add(MediaUtils.getMediaUniqueKey(it));
    }
    const extra: Array<MusicItem> = [];
    for (const it of online) {
      const key = MediaUtils.getMediaUniqueKey(it);
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      extra.push(it);
    }
    if (extra.length === 0) {
      return;
    }
    // 防串台：用户已手动切到其它队列（当前队列不含任何心动条目）时放弃追加
    let stillMoodQueue = false;
    for (const it of trackPlayer.playList) {
      if (initialKeys.has(MediaUtils.getMediaUniqueKey(it))) {
        stillMoodQueue = true;
        break;
      }
    }
    if (!stillMoodQueue) {
      return;
    }
    // 补充条目同样计入心动歌单（用户在队列中删歌后仍能识别心动队列）
    for (const it of extra) {
      this.moodKeys.add(MediaUtils.getMediaUniqueKey(it));
    }
    trackPlayer.addAll(extra);
    this.toast('已补充 ' + extra.length.toString() + ' 首线上候选');
  }

  // ==================== 特征提取 ====================

  /** 构建偏好特征表：历史按位置 1/(i+1) 衰减 × log2(1+播放次数)，种子权重置顶 */
  private buildFeatures(recent: Array<MusicItem>, seed: MusicItem | null): MoodFeatures {
    const features = new MoodFeatures();
    if (seed !== null) {
      this.accumulateFeatures(features, seed, MOOD_SEED_WEIGHT);
    }
    for (let i = 0; i < recent.length; i++) {
      const item = recent[i];
      let weight = 1 / (i + 1);
      const stat = musicHistory.getStat(item);
      if (stat !== null && stat.count > 0) {
        weight *= Math.log2(1 + stat.count);
      }
      this.accumulateFeatures(features, item, weight);
    }
    return features;
  }

  private accumulateFeatures(features: MoodFeatures, item: MusicItem, weight: number): void {
    if (weight <= 0) {
      return;
    }
    for (const artist of MoodMode.splitArtists(item.artist)) {
      features.artistWeights.set(artist, (features.artistWeights.get(artist) ?? 0) + weight);
      if (!features.artistNameByLower.has(artist)) {
        features.artistNameByLower.set(artist, item.artist);
      }
    }
    if (item.album.length > 0) {
      features.albumWeights.set(item.album, (features.albumWeights.get(item.album) ?? 0) + weight);
    }
    if (item.platform.length > 0) {
      features.platformWeights.set(item.platform,
        (features.platformWeights.get(item.platform) ?? 0) + weight);
    }
  }

  /** 拆分多歌手字符串（"A/B"、"A、B"、"A&B"），返回小写归一化名列表 */
  private static splitArtists(artist: string): Array<string> {
    const result: Array<string> = [];
    if (artist.length === 0) {
      return result;
    }
    const parts = artist.split(new RegExp(ARTIST_SPLIT_PATTERN));
    for (const part of parts) {
      const trimmed = part.trim().toLowerCase();
      if (trimmed.length > 0) {
        result.push(trimmed);
      }
    }
    return result;
  }

  // ==================== 本地匹配 ====================

  /** 汇集本地语料：收藏 + 全部用户歌单 + 本地音乐 + 已下载（按唯一键去重） */
  private collectLocalCorpus(): Array<MusicItem> {
    const result: Array<MusicItem> = [];
    const seen = new Set<string>();
    const push = (items: Array<MusicItem>): void => {
      for (const it of items) {
        const key = MediaUtils.getMediaUniqueKey(it);
        if (seen.has(key)) {
          continue;
        }
        seen.add(key);
        result.push(it);
      }
    };
    push(musicSheet.getMusicList(musicSheet.defaultSheet.id));
    for (const sheet of musicSheet.sheets) {
      push(musicSheet.getMusicList(sheet.id));
    }
    push(localMusicSheet.getMusicList());
    push(downloadedSheet.getMusicList());
    return result;
  }

  /** 本地匹配打分：3×歌手权重 + 2×专辑权重 + 0.5×平台权重；按分降序、单歌手限量 */
  private matchLocal(features: MoodFeatures, excludeKeys: Set<string>): Array<MusicItem> {
    const corpus = this.collectLocalCorpus();
    const candidates: Array<MoodCandidate> = [];
    for (const item of corpus) {
      if (excludeKeys.has(MediaUtils.getMediaUniqueKey(item))) {
        continue;
      }
      const score = this.scoreItem(item, features);
      if (score <= 0) {
        continue;
      }
      candidates.push(new MoodCandidate(item, score));
    }
    candidates.sort((a: MoodCandidate, b: MoodCandidate): number => b.score - a.score);

    const result: Array<MusicItem> = [];
    const primaryArtistCount: Map<string, number> = new Map<string, number>();
    for (const candidate of candidates) {
      // 多样性：主歌手（第一个拆分名）贡献达到上限后跳过
      const primaryArtists = MoodMode.splitArtists(candidate.item.artist);
      const primary = primaryArtists.length > 0 ? primaryArtists[0] : '';
      if (primary.length > 0) {
        const count = primaryArtistCount.get(primary) ?? 0;
        if (count >= MOOD_PER_ARTIST_CAP) {
          continue;
        }
        primaryArtistCount.set(primary, count + 1);
      }
      result.push(candidate.item);
      if (result.length >= MOOD_LOCAL_MAX) {
        break;
      }
    }
    return result;
  }

  private scoreItem(item: MusicItem, features: MoodFeatures): number {
    let score = 0;
    for (const artist of MoodMode.splitArtists(item.artist)) {
      score += 3 * (features.artistWeights.get(artist) ?? 0);
    }
    if (item.album.length > 0) {
      score += 2 * (features.albumWeights.get(item.album) ?? 0);
    }
    if (item.platform.length > 0) {
      score += 0.5 * (features.platformWeights.get(item.platform) ?? 0);
    }
    return score;
  }

  // ==================== 在线扩展 ====================

  /** 并发拉取权重 Top 歌手的作品（失败/超时静默降级） */
  private async expandOnline(features: MoodFeatures, contextItems: Array<MusicItem>,
    excludeKeys: Set<string>): Promise<Array<MusicItem>> {
    const pairs = this.resolveArtistPlugins(features, contextItems);
    if (pairs.length === 0) {
      return [];
    }
    const tasks: Array<Promise<Array<MusicItem>>> = [];
    for (const pair of pairs) {
      tasks.push(this.fetchArtistSongs(pair, excludeKeys));
    }
    const results = await Promise.all(tasks);
    const seen = new Set<string>();
    for (const key of excludeKeys) {
      seen.add(key);
    }
    const merged: Array<MusicItem> = [];
    for (const list of results) {
      for (const item of list) {
        const key = MediaUtils.getMediaUniqueKey(item);
        if (seen.has(key)) {
          continue;
        }
        seen.add(key);
        merged.push(item);
      }
    }
    return merged;
  }

  /** 解析权重 Top 歌手与其来源插件（需插件支持歌手搜索 + getArtistWorks） */
  private resolveArtistPlugins(features: MoodFeatures,
    contextItems: Array<MusicItem>): Array<ArtistPluginPair> {
    // 歌手权重降序
    const sortedArtists: Array<string> = [];
    for (const artist of features.artistWeights.keys()) {
      sortedArtists.push(artist);
    }
    sortedArtists.sort((a: string, b: string): number =>
      (features.artistWeights.get(b) ?? 0) - (features.artistWeights.get(a) ?? 0));

    // 歌手 → 出现过的平台（按历史顺序）
    const platformsByArtist: Map<string, Array<string>> = new Map<string, Array<string>>();
    for (const item of contextItems) {
      for (const artist of MoodMode.splitArtists(item.artist)) {
        let platforms = platformsByArtist.get(artist);
        if (platforms === undefined) {
          platforms = [];
          platformsByArtist.set(artist, platforms);
        }
        if (platforms.indexOf(item.platform) === -1) {
          platforms.push(item.platform);
        }
      }
    }

    const searchable = pluginManager.getSearchablePlugins(SupportMediaType.Artist);
    const result: Array<ArtistPluginPair> = [];
    for (const artistLower of sortedArtists) {
      if (result.length >= MOOD_ONLINE_ARTISTS) {
        break;
      }
      const platforms = platformsByArtist.get(artistLower) ?? [];
      for (const platform of platforms) {
        let plugin: Plugin | null = null;
        for (const candidate of searchable) {
          if (candidate.name === platform) {
            plugin = candidate;
            break;
          }
        }
        if (plugin === null) {
          continue;
        }
        if (!plugin.hasMethod('getArtistWorks')) {
          continue;
        }
        const artistName = features.artistNameByLower.get(artistLower) ?? artistLower;
        result.push(new ArtistPluginPair(artistName, plugin));
        break;
      }
    }
    return result;
  }

  /** 拉取单个歌手的作品：搜索歌手解析 id → getArtistWorks 取音乐列表 */
  private async fetchArtistSongs(pair: ArtistPluginPair,
    excludeKeys: Set<string>): Promise<Array<MusicItem>> {
    try {
      // 1. 搜索歌手解析 id（取前 3 个候选按编辑距离选最优）
      const searchTask = pair.plugin.methods.search(pair.artistName, 1, SupportMediaType.Artist);
      const searchResult =
        await MoodMode.withTimeout<SearchResult>(searchTask, MOOD_CALL_TIMEOUT);
      if (searchResult === null) {
        return [];
      }
      let best: ArtistItem | null = null;
      let bestDistance = Number.POSITIVE_INFINITY;
      for (const artist of searchResult.artistData.slice(0, 3)) {
        if (artist.name === pair.artistName) {
          best = artist;
          break;
        }
        const distance = MinDistance.compute(pair.artistName, artist.name);
        if (distance < bestDistance) {
          bestDistance = distance;
          best = artist;
        }
      }
      if (best === null) {
        return [];
      }
      // 2. 拉取该歌手的音乐作品
      const worksTask = pair.plugin.methods.getArtistWorks(best, 1, SupportMediaType.Music);
      const works = await MoodMode.withTimeout<SearchResult>(worksTask, MOOD_CALL_TIMEOUT);
      if (works === null) {
        return [];
      }
      const result: Array<MusicItem> = [];
      for (const item of works.musicData) {
        if (item.title.length === 0) {
          continue;
        }
        if (excludeKeys.has(MediaUtils.getMediaUniqueKey(item))) {
          continue;
        }
        result.push(item);
        if (result.length >= MOOD_ONLINE_PER_ARTIST) {
          break;
        }
      }
      return result;
    } catch (e) {
      Log.error('心动模式：拉取歌手作品失败 - ' + pair.artistName);
      return [];
    }
  }

  /** 带超时的 Promise 包装（超时/失败返回 null） */
  private static async withTimeout<T>(task: Promise<T>, ms: number): Promise<T | null> {
    const safeTask: Promise<T | null> = task
      .then((v: T): T | null => v)
      .catch((_e: Object): T | null => null);
    const timeoutTask: Promise<T | null> = new Promise<T | null>(
      (resolve: (v: T | null) => void) => {
        setTimeout((): void => resolve(null), ms);
      });
    const racers: Array<Promise<T | null>> = [safeTask, timeoutTask];
    return Promise.race(racers);
  }

  /** 全局 Toast（UI 上下文不可用时静默） */
  private toast(message: string): void {
    try {
      showUiToast(ContextHolder.getUiContext(), message);
    } catch (e) {
      // UI 上下文未初始化（如 headless 模式）时忽略
    }
  }
}

export const moodMode = new MoodMode();
