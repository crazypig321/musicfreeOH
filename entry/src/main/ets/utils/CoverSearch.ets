import { MusicItem } from '../common/model/MediaTypes';
import { SupportMediaType } from '../common/model/SheetTypes';
import { JsonUtil } from '../common/JsonUtil';
import { pluginManager } from '../plugin/PluginManager';
import { localMusicSheet, downloadedSheet } from '../core/LocalMusicSheet';

/**
 * 本地音乐封面搜索（更多面板「搜索封面」/ 批量搜索封面 共用）
 * 优先来源插件 getMusicInfo 取详情封面；无结果时按 标题+歌手 在支持搜索的
 * 已启用插件中逐个搜索（按插件排序），取第一个带封面的结果；
 * 命中后写回本地音乐/已下载两域的匹配条目（列表随更新事件自动刷新）
 */
export class CoverSearch {
  /** 搜索并写回单首本地音乐的封面；返回是否命中 */
  static async searchAndApply(item: MusicItem): Promise<boolean> {
    const artwork = await CoverSearch.searchCover(item);
    if (artwork.length === 0) {
      return false;
    }
    localMusicSheet.setArtwork(item, artwork);
    downloadedSheet.setArtwork(item, artwork);
    return true;
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
}
