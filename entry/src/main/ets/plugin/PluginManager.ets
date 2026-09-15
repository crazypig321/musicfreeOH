import { KVStore } from '../infra/KVStore';
import { JsonUtil, JsonRecord } from '../common/JsonUtil';
import { PathConst } from '../common/PathConst';
import { LOCAL_PLUGIN_HASH, LOCAL_PLUGIN_PLATFORM } from '../common/Consts';
import { FileUtils } from '../utils/FileUtils';
import { CryptoUtil } from '../utils/CryptoUtil';
import { HttpClient } from '../infra/HttpClient';
import { Delay } from '../utils/Delay';
import { Log } from '../utils/Log';
import { EventEmitter, EventListenerFn } from '../common/EventBus';
import { MusicItem } from '../model/MediaTypes';
import { SupportMediaType } from '../model/SheetTypes';
import { appConfig } from '../core/AppConfig';
import { MediaExtra } from '../core/MediaExtra';
import { Plugin } from './Plugin';
import { PluginState } from './PluginTypes';
import { InstallPluginResult, LazyProps } from './PluginTypes';
import { PluginMeta } from './PluginMeta';
import { LocalPluginExecutor } from './LocalPluginExecutor';
import { WebPluginExecutor } from './WebPluginExecutor';
import { VersionCompare } from '../utils/VersionCompare';

/** 顺序更新事件 */
export class PluginOrderUpdatedEvent {
}

/** 启用状态更新事件 */
export class PluginEnabledUpdatedEvent {
  pluginName: string = '';
  enabled: boolean = false;
}

/**
 * 插件管理器（移植自 pluginManager/index.ts）
 */
export class PluginManager {
  private plugins: Array<Plugin> = new Array<Plugin>();
  private localFilePlugin: Plugin | null = null;
  private ee: EventEmitter = new EventEmitter();

  private static pluginCacheStore(): KVStore {
    return KVStore.getOrCreate('plugin.cache');
  }

  /**
   * 初始化插件管理器：加载插件目录中的所有插件
   */
  async setup(): Promise<void> {
    try {
      // 本地文件插件
      this.localFilePlugin = await Plugin.createNative(
        LocalPluginExecutor.instance, 'internal-plugin://local-file-plugin', LOCAL_PLUGIN_HASH);

      const names = FileUtils.listDir(PathConst.pluginPath);
      const allPlugins: Array<Plugin> = [];
      const cacheStore = PluginManager.pluginCacheStore();
      for (let i = 0; i < names.length; ++i) {
        const name = names[i];
        if (!name.endsWith('.js')) {
          continue;
        }
        const pluginFilePath = PathConst.pluginPath + name;
        Log.info('初始化插件 ' + pluginFilePath);
        let plugin: Plugin;
        let isLazyLoad = false;
        if (appConfig.getLazyLoadPlugin() && cacheStore.contains(pluginFilePath)) {
          isLazyLoad = true;
          const lazyProps = LazyProps.fromRecord(JsonUtil.parseRecord(cacheStore.get(pluginFilePath)) ?? {});
          lazyProps.path = pluginFilePath;
          lazyProps.loadFuncCode = (): Promise<string> => {
            const content = FileUtils.readFileText(pluginFilePath);
            return Promise.resolve(content === null ? '' : content);
          };
          plugin = Plugin.createLazy(lazyProps, WebPluginExecutor.getInstance());
        } else {
          const content = FileUtils.readFileText(pluginFilePath);
          const funcCode = content === null ? '' : content;
          plugin = await Plugin.create(funcCode, pluginFilePath, WebPluginExecutor.getInstance());
        }

        if (plugin.hash.length > 0) {
          let dup = false;
          for (const p of allPlugins) {
            if (p.hash === plugin.hash) {
              dup = true;
              break;
            }
          }
          if (dup) {
            // 重复插件，直接忽略
            continue;
          }
        }
        if (plugin.state === PluginState.Mounted || isLazyLoad) {
          allPlugins.push(plugin);
        }
      }

      this.setPlugins(allPlugins);
      // 延迟初始化懒加载插件（必须 catch，否则未处理拒绝会导致 jscrash）
      Delay.wait(10000).then(async (): Promise<void> => {
        for (const plugin of allPlugins) {
          if (plugin.state === PluginState.Initializing) {
            await plugin.ensureMounted();
            this.updatePluginCache(plugin);
          }
        }
      }).catch((e: Object): void => {
        Log.error('懒加载插件延迟初始化失败: ' + (e instanceof Error ? e.message : ''));
      });
    } catch (e) {
      const message = e instanceof Error ? e.message : '';
      Log.error('插件初始化失败: ' + message);
      throw e instanceof Error ? e : new Error('插件初始化失败');
    }

    Plugin.injectDependencies(this);
  }

