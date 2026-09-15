import web_webview from '@ohos.web.webview';
import { WebPluginExecutor } from '../plugin/WebPluginExecutor';
import { Bootstrap } from '../core/Bootstrap';
import { trackPlayer } from '../core/TrackPlayer';
import { PlayState } from '../core/PlayerEngine';
import { MusicItem } from '../model/MediaTypes';
import {
  HdsBarStyle,
  HdsNavigation, HdsNavigationTitleMode, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { appState } from '../entryability/AppState';
import { deviceInfo } from '@kit.BasicServicesKit';
import { MENU_CONFIG, MenuItem, tabBarSymbolOf } from '../model/TabsModels';
import { Home } from './Home';
import { DownloadPage } from './DownloadPage';
import { PluginPage } from './PluginPage';
import { SettingsPage } from './SettingsPage';

@Entry
@ComponentV2
struct Index {
  private controller: web_webview.WebviewController = new web_webview.WebviewController();
  private tabsController: HdsTabsController = new HdsTabsController();
  @Local bootReady: boolean = false;
  @Local currentMusic: MusicItem | null = null;
  @Local isPlaying: boolean = false;

  aboutToAppear(): void {
    WebPluginExecutor.getInstance().attachController(this.controller);
    this.currentMusic = trackPlayer.currentMusic;
    this.isPlaying = trackPlayer.playState === PlayState.Playing;
    trackPlayer.onCurrentMusicChanged((music: MusicItem | null) => {
      this.currentMusic = music;
    });
    trackPlayer.onPlayStateChanged((state: PlayState) => {
      this.isPlaying = state === PlayState.Playing;
    });
    trackPlayer.onCellularForbidden(() => {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '移动网络下播放已被禁止', duration: 2000 });
      } catch (error) {
        // TODO: Implement error handling.
      }
    });
    this.initApp();
  }

  private async initApp(): Promise<void> {
    try {
      await Bootstrap.setup();
      this.bootReady = true;
    } catch (e) {
      const message = e instanceof Error ? e.message : '未知错误';
      this.getUIContext().getPromptAction().showToast({ message: '初始化失败: ' + message, duration: 3000 });
    }
  }

  private togglePlay(): void {
    if (this.isPlaying) {
      trackPlayer.pause().catch(() => {
      });
    } else {
      trackPlayer.play().catch(() => {
      });
    }
  }

  private skipToNext(): void {
    trackPlayer.skipToNext().catch(() => {
    });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavigation(appState.pageInfos) {
        HdsTabs({ controller: this.tabsController }) {
          ForEach(MENU_CONFIG, (item: MenuItem, i: number) => {
            TabContent() {
              if (i === 0) {
                Home({ bootReady: this.bootReady })
              } else if (i === 1) {
                DownloadPage()
              } else if (i === 2) {
                PluginPage()
              } else {
                SettingsPage()
              }
            }
            .tabBar(new BottomTabBarStyle(tabBarSymbolOf(item), item.label))
          }, (item: MenuItem, i: number) => 'tab_' + i.toString())
        }
        .barOverlap(true)
        .vertical(false)
        .scrollable(false)
        .barPosition(BarPosition.End)
        .barFloatingStyle({
          barBottomMargin: 28,
          systemMaterialEffect: {
            materialType: appState.materialType,
            materialLevel: appState.materialLevel
          },
          adaptToHandedness: true,
          miniBar: {
            miniBarBuilder: () => {
              this.miniBarBuilder()
            },
            miniBarStyle: appState.miniBarStyle,
            onBarStyleChange: (miniBarStyle: HdsBarStyle) => {
              appState.miniBarStyle = miniBarStyle
            },
          },
        })
        .animationDuration(500)
        .onSelected((index: number) => {
          appState.currTabsIndex = index
        })
      }
      .titleMode(HdsNavigationTitleMode.MINI)
      .mode(NavigationMode.Stack)
      .navBarWidth('40%')
      .hideBackButton(true)
      .hideTitleBar(true)
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.background_secondary'))
      .foregroundBlurStyle(appState.isForegroundBlur ? BlurStyle.Thin : BlurStyle.NONE,
        { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT, scale: 0.3 })

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
    .height('100%')
  }

  @Builder
  miniBarBuilder() {
    Row({ space: 12 }) {
      if (this.currentMusic !== null && this.currentMusic.artwork.length > 0) {
        Image(this.currentMusic.artwork)
          .width(44)
          .height(44)
          .borderRadius(11)
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.music_note_list'))
            .fontSize(22)
            .fontColor([$r('sys.color.icon_secondary')])
        }
        .width(44)
        .height(44)
        .borderRadius(11)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .justifyContent(FlexAlign.Center)
      }

      Column({ space: 2 }) {
        Text(this.currentMusic === null ? $r('app.string.playbar_no_music') : this.currentMusic.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.currentMusic !== null) {
          Text(this.currentMusic.artist)
            .fontSize(11)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause') : $r('sys.symbol.play_fill'))
        .fontSize(26)
        .fontColor([$r('sys.color.icon_primary')])
        .onClick(() => {
          this.togglePlay()
        })

      SymbolGlyph($r('sys.symbol.forward_end_fill'))
        .fontSize(22)
        .fontColor([$r('sys.color.icon_primary')])
        .onClick(() => {
          this.skipToNext()
        })
    }
    .width('100%')
    .height(52)
    .padding({ left: 8, right: 12 })
    .alignItems(VerticalAlign.Center)
  }
}

export function IsApiVersion_24(): boolean {
  return deviceInfo.distributionOSApiVersion >= 60101
}
