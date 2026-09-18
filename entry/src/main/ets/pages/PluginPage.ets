import { pluginManager } from '../plugin/PluginManager';
import { Plugin } from '../plugin/Plugin';
import { PluginState } from '../plugin/PluginTypes';
import { PluginInstanceInfo } from '../plugin/PluginTypes';
import { InstallPluginResult } from '../plugin/PluginTypes';
import { musicSheet } from '../core/MusicSheet';
import { MusicItem } from '../common/model/MediaTypes';
import { SheetItem, SheetInfoResult } from '../common/model/SheetTypes';
import { appConfig } from '../core/AppConfig';
import { CommonNav, titleBarOf } from '../view/CommonNav';
import { appState } from '../entryability/AppState';
import { HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { CommonBlur, MenuItemParams } from '../view/CommonCom';
import { MenuUtils } from '../utils/MenuUtils';
import { BarScrollHelper, IsApiVersion_24 } from '../utils/BarScrollHelper';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { ContextHolder } from '../common/ContextHolder';
import { PathConst } from '../common/PathConst';
import { FileUtils } from '../utils/FileUtils';
import { JsonUtil } from '../common/JsonUtil';
import { DialogManager, PluginVarField } from '../utils/DialogUtils';
import { PluginImport } from '../plugin/PluginImport';
import { Subscriptions } from '../plugin/Subscriptions';

interface PluginRow {
  name: string;
  version: string;
  author: string;
  state: PluginState;
  hash: string;
  enabled: boolean;
}

const ADD_ANCHOR_ID = 'plugin_add_anchor';
const MORE_ANCHOR_ID = 'plugin_more_anchor';

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
  @Local detailAbilities: string = '';
  @Local detailVars: Array<PluginVarField> = [];
  /** 插件内导入半模态（详情 sheet 内嵌套，固定来源为当前详情插件） */
  @Local showPluginImportSheet: boolean = false;
  @Local pluginImportSingleMode: boolean = false;
  @Local pluginImportUrl: string = '';
  @Local pluginImporting: boolean = false;
  @Local pluginImportTargetSheetIds: Array<string> = [];
  @Local pluginImportTargetSheetTitles: Array<string> = [];
  @Local pluginImportTargetIndex: number = 0;
  /** 说明文本刷新标记：懒加载插件挂载完成后 +1 触发重绘 */
  @Local pluginImportHintRev: number = 0;
  @Local batchSelected: Array<string> = [];
  private detailHash: string = '';
  /** 是否正在同步订阅源 */
  private syncingSubscriptions: boolean = false;

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
      this.detailUsage = info.description.trim().length > 0 ? info.description : '该插件未提供使用说明。';
      this.detailAbilities = PluginPage.usageText(info);
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
      this.detailUsage = '插件尚未挂载，暂时无法获取使用说明。';
      this.detailAbilities = '插件尚未挂载，暂时无法获取能力信息。';
    }
    this.detailVars = fields;
    this.showDetailSheet = true;
    // 懒加载插件：挂载完成后用新实例信息刷新详情
    if (plugin !== null && plugin.state === PluginState.Initializing) {
      plugin.ensureMounted().then((): void => {
        if (this.detailName === row.name) {
          this.openDetailSheet(row);
        }
      }).catch((_e: Object): void => {
      });
    }
  }

  /** 使用说明弹窗 */
  private showUsageDialog(): void {
    let message = this.detailUsage;
    if (this.detailVars.length > 0) {
      message += '\n\n部分功能需要在「配置」中填写变量后使用。';
    }
    DialogManager.usageTitle = this.detailName + ' 使用说明';
    DialogManager.usageMessage = message;
    DialogManager.OpenDialog('使用说明');
  }

  /** 支持能力弹窗 */
  private showAbilitiesDialog(): void {
    DialogManager.usageTitle = this.detailName + ' 支持能力';
    DialogManager.usageMessage = this.detailAbilities;
    DialogManager.OpenDialog('使用说明');
  }

  /** 当前详情插件是否支持指定方法 */
  private detailHasMethod(method: string): boolean {
    const plugin = pluginManager.getByName(this.detailName);
    return plugin !== null && plugin.hasMethod(method);
  }

  /** 打开插件内导入半模态（单曲/歌单，来源固定为当前详情插件） */
  private openPluginImportSheet(singleMode: boolean): void {
    const method: string = singleMode ? 'importMusicItem' : 'importMusicSheet';
    const plugin = pluginManager.getByName(this.detailName);
    if (plugin === null || !plugin.hasMethod(method)) {
      this.showToast('该插件不支持此功能');
      return;
    }
    this.pluginImportSingleMode = singleMode;
    if (singleMode) {
      const ids: Array<string> = [];
      const titles: Array<string> = [];
      for (const sheet of musicSheet.sheets) {
        ids.push(sheet.id);
        titles.push(sheet.title);
      }
      this.pluginImportTargetSheetIds = ids;
      this.pluginImportTargetSheetTitles = titles;
      this.pluginImportTargetIndex = ids.length > 0 ? 0 : -1;
    }
    this.pluginImportUrl = '';
    this.pluginImporting = false;
    this.showPluginImportSheet = true;
    // 懒加载插件：挂载完成后 hints 才可用，刷新说明文本
    if (plugin.state === PluginState.Initializing) {
      plugin.ensureMounted().then((): void => {
        this.pluginImportHintRev++;
      }).catch((_e: Object): void => {
      });
    }
  }

  /** 导入单曲目标歌单 Select 选项 */
  private pluginImportTargetOptions(): Array<SelectOption> {
    const opts: Array<SelectOption> = [];
    for (const title of this.pluginImportTargetSheetTitles) {
      opts.push({ value: title });
    }
    if (opts.length === 0) {
      opts.push({ value: '暂无可加入的歌单' });
    }
    return opts;
  }

  /** 导入单曲目标歌单 Select 当前展示值 */
  private selectedPluginImportTargetName(): string {
    if (this.pluginImportTargetIndex >= 0 && this.pluginImportTargetIndex < this.pluginImportTargetSheetTitles.length) {
      return this.pluginImportTargetSheetTitles[this.pluginImportTargetIndex];
    }
    return '暂无可加入的歌单';
  }

  /** 导入说明：与 RN 原版一致，取插件 hints（string[]），逐条 ￮ 前缀显示；未提供则不显示 */
  private pluginImportHint(): string {
    const plugin = pluginManager.getByName(this.detailName);
    if (plugin !== null && plugin.instanceInfo !== null && plugin.instanceInfo.hints !== null) {
      const arr = JsonUtil.recArray(plugin.instanceInfo.hints,
        this.pluginImportSingleMode ? 'importMusicItem' : 'importMusicSheet');
      if (arr !== null) {
        const parts: Array<string> = [];
        for (const it of arr) {
          if (typeof it === 'string' && it.length > 0) {
            parts.push('· ' + it);
          }
        }
        return parts.join('\n');
      }
    }
    return '';
  }

  /** 确认插件内导入：歌单 → 建新歌单（原歌单名）并写入全部歌曲；单曲 → 导入后加入所选歌单 */
  private confirmPluginImport(): void {
    if (this.pluginImporting) {
      return;
    }
    const plugin = pluginManager.getByName(this.detailName);
    if (plugin === null) {
      this.showToast('插件不存在');
      return;
    }
    if (this.pluginImportSingleMode &&
      (this.pluginImportTargetSheetIds.length === 0 || this.pluginImportTargetIndex < 0 ||
        this.pluginImportTargetIndex >= this.pluginImportTargetSheetIds.length)) {
      this.showToast('暂无可加入的歌单');
      return;
    }
    const url = this.pluginImportUrl.trim();
    if (url.length === 0) {
      this.showToast(this.pluginImportSingleMode ? '请输入目标歌曲' : '请输入目标歌单');
      return;
    }
    this.pluginImporting = true;
    if (this.pluginImportSingleMode) {
      const targetId = this.pluginImportTargetSheetIds[this.pluginImportTargetIndex];
      const targetTitle = this.pluginImportTargetSheetTitles[this.pluginImportTargetIndex];
      plugin.methods.importMusicItem(url).then((item: MusicItem | null): void => {
        this.pluginImporting = false;
        if (item === null) {
          this.showToast('导入歌曲失败');
          return;
        }
        musicSheet.addMusic(targetId, item).then((): void => {
          this.showPluginImportSheet = false;
          this.showToast('已将「' + item.title + '」加入「' + targetTitle + '」');
        }).catch((_e: Object): void => {
          this.showToast('加入歌单失败');
        });
      }).catch((_e: Object): void => {
        this.pluginImporting = false;
        this.showToast('导入歌曲失败');
      });
    } else {
      plugin.methods.importMusicSheet(url).then((items: Array<MusicItem>): void => {
        if (items.length === 0) {
          this.pluginImporting = false;
          this.showToast('链接有误或目标歌单为空');
          return;
        }
        this.resolvePluginImportTitle(plugin).then((title: string): Promise<string> => {
          return musicSheet.addSheet(title);
        }).then((sheetId: string): Promise<void> => {
          return musicSheet.addMusic(sheetId, items);
        }).then((): void => {
          this.pluginImporting = false;
          this.showPluginImportSheet = false;
          this.showToast('已导入 ' + items.length.toString() + ' 首歌曲');
        }).catch((_e: Object): void => {
          this.pluginImporting = false;
          this.showToast('创建歌单失败');
        });
      }).catch((_e: Object): void => {
        this.pluginImporting = false;
        this.showToast('导入歌单失败');
      });
    }
  }

  /** 解析导入歌单标题：优先 getMusicSheetInfo 取原歌单名，失败回退「导入歌单(插件名)」 */
  private resolvePluginImportTitle(plugin: Plugin): Promise<string> {
    const fallback = '导入歌单(' + plugin.name + ')';
    if (!plugin.hasMethod('getMusicSheetInfo')) {
      return Promise.resolve(fallback);
    }
    const query = new SheetItem();
    query.id = this.pluginImportUrl.trim();
    query.platform = plugin.name;
    query.title = this.pluginImportUrl.trim();
    return plugin.methods.getMusicSheetInfo(query, 1).then((info: SheetInfoResult | null): string => {
      if (info !== null && info.sheetItem !== null && info.sheetItem.title.trim().length > 0) {
        return info.sheetItem.title.trim();
      }
      return fallback;
    }).catch((_e: Object): string => {
      return fallback;
    });
  }

  /** 打开变量编辑弹窗（所有变量在同一个弹窗填写） */
  private openVarDialog(): void {
    DialogManager.varPluginName = this.detailName;
    DialogManager.varFields = this.detailVars;
    DialogManager.OpenDialog('配置变量');
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

  /** 导出单个插件文件到 下载目录/插件 文件夹 */
  private exportPluginFile(plugin: Plugin): boolean {
    if (plugin.path.length === 0 || !FileUtils.exists(plugin.path)) {
      return false;
    }
    // downloadPath 可能无结尾斜杠（公共目录），先补齐再拼接，避免目录名黏连
    const base = PathConst.downloadPath.endsWith('/') ? PathConst.downloadPath : PathConst.downloadPath + '/';
    const destPath = base + '插件/' + FileUtils.escapeCharacter(plugin.name) + '.js';
    return FileUtils.copyFile(plugin.path, destPath);
  }

  /** 导出当前详情插件文件 */
  private exportDetailFile(): void {
    if (this.detailName === '本地') {
      this.showToast('内置插件无法导出');
      return;
    }
    const plugin = pluginManager.getByName(this.detailName);
    if (plugin === null) {
      this.showToast('插件不存在');
      return;
    }
    if (this.exportPluginFile(plugin)) {
      this.showToast('已导出到 下载目录/插件 文件夹');
    } else {
      this.showToast('插件文件不存在或导出失败');
    }
  }

  /** 进入批量模式（全局状态：隐藏 tab 栏、返回键退出；显式动画包裹避免突兀） */
  private enterBatchMode(): void {
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      appState.isBatchMode = true;
    });
    this.batchSelected = [];
  }

  /** 退出批量模式 */
  private exitBatchMode(): void {
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      appState.isBatchMode = false;
    });
    this.batchSelected = [];
  }

  /** 行是否被勾选 */
  private isSelected(row: PluginRow): boolean {
    return this.batchSelected.indexOf(row.hash) !== -1;
  }

  /** 批量模式下点击行：切换勾选状态 */
  private toggleBatchSelect(row: PluginRow): void {
    if (row.name === '本地') {
      this.showToast('内置插件不支持批量操作');
      return;
    }
    const next = this.batchSelected.slice();
    const idx = next.indexOf(row.hash);
    if (idx === -1) {
      next.push(row.hash);
    } else {
      next.splice(idx, 1);
    }
    this.batchSelected = next;
  }

  /** 全选/取消全选（不含内置插件） */
  private toggleSelectAll(): void {
    const all: Array<string> = [];
    for (const row of this.pluginRows) {
      if (row.name !== '本地') {
        all.push(row.hash);
      }
    }
    // 已全部勾选时再次点击则清空
    this.batchSelected = this.batchSelected.length === all.length ? [] : all;
  }

  /** 批量操作按钮文案（全部勾选后「全选」切换为「取消全选」） */
  private batchButtonLabels(): Array<string> {
    let selectable = 0;
    for (const row of this.pluginRows) {
      if (row.name !== '本地') {
        selectable++;
      }
    }
    const allSelected = selectable > 0 && this.batchSelected.length === selectable;
    return [allSelected ? '取消全选' : '全选', '导出', '分享', '删除'];
  }

  /** 勾选的插件实体列表 */
  private selectedPlugins(): Array<Plugin> {
    const result: Array<Plugin> = [];
    for (const hash of this.batchSelected) {
      const p = pluginManager.getByHash(hash);
      if (p !== null) {
        result.push(p);
      }
    }
    return result;
  }

  /** 批量导出选中插件文件 */
  private batchExport(): void {
    const plugins = this.selectedPlugins();
    if (plugins.length === 0) {
      this.showToast('请先勾选插件');
      return;
    }
    let ok = 0;
    let fail = 0;
    for (const p of plugins) {
      if (this.exportPluginFile(p)) {
        ok++;
      } else {
        fail++;
      }
    }
    if (fail === 0) {
      this.showToast('已导出 ' + ok.toString() + ' 个插件文件');
    } else {
      this.showToast('导出完成：' + ok.toString() + ' 成功，' + fail.toString() + ' 失败');
    }
  }

  /** 批量分享：复制选中插件的源地址 */
  private batchShare(): void {
    const plugins = this.selectedPlugins();
    const urls: Array<string> = [];
    for (const p of plugins) {
      const srcUrl = p.instanceInfo !== null ? p.instanceInfo.srcUrl : '';
      if (srcUrl.length > 0) {
        urls.push(srcUrl);
      }
    }
    if (urls.length === 0) {
      this.showToast('选中插件没有源地址');
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, urls.join('\n'));
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      this.showToast('已复制 ' + urls.length.toString() + ' 个源地址，可粘贴分享');
    }).catch((_e: Object): void => {
      this.showToast('复制失败');
    });
  }

  /** 批量卸载选中插件 */
  private async batchUninstall(): Promise<void> {
    const plugins = this.selectedPlugins();
    if (plugins.length === 0) {
      this.showToast('请先勾选插件');
      return;
    }
    let ok = 0;
    let fail = 0;
    for (const p of plugins) {
      try {
        await pluginManager.uninstallPlugin(p.hash);
        ok++;
      } catch (e) {
        fail++;
      }
    }
    this.exitBatchMode();
    this.refreshPlugins();
    this.showToast('已卸载 ' + ok.toString() + ' 个插件' +
      (fail > 0 ? '，' + fail.toString() + ' 个失败' : ''));
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
    MenuUtils.Dismiss();
    action();
  }

  private openAddMenu(): void {
    const netItem = new MenuItemParams();
    netItem.icon = $r('sys.symbol.dot_radiowaves_left_and_right');
    netItem.label = '网络导入';
    netItem.onAction = (): void => {
      this.runMenuAction((): void => {
        this.importUrl = '';
        this.showImportSheet = true;
      });
    };
    const localItem = new MenuItemParams();
    localItem.icon = $r('sys.symbol.folder');
    localItem.label = '本地导入';
    localItem.onAction = (): void => {
      this.runMenuAction((): void => {
        this.pickLocalPlugin();
      });
    };
    MenuUtils.Open(this.getUIContext(), ADD_ANCHOR_ID, [netItem, localItem], {
      placement: Placement.BottomRight
    });
  }

  private openMoreMenu(): void {
    const updateItem = new MenuItemParams();
    updateItem.icon = $r('sys.symbol.arrow_clockwise');
    updateItem.label = '更新插件';
    updateItem.onAction = (): void => {
      this.runMenuAction((): void => {
        this.updateAllPlugins();
      });
    };
    const sortItem = new MenuItemParams();
    sortItem.icon = $r('sys.symbol.line_3_horizontal');
    sortItem.label = '插件排序';
    sortItem.onAction = (): void => {
      this.runMenuAction((): void => {
        this.openSortSheet();
      });
    };
    const syncSubItem = new MenuItemParams();
    syncSubItem.icon = $r('sys.symbol.dot_radiowaves_left_and_right');
    syncSubItem.label = '同步订阅源';
    syncSubItem.onAction = (): void => {
      this.runMenuAction((): void => {
        this.syncSubscriptions();
      });
    };
    const batchItem = new MenuItemParams();
    batchItem.icon = $r('sys.symbol.checkmark_square');
    batchItem.label = '批量操作';
    batchItem.onAction = (): void => {
      this.runMenuAction((): void => {
        this.enterBatchMode();
      });
    };
    MenuUtils.Open(this.getUIContext(), MORE_ANCHOR_ID, [updateItem, sortItem, syncSubItem, batchItem], {
      placement: Placement.BottomRight
    });
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

  /** 本地导入（支持批量选择，最多 20 个） */
  private pickLocalPlugin(): void {
    try {
      const ctx = ContextHolder.get();
      const documentPicker = new picker.DocumentViewPicker(ctx);
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 20;
      options.fileSuffixFilters = ['.js'];
      documentPicker.select(options).then((uris: Array<string>) => {
        if (uris.length === 0) {
          return;
        }
        this.installLocalPlugins(uris);
      }).catch((_e: Object): void => {
        this.showToast('选择文件失败');
      });
    } catch (error) {
      this.showToast('无法打开文件选择器');
    }
  }

  /** 批量安装本地插件文件：逐个导入并汇总结果 */
  private async installLocalPlugins(uris: Array<string>): Promise<void> {
    if (this.installing) {
      return;
    }
    this.installing = true;
    this.showToast('开始导入 ' + uris.length.toString() + ' 个插件');
    const summary = await PluginImport.installLocalJsFiles(uris);
    this.installing = false;
    this.refreshPlugins();
    if (summary.failed === 0) {
      this.showToast('成功导入 ' + summary.success.toString() + ' 个插件');
    } else {
      this.showToast('导入完成：' + summary.success.toString() + ' 成功，' + summary.failed.toString() + ' 失败' +
        (summary.lastMessage.length > 0 ? '（' + summary.lastMessage + '）' : ''));
    }
  }

  /** 同步全部订阅源：安装/更新其中的插件 */
  private async syncSubscriptions(): Promise<void> {
    if (this.syncingSubscriptions) {
      this.showToast('正在同步中，请稍候');
      return;
    }
    this.syncingSubscriptions = true;
    this.showToast('开始同步订阅源');
    const message = await Subscriptions.syncAll();
    this.syncingSubscriptions = false;
    this.refreshPlugins();
    this.showToast(message);
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

  /** 打开「跳转排序」弹窗：将当前条目直接移动到输入的序号位置 */
  private openSortJump(index: number): void {
    DialogManager.sortJumpValue = (index + 1).toString();
    DialogManager.sortJumpMax = this.sortNames.length;
    DialogManager.sortJumpConfirm = (target: number): void => {
      this.moveSortItemTo(index, target);
    };
    DialogManager.OpenDialog('跳转排序');
  }

  /** 将排序条目从 from 移动到 to（0 基索引） */
  private moveSortItemTo(from: number, to: number): void {
    if (from === to || from < 0 || from >= this.sortNames.length ||
      to < 0 || to >= this.sortNames.length) {
      return;
    }
    const names = this.sortNames.slice();
    const item = names.splice(from, 1)[0];
    names.splice(to, 0, item);
    this.sortNames = names;
    this.showToast('已移动到第 ' + (to + 1).toString() + ' 位');
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
      titleBarOp: titleBarOf($r('app.string.tab_plugin'), '共 ' + this.pluginRows.length.toString() + ' 个插件', this.titleMenus()),
      isHideBackButton: true,
      scroller: this.scroller,
      doubleTapToTop: true,
    }) {
      Stack({ alignContent: Alignment.Top }) {
          List({ scroller: this.scroller, space: 16 }) {
          if (this.pluginRows.length > 0) {
            ForEach(this.pluginRows, (row: PluginRow, index: number) => {
              ListItem() {
                Row({ space: 12 }) {
                  // 批量模式：勾选圈
                  if (appState.isBatchMode && row.name !== '本地') {
                    SymbolGlyph(this.isSelected(row) ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
                      .fontSize(24)
                      .fontColor([this.isSelected(row) ? $r('sys.color.icon_emphasize') : $r('sys.color.icon_tertiary')])
                      .transition(TransitionEffect.OPACITY)
                  }
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

                  if (!appState.isBatchMode && row.name !== '本地') {
                    Toggle({ type: ToggleType.Switch, isOn: row.enabled })
                      .onChange((isOn: boolean) => {
                        this.togglePluginEnabled(row, isOn);
                      })
                  }
                }
                .width('100%')
                .height(56)
                .borderRadius(12)
                .gesture(
                  LongPressGesture({ repeat: false, duration: 500 })
                    .onAction((_event: GestureEvent) => {
                      // 长按进入批量模式并勾选当前条目（内置插件仅进入批量模式）
                      if (appState.isBatchMode) {
                        return;
                      }
                      this.enterBatchMode();
                      this.toggleBatchSelect(row);
                    })
                )
              }.ListItemStyle()
              .onClick(() => {
                if (appState.isBatchMode) {
                  this.toggleBatchSelect(row);
                } else {
                  this.openDetailSheet(row);
                }
              })
            }, (row: PluginRow, index: number) => row.name + '_' + row.hash + '_' + index.toString() + '_' + row.enabled.toString() +
              (appState.isBatchMode && this.isSelected(row) ? '_sel' : ''))
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
        .ListStyle()
        .onScrollFrameBegin((offset: number) => {
          BarScrollHelper.notifyScrollDelta(this.getUIContext(), offset)
          return { offsetRemain: offset }
        })
        .bindSheet(!!this.showSortSheet, this.SortSheetBuilder(), {
          scrollSizeMode: ScrollSizeMode.CONTINUOUS, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          dragBar: true,
          onWillDisappear: () => {
            this.showSortSheet = false;
            appState.isForegroundBlur = false
          },
          onWillAppear: () => {
            appState.isForegroundBlur = true
          }
        })

        // 底部批量模式时的渐变模糊组件
        // 批量模式底栏（透明悬浮于列表之上，列表底部渐变模糊）：全选 / 导出 / 分享 / 删除
        if (appState.isBatchMode) {
          CommonBlur().position({ bottom: 0 })
            .transition(TransitionEffect.OPACITY)

          Column({ space: 10 }) {
            Row() {
              Text('已选 ' + this.batchSelected.length.toString() + ' 个插件')
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
              Blank()
              Text('取消')
                .fontSize(16)
                .fontColor($r('sys.color.font_secondary'))
                .onClick(() => {
                  this.exitBatchMode();
                })
            }
            .width('100%')

            Row({ space: 8 }) {
              ForEach(this.batchButtonLabels(), (v: string, i: number) => {
                Button(v)
                  .layoutWeight(1)
                  .height(36)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .borderRadius(10)
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  .fontColor($r('sys.color.font_primary'))
                  .onClick(() => {
                    if (i === 0) {// 全选/取消全选
                      this.toggleSelectAll();
                    } else if (i === 1) {// 导出
                      this.batchExport();
                    } else if (i === 2) {// 分享
                      this.batchShare();
                    } else {// 删除
                      this.batchUninstall();
                    }
                  })
              }, (v: string, i: number) => v + '_' + i.toString())
            }
            .width('100%')
          }
          .width('100%')
          .position({ bottom: 0 })
          .padding({ top: 14, left: 16, right: 16, bottom: appState.bottomRect + 12 })
          .transition(TransitionEffect.OPACITY)
        }

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
        .margin({ top: appState.topRect + 20 })
        .bindSheet(!!this.showDetailSheet, this.DetailSheetBuilder(), {
          scrollSizeMode: ScrollSizeMode.CONTINUOUS, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
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
        scrollSizeMode: ScrollSizeMode.CONTINUOUS, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
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

              ForEach([$r('sys.symbol.chevron_up'), $r('sys.symbol.chevron_down'), $r('sys.symbol.arrow_left_arrow_right')],(v: Resource, i: number)=>{
                SymbolGlyph(v)
                  .fontSize(18)
                  .fontColor([$r('sys.color.icon_secondary')])
                  .onClick(() => {
                    if (i === 0) {// 上移
                      this.moveSortItem(index, -1);
                    }else if (i === 1) {// 下移
                      this.moveSortItem(index, 1);
                    }else{// 跳转
                      this.openSortJump(index);
                    }
                  })
              })
            }
            .width('100%')
            .height(52)
          }
        }, (name: string, index: number) => name + '_' + index.toString())
      }
      .divider({
        strokeWidth: 0.5,
        color: $r('sys.color.comp_divider'),
      })
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
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
        .margin({ top: 4, bottom: 12 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // 支持能力 / 使用说明（点击弹窗显示）
      Column() {
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
          Text('支持能力')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('sys.color.icon_tertiary')])
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.showAbilitiesDialog();
        })

        Divider().DividerStyle()
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
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.showUsageDialog();
        })
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor($r('sys.color.comp_background_list_card'))

      // 配置：用户变量（点击弹窗统一填写）
      if (this.detailVars.length > 0) {
        Text('配置')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .margin({ top: 20, bottom: 6 })
        Column() {
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.highlighter_line'))
              .fontSize(20)
              .fontColor([$r('sys.color.icon_secondary')])
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
          .padding({ left: 16, right: 16 })
          .onClick(() => {
            this.openVarDialog();
          })
        }
        .width('100%')
        .borderRadius(16)
        .backgroundColor($r('sys.color.comp_background_list_card'))
      }

      // 功能：插件支持的导入入口（单曲 → 加入所选歌单；歌单 → 建新歌单）
      if (this.detailHasMethod('importMusicItem') || this.detailHasMethod('importMusicSheet')) {
        Text('功能')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .margin({ top: 20, bottom: 6 })
        Column() {
          if (this.detailHasMethod('importMusicItem')) {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.music'))
                .fontSize(20)
                .fontColor([$r('sys.color.icon_secondary')])
              Text('导入单曲')
                .fontSize(15)
                .fontColor($r('sys.color.font_primary'))
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(16)
                .fontColor([$r('sys.color.icon_tertiary')])
            }
            .width('100%')
            .height(48)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.openPluginImportSheet(true);
            })
          }
          if (this.detailHasMethod('importMusicItem') && this.detailHasMethod('importMusicSheet')) {
            Divider().DividerStyle()
          }
          if (this.detailHasMethod('importMusicSheet')) {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
                .fontSize(20)
                .fontColor([$r('sys.color.icon_secondary')])
              Text('导入歌单')
                .fontSize(15)
                .fontColor($r('sys.color.font_primary'))
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(16)
                .fontColor([$r('sys.color.icon_tertiary')])
            }
            .width('100%')
            .height(48)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.openPluginImportSheet(false);
            })
          }
        }
        .width('100%')
        .borderRadius(16)
        .backgroundColor($r('sys.color.comp_background_list_card'))
      }

      // 操作分组：检查更新 / 分享源地址 / 卸载插件（卡片内以分割线隔开）
      Text('操作')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .margin({ top: 20, bottom: 6 })
      Column() {
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
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.checkDetailUpdate();
        })

        Divider()
          .DividerStyle()
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
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.shareDetailSrc();
        })

        Divider().DividerStyle()
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
          Text('导出插件文件')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.exportDetailFile();
        })

        Divider().DividerStyle()
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
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.uninstallDetail();
        })
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor($r('sys.color.comp_background_list_card'))
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 32 })
    .alignItems(HorizontalAlign.Start)
    .bindSheet(!!this.showPluginImportSheet, this.PluginImportSheetBuilder(), {
      scrollSizeMode: ScrollSizeMode.CONTINUOUS, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      onWillDisappear: () => {
        this.showPluginImportSheet = false;
      }
    })
  }

  /** 插件内导入半模态：来源固定为当前详情插件（不选插件），单曲需选目标歌单 */
  @Builder
  PluginImportSheetBuilder() {
    Column() {
      Text(this.pluginImportSingleMode ? '导入单曲' : '导入歌单')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 4, bottom: 4 })
      Text('来源插件：' + this.detailName)
        .fontSize(13)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
        .margin({ bottom: 12 })
      if (this.pluginImportSingleMode) {
        Text('加入歌单')
          .fontSize(13)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .margin({ bottom: 8 })
        Select(this.pluginImportTargetOptions())
          .selected(this.pluginImportTargetIndex)
          .value(this.selectedPluginImportTargetName())
          .font({ size: 14 })
          .fontColor($r('sys.color.font_primary'))
          .selectedOptionFont({ size: 14 })
          .optionFont({ size: 14 })
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .borderRadius(12)
          .height(44)
          .width('100%')
          .onSelect((index: number, _text: string) => {
            if (this.pluginImportTargetSheetIds.length > 0) {
              this.pluginImportTargetIndex = index;
            }
          })
      }
      TextInput({
        text: this.pluginImportUrl,
        placeholder: this.pluginImportSingleMode ? '输入目标歌曲' : '输入目标歌单'
      })
        .width('100%')
        .height(44)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(12)
        .margin({ top: 12 })
        .onChange((v: string) => {
          this.pluginImportUrl = v;
        })
        .onSubmit((_enterKey: EnterKeyType) => {
          this.confirmPluginImport();
        })
      Button(this.pluginImporting ? '导入中...' : '导入')
        .width('100%')
        .height(42)
        .fontSize(15)
        .margin({ top: 20 })
        .backgroundColor($r('sys.color.background_emphasize'))
        .onClick(() => {
          this.confirmPluginImport();
        })
      if (this.pluginImportHint().length > 0) {
        Text(this.pluginImportHint())
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .margin({ top: 16 })
          .lineHeight(18)
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }
}

@Extend(ListItem)
function ListItemStyle(){
  .width('100%')
  .borderRadius(16)
  .padding(12)
  .backgroundColor($r('sys.color.comp_background_list_card'))
}

@Extend(List)
function ListStyle(){
  .width('100%')
  .height('100%')
  .scrollBar(BarState.Off)
  .edgeEffect(EdgeEffect.Spring)
  .contentStartOffset(appState.topRect + 66)
  // 批量模式/上下两排时底栏更高，末尾内容需多留滚动空间
  .contentEndOffset(appState.bottomRect + (appState.isBatchMode ? 170 :
    (IsApiVersion_24() && appState.hdsBarLayoutMode === 1 ? 130 : 60)))
  .padding({ left: 16, right: 16 })
}

@Extend(Divider)
function DividerStyle(){
  .color($r('sys.color.comp_divider'))
  .margin({ left: 48, right: 12 })
}