  private setPlugins(plugins: Array<Plugin>): void {
    this.plugins = plugins;

    // 清理缓存中已卸载的插件
    const cacheStore = PluginManager.pluginCacheStore();
    const cachedKeys = cacheStore.getAllKeys();
    for (const key of cachedKeys) {
      let found = false;
      for (const p of plugins) {
        if (p.path === key) {
          found = true;
          break;
        }
      }
      if (!found) {
        cacheStore.delete(key);
      }
    }

    for (const p of plugins) {
      this.updatePluginCache(p);
    }
  }

  private updatePluginCache(plugin: Plugin): void {
    if (plugin.path.length > 0 && plugin.state === PluginState.Mounted) {
      const rec: JsonRecord = {
        'name': plugin.name,
        'hash': plugin.hash,
        'path': plugin.path,
      };
      if (plugin.instanceInfo !== null) {
        rec['instance'] = plugin.instanceInfo.toRecord();
      }
      const methods: Array<string> = [];
      for (const m of plugin.supportedMethods) {
        methods.push(m);
      }
      rec['supportedMethods'] = methods;
      PluginManager.pluginCacheStore().set(plugin.path, JsonUtil.safeStringify(rec));
    }
  }

  /** 从本地文件安装插件 */
  async installPluginFromLocalFile(pluginPath: string, notCheckVersion?: boolean): Promise<InstallPluginResult> {
    const result = new InstallPluginResult();
    const content = FileUtils.readFileText(pluginPath);
    const funcCode = content === null ? '' : content;
    if (funcCode.length > 0) {
      const plugin = await Plugin.create(funcCode, pluginPath, WebPluginExecutor.getInstance());
      let allPlugins = this.plugins.slice();

      if (plugin.hash.length > 0) {
        for (const p of allPlugins) {
          if (p.hash === plugin.hash) {
            // 静默忽略
            result.success = true;
            result.message = '插件已安装';
            result.pluginName = plugin.name;
            result.pluginHash = plugin.hash;
            return result;
          }
        }
      }
      const oldVersionPlugin = this.findByName(allPlugins, plugin.name);
      if (oldVersionPlugin !== null && notCheckVersion !== true) {
        const oldVersion = oldVersionPlugin.instanceInfo !== null ? oldVersionPlugin.instanceInfo.version : '';
        const newVersion = plugin.instanceInfo !== null ? plugin.instanceInfo.version : '';
        if (VersionCompare.compareWith(oldVersion, newVersion, '>')) {
          result.success = false;
          result.message = '已安装更新版本的插件';
          result.pluginName = plugin.name;
          result.pluginHash = plugin.hash;
          return result;
        }
      }

      if (plugin.state === PluginState.Mounted) {
        const fn = CryptoUtil.nanoid();
        if (oldVersionPlugin !== null) {
          allPlugins = allPlugins.filter((_: Plugin): boolean => _.hash !== oldVersionPlugin.hash);
          FileUtils.unlink(oldVersionPlugin.path);
        }
        const newPluginPath = PathConst.pluginPath + fn + '.js';
        FileUtils.copyFile(pluginPath, newPluginPath);
        plugin.path = newPluginPath;
        allPlugins = allPlugins.concat([plugin]);
        this.setPlugins(allPlugins);

        result.success = true;
        result.pluginName = plugin.name;
        result.pluginHash = plugin.hash;
        return result;
      }
      result.success = false;
      result.message = '插件无法解析';
      return result;
    }
    result.success = false;
    result.message = '插件无法识别';
    return result;
  }

