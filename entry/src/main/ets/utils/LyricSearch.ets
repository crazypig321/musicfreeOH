import { MusicItem, LyricSource } from '../common/model/MediaTypes';
import { SearchResult, SupportMediaType } from '../common/model/SheetTypes';
import { Plugin } from '../plugin/Plugin';
import { pluginManager } from '../plugin/PluginManager';
import { MediaExtra, MediaExtraProperties } from '../core/MediaExtra';
import { MinDistance } from './MinDistance';


/**
 * 歌词音源搜索工具：按用户选定的插件（或「自动」）为歌曲搜索并匹配歌词
 */
export class LyricSearch {
  /** 「自动」音源：按原有逻辑遍历支持歌词搜索的插件自动匹配 */
  static readonly AUTO_SOURCE: string = '自动';

  /** 可作为歌词音源的插件（已启用、支持 getLyric，按用户配置顺序） */
  static lyricSourcePlugins(): Array<Plugin> {
    return pluginManager.getSortedPluginsWithAbility('getLyric');
  }

  /** 按弹窗选择的音源名搜索歌词：AUTO_SOURCE 走自动跨插件匹配，否则从指定插件匹配 */
  static async searchLyric(item: MusicItem, pluginName: string): Promise<LyricSource | null> {
    if (pluginName === LyricSearch.AUTO_SOURCE) {
      return LyricSearch.searchLyricAuto(item);
    }
    const plugin = pluginManager.getByName(pluginName);
    if (plugin === null) {
      return null;
    }
    return LyricSearch.searchLyricFromPlugin(item, plugin);
  }

  /** 自动匹配（原有逻辑）：遍历支持歌词搜索的插件（跳过来源插件），
   *  取标题+歌手编辑距离最小的结果拉取歌词 */
  static async searchLyricAuto(item: MusicItem): Promise<LyricSource | null> {
    const keyword = item.alias.length > 0 ? item.alias : item.title;
    const plugins = pluginManager.getSearchablePlugins(SupportMediaType.Lyric);

    let best: MusicItem | null = null;
    let targetPlugin: Plugin | null = null;
    let distance = Number.POSITIVE_INFINITY;

    for (const plugin of plugins) {
      if (plugin.name === item.platform) {
        continue;
      }
      const candidates = await LyricSearch.searchCandidates(plugin, keyword, SupportMediaType.Lyric, 2);
      for (const cand of candidates) {
        if (LyricSearch.isExactMatch(cand, keyword, item)) {
          return LyricSearch.tryGetLyric(item, cand, plugin);
        }
        const dist = LyricSearch.titleArtistDistance(cand, item);
        if (dist < distance) {
          distance = dist;
          best = cand;
          targetPlugin = plugin;
        }
      }
    }

    if (best !== null && targetPlugin !== null) {
      return LyricSearch.tryGetLyric(item, best, targetPlugin);
    }
    return null;
  }

  /** 从指定插件为歌曲匹配歌词：
   *  - 歌曲来自该插件时，直接拉取该歌曲歌词；
   *  - 否则先按歌词类型搜索；很多插件不实现歌词类型搜索（supportedSearchType 只有
   *    music 等）但其歌曲详情带歌词，此时退回音乐搜索（关键词 标题+歌手），
   *    再对匹配歌曲取歌词。
   *  匹配成功后把匹配项写入原歌曲的 associatedLrc 附加属性，使原歌曲后续 getLyric 命中。
   *  未找到返回 null。 */
  static async searchLyricFromPlugin(item: MusicItem, plugin: Plugin): Promise<LyricSource | null> {
    if (plugin.name === item.platform) {
      try {
        return await plugin.methods.getLyric(item);
      } catch (e) {
        return null;
      }
    }

    const keyword = item.alias.length > 0 ? item.alias : item.title;
    let candidates = await LyricSearch.searchCandidates(plugin, keyword, SupportMediaType.Lyric, 2);
    if (candidates.length === 0) {
      const musicKeyword = item.artist.length > 0 ? item.title + ' ' + item.artist : item.title;
      candidates = await LyricSearch.searchCandidates(plugin, musicKeyword, SupportMediaType.Music, 5);
    }

    const best = LyricSearch.matchBest(item, keyword, candidates);
    if (best === null) {
      return null;
    }
    return LyricSearch.tryGetLyric(item, best, plugin);
  }

  private static async searchCandidates(plugin: Plugin, keyword: string, type: SupportMediaType,
    limit: number): Promise<Array<MusicItem>> {
    let results: SearchResult | null = null;
    try {
      results = await plugin.methods.search(keyword, 1, type);
    } catch (e) {
      results = null;
    }
    if (results === null) {
      return [];
    }
    const data = type === SupportMediaType.Lyric ? results.lyricData : results.musicData;
    return data.slice(0, limit);
  }

  private static matchBest(item: MusicItem, keyword: string, candidates: Array<MusicItem>): MusicItem | null {
    let best: MusicItem | null = null;
    let distance = Number.POSITIVE_INFINITY;
    for (const cand of candidates) {
      if (LyricSearch.isExactMatch(cand, keyword, item)) {
        return cand;
      }
      const dist = LyricSearch.titleArtistDistance(cand, item);
      if (dist < distance) {
        distance = dist;
        best = cand;
      }
    }
    return best;
  }

  private static isExactMatch(cand: MusicItem, keyword: string, item: MusicItem): boolean {
    return cand.title === keyword && cand.artist === item.artist;
  }

  private static titleArtistDistance(cand: MusicItem, item: MusicItem): number {
    return MinDistance.compute(cand.title, item.title) + MinDistance.compute(cand.artist, item.artist);
  }

  /** 对匹配歌曲拉取歌词；非空时把匹配项关联到原歌曲（associatedLrc） */
  private static async tryGetLyric(item: MusicItem, matched: MusicItem,
    plugin: Plugin): Promise<LyricSource | null> {
    try {
      const lyric = await plugin.methods.getLyric(matched);
      if (lyric !== null && !lyric.isEmpty()) {
        const patch = new MediaExtraProperties();
        patch.associatedLrc = matched.toPersistRecord();
        MediaExtra.patchMediaExtra(item, patch);
      }
      return lyric;
    } catch (e) {
      return null;
    }
  }
}
