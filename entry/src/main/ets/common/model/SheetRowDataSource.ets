import { SheetItem } from './SheetTypes';

/**
 * 推荐歌单行数据源（LazyForEach 用，按行整体替换并通知刷新）
 * 首页预览与推荐歌单页共用
 */
export class SheetRowDataSource implements IDataSource {
  private rows: Array<Array<SheetItem>> = [];
  private listeners: Array<DataChangeListener> = [];

  /** 整体替换行数据并通知刷新 */
  setRows(rows: Array<Array<SheetItem>>): void {
    this.rows = rows;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): Array<SheetItem> {
    return index >= 0 && index < this.rows.length ? this.rows[index] : [];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) === -1) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const i = this.listeners.indexOf(listener);
    if (i >= 0) {
      this.listeners.splice(i, 1);
    }
  }
}