  /** 从 URL 安装插件 */
  async installPluginFromUrl(url: string, notCheckVersion?: boolean): Promise<InstallPluginResult> {
    const result = new InstallPluginResult();
    result.pluginUrl = url;
    const resp = await HttpClient.get(url, {
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
      'Expires': '0',
    });
    if (resp === null) {
      result.success = false;
      result.message = '插件下载失败';
      return result;
    }
    const funcCode = resp.body;
    if (funcCode.length > 0) {
      const plugin = await Plugin.create(funcCode, '', WebPluginExecutor.getInstance());
      let allPlugins = this.plugins.slice();

      if (plugin.hash.length > 0) {
        for (const p of allPlugins) {
          if (p.hash === plugin.hash) {
            // 静默忽略
            result.success = true;
            result.message = '插件已安装';
            result.pluginName = plugin.name;
            result.pluginHash = plugin.hash;
            return result;
          }
        }
      }
      const oldVersionPlugin = this.findByName(allPlugins, plugin.name);
      if (oldVersionPlugin !== null && notCheckVersion !== true) {
        const oldVersion = oldVersionPlugin.instanceInfo !== null ? oldVersionPlugin.instanceInfo.version : '';
        const newVersion = plugin.instanceInfo !== null ? plugin.instanceInfo.version : '';
        if (VersionCompare.compareWith(oldVersion, newVersion, '>')) {
          result.success = false;
          result.message = '已安装更新版本的插件';
          result.pluginName = plugin.name;
          result.pluginHash = plugin.hash;
          return result;
        }
      }

      if (plugin.hash.length > 0) {
        const fn = CryptoUtil.nanoid();
        const newPluginPath = PathConst.pluginPath + fn + '.js';
        FileUtils.writeFileText(newPluginPath, funcCode);
        plugin.path = newPluginPath;
        allPlugins = allPlugins.concat([plugin]);
        if (oldVersionPlugin !== null) {
          allPlugins = allPlugins.filter((_: Plugin): boolean => _.hash !== oldVersionPlugin.hash);
          FileUtils.unlink(oldVersionPlugin.path);
        }
        this.setPlugins(allPlugins);
        result.success = true;
        result.pluginName = plugin.name;
        result.pluginHash = plugin.hash;
        return result;
      }
      result.success = false;
      result.message = '插件无法解析';
      return result;
    }
    result.success = false;
    result.message = '插件无法识别';
    return result;
  }

  /** 通过 hash 卸载插件 */
  uninstallPlugin(hash: string): Promise<void> {
    let plugins = this.plugins.slice();
    let targetIndex = -1;
    for (let i = 0; i < plugins.length; ++i) {
      if (plugins[i].hash === hash) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex !== -1) {
      try {
        const pluginName = plugins[targetIndex].name;
        FileUtils.unlink(plugins[targetIndex].path);
        plugins = plugins.filter((_: Plugin): boolean => _.hash !== hash);
        this.setPlugins(plugins);
        // 防止其他重名
        let hasSameName = false;
        for (const p of plugins) {
          if (p.name === pluginName) {
            hasSameName = true;
            break;
          }
        }
        if (!hasSameName) {
          MediaExtra.removeAllMediaExtra(pluginName);
        }
      } catch (e) {
        // ignore
      }
    }
    return Promise.resolve();
  }

  /** 卸载全部插件 */
  async uninstallAllPlugins(): Promise<void> {
    for (const plugin of this.plugins) {
      try {
        const pluginName = plugin.name;
        FileUtils.unlink(plugin.path);
        MediaExtra.removeAllMediaExtra(pluginName);
      } catch (e) {
        // ignore
      }
    }
    this.setPlugins([]);

    // 清除残余文件
    const names = FileUtils.listDir(PathConst.pluginPath);
    for (const n of names) {
      FileUtils.unlink(PathConst.pluginPath + n);
    }
  }

  /** 使用插件的源 URL 更新插件 */
  async updatePlugin(plugin: Plugin): Promise<void> {
    const updateUrl = plugin.instanceInfo !== null ? plugin.instanceInfo.srcUrl : '';
    if (updateUrl.length === 0) {
      throw new Error('没有更新源');
    }
    const result = await this.installPluginFromUrl(updateUrl);
    if (!result.success) {
      if (result.message === '插件已安装') {
        throw new Error('当前已是最新版本');
      }
      throw new Error(result.message.length > 0 ? result.message : '更新失败');
    }
  }

  private findByName(plugins: Array<Plugin>, name: string): Plugin | null {
    for (const p of plugins) {
      if (p.name === name) {
        return p;
      }
    }
    return null;
  }

  /** 通过媒体项获取插件 */
  getByMedia(mediaItem: MusicItem): Plugin | null {
    return this.getByName(mediaItem.platform);
  }

  /** 通过名称获取插件 */
  getByName(name: string): Plugin | null {
    if (name === LOCAL_PLUGIN_PLATFORM) {
      return this.localFilePlugin;
    }
    return this.findByName(this.plugins, name);
  }

  /** 通过 hash 获取插件 */
  getByHash(hash: string): Plugin | null {
    if (hash === LOCAL_PLUGIN_HASH) {
      return this.localFilePlugin;
    }
    for (const p of this.plugins) {
      if (p.hash === hash) {
        return p;
      }
    }
    return null;
  }

  /** 获取插件列表 */
  getPlugins(): Array<Plugin> {
    return this.plugins;
  }

  /** 获取已启用的插件 */
  getEnabledPlugins(): Array<Plugin> {
    const result: Array<Plugin> = [];
    for (const it of this.plugins) {
      if (PluginMeta.isPluginEnabled(it.name)) {
        result.push(it);
      }
    }
    return result;
  }

