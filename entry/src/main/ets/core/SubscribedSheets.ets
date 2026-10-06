import { KVStore } from '../infra/KVStore';
import { JsonUtil, JsonRecord } from '../utils/JsonUtil';
import { EventEmitter, EventListenerFn } from '../common/EventBus';
import { SheetItem, AlbumItem, ArtistItem, SheetInfoResult, AlbumInfoResult, TopListInfoResult } from '../common/model/SheetTypes';
import { Plugin } from '../plugin/Plugin';
import { pluginManager } from '../plugin/PluginManager';

/** 订阅媒体类型（歌单/榜单进歌单详情页，专辑/歌手进对应详情页） */
export class SubscribedMediaType {
  static readonly SHEET: string = 'sheet';
  static readonly TOP_LIST: string = 'toplist';
  static readonly ALBUM: string = 'album';
  static readonly ARTIST: string = 'artist';
}

/** 订阅歌单数据更新事件 */
export class SubscribedSheetsUpdatedEvent {
}

/** 订阅记录（快照 + 更新标记，存于 KV 存储 'storage'，自动随备份） */
export class SubscribedSheetRecord {
  /** 来源插件名 */
  platform: string = '';
  id: string = '';
  title: string = '';
  mediaType: string = SubscribedMediaType.SHEET;
  /** 曲目数快照（同步时对比检测更新；0 表示未知，首次同步只建立基线不标记） */
  worksNum: number = 0;
  /** 有更新（曲目数与上次查看时不同） */
  hasUpdate: boolean = false;
  /** 订阅时间戳 */
  subscribeAt: number = 0;
  /** 上次同步时间戳 */
  lastSyncAt: number = 0;
  /** 原始条目快照 record（按 mediaType 还原为 SheetItem/AlbumItem/ArtistItem） */
  itemRecord: JsonRecord = {};

  /** 封面地址（歌手取 avatar，专辑/歌单取 coverImg→artwork） */
  coverUrl(): string {
    if (this.mediaType === SubscribedMediaType.ARTIST) {
      return JsonUtil.recStr(this.itemRecord, 'avatar');
    }
    const coverImg = JsonUtil.recStr(this.itemRecord, 'coverImg');
    return coverImg.length > 0 ? coverImg : JsonUtil.recStr(this.itemRecord, 'artwork');
  }

  /** 还原歌单条目 */
  sheetItem(): SheetItem {
    return SheetItem.fromRecord(this.itemRecord);
  }

  /** 还原专辑条目 */
  albumItem(): AlbumItem {
    return AlbumItem.fromRecord(this.itemRecord);
  }

  /** 还原歌手条目 */
  artistItem(): ArtistItem {
    return ArtistItem.fromRecord(this.itemRecord);
  }

  static fromRecord(rec: JsonRecord): SubscribedSheetRecord {
    const r = new SubscribedSheetRecord();
    r.platform = JsonUtil.recStr(rec, 'platform');
    r.id = JsonUtil.recStr(rec, 'id');
    r.title = JsonUtil.recStr(rec, 'title');
    r.mediaType = JsonUtil.recStr(rec, 'mediaType');
    r.worksNum = JsonUtil.recNum(rec, 'worksNum');
    r.hasUpdate = JsonUtil.recBool(rec, 'hasUpdate', false);
    r.subscribeAt = JsonUtil.recNum(rec, 'subscribeAt');
    r.lastSyncAt = JsonUtil.recNum(rec, 'lastSyncAt');
    const itemRec = JsonUtil.recRecord(rec, 'itemRecord');
    if (itemRec !== null) {
      r.itemRecord = itemRec;
    }
    return r;
  }

  toRecord(): JsonRecord {
    const rec: JsonRecord = {
      'platform': this.platform,
      'id': this.id,
      'mediaType': this.mediaType,
      'worksNum': this.worksNum,
      'hasUpdate': this.hasUpdate,
      'subscribeAt': this.subscribeAt,
      'lastSyncAt': this.lastSyncAt,
      'itemRecord': this.itemRecord,
    };
    if (this.title.length > 0) {
      rec['title'] = this.title;
    }
    return rec;
  }
}

