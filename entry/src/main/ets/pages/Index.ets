import web_webview from '@ohos.web.webview';
import { WebPluginExecutor } from '../plugin/WebPluginExecutor';
import { pluginManager } from '../plugin/PluginManager';
import { PluginState, InstallPluginResult } from '../plugin/PluginTypes';
import { Bootstrap } from '../core/Bootstrap';
import { trackPlayer } from '../core/TrackPlayer';
import { PlayState } from '../core/PlayerEngine';
import { lyricManager } from '../core/LyricManager';
import { downloader, DownloadStatus, DownloadTaskInfo } from '../core/Downloader';
import { appConfig } from '../core/AppConfig';
import { SupportMediaType, SearchResult } from '../model/SheetTypes';
import { MusicItem } from '../model/MediaTypes';
import { ParsedLrcItem } from '../utils/LyricParser';
import { HdsNavigation, HdsNavigationTitleMode, HdsTabs, HdsTabsController } from '@hms.hds.hdsBaseComponent';
import { appState } from '../entryability/AppState';
import { NavTitleBarOp } from '../model/NavModels';

/**
 * 链路验证演示页：
 * - 承载隐藏的插件沙箱 WebView（plugin_host.html）
 * - Bootstrap 初始化入口
 * - 完整链路：安装插件 → 搜索 → 播放 → 歌词 → 下载
 */
@Entry
@ComponentV2
struct Index {
  private controller: web_webview.WebviewController = new web_webview.WebviewController();
  @Local status: string = '等待初始化';
  @Local pluginInfo: string = '';
  @Local pluginUrl: string = 'https://gitee.com/maotoumao/MusicFreePlugins/raw/v0.1/dist/bilibili/index.js';
  @Local installStatus: string = '';
  @Local keyword: string = '周杰伦';
  @Local searchStatus: string = '';
  @Local searchResults: Array<MusicItem> = [];
  @Local nowPlaying: string = '无';
  @Local playStateText: string = '未播放';
  @Local progressText: string = '';
  @Local isPlaying: boolean = false;
  @Local lyricText: string = '';
  @Local downloadText: string = '';

  aboutToAppear(): void {
    WebPluginExecutor.getInstance().attachController(this.controller);
    this.initApp()
   /* trackPlayer.onCurrentMusicChanged((m: MusicItem | null) => {
      this.nowPlaying = m === null ? '无' : m.title + ' - ' + m.artist + ' [' + m.platform + ']';
    });
    trackPlayer.onPlayStateChanged((s: PlayState) => {
      this.isPlaying = s === PlayState.Playing;
      if (s === PlayState.Playing) {
        this.playStateText = '播放中';
      } else if (s === PlayState.Paused) {
        this.playStateText = '已暂停';
      } else if (s === PlayState.Completed) {
        this.playStateText = '播放完成';
      } else if (s === PlayState.Error) {
        this.playStateText = '播放错误';
      } else {
        this.playStateText = '状态: ' + s;
      }
    });
    trackPlayer.onProgressChanged((pos: number, dur: number) => {
      this.progressText = pos.toFixed(1) + 's / ' + (dur > 0 ? dur.toFixed(1) + 's' : '?');
    });
    lyricManager.onCurrentLyricChanged((item: ParsedLrcItem | null) => {
      this.lyricText = item === null ? '暂无歌词' : item.lrc;
    });
    downloader.onDownloadTaskUpdate((task: DownloadTaskInfo) => {
      if (task.status === DownloadStatus.Completed) {
        this.downloadText = '下载完成: ' + task.filename;
      } else if (task.status === DownloadStatus.Error) {
        this.downloadText = '下载失败: ' + task.errorReason;
      } else if (task.status === DownloadStatus.Downloading) {
        this.downloadText = '下载中 ' + task.downloadedSize + '/' + task.fileSize;
      } else {
        this.downloadText = '下载准备中...';
      }
    });
    downloader.onDownloadError((reason: string, message: string) => {
      this.downloadText = '下载失败: ' + reason + ' ' + message;
    });*/
  }

  private static stateText(state: PluginState): string {
    if (state === PluginState.Mounted) {
      return '已挂载';
    }
    if (state === PluginState.Error) {
      return '错误';
    }
    if (state === PluginState.Loading) {
      return '加载中';
    }
    return '未挂载';
  }

