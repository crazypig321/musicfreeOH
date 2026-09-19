import { BlurStrategy, HdsNavigationTitleBarOptions, ScrollEffectType } from "@kit.UIDesignKit";
import { LengthMetrics } from "@kit.ArkUI";
import { TimeTipUtils } from "../../utils/TimeTipUtils";
import { appState } from "../../entryability/AppState";
import { MediaTag, SheetItem, AlbumItem, ArtistItem } from "./SheetTypes";

export const ROUTE_SEARCH: string = 'search';
export const ROUTE_DOWNLOAD: string = 'download';
export const ROUTE_LOCAL_MUSIC: string = 'localMusic';
export const ROUTE_RECOMMEND_SHEETS: string = 'recommendSheets';
export const ROUTE_SHEET_DETAIL: string = 'sheetDetail';
export const ROUTE_ALBUM_DETAIL: string = 'albumDetail';
export const ROUTE_ARTIST_DETAIL: string = 'artistDetail';
export const ROUTE_PLAYER: string = 'player';
export const ROUTE_ABOUT: string = 'about';
export const ROUTE_CACHE: string = 'cache';
export const ROUTE_PLAY_SETTING: string = 'playSetting';
export const ROUTE_DOWNLOAD_SETTING: string = 'downloadSetting';
export const ROUTE_LYRIC_SETTING: string = 'lyricSetting';
export const ROUTE_PLUGIN_SETTING: string = 'pluginSetting';
export const ROUTE_BACKUP_SETTING: string = 'backupSetting';
export const ROUTE_WEBDAV_SETTING: string = 'webDavSetting';
export const ROUTE_APPEARANCE_SETTING: string = 'appearanceSetting';

/**
 * 推荐歌单页跳转参数（push 前由首页赋值，页面 aboutToAppear 读取）
 */
export class RecommendSheetNavParams {
  static pluginName: string = '';
  static tags: Array<MediaTag> = [];
  static selectedIndex: number = 0;
}

/**
 * 歌单详情页跳转参数（push 前由来源页赋值，页面 aboutToAppear 读取）
 */
export class SheetDetailNavParams {
  /** 插件名（榜单条目的 platform 可能为空，需显式传来源插件名） */
  static pluginName: string = '';
  static sheet: SheetItem | null = null;
  /** true：榜单（getTopListDetail）；false：歌单（getMusicSheetInfo） */
  static isTopList: boolean = false;
}

/**
 * 专辑/歌手详情页跳转参数（album 与 artist 二选一，均非空时按专辑处理）
 */
export class MediaDetailNavParams {
  /** 来源插件名 */
  static pluginName: string = '';
  /** 专辑详情模式 */
  static album: AlbumItem | null = null;
  /** 歌手详情模式 */
  static artist: ArtistItem | null = null;
}

export function NavTitleBarOp() : HdsNavigationTitleBarOptions {
return {
content: {
title: {
mainTitle: TimeTipUtils(),
},
menu: {
value: [{
  content: {
    icon: $r('sys.symbol.magnifyingglass'),
    label: 'search',
    action: () => {
      // 搜索操作
    },
  }
}]
},
},
style: {
scrollEffectOpts: {
enableScrollEffect: true,
scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR, // 设置模糊类型
blurEffectiveStartOffset: LengthMetrics.vp(0), // 动态样式线性过渡的起始位置
blurEffectiveEndOffset: LengthMetrics.vp(80) // 动态样式线性过渡的终点位置
},
blurStrategy: BlurStrategy.ADAPTIVE,
originalStyle: {
backgroundStyle: { backgroundColor: '#00ffffff', maskExtraHeight: 0, blurRadius: 50 },
contentStyle: {
  titleStyle: { mainTitleColor: $r('sys.color.font'), subTitleColor: $r('sys.color.font_tertiary') },
  menuStyle: {
    iconColor: $r('sys.color.icon')
  },
},
},
scrollEffectStyle: { backgroundStyle: { backgroundColor: '#00ffffff', maskExtraHeight: 0, blurRadius: 100 } },
systemMaterialEffect: {
materialType: appState.materialType,
materialLevel: appState.materialLevel
},
},
avoidLayoutSafeArea: true,
}
}