/** 订阅列表 LazyForEach 数据源（整体替换 + 重载通知） */
export class SubscribedSheetsDataSource implements IDataSource {
  private items: Array<SubscribedSheetRecord> = [];
  private listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): SubscribedSheetRecord {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) === -1) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /** 整体替换数据并通知重载 */
  reload(items: Array<SubscribedSheetRecord>): void {
    this.items = items;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }
}

/**
 * 订阅歌单（拉取式同步）：详情页心形按钮订阅插件歌单/榜单/专辑/歌手，
 * 我的歌单页展示订阅列表并标记「有更新」；进入页面/手动触发时逐条拉取第一页对比曲目数
 */
export class SubscribedSheets {
  private static readonly STORE_KEY: string = 'subscribedSheets';
  /** 同步节流间隔（毫秒） */
  private static readonly SYNC_THROTTLE_MS: number = 10 * 60 * 1000;
  private records: Array<SubscribedSheetRecord> = [];
  private loaded: boolean = false;
  /** 进行中的同步任务（并发触发时复用） */
  private syncing: Promise<void> | null = null;
  private ee: EventEmitter = new EventEmitter();

  private getStore(): KVStore {
    return KVStore.getOrCreate('storage');
  }

  /** 懒加载持久化数据（首次访问时读取） */
  private ensureLoaded(): void {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    const raw = this.getStore().get(SubscribedSheets.STORE_KEY);
    if (raw.length === 0) {
      return;
    }
    const arr = JsonUtil.parseRecordArray(raw);
    if (arr === null) {
      return;
    }
    for (const rec of arr) {
      this.records.push(SubscribedSheetRecord.fromRecord(rec));
    }
  }

  private save(): void {
    const arr: Array<JsonRecord> = [];
    for (const r of this.records) {
      arr.push(r.toRecord());
    }
    this.getStore().set(SubscribedSheets.STORE_KEY, JSON.stringify(arr));
  }

  private notify(): void {
    this.ee.emit('updated', new SubscribedSheetsUpdatedEvent());
  }

  getAll(): Array<SubscribedSheetRecord> {
    this.ensureLoaded();
    return this.records;
  }

  get(platform: string, id: string): SubscribedSheetRecord | null {
    this.ensureLoaded();
    for (const record of this.records) {
      if (record.platform === platform && record.id === id) {
        return record;
      }
    }
    return null;
  }

  isSubscribed(platform: string, id: string): boolean {
    return this.get(platform, id) !== null;
  }

  /** 订阅（itemRecord 为条目序列化快照，platform 归一为插件名便于详情页解析来源） */
  subscribeSheet(mediaType: string, itemRecord: JsonRecord, pluginName: string,
    title: string, worksNum: number): void {
    this.ensureLoaded();
    const id = JsonUtil.recStr(itemRecord, 'id');
    if (id.length === 0 || this.isSubscribed(pluginName, id)) {
      return;
    }
    const snapshot = JsonUtil.cloneRecord(itemRecord);
    snapshot['platform'] = pluginName;
    const record = new SubscribedSheetRecord();
    record.platform = pluginName;
    record.id = id;
    record.title = title;
    record.mediaType = mediaType;
    record.worksNum = worksNum;
    record.subscribeAt = Date.now();
    record.itemRecord = snapshot;
    this.records.push(record);
    this.save();
    this.notify();
  }

  /** 取消订阅 */
  unsubscribe(platform: string, id: string): void {
    this.ensureLoaded();
    for (let i = 0; i < this.records.length; ++i) {
      const record = this.records[i];
      if (record.platform === platform && record.id === id) {
        this.records.splice(i, 1);
        this.save();
        this.notify();
        return;
      }
    }
  }

