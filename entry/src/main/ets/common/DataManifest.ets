/**
 * 应用数据清单（备份与恢复功能的依据）
 * 新增 KVStore 实例或数据目录时必须同步登记到这里，
 * 后续 BackupManager 基于此清单枚举需要备份/恢复的数据。
 */
export class DataManifest {
  /** 需要备份的 KV 存储名（固定名） */
  static readonly BACKUP_KV_STORES: Array<string> = [
    'App.config',         // 应用设置
    'App.meta',           // 应用元数据
    'App.PersistStatus',  // 播放中断状态
    'plugin-meta',        // 插件排序/禁用列表/用户变量/备选插件
    'storage',            // 本地音乐列表
    'music.MusicHistory', // 播放历史
  ];

  /** 需要备份的 KV 存储名前缀（动态实例，运行时经 KVStore.getRegisteredNames 按前缀枚举） */
  static readonly BACKUP_KV_STORE_PREFIXES: Array<string> = [
    'LocalSheet.',  // 自建歌单
    'MediaExtra.',  // 媒体扩展信息
  ];

  /** 可重建的缓存存储（不参与备份） */
  static readonly CACHE_KV_STORES: Array<string> = [
    'plugin.cache',     // 插件懒加载缓存（可从插件文件重建）
    'cache.MediaCache', // 媒体缓存（可从网络重建）
  ];

  /** 需要备份的数据目录（相对 PathConst.basePath） */
  static readonly BACKUP_DATA_DIRS: Array<string> = [
    'plugins/',   // 插件脚本文件（<nanoid>.js，插件更新/安装的持久化本体）
    'local_lrc/', // 本地歌词文件
  ];

  /** 备份文件格式版本（备份时写入，恢复时用于兼容判断） */
  static readonly BACKUP_FORMAT_VERSION: number = 1;
}
