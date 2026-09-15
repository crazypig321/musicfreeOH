import { appState } from '../entryability/AppState';
import { pluginManager } from '../plugin/PluginManager';
import { Plugin } from '../plugin/Plugin';
import { PluginState } from '../plugin/PluginTypes';
import { InstallPluginResult } from '../plugin/PluginTypes';
import { appConfig } from '../core/AppConfig';

interface PluginRow {
  name: string;
  version: string;
  author: string;
  state: PluginState;
  hash: string;
}

@ComponentV2
export struct PluginPage {
  @Local pluginUrl: string = '';
  @Local installStatus: string = '';
  @Local installing: boolean = false;
  @Local pluginRows: Array<PluginRow> = [];

  aboutToAppear(): void {
    this.pluginUrl = 'https://gitee.com/maotoumao/MusicFreePlugins/raw/v0.1/dist/bilibili/index.js';
    this.refreshPlugins();
    pluginManager.onOrderUpdated(() => {
      this.refreshPlugins();
    });
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
    const rows: Array<PluginRow> = [];
    const plugins = pluginManager.getSortedPlugins();
    for (const p of plugins) {
      const row: PluginRow = {
        name: p.name,
        version: p.instanceInfo !== null ? p.instanceInfo.version : '',
        author: p.instanceInfo !== null ? p.instanceInfo.author : '',
        state: p.state,
        hash: p.hash
      };
      rows.push(row);
    }
    const localPlugin = pluginManager.getByName('本地');
    if (localPlugin !== null) {
      const row: PluginRow = {
        name: localPlugin.name,
        version: localPlugin.instanceInfo !== null ? localPlugin.instanceInfo.version : '',
        author: '内置',
        state: localPlugin.state,
        hash: localPlugin.hash
      };
      rows.push(row);
    }
    this.pluginRows = rows;
  }

  private installPlugin(): void {
    const url = this.pluginUrl.trim();
    if (url.length === 0) {
      this.installStatus = '请输入插件 URL';
      return;
    }
    if (this.installing) {
      return;
    }
    this.installing = true;
    this.installStatus = '安装中...';
    pluginManager.installPluginFromUrl(url, appConfig.getNotCheckPluginVersion())
      .then((r: InstallPluginResult) => {
        this.installing = false;
        if (r.success) {
          this.installStatus = '安装成功: ' + r.pluginName;
          this.refreshPlugins();
        } else {
          this.installStatus = '安装失败: ' + r.message;
        }
      })
      .catch((e: Object) => {
        this.installing = false;
        this.installStatus = '安装失败: ' + (e instanceof Error ? e.message : '');
      });
  }

  private uninstall(row: PluginRow): void {
    if (row.name === '本地') {
      return;
    }
    pluginManager.uninstallPlugin(row.hash)
      .then(() => {
        this.installStatus = '已卸载: ' + row.name;
        this.refreshPlugins();
      })
      .catch((e: Object) => {
        this.installStatus = '卸载失败: ' + (e instanceof Error ? e.message : '');
      });
  }

  build() {
    Scroll() {
      Column() {
        Text($r('app.string.tab_plugin'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .margin({ top: 12, bottom: 16 })

        Row({ space: 8 }) {
          TextInput({ text: this.pluginUrl, placeholder: '插件 URL' })
            .layoutWeight(1)
            .height(40)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .borderRadius(20)
            .fontSize(12)
            .onChange((v: string) => {
              this.pluginUrl = v;
            })
          Button(this.installing ? '...' : '安装')
            .height(40)
            .fontSize(14)
            .borderRadius(20)
            .backgroundColor($r('sys.color.background_emphasize'))
            .onClick(() => {
              this.installPlugin();
            })
        }
        .width('100%')

        if (this.installStatus.length > 0) {
          Text(this.installStatus)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .margin({ top: 8 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        if (this.pluginRows.length > 0) {
          ForEach(this.pluginRows, (row: PluginRow, index: number) => {
            Row({ space: 12 }) {
              Column() {
                SymbolGlyph($r('sys.symbol.AI_panels'))
                  .fontSize(22)
                  .fontColor([$r('sys.color.icon_secondary')])
              }
              .width(40)
              .height(40)
              .borderRadius(10)
              .backgroundColor($r('sys.color.comp_background_tertiary'))
              .justifyContent(FlexAlign.Center)

              Column({ space: 2 }) {
                Text(row.name)
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text((row.version.length > 0 ? 'v' + row.version : '') +
                  (row.author.length > 0 ? ' · ' + row.author : ''))
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Text(PluginPage.stateText(row.state))
                .fontSize(12)
                .fontColor(row.state === PluginState.Mounted ? $r('sys.color.font_emphasize') : $r('sys.color.font_tertiary'))

              if (row.name !== '本地') {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(18)
                  .fontColor([$r('sys.color.icon_tertiary')])
                  .onClick(() => {
                    this.uninstall(row);
                  })
              }
            }
            .width('100%')
            .height(56)
            .borderRadius(12)
            .onClick(() => {
              this.refreshPlugins();
            })
          }, (row: PluginRow, index: number) => row.name + '_' + row.hash + '_' + index.toString())
        } else {
          Text($r('app.string.home_no_plugin'))
            .fontSize(13)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 32 })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: appState.topRect, bottom: 180 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}
