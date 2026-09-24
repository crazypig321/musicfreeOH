import { MENU_CONFIG, MenuItem, tabBarSymbolOf } from '../common/model/TabsModels';
import { appState } from '../entryability/AppState';
import {
  ROUTE_SEARCH, ROUTE_DOWNLOAD, ROUTE_LOCAL_MUSIC, ROUTE_RECOMMEND_SHEETS, ROUTE_SHEET_DETAIL,
  ROUTE_ALBUM_DETAIL, ROUTE_ARTIST_DETAIL, ROUTE_ABOUT, ROUTE_CACHE, ROUTE_PLAY_SETTING,
  ROUTE_DOWNLOAD_SETTING, ROUTE_LYRIC_SETTING, ROUTE_PLUGIN_SETTING, ROUTE_BACKUP_SETTING,
  ROUTE_WEBDAV_SETTING, ROUTE_APPEARANCE_SETTING
} from '../common/model/NavModels';
import { HomePage } from '../pages/HomePage';
import { MySheetsPage } from '../pages/MySheetsPage';
import { PluginPage } from '../pages/PluginPage';
import { SubscriptionPage } from '../pages/SubscriptionPage';
import { SettingsPage } from '../pages/SettingsPage';
import { SearchPage } from '../pages/SearchPage';
import { DownloadPage } from '../pages/DownloadPage';
import { LocalMusicPage } from '../pages/LocalMusicPage';
import { RecommendSheetsPage } from '../pages/RecommendSheetsPage';
import { SheetDetailPage } from '../pages/SheetDetailPage';
import { MediaDetailPage } from '../pages/MediaDetailPage';
import { AboutPage } from '../pages/settingSecPage/AboutPage';
import { CachePage } from '../pages/settingSecPage/CachePage';
import { PlaySettingPage } from '../pages/settingSecPage/PlaySettingPage';
import { DownloadSettingPage } from '../pages/settingSecPage/DownloadSettingPage';
import { LyricSettingPage } from '../pages/settingSecPage/LyricSettingPage';
import { PluginSettingPage } from '../pages/settingSecPage/PluginSettingPage';
import { BackupSettingPage } from '../pages/settingSecPage/BackupSettingPage';
import { WebDavSettingPage } from '../pages/settingSecPage/WebDavSettingPage';
import { AppearanceSettingPage } from '../pages/settingSecPage/AppearanceSettingPage';

/**
 * 公共页面装配（手机 HdsTabs 布局与 PC 侧边栏布局共用）：
 * - MainTabPagesBuilder：五个主页面 TabContent（保持页面状态不丢失）
 * - PageMapBuilder：二级路由页（搜索/下载/详情/设置子页等）
 */

/** 底部 tab 样式：文本选中色直接适配主题色 */
function tabBarOf(item: MenuItem): BottomTabBarStyle {
  const style: BottomTabBarStyle = new BottomTabBarStyle(tabBarSymbolOf(item), item.label);
  style.labelStyle({ selectedColor: appState.accentColor });
  return style;
}

/** 主页面 TabContent 装配（手机底部 tab 与 PC 侧边栏内容区共用） */
@Builder
export function MainTabPagesBuilder() {
  ForEach(MENU_CONFIG, (item: MenuItem, i: number) => {
    TabContent() {
      if (i === 0) {
        HomePage({ bootReady: appState.bootReady })
      } else if (i === 1) {
        MySheetsPage({ hostTabIndex: appState.currTabsIndex })
      } else if (i === 2) {
        PluginPage({ hostTabIndex: appState.currTabsIndex })
      } else if (i === 3) {
        SubscriptionPage()
      } else {
        SettingsPage()
      }
    }
    .tabBar(tabBarOf(item))
  }, (item: MenuItem, i: number) => 'tab_' + i.toString())
}

/** 二级路由页装配（由 HdsNavigation.navDestination 调用） */
@Builder
export function PageMapBuilder(name: string) {
  if (name === ROUTE_SEARCH) {
    SearchPage({ bootReady: appState.bootReady })
  } else if (name === ROUTE_DOWNLOAD) {
    DownloadPage()
  } else if (name === ROUTE_LOCAL_MUSIC) {
    LocalMusicPage()
  } else if (name === ROUTE_RECOMMEND_SHEETS) {
    RecommendSheetsPage()
  } else if (name === ROUTE_SHEET_DETAIL) {
    SheetDetailPage()
  } else if (name === ROUTE_ALBUM_DETAIL || name === ROUTE_ARTIST_DETAIL) {
    MediaDetailPage()
  } else if (name === ROUTE_ABOUT) {
    AboutPage()
  } else if (name === ROUTE_CACHE) {
    CachePage()
  } else if (name === ROUTE_PLAY_SETTING) {
    PlaySettingPage()
  } else if (name === ROUTE_DOWNLOAD_SETTING) {
    DownloadSettingPage()
  } else if (name === ROUTE_LYRIC_SETTING) {
    LyricSettingPage()
  } else if (name === ROUTE_PLUGIN_SETTING) {
    PluginSettingPage()
  } else if (name === ROUTE_BACKUP_SETTING) {
    BackupSettingPage()
  } else if (name === ROUTE_WEBDAV_SETTING) {
    WebDavSettingPage()
  } else if (name === ROUTE_APPEARANCE_SETTING) {
    AppearanceSettingPage()
  }
}
