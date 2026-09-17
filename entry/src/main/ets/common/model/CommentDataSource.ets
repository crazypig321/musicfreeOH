import { CommentItem } from './SheetTypes';

/**
 * LazyForEach 数据源：评论懒加载列表
 * 列表整体刷新（首屏/翻页拼接），用 onDataReloaded 通知
 */
export class CommentDataSource implements IDataSource {
  private items: Array<CommentItem> = [];
  private listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): CommentItem {
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
  reload(items: Array<CommentItem>): void {
    this.items = items;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }
}
