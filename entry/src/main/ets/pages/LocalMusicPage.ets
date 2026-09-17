import { DownloadPage } from './DownloadPage';

/**
 * 本地音乐页：复用下载页组件（本地模式），保证两页 UI 永久一致；
 * 差异（标题/导入/刷新菜单/数据源/移出语义）由 DownloadPage 的 isLocalMode 控制
 */
@ComponentV2
export struct LocalMusicPage {
  build() {
    DownloadPage({ isLocalMode: true })
  }
}
