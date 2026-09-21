import { MediaTag } from './SheetTypes';

/**
 * LazyForEach 数据源：推荐歌单标签条（插件返回的标签可能较多，按需创建）
 * 首页推荐板块与推荐歌单页共用
 */
export class MediaTagDataSource implements IDataSource {
  private items: Array<MediaTag> = [];
  private listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): MediaTag {
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

  /** 整体替换数据并通知刷新 */
  reload(items: Array<MediaTag>): void {
    this.items = items;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }
}