  /** 标记已查看（清除更新标记） */
  markViewed(platform: string, id: string): void {
    this.ensureLoaded();
    const record = this.get(platform, id);
    if (record === null || !record.hasUpdate) {
      return;
    }
    record.hasUpdate = false;
    this.save();
    this.notify();
  }

  /** 订阅在全量列表中的序号（0 基；不存在返回 -1） */
  indexOf(platform: string, id: string): number {
    this.ensureLoaded();
    for (let i = 0; i < this.records.length; ++i) {
      if (this.records[i].platform === platform && this.records[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  /** 将订阅移动到 toIndex（0 基，按全量列表顺序）并保存 */
  moveRecordTo(platform: string, id: string, toIndex: number): void {
    this.ensureLoaded();
    const from = this.indexOf(platform, id);
    if (from < 0 || toIndex < 0 || toIndex >= this.records.length || from === toIndex) {
      return;
    }
    const record = this.records.splice(from, 1)[0];
    this.records.splice(toIndex, 0, record);
    this.save();
    this.notify();
  }

  /** 按给定键顺序（platform_id）重排订阅列表并保存；未包含的记录按原顺序追加 */
  setOrder(keys: Array<string>): void {
    this.ensureLoaded();
    const sorted: Array<SubscribedSheetRecord> = [];
    const rest: Array<SubscribedSheetRecord> = [];
    for (const record of this.records) {
      if (keys.indexOf(record.platform + '_' + record.id) >= 0) {
        sorted.push(record);
      } else {
        rest.push(record);
      }
    }
    // 按传入键顺序稳定重排（插入排序）
    for (let i = 0; i < keys.length; ++i) {
      for (let j = i; j < sorted.length; ++j) {
        if (sorted[j].platform + '_' + sorted[j].id === keys[i]) {
          if (j !== i) {
            const record = sorted.splice(j, 1)[0];
            sorted.splice(i, 0, record);
          }
          break;
        }
      }
    }
    for (const record of rest) {
      sorted.push(record);
    }
    this.records = sorted;
    this.save();
    this.notify();
  }

  /**
   * 手动同步单条订阅（忽略节流）；返回是否执行了同步：
   * 不存在/插件不可用/歌手订阅（无变更信号）返回 false
   */
  syncRecord(platform: string, id: string): Promise<boolean> {
    this.ensureLoaded();
    const record = this.get(platform, id);
    if (record === null || record.mediaType === SubscribedMediaType.ARTIST) {
      return Promise.resolve(false);
    }
    const plugin: Plugin | null = pluginManager.getByName(record.platform);
    if (plugin === null || !pluginManager.isPluginEnabled(plugin)) {
      return Promise.resolve(false);
    }
    record.lastSyncAt = Date.now();
    return this.syncOne(record).then((): boolean => {
      return true;
    }).catch((_e: Object): boolean => {
      return false;
    });
  }

  /**
   * 用源端最新信息刷新订阅快照（同步与详情页刷新共用）：
   * 曲目数与快照不同且快照非 0 → 标记「有更新」；markSeen=true 表示用户正在查看，清除标记
   */
  refreshSnapshot(platform: string, id: string, latestRecord: JsonRecord, latestTitle: string,
    latestCover: string, count: number, markSeen: boolean): void {
    this.ensureLoaded();
    const record = this.get(platform, id);
    if (record === null) {
      return;
    }
    const countChanged = count > 0 && count !== record.worksNum;
    const titleChanged = latestTitle.length > 0 && latestTitle !== record.title;
    const coverChanged = latestCover.length > 0 && latestCover !== record.coverUrl();
    let changed = false;
    if (countChanged) {
      if (record.worksNum > 0 && !markSeen) {
        record.hasUpdate = true;
      }
      record.worksNum = count;
      changed = true;
    }
    if (titleChanged) {
      record.title = latestTitle;
      changed = true;
    }
    if (countChanged || titleChanged || coverChanged) {
      // 快照回写保留原 id/platform（订阅按 platform+id 索引）：
      // 部分插件的详情接口返回的条目 id 与请求 id 不一致（如 QQ 歌单的内部 dissid），
      // 直接覆盖会破坏重启后的还原
      const snap = JsonUtil.cloneRecord(latestRecord);
      snap['id'] = record.id;
      snap['platform'] = record.platform;
      record.itemRecord = snap;
      changed = true;
    }
    if (markSeen && record.hasUpdate) {
      record.hasUpdate = false;
      changed = true;
    }
    if (changed) {
      this.save();
      this.notify();
    }
  }

  /** 同步全部订阅（逐条拉取源端第一页对比曲目数）；force=true 忽略节流强制刷新 */
  syncAll(force: boolean): Promise<void> {
    this.ensureLoaded();
    if (this.syncing !== null) {
      return this.syncing;
    }
    const task = this.performSync(force).then((): void => {
      this.syncing = null;
    }).catch((_e: Object): void => {
      this.syncing = null;
    });
    this.syncing = task;
    return task;
  }

  private async performSync(force: boolean): Promise<void> {
    const now = Date.now();
    // 快照遍历：同步过程中用户取消订阅不影响本轮迭代
    const snapshot = this.records.slice();
    for (const record of snapshot) {
      if (!force && now - record.lastSyncAt < SubscribedSheets.SYNC_THROTTLE_MS) {
        continue;
      }
      record.lastSyncAt = now;
      try {
        await this.syncOne(record);
      } catch (_e) {
        // 单条失败跳过，继续同步其余订阅
      }
    }
  }

  /** 同步单条订阅：插件缺失/禁用跳过保留快照；榜单缺 getTopListDetail 能力时回退歌单接口 */
  private async syncOne(record: SubscribedSheetRecord): Promise<void> {
    const plugin: Plugin | null = pluginManager.getByName(record.platform);
    if (plugin === null || !pluginManager.isPluginEnabled(plugin)) {
      return;
    }
    if (record.mediaType === SubscribedMediaType.ALBUM) {
      await this.syncAlbum(record, plugin);
      return;
    }
    if (record.mediaType === SubscribedMediaType.ARTIST) {
      // 歌手作品接口（getArtistWorks）不返回歌手信息快照，无可靠变更信号，跳过同步
      return;
    }
    let latest: SheetItem | null = null;
    let musicCount = 0;
    if (record.mediaType === SubscribedMediaType.TOP_LIST && plugin.hasMethod('getTopListDetail')) {
      const result: TopListInfoResult = await plugin.methods.getTopListDetail(record.sheetItem(), 1);
      latest = result.topListItem;
      musicCount = result.musicList.length;
    } else {
      const result: SheetInfoResult | null = await plugin.methods.getMusicSheetInfo(record.sheetItem(), 1);
      if (result !== null) {
        latest = result.sheetItem;
        musicCount = result.musicList.length;
      }
    }
    const count = latest !== null && latest.worksNum > 0 ? latest.worksNum : musicCount;
    if (latest === null && count <= 0) {
      return;
    }
    const latestItem = latest !== null ? latest : record.sheetItem();
    this.refreshSnapshot(record.platform, record.id, latestItem.toRecord(),
      latestItem.title, latestItem.coverUrl(), count, false);
  }

  /** 同步专辑订阅：getAlbumInfo 首页合并信息对比曲目数 */
  private async syncAlbum(record: SubscribedSheetRecord, plugin: Plugin): Promise<void> {
    const result: AlbumInfoResult | null = await plugin.methods.getAlbumInfo(record.albumItem(), 1);
    if (result === null || result.albumItem === null) {
      return;
    }
    const album = result.albumItem;
    const count = album.worksNum > 0 ? album.worksNum : result.musicList.length;
    this.refreshSnapshot(record.platform, record.id, album.toRecord(),
      album.title, album.artwork, count, false);
  }

  onUpdated(cb: () => void): void {
    const wrapper: EventListenerFn = (_payload?: Object) => {
      cb();
    };
    this.ee.on('updated', wrapper);
  }
}

/** 订阅歌单单例 */
export const subscribedSheets = new SubscribedSheets();
