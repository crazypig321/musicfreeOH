import { MenuItem, tabItemsOf, tabBarSymbolOf, TAB_KEY_HOME, TAB_KEY_SHEETS, TAB_KEY_MINE, TAB_KEY_PLUGIN, TAB_KEY_SUBSCRIPTION } from '../common/model/TabsModels';
import { appState } from '../entryability/AppState';
import {
  ROUTE_SEARCH, ROUTE_DOWNLOAD, ROUTE_LOCAL_MUSIC, ROUTE_RECOMMEND_SHEETS, ROUTE_SHEET_DETAIL,
  ROUTE_ALBUM_DETAIL, ROUTE_ARTIST_DETAIL, ROUTE_ABOUT, ROUTE_CACHE, ROUTE_PLAY_SETTING,
  ROUTE_DOWNLOAD_SETTING, ROUTE_LYRIC_SETTING, ROUTE_PLUGIN_SETTING, ROUTE_BACKUP_SETTING,
  ROUTE_WEBDAV_SETTING, ROUTE_APPEARANCE_SETTING, ROUTE_MINE, ROUTE_SETTINGS
} from '../common/model/NavModels';
import { HomePage } from '../pages/HomePage';
import { MySheetsPage } from '../pages/MySheetsPage';
import { PluginPage } from '../pages/PluginPage';
import { SubscriptionPage } from '../pages/SubscriptionPage';
import { MinePage } from '../pages/MinePage';
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

/** 主页面 TabContent 装配（手机底部 tab 与 PC 侧边栏内容区共用；
 *  tab 列表按「我的、设置页面显示样式」动态组合，key 用页面键保证增删 tab 时正确差分） */
@Builder
export function MainTabPagesBuilder() {
  ForEach(tabItemsOf(appState.mineSettingStyle), (item: MenuItem, _i: number) => {
    TabContent() {
      if (item.key === TAB_KEY_HOME) {
        HomePage({ bootReady: appState.bootReady })
      } else if (item.key === TAB_KEY_SHEETS) {
        MySheetsPage({ hostTabIndex: appState.currTabsIndex })
      } else if (item.key === TAB_KEY_MINE) {
        MinePage({ hostTabIndex: appState.currTabsIndex })
      } else if (item.key === TAB_KEY_PLUGIN) {
        PluginPage({ hostTabIndex: appState.currTabsIndex })
      } else if (item.key === TAB_KEY_SUBSCRIPTION) {
        SubscriptionPage({ hostTabIndex: appState.currTabsIndex })
      } else {
        SettingsPage()
      }
    }
    .tabBar(tabBarOf(item))
  }, (item: MenuItem) => 'tab_' + item.key)
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
  } else if (name === ROUTE_MINE) {
    // 设置含我的入口样式：设置页「我的」条目进入（非 tab 挂载，显示返回键）
    MinePage({ pushed: true })
  } else if (name === ROUTE_SETTINGS) {
    // 我的含设置入口样式：我的页「设置」条目/按钮进入（非 tab 挂载，显示返回键）
    SettingsPage({ pushed: true })
  }
}
