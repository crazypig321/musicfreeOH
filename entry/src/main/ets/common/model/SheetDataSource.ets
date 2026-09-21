import { SheetItem } from './SheetTypes';

/**
 * LazyForEach 数据源：歌单搜索结果懒加载列表
 * 追加时按 platform + id 去重
 */
export class SheetDataSource implements IDataSource {
  private items: Array<SheetItem> = [];
  private listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): SheetItem {
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

  /** 追加数据（去重后通知刷新） */
  appendData(items: Array<SheetItem>): void {
    const existing: Set<string> = new Set<string>();
    for (const it of this.items) {
      existing.add(it.platform + '_' + it.id);
    }
    const next: Array<SheetItem> = this.items.slice();
    for (const it of items) {
      const key = it.platform + '_' + it.id;
      if (existing.has(key)) {
        continue;
      }
      existing.add(key);
      next.push(it);
    }
    this.items = next;
    this.notifyReload();
  }

  clear(): void {
    this.items = [];
    this.notifyReload();
  }

  private notifyReload(): void {
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }
}
