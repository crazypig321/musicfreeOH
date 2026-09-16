import { pluginManager } from '../plugin/PluginManager';
import { Plugin } from '../plugin/Plugin';
import { PluginState } from '../plugin/PluginTypes';
import { PluginInstanceInfo } from '../plugin/PluginTypes';
import { InstallPluginResult } from '../plugin/PluginTypes';
import { appConfig } from '../core/AppConfig';
import { CommonNav, titleBarOf } from '../view/CommonNav';
import { appState } from '../entryability/AppState';
import { HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { ComponentContent } from '@kit.ArkUI';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { ContextHolder } from '../common/ContextHolder';
import { PathConst } from '../common/PathConst';
import { JsonUtil } from '../common/JsonUtil';

interface PluginRow {
  name: string;
  version: string;
  author: string;
  state: PluginState;
  hash: string;
  enabled: boolean;
}

/** 插件用户变量字段 */
class PluginVarField {
  key: string = '';
  name: string = '';
  value: string = '';
}

const ADD_ANCHOR_ID = 'plugin_add_anchor';
const MORE_ANCHOR_ID = 'plugin_more_anchor';

/** openMenu 菜单项参数 */
class PluginMenuItemParams {
  icon: ResourceStr = '';
  label: string = '';
  onAction: () => void = (): void => {};
}

/** openMenu 菜单内容参数 */
class PluginMenuParams {
  items: Array<PluginMenuItemParams> = [];
}

@Builder
function pluginMenuBuilder(params: PluginMenuParams) {
  Menu() {
    ForEach(params.items, (item: PluginMenuItemParams) => {
      MenuItem({ startIcon: item.icon, content: item.label })
        .onClick(() => {
          item.onAction();
        })
    }, (item: PluginMenuItemParams) => item.label)
  }
}

const pluginMenuWrapped: WrappedBuilder<[PluginMenuParams]> = wrapBuilder(pluginMenuBuilder);

@ComponentV2
export struct PluginPage {
  scroller: Scroller = new Scroller();
  @Local pluginRows: Array<PluginRow> = [];
  @Local showImportSheet: boolean = false;
  @Local importUrl: string = '';
  @Local installing: boolean = false;
  @Local updating: boolean = false;
  @Local showSortSheet: boolean = false;
  @Local sortNames: Array<string> = [];
  @Local showDetailSheet: boolean = false;
  @Local detailName: string = '';
  @Local detailVersion: string = '';
  @Local detailAuthor: string = '';
  @Local detailSrcUrl: string = '';
  @Local detailUsage: string = '';
  @Local detailVars: Array<PluginVarField> = [];
  private detailHash: string = '';
  private menuContent: ComponentContent<PluginMenuParams> | null = null;
  private varDialogId: number = -1;

  aboutToAppear(): void {
    this.refreshPlugins();
    pluginManager.onOrderUpdated((): void => {
      this.refreshPlugins();
    });
    pluginManager.onPluginEnabled((_name: string, _enabled: boolean): void => {
      this.refreshPlugins();
    });
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
        hash: p.hash,
        enabled: pluginManager.isPluginEnabled(p)
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
        hash: localPlugin.hash,
        enabled: true
      };
      rows.push(row);
    }
    this.pluginRows = rows;
  }

  private static searchTypeName(type: string): string {
    if (type === 'music') {
      return '音乐';
    }
    if (type === 'album') {
      return '专辑';
    }
    if (type === 'artist') {
      return '歌手';
    }
    if (type === 'sheet') {
      return '歌单';
    }
    if (type === 'lyric') {
      return '歌词';
    }
    return type;
  }

  private static usageText(info: PluginInstanceInfo): string {
    const parts: Array<string> = [];
    if (info.supportedSearchType.length > 0) {
      const names: Array<string> = [];
      for (const t of info.supportedSearchType) {
        names.push(PluginPage.searchTypeName(t));
      }
      parts.push('支持搜索：' + names.join('、'));
    }
    const abilities: Array<string> = [];
    const methods = info.supportedMethods;
    if (methods.indexOf('getMediaSource') !== -1) {
      abilities.push('获取音源');
    }
    if (methods.indexOf('getLyric') !== -1) {
      abilities.push('获取歌词');
    }
    if (methods.indexOf('getAlbumInfo') !== -1) {
      abilities.push('专辑详情');
    }
    if (methods.indexOf('getArtistWorks') !== -1) {
      abilities.push('歌手作品');
    }
    if (methods.indexOf('getTopLists') !== -1) {
      abilities.push('排行榜');
    }
    if (methods.indexOf('getRecommendSheetsByTag') !== -1) {
      abilities.push('推荐歌单');
    }
    if (methods.indexOf('importMusicSheet') !== -1) {
      abilities.push('导入歌单');
    }
    if (abilities.length > 0) {
      parts.push('支持能力：' + abilities.join('、'));
    }
    if (parts.length === 0) {
      return '该插件未声明任何能力。';
    }
    return parts.join('；') + '。';
  }

  /** 切换插件启用状态 */
  private togglePluginEnabled(row: PluginRow, on: boolean): void {
    const plugin = pluginManager.getByName(row.name);
    if (plugin === null) {
      return;
    }
    pluginManager.setPluginEnabled(plugin, on);
    this.showToast(on ? '已启用「' + row.name + '」' : '已停用「' + row.name + '」');
  }

  /** 打开插件详情半模态 */
  private openDetailSheet(row: PluginRow): void {
    this.detailName = row.name;
    this.detailVersion = row.version;
    this.detailAuthor = row.author;
    this.detailHash = row.hash;
    this.detailSrcUrl = '';
    const fields: Array<PluginVarField> = [];
    const plugin = pluginManager.getByName(row.name);
    if (plugin !== null && plugin.instanceInfo !== null) {
      const info = plugin.instanceInfo;
      this.detailSrcUrl = info.srcUrl;
      this.detailUsage = PluginPage.usageText(info);
      const values = pluginManager.getUserVariables(plugin);
      for (const rec of info.userVariables) {
        const key = JsonUtil.recStr(rec, 'key');
        if (key.length === 0) {
          continue;
        }
        const f = new PluginVarField();
        f.key = key;
        f.name = JsonUtil.recStr(rec, 'name');
        if (f.name.length === 0) {
          f.name = key;
        }
        f.value = values[key] !== undefined ? values[key] : '';
        fields.push(f);
      }
    } else {
      this.detailUsage = '插件尚未挂载，暂时无法获取详细信息。';
    }
    this.detailVars = fields;
    this.showDetailSheet = true;
  }

  /** 使用说明弹窗 */
  private showUsageDialog(): void {
    let message = this.detailUsage;
    if (this.detailVars.length > 0) {
      message += '\n\n部分功能需要在「配置」中填写变量后使用。';
    }
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: this.detailName + ' 使用说明',
        message: message,
        buttons: [
          { text: '知道了', color: $r('sys.color.font_emphasize') }
        ]
      }).catch((_e: Object): void => {
      });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  /** 保存插件用户变量 */
  private saveDetailVars(): void {
    const plugin = pluginManager.getByName(this.detailName);
    if (plugin === null) {
      this.showToast('插件不存在');
      return;
    }
    const vars: Record<string, string> = {};
    for (const f of this.detailVars) {
      vars[f.key] = f.value;
    }
    pluginManager.setUserVariables(plugin, vars);
    this.showToast('配置已保存');
  }

  /** 打开变量编辑弹窗（所有变量在同一个弹窗填写） */
  private openVarDialog(): void {
    try {
      this.getUIContext().getPromptAction().openCustomDialog({
        builder: (): void => {
          this.VarInputDialog();
        },
        alignment: DialogAlignment.Center,
        isModal: true,
        autoCancel: true,
        width: '88%'
      }).then((id: number): void => {
        this.varDialogId = id;
      }).catch((_e: Object): void => {
      });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  /** 确认变量修改 */
  private confirmVarEdit(): void {
    const next: Array<PluginVarField> = [];
    for (const src of this.detailVars) {
      const f = new PluginVarField();
      f.key = src.key;
      f.name = src.name;
      f.value = src.value;
      next.push(f);
    }
    this.detailVars = next;
    this.saveDetailVars();
    this.closeVarDialog();
  }

  /** 关闭变量编辑弹窗 */
  private closeVarDialog(): void {
    if (this.varDialogId >= 0) {
      try {
        this.getUIContext().getPromptAction().closeCustomDialog(this.varDialogId);
      } catch (error) {
        // TODO: Implement error handling.
      }
      this.varDialogId = -1;
    }
  }

  /** 变量编辑弹窗内容 */
  @Builder
  VarInputDialog() {
    Column() {
      Text('配置变量')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: 16 })
      Scroll() {
        Column({ space: 14 }) {
          ForEach(this.detailVars, (f: PluginVarField, index: number) => {
            Column({ space: 6 }) {
              Text(f.name)
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              TextInput({ text: f.value, placeholder: f.key })
                .width('100%')
                .height(42)
                .fontSize(14)
                .fontColor($r('sys.color.font_primary'))
                .placeholderColor($r('sys.color.font_tertiary'))
                .backgroundColor($r('sys.color.comp_background_tertiary'))
                .borderRadius(10)
                .onChange((v: string): void => {
                  f.value = v;
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }, (f: PluginVarField, index: number) => f.key + '_' + index.toString())
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .constraintSize({ maxHeight: 360 })
      .width('100%')
      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .onClick(() => {
            this.closeVarDialog();
          })
        Button('确定')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .backgroundColor($r('sys.color.background_emphasize'))
          .onClick(() => {
            this.confirmVarEdit();
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .padding(20)
  }

  /** 检查更新（当前详情插件） */
  private checkDetailUpdate(): void {
    if (this.updating) {
      this.showToast('正在更新中，请稍候');
      return;
    }
    const plugin = pluginManager.getByName(this.detailName);
    if (plugin === null) {
      this.showToast('插件不存在');
      return;
    }
    const srcUrl = plugin.instanceInfo !== null ? plugin.instanceInfo.srcUrl : '';
    if (srcUrl.length === 0) {
      this.showToast('该插件没有更新源');
      return;
    }
    this.updating = true;
    this.showToast('正在检查更新...');
    pluginManager.updatePlugin(plugin).then((): void => {
      this.updating = false;
      this.showToast('更新成功');
      this.refreshPlugins();
    }).catch((e: Object): void => {
      this.updating = false;
      this.showToast(e instanceof Error && e.message.length > 0 ? e.message : '更新失败');
    });
  }

  /** 分享源地址 */
  private shareDetailSrc(): void {
    if (this.detailSrcUrl.length === 0) {
      this.showToast('该插件没有源地址');
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.detailSrcUrl);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      this.showToast('已复制源地址，可粘贴分享');
    }).catch((_e: Object): void => {
      this.showToast('复制失败');
    });
  }

  /** 卸载当前详情插件 */
  private uninstallDetail(): void {
    if (this.detailName === '本地') {
      this.showToast('内置插件无法卸载');
      return;
    }
    const hash = this.detailHash;
    this.showDetailSheet = false;
    pluginManager.uninstallPlugin(hash)
      .then(() => {
        this.showToast('已卸载: ' + this.detailName);
        this.refreshPlugins();
      })
      .catch((e: Object) => {
        this.showToast('卸载失败: ' + (e instanceof Error ? e.message : ''));
      });
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  /** titleBar 菜单按钮（添加 + 菜单） */
  private titleMenus(): Array<HdsNavigationMenuItemOptions> {
    const add: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.plus'),
        label: '添加',
        action: (): void => {
          this.openAddMenu();
        }
      }
    };
    const more: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.ellipsis_circle'),
        label: '菜单',
        action: (): void => {
          this.openMoreMenu();
        }
      }
    };
    return [add, more];
  }

  private runMenuAction(action: () => void): void {
    this.dismissMenu();
    action();
  }

  private dismissMenu(): void {
    const content = this.menuContent;
    this.menuContent = null;
    if (content !== null) {
      this.getUIContext().getPromptAction().closeMenu(content).catch((_e: Object): void => {
      });
    }
  }

  private openMenuAt(anchorId: string, params: PluginMenuParams): void {
    this.dismissMenu();
    const content = new ComponentContent<PluginMenuParams>(this.getUIContext(), pluginMenuWrapped, params);
    this.menuContent = content;
    this.getUIContext().getPromptAction().openMenu(content, { id: anchorId }, {
      placement: Placement.BottomRight
    }).then((): void => {
      if (this.menuContent === content) {
        this.menuContent = null;
      }
    }).catch((_e: Object): void => {
      this.showToast('菜单弹出失败');
    });
  }

  private openAddMenu(): void {
    const netItem = new PluginMenuItemParams();
    netItem.icon = $r('sys.symbol.dot_radiowaves_left_and_right');
    netItem.label = '网络导入';
    netItem.onAction = (): void => {
      this.runMenuAction((): void => {
        this.importUrl = '';
        this.showImportSheet = true;
      });
    };
    const localItem = new PluginMenuItemParams();
    localItem.icon = $r('sys.symbol.folder');
    localItem.label = '本地导入';
    localItem.onAction = (): void => {
      this.runMenuAction((): void => {
        this.pickLocalPlugin();
      });
    };
    const params = new PluginMenuParams();
    params.items = [netItem, localItem];
    this.openMenuAt(ADD_ANCHOR_ID, params);
  }

  private openMoreMenu(): void {
    const updateItem = new PluginMenuItemParams();
    updateItem.icon = $r('sys.symbol.arrow_clockwise');
    updateItem.label = '更新插件';
    updateItem.onAction = (): void => {
      this.runMenuAction((): void => {
        this.updateAllPlugins();
      });
    };
    const sortItem = new PluginMenuItemParams();
    sortItem.icon = $r('sys.symbol.line_3_horizontal');
    sortItem.label = '插件排序';
    sortItem.onAction = (): void => {
      this.runMenuAction((): void => {
        this.openSortSheet();
      });
    };
    const params = new PluginMenuParams();
    params.items = [updateItem, sortItem];
    this.openMenuAt(MORE_ANCHOR_ID, params);
  }

  /** 网络导入 */
  private installFromInput(): void {
    const url = this.importUrl.trim();
    if (url.length === 0) {
      this.showToast('请输入插件 URL');
      return;
    }
    if (this.installing) {
      return;
    }
    this.installing = true;
    pluginManager.installPluginFromUrl(url, appConfig.getNotCheckPluginVersion())
      .then((r: InstallPluginResult) => {
        this.installing = false;
        if (r.success) {
          this.showImportSheet = false;
          this.showToast('安装成功: ' + r.pluginName);
        } else {
          this.showToast('安装失败: ' + r.message);
        }
        this.refreshPlugins();
      })
      .catch((e: Object) => {
        this.installing = false;
        this.showToast('安装失败: ' + (e instanceof Error ? e.message : ''));
      });
  }

  /** 本地导入 */
  private pickLocalPlugin(): void {
    try {
      const ctx = ContextHolder.get();
      const documentPicker = new picker.DocumentViewPicker(ctx);
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.js'];
      documentPicker.select(options).then((uris: Array<string>) => {
        if (uris.length === 0) {
          return;
        }
        this.installLocalPlugin(uris[0]);
      }).catch((_e: Object): void => {
        this.showToast('选择文件失败');
      });
    } catch (error) {
      this.showToast('无法打开文件选择器');
    }
  }

  private installLocalPlugin(fileUriStr: string): void {
    const destPath = PathConst.cachePath + 'plugin_import_' + Date.now().toString() + '.js';
    try {
      const src = fs.openSync(fileUriStr, fs.OpenMode.READ_ONLY);
      const dst = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.copyFileSync(src.fd, dst.fd);
      fs.closeSync(src);
      fs.closeSync(dst);
    } catch (error) {
      this.showToast('读取插件文件失败');
      return;
    }
    if (this.installing) {
      return;
    }
    this.installing = true;
    pluginManager.installPluginFromLocalFile(destPath, appConfig.getNotCheckPluginVersion())
      .then((r: InstallPluginResult) => {
        this.installing = false;
        this.showToast(r.success ? '安装成功: ' + r.pluginName : '安装失败: ' + r.message);
        this.refreshPlugins();
      })
      .catch((e: Object) => {
        this.installing = false;
        this.showToast('安装失败: ' + (e instanceof Error ? e.message : ''));
      });
  }

  /** 更新全部插件 */
  private async updateAllPlugins(): Promise<void> {
    if (this.updating) {
      this.showToast('正在更新中，请稍候');
      return;
    }
    const updatables: Array<Plugin> = [];
    for (const p of pluginManager.getSortedPlugins()) {
      const srcUrl = p.instanceInfo !== null ? p.instanceInfo.srcUrl : '';
      if (srcUrl.length > 0) {
        updatables.push(p);
      }
    }
    if (updatables.length === 0) {
      this.showToast('没有可更新的插件');
      return;
    }
    this.updating = true;
    this.showToast('开始更新 ' + updatables.length.toString() + ' 个插件');
    let updated = 0;
    let failed = 0;
    for (const p of updatables) {
      try {
        await pluginManager.updatePlugin(p);
        updated++;
      } catch (e) {
        failed++;
      }
    }
    this.updating = false;
    this.refreshPlugins();
    this.showToast('更新完成：' + updated.toString() + ' 成功，' + failed.toString() + ' 失败');
  }

  /** 插件排序 */
  private openSortSheet(): void {
    const names: Array<string> = [];
    for (const p of pluginManager.getSortedPlugins()) {
      names.push(p.name);
    }
    this.sortNames = names;
    this.showSortSheet = true;
  }

  private moveSortItem(index: number, delta: number): void {
    const target = index + delta;
    if (index < 0 || index >= this.sortNames.length || target < 0 || target >= this.sortNames.length) {
      return;
    }
    const names = this.sortNames.slice();
    const tmp = names[index];
    names[index] = names[target];
    names[target] = tmp;
    this.sortNames = names;
  }

  private saveSortOrder(): void {
    const plugins: Array<Plugin> = [];
    for (const name of this.sortNames) {
      const p = pluginManager.getByName(name);
      if (p !== null) {
        plugins.push(p);
      }
    }
    pluginManager.setPluginOrder(plugins);
    this.showSortSheet = false;
    this.showToast('插件排序已保存');
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf($r('app.string.tab_plugin'), undefined, this.titleMenus()),
      isHideBackButton: true,
      scroller: this.scroller
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller }) {
          if (this.pluginRows.length > 0) {
            ForEach(this.pluginRows, (row: PluginRow, index: number) => {
              ListItem() {
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

                  if (row.name !== '本地') {
                    Toggle({ type: ToggleType.Switch, isOn: row.enabled })
                      .onChange((isOn: boolean) => {
                        this.togglePluginEnabled(row, isOn);
                      })
                  }
                }
                .width('100%')
                .height(56)
                .borderRadius(12)
                .onClick(() => {
                  this.openDetailSheet(row);
                })
              }
            }, (row: PluginRow, index: number) => row.name + '_' + row.hash + '_' + index.toString() + '_' + row.enabled.toString())
          } else {
            ListItem() {
              Text($r('app.string.home_no_plugin'))
                .fontSize(13)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ top: 32 })
            }
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .safeAreaPadding({ top: appState.topRect + 66, bottom: appState.bottomRect, left: 16, right: 16 })
        .bindSheet(!!this.showSortSheet, this.SortSheetBuilder(), {
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          dragBar: true,
          onWillDisappear: () => {
            this.showSortSheet = false;
            appState.isForegroundBlur = false
          },
          onWillAppear: () => {
            appState.isForegroundBlur = true
          }
        })

        // openMenu 锚点（位于标题栏下方右上角，菜单在锚点处弹出）
        Row({ space: 12 }) {
          Column()
            .id(ADD_ANCHOR_ID)
            .width(24)
            .height(24)
          Column()
            .id(MORE_ANCHOR_ID)
            .width(24)
            .height(24)
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: 16 })
        .margin({ top: appState.topRect + 66 })
        .bindSheet(!!this.showDetailSheet, this.DetailSheetBuilder(), {
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          dragBar: true,
          onWillDisappear: () => {
            this.showDetailSheet = false;
            appState.isForegroundBlur = false
          },
          onWillAppear: () => {
            appState.isForegroundBlur = true
          }
        })
      }
      .width('100%')
      .height('100%')
      .bindSheet(!!this.showImportSheet, this.ImportSheetBuilder(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        dragBar: true,
        onWillDisappear: () => {
          this.showImportSheet = false;
          appState.isForegroundBlur = false
        },
        onWillAppear: () => {
          appState.isForegroundBlur = true
        }
      })
    }
  }

  @Builder
  ImportSheetBuilder() {
    Column() {
      Text('网络导入插件')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 4, bottom: 16 })
      TextInput({ text: this.importUrl, placeholder: '插件 URL' })
        .width('100%')
        .height(44)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(12)
        .onChange((v: string) => {
          this.importUrl = v;
        })
        .onSubmit((_enterKey: EnterKeyType) => {
          this.installFromInput();
        })
      Button(this.installing ? '安装中...' : '安装')
        .width('100%')
        .height(42)
        .fontSize(15)
        .margin({ top: 20 })
        .backgroundColor($r('sys.color.background_emphasize'))
        .onClick(() => {
          this.installFromInput();
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SortSheetBuilder() {
    Column() {
      Text('插件排序')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 4, bottom: 8 })
      List() {
        ForEach(this.sortNames, (name: string, index: number) => {
          ListItem() {
            Row({ space: 12 }) {
              Text((index + 1).toString())
                .fontSize(13)
                .fontColor($r('sys.color.font_tertiary'))
                .width(20)
                .textAlign(TextAlign.Center)
              Text(name)
                .fontSize(15)
                .fontColor($r('sys.color.font_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.chevron_up'))
                .fontSize(18)
                .fontColor([$r('sys.color.icon_secondary')])
                .onClick(() => {
                  this.moveSortItem(index, -1);
                })
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(18)
                .fontColor([$r('sys.color.icon_secondary')])
                .onClick(() => {
                  this.moveSortItem(index, 1);
                })
            }
            .width('100%')
            .height(52)
          }
        }, (name: string, index: number) => name + '_' + index.toString())
      }
      .width('100%')
      .layoutWeight(1)
      .margin({ top: 4 })
      Button('保存排序')
        .width('100%')
        .height(42)
        .fontSize(15)
        .margin({ top: 12 })
        .backgroundColor($r('sys.color.background_emphasize'))
        .onClick(() => {
          this.saveSortOrder();
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  DetailSheetBuilder() {
    Column() {
      // 头部：名字 + 版本 + 作者
      Text(this.detailName)
        .fontSize(19)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 4 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text((this.detailVersion.length > 0 ? 'v' + this.detailVersion : '') +
        (this.detailAuthor.length > 0 ? ' · ' + this.detailAuthor : ''))
        .fontSize(12)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
        .margin({ top: 4 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // 使用说明（点击弹窗显示）
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.info_circle'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
        Text('使用说明')
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('sys.color.icon_tertiary')])
      }
      .width('100%')
      .height(48)
      .margin({ top: 8 })
      .onClick(() => {
        this.showUsageDialog();
      })

      // 配置：用户变量（点击弹窗统一填写）
      if (this.detailVars.length > 0) {
        Text('配置')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .margin({ top: 20, bottom: 6 })
        Row({ space: 8 }) {
          Text('变量')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('sys.color.icon_tertiary')])
        }
        .width('100%')
        .height(44)
        .onClick(() => {
          this.openVarDialog();
        })
      }

      // 操作
      Text('操作')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .margin({ top: 20, bottom: 4 })
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
        Text('检查更新')
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(48)
      .onClick(() => {
        this.checkDetailUpdate();
      })
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.share'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
        Text('分享源地址')
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        if (this.detailSrcUrl.length > 0) {
          Text(this.detailSrcUrl)
            .fontSize(11)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '45%' })
        }
      }
      .width('100%')
      .height(48)
      .onClick(() => {
        this.shareDetailSrc();
      })
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
        Text('卸载插件')
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(48)
      .onClick(() => {
        this.uninstallDetail();
      })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }
}
