import { MusicItem } from '../common/model/MediaTypes';
import { SupportMediaType, SearchResult } from '../common/model/SheetTypes';
import { JsonUtil } from '../common/JsonUtil';
import { pluginManager } from '../plugin/PluginManager';
import { Plugin } from '../plugin/Plugin';
import { trackPlayer } from '../core/TrackPlayer';
import { localMusicSheet, downloadedSheet } from '../core/LocalMusicSheet';

/**
 * 本地音乐封面搜索（更多面板「搜索封面」/「选择封面」/ 批量搜索封面 共用）
 * 优先来源插件 getMusicInfo 取详情封面；无结果时按 标题+歌手 在支持搜索的
 * 已启用插件中逐个搜索（按插件排序），取第一个带封面的结果；
 * 命中后写回本地音乐/已下载两域的匹配条目（列表随更新事件自动刷新），
 * 若正在播放则同步刷新播放页与通知栏的当前歌曲封面
 */
export class CoverSearch {
  /** 搜索并写回单首本地音乐的封面；返回是否命中 */
  static async searchAndApply(item: MusicItem): Promise<boolean> {
    const artwork = await CoverSearch.searchCover(item);
    if (artwork.length === 0) {
      return false;
    }
    CoverSearch.applyArtwork(item, artwork);
    return true;
  }

  /** 写回封面到本地音乐/已下载两域，并同步播放中的当前歌曲 */
  static applyArtwork(item: MusicItem, artwork: string): void {
    if (artwork.length === 0) {
      return;
    }
    localMusicSheet.setArtwork(item, artwork);
    downloadedSheet.setArtwork(item, artwork);
    trackPlayer.patchArtwork(item, artwork);
  }

  /** 搜索封面：来源插件详情优先，其次全插件按 标题+歌手 搜索 */
  static async searchCover(item: MusicItem): Promise<string> {
    // 1. 来源插件 getMusicInfo（详情通常带封面）
    const plugin = pluginManager.getByMedia(item);
    if (plugin !== null) {
      try {
        const rec = await plugin.methods.getMusicInfo(item);
        if (rec !== null) {
          const artwork = JsonUtil.recStr(rec, 'artwork');
          if (artwork.length > 0) {
            return artwork;
          }
        }
      } catch (e) {
        // 详情失败继续走搜索
      }
    }
    // 2. 按 标题+歌手 搜索，取第一个带封面的结果
    const keyword = item.artist.length > 0 ? item.title + ' ' + item.artist : item.title;
    const plugins = pluginManager.getSortedSearchablePlugins(SupportMediaType.Music);
    for (const p of plugins) {
      try {
        const result = await p.methods.search(keyword, 1, SupportMediaType.Music);
        for (const m of result.musicData) {
          if (m.artwork.length > 0) {
            return m.artwork;
          }
        }
      } catch (e) {
        // 单个插件失败继续下一个
      }
    }
    return '';
  }

  /**
   * 搜索候选封面列表（「选择封面」弹窗用）：
   * 来源插件详情封面置顶，其次并发搜索全部插件收集第一页结果的封面；去重，上限 12
   */
  static async searchCandidates(item: MusicItem): Promise<Array<string>> {
    const result: Array<string> = [];
    const seen: Set<string> = new Set<string>();
    const push = (artwork: string): void => {
      if (artwork.length > 0 && !seen.has(artwork) && result.length < 12) {
        seen.add(artwork);
        result.push(artwork);
      }
    };
    // 1. 来源插件详情封面置顶
    const plugin = pluginManager.getByMedia(item);
    if (plugin !== null) {
      try {
        const rec = await plugin.methods.getMusicInfo(item);
        if (rec !== null) {
          push(JsonUtil.recStr(rec, 'artwork'));
        }
      } catch (e) {
        // 详情失败继续搜索
      }
    }
    // 2. 并发搜索全部插件（单个插件超时 6s），收集第一页结果的封面
    const keyword = item.artist.length > 0 ? item.title + ' ' + item.artist : item.title;
    const plugins = pluginManager.getSortedSearchablePlugins(SupportMediaType.Music);
    const tasks: Array<Promise<Array<string>>> = [];
    for (const p of plugins) {
      tasks.push(CoverSearch.searchArtworkFromPlugin(p, keyword));
    }
    const lists = await Promise.all(tasks);
    for (const artworks of lists) {
      for (const artwork of artworks) {
        push(artwork);
      }
    }
    return result;
  }

  /** 单插件搜索第一页封面（超时/失败返回空列表） */
  private static async searchArtworkFromPlugin(plugin: Plugin, keyword: string): Promise<Array<string>> {
    const searchTask: Promise<SearchResult | null> =
      plugin.methods.search(keyword, 1, SupportMediaType.Music)
        .catch((_e: Object): SearchResult | null => null);
    const timeoutTask: Promise<SearchResult | null> =
      new Promise<SearchResult | null>((resolve: (v: SearchResult | null) => void) => {
        setTimeout((): void => resolve(null), 6000);
      });
    const racers: Array<Promise<SearchResult | null>> = [searchTask, timeoutTask];
    const result = await Promise.race(racers);
    const artworks: Array<string> = [];
    if (result !== null) {
      for (const m of result.musicData) {
        if (m.artwork.length > 0) {
          artworks.push(m.artwork);
        }
      }
    }
    return artworks;
  }
}
