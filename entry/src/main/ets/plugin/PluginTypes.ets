import { JsonRecord, JsonArray, JsonUtil } from '../common/JsonUtil';

/** 插件状态（对应 RN PluginState） */
export enum PluginState {
  /** 初始化（懒加载未挂载） */
  Initializing = 'Initializing',
  /** 加载中 */
  Loading = 'Loading',
  /** 已挂载 */
  Mounted = 'Mounted',
  /** 出错 */
  Error = 'Error',
}

/** 插件错误原因 */
export enum PluginErrorReason {
  /** 版本不匹配 */
  VersionNotMatch = 'VersionNotMatch',
  /** 无法解析 */
  CannotParse = 'CannotParse',
}

/** 挂载后的插件实例信息（沙箱回传的 instance 描述） */
export class PluginInstanceInfo {
  platform: string = '';
  version: string = '';
  srcUrl: string = '';
  author: string = '';
  /** 缓存控制：cache / no-cache / no-store */
  cacheControl: string = '';
  /** 插件声明支持的应用版本范围 */
  appVersion: string = '';
  /** 支持的搜索类型 */
  supportedSearchType: Array<string> = [];
  /** 用户变量声明（原始 record 数组） */
  userVariables: JsonArray = [];
  /** 支持的方法名 */
  supportedMethods: Array<string> = [];
  /** 使用说明（插件自述文本） */
  description: string = '';
  /** 导入功能提示文案（key: importMusicItem / importMusicSheet） */
  hints: JsonRecord | null = null;

  static fromRecord(rec: JsonRecord): PluginInstanceInfo {
    const info = new PluginInstanceInfo();
    info.platform = JsonUtil.recStr(rec, 'platform');
    info.version = JsonUtil.recStr(rec, 'version');
    info.srcUrl = JsonUtil.recStr(rec, 'srcUrl');
    info.author = JsonUtil.recStr(rec, 'author');
    info.cacheControl = JsonUtil.recStr(rec, 'cacheControl');
    info.appVersion = JsonUtil.recStr(rec, 'appVersion');
    const searchType = JsonUtil.recArray(rec, 'supportedSearchType');
    if (searchType !== null) {
      for (const t of searchType) {
        if (typeof t === 'string') {
          info.supportedSearchType.push(t);
        }
      }
    }
    const userVars = JsonUtil.objToRecordArray(rec['userVariables']);
    if (userVars !== null) {
      info.userVariables = userVars;
    }
    const methods = JsonUtil.recArray(rec, 'supportedMethods');
    if (methods !== null) {
      for (const m of methods) {
        if (typeof m === 'string') {
          info.supportedMethods.push(m);
        }
      }
    }
    info.description = JsonUtil.recStr(rec, 'description');
    const hints = JsonUtil.recRecord(rec, 'hints');
    if (hints !== null) {
      info.hints = hints;
    }
    return info;
  }

  toRecord(): JsonRecord {
    const rec: JsonRecord = {
      'platform': this.platform,
      'supportedMethods': this.supportedMethods,
    };
    if (this.version.length > 0) {
      rec['version'] = this.version;
    }
    if (this.srcUrl.length > 0) {
      rec['srcUrl'] = this.srcUrl;
    }
    if (this.author.length > 0) {
      rec['author'] = this.author;
    }
    if (this.cacheControl.length > 0) {
      rec['cacheControl'] = this.cacheControl;
    }
    if (this.appVersion.length > 0) {
      rec['appVersion'] = this.appVersion;
    }
    if (this.supportedSearchType.length > 0) {
      rec['supportedSearchType'] = this.supportedSearchType;
    }
    if (this.userVariables.length > 0) {
      rec['userVariables'] = this.userVariables;
    }
    if (this.description.length > 0) {
      rec['description'] = this.description;
    }
    if (this.hints !== null) {
      rec['hints'] = this.hints;
    }
    return rec;
  }
}

/** 懒加载属性（对应 RN ILazyProps） */
export class LazyProps {
  name: string = '';
  hash: string = '';
  path: string = '';
  supportedMethods: Array<string> = [];
  /** 缓存的实例信息（可空） */
  instanceInfo: PluginInstanceInfo | null = null;
  /** 源码加载函数 */
  loadFuncCode: () => Promise<string> = (): Promise<string> => {
    return Promise.resolve('');
  };

  static fromRecord(rec: JsonRecord): LazyProps {
    const props = new LazyProps();
    props.name = JsonUtil.recStr(rec, 'name');
    props.hash = JsonUtil.recStr(rec, 'hash');
    props.path = JsonUtil.recStr(rec, 'path');
    const methods = JsonUtil.recArray(rec, 'supportedMethods');
    if (methods !== null) {
      for (const m of methods) {
        if (typeof m === 'string') {
          props.supportedMethods.push(m);
        }
      }
    }
    const infoRec = JsonUtil.recRecord(rec, 'instance');
    if (infoRec !== null) {
      props.instanceInfo = PluginInstanceInfo.fromRecord(infoRec);
    }
    return props;
  }
}

/**
 * 插件执行器：承载插件代码的运行环境
 * - WebPluginExecutor：WebView 沙箱（远程插件）
 * - LocalPluginExecutor：本地插件（原生实现）
 */
export interface IPluginExecutor {
  /** 挂载插件源码，返回实例信息；失败抛错 */
  mount(pluginKey: string, funcCode: string, appVersion: string): Promise<PluginInstanceInfo>;
  /** 调用插件方法，返回结果 JSON 字符串；失败抛错 */
  callMethod(pluginKey: string, method: string, argsJson: string): Promise<string>;
}

/** 插件安装结果（对应 IInstallPluginResult） */
export class InstallPluginResult {
  success: boolean = false;
  message: string = '';
  pluginName: string = '';
  pluginHash: string = '';
  pluginUrl: string = '';
}
