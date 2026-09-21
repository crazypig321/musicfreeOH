/**
 * LazyForEach 数据源：字符串标签条（插件标签/分组标签等横向滚动标签，数量可能较多）
 * 整体替换数据，用 onDataReloaded 通知
 */
export class StringDataSource implements IDataSource {
  private items: Array<string> = [];
  private listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): string {
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
  reload(items: Array<string>): void {
    this.items = items;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }
}