  private static orderOf(order: Record<string, number>, name: string): number {
    const v: number | undefined = order[name];
    return v === undefined ? Number.MAX_VALUE : v;
  }

  private static sortByOrder(plugins: Array<Plugin>): Array<Plugin> {
    const order = PluginMeta.getPluginOrder();
    const result = plugins.slice();
    result.sort((a: Plugin, b: Plugin): number => {
      const oa = PluginManager.orderOf(order, a.name);
      const ob = PluginManager.orderOf(order, b.name);
      if (oa === ob) {
        return 0;
      }
      return oa < ob ? -1 : 1;
    });
    return result;
  }

  /** 获取按顺序排序的插件 */
  getSortedPlugins(): Array<Plugin> {
    return PluginManager.sortByOrder(this.plugins);
  }

  /** 获取支持搜索的已启用插件 */
  getSearchablePlugins(supportedSearchType?: SupportMediaType): Array<Plugin> {
    const result: Array<Plugin> = [];
    for (const it of this.plugins) {
      if (!PluginMeta.isPluginEnabled(it.name) || !it.hasMethod('search')) {
        continue;
      }
      if (supportedSearchType !== undefined && it.instanceInfo !== null &&
        it.instanceInfo.supportedSearchType.length > 0) {
        if (it.instanceInfo.supportedSearchType.indexOf(supportedSearchType) === -1) {
          continue;
        }
      }
      result.push(it);
    }
    return result;
  }

  /** 获取支持搜索的已启用插件（按顺序） */
  getSortedSearchablePlugins(supportedSearchType?: SupportMediaType): Array<Plugin> {
    return PluginManager.sortByOrder(this.getSearchablePlugins(supportedSearchType));
  }

  /** 获取拥有指定能力的已启用插件 */
  getPluginsWithAbility(ability: string): Array<Plugin> {
    const result: Array<Plugin> = [];
    for (const it of this.plugins) {
      if (PluginMeta.isPluginEnabled(it.name) && it.hasMethod(ability)) {
        result.push(it);
      }
    }
    return result;
  }

  /** 获取拥有指定能力的已启用插件（按顺序） */
  getSortedPluginsWithAbility(ability: string): Array<Plugin> {
    return PluginManager.sortByOrder(this.getPluginsWithAbility(ability));
  }

  /** 设置插件启用状态 */
  setPluginEnabled(plugin: Plugin, enabled: boolean): void {
    const event = new PluginEnabledUpdatedEvent();
    event.pluginName = plugin.name;
    event.enabled = enabled;
    this.ee.emit('enabled-updated', event);
    PluginMeta.setPluginEnabled(plugin.name, enabled);
  }

  /** 插件是否启用 */
  isPluginEnabled(plugin: Plugin): boolean {
    return PluginMeta.isPluginEnabled(plugin.name);
  }

  /** 设置插件顺序 */
  setPluginOrder(sortedPlugins: Array<Plugin>): void {
    const orderMap: Record<string, number> = {};
    sortedPlugins.forEach((plugin: Plugin, index: number) => {
      orderMap[plugin.name] = index;
    });
    PluginMeta.setPluginOrder(orderMap);
    this.ee.emit('order-updated', new PluginOrderUpdatedEvent());
  }

  onOrderUpdated(cb: () => void): void {
    const wrapper: EventListenerFn = (_payload?: Object) => {
      cb();
    };
    this.ee.on('order-updated', wrapper);
  }

  onPluginEnabled(cb: (pluginName: string, enabled: boolean) => void): void {
    const wrapper: EventListenerFn = (payload?: Object) => {
      if (payload instanceof PluginEnabledUpdatedEvent) {
        cb(payload.pluginName, payload.enabled);
      }
    };
    this.ee.on('enabled-updated', wrapper);
  }

  setUserVariables(plugin: Plugin, userVariables: Record<string, string>): void {
    PluginMeta.setUserVariables(plugin.name, userVariables);
  }

  getUserVariables(plugin: Plugin): Record<string, string> {
    return PluginMeta.getUserVariables(plugin.name);
  }

  setAlternativePluginName(plugin: Plugin, alternativePluginName: string): void {
    PluginMeta.setAlternativePlugin(plugin.name, alternativePluginName);
  }

  getAlternativePluginName(plugin: Plugin): string | null {
    return PluginMeta.getAlternativePlugin(plugin.name);
  }

  getAlternativePlugin(plugin: Plugin): Plugin | null {
    const alternativePluginName = this.getAlternativePluginName(plugin);
    if (alternativePluginName !== null && alternativePluginName.length > 0) {
      return this.getByName(alternativePluginName);
    }
    return null;
  }
}

export const pluginManager = new PluginManager();