  private refreshPlugins(): void {
    const plugins = pluginManager.getPlugins();
    const lines: Array<string> = [];
    for (const p of plugins) {
      lines.push(p.name + '  [' + Index.stateText(p.state) + ']  ' + p.hash.substring(0, 10));
    }
    const localPlugin = pluginManager.getByName('本地');
    if (localPlugin !== null) {
      lines.push(localPlugin.name + '  [' + Index.stateText(localPlugin.state) + ']  内置');
    }
    this.pluginInfo = '已加载 ' + plugins.length + ' 个插件\n' + lines.join('\n');
  }

  private async initApp(): Promise<void> {
    this.status = '正在初始化...';
    try {
      await Bootstrap.setup();
      this.refreshPlugins();
      this.status = '初始化完成';
    } catch (e) {
      this.status = '初始化失败: ' + (e instanceof Error ? e.message : '');
    }
  }

 /* private installPlugin(): void {
    const url = this.pluginUrl.trim();
    if (url === '') {
      this.installStatus = '请输入插件 URL';
      return;
    }
    this.installStatus = '安装中...';
    pluginManager.installPluginFromUrl(url, appConfig.getNotCheckPluginVersion())
      .then((r: InstallPluginResult) => {
        if (r.success) {
          this.installStatus = '安装成功: ' + r.pluginName;
          this.refreshPlugins();
        } else {
          this.installStatus = '安装失败: ' + r.message;
        }
      })
      .catch((e: Object) => {
        this.installStatus = '安装失败: ' + (e instanceof Error ? e.message : '');
      });
  }

  private doSearch(): void {
    const kw = this.keyword.trim();
    if (kw === '') {
      this.searchStatus = '请输入关键词';
      return;
    }
    const plugins = pluginManager.getSearchablePlugins(SupportMediaType.Music);
    if (plugins.length === 0) {
      this.searchStatus = '无可用音乐搜索插件';
      return;
    }
    this.searchStatus = '搜索中...';
    plugins[0].methods.search(kw, 1, SupportMediaType.Music)
      .then((r: SearchResult) => {
        this.searchResults = r.musicData;
        this.searchStatus = '共 ' + r.musicData.length + ' 条结果';
      })
      .catch((e: Object) => {
        this.searchStatus = '搜索失败: ' + (e instanceof Error ? e.message : '');
      });
  }

  private playItem(item: MusicItem): void {
    this.searchStatus = '正在播放: ' + item.title;
    trackPlayer.play(item).catch((e: Object) => {
      this.searchStatus = '播放失败: ' + (e instanceof Error ? e.message : '');
    });
  }

  private downloadCurrent(): void {
    const cur = trackPlayer.currentMusic;
    if (cur === null) {
      this.downloadText = '无当前曲目';
      return;
    }
    this.downloadText = '已加入下载队列';
    downloader.download([cur], 'standard');
  }*/
  
  private tabsController: HdsTabsController = new HdsTabsController();
  @Local currTabsIndex: number = 0
  
  build() {
    HdsNavigation(appState.pageInfos){
      HdsTabs({ controller: this.tabsController }){
        ForEach([],()=>{
          TabContent() {
           
          }
        })
      }
      .barOverlap(true)
      .vertical(false)
      .scrollable(false)
      .barPosition(BarPosition.End)
      .barFloatingStyle({
        barBottomMargin: 28,
        barWidth: { smallWidth: 200, mediumWidth: 300, largeWidth: 400 },
        systemMaterialEffect: {
          materialType: appState.materialType,
          materialLevel: appState.materialLevel
        },
        adaptToHandedness: true,
        gradientMask: { maskColor: $r('sys.color.background_secondary'), maskHeight: 50 },
        miniBar: {
          miniBarBuilder: ()=>{ this.miniBarBuilder() },
        //  barLayoutMode: appState.hdsBarLayoutMode,
        },
      })
      .onAnimationStart((index: number, targetIndex: number) => {
        console.info(`Succeeded in getting info.Index:${index},targetIndex:${targetIndex}.`);
        this.currTabsIndex = targetIndex;// todo 要写动画
      });
    }
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .width('100%')
    .height('100%')
    .titleBar(NavTitleBarOp())
    .backgroundColor($r('sys.color.background_secondary'))
    
    /*Scroll() {
      Column({ space: 10 }) {
        Text('MusicFree HarmonyOS')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 24 })
        Text(this.status)
          .fontSize(14)
          .fontColor('#666666')
        Text(this.pluginInfo)
          .fontSize(13)
          .fontColor('#333333')
          .textAlign(TextAlign.Start)
          .width('90%')
        Button('初始化应用')
          .onClick(() => {
            this.initApp();
          })

        Divider().margin({ top: 8 })
        Text('安装插件').fontSize(16).fontWeight(FontWeight.Medium)
        Row({ space: 8 }) {
          TextInput({ text: this.pluginUrl, placeholder: '插件 URL' })
            .layoutWeight(1)
            .fontSize(12)
            .height(40)
            .onChange((v: string) => {
              this.pluginUrl = v;
            })
          Button('安装')
            .height(40)
            .onClick(() => {
              this.installPlugin();
            })
        }
        .width('90%')
        Text(this.installStatus)
          .fontSize(13)
          .fontColor('#0066CC')
          .width('90%')

        Divider().margin({ top: 8 })
        Text('搜索').fontSize(16).fontWeight(FontWeight.Medium)
        Row({ space: 8 }) {
          TextInput({ text: this.keyword, placeholder: '关键词' })
            .layoutWeight(1)
            .fontSize(12)
            .height(40)
            .onChange((v: string) => {
              this.keyword = v;
            })
          Button('搜索')
            .height(40)
            .onClick(() => {
              this.doSearch();
            })
        }
        .width('90%')
        Text(this.searchStatus)
          .fontSize(13)
          .fontColor('#0066CC')
          .width('90%')
        ForEach(this.searchResults.slice(0, 10), (item: MusicItem, idx: number) => {
          Text((idx + 1) + '. ' + item.title + ' - ' + item.artist)
            .fontSize(14)
            .fontColor('#1a1a1a')
            .width('90%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ top: 4, bottom: 4 })
            .onClick(() => {
              this.playItem(item);
            })
        }, (item: MusicItem, idx: number) => item.platform + '_' + item.id + '_' + idx.toString())

        Divider().margin({ top: 8 })
        Text('当前播放: ' + this.nowPlaying)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .width('90%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.playStateText + '  ' + this.progressText)
          .fontSize(13)
          .fontColor('#666666')
        Row({ space: 12 }) {
          Button('上一曲')
            .height(38)
            .onClick(() => {
              trackPlayer.skipToPrevious().catch((): void => {
                this.playStateText = '上一曲失败';
              });
            })
          Button(this.isPlaying ? '暂停' : '播放')
            .height(38)
            .onClick(() => {
              if (this.isPlaying) {
                trackPlayer.pause().catch((): void => {
                  this.playStateText = '暂停失败';
                });
              } else {
                trackPlayer.play().catch((): void => {
                  this.playStateText = '播放失败';
                });
              }
            })
          Button('下一曲')
            .height(38)
            .onClick(() => {
              trackPlayer.skipToNext().catch((): void => {
                this.playStateText = '下一曲失败';
              });
            })
        }
        Text('歌词: ' + this.lyricText)
          .fontSize(14)
          .fontColor('#C71585')
          .width('90%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Divider().margin({ top: 8 })
        Button('下载当前曲')
          .height(38)
          .onClick(() => {
            this.downloadCurrent();
          })
        Text(this.downloadText)
          .fontSize(13)
          .fontColor('#0066CC')
          .width('90%')

      // 隐藏的插件沙箱（?v= 版本参数用于绕过 rawfile 资源缓存，改 HTML/库时递增）
      Web({ src: 'resource://rawfile/plugin_host.html?v=4', controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .javaScriptProxy({
            object: WebPluginExecutor.getInstance().bridge,
            name: 'mfNative',
            methodList: ['onPluginResult', 'markReady', 'getUserVariables', 'httpRequest', 'log'],
            controller: this.controller
          })
          .width(1)
          .height(1)
          .opacity(0)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, bottom: 40 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Auto)*/
  }
  
  @Builder
    miniBarBuilder() {
      Row() {
        Column() {
          Image($r('sys.symbol.book'))
            .width(40)
            .height(40)
            .borderRadius(40)
        }
        .width(48)
        .height(48)
        .justifyContent(FlexAlign.Center)
        .margin({ left: 4, right: 4 })

        Text('Hello')

        Column() {
          Image($r('app.media.startIcon'))
            .width(40)
            .height(40)
            .borderRadius(40)
        }
        .width(48)
        .height(48)
        .justifyContent(FlexAlign.Center)
      }
    }
}
