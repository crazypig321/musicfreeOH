/**
 * 类型化事件总线（替代 eventemitter3）
 * 由于 ArkTS 禁止任意函数类型，使用 (payload?: Object) => void 作为底层回调，
 * 各模块通过 typed 包装方法提供类型安全的事件。
 */
export type EventListenerFn = (payload?: Object) => void;

export class EventEmitter {
  private listeners: Map<string, Set<EventListenerFn>> = new Map();

  on(event: string, cb: EventListenerFn): void {
    let set = this.listeners.get(event);
    if (set === undefined) {
      set = new Set<EventListenerFn>();
      this.listeners.set(event, set);
    }
    set.add(cb);
  }

  once(event: string, cb: EventListenerFn): void {
    const wrapper: EventListenerFn = (payload?: Object) => {
      this.off(event, wrapper);
      cb(payload);
    };
    this.on(event, wrapper);
  }

  off(event: string, cb: EventListenerFn): void {
    const set = this.listeners.get(event);
    if (set !== undefined) {
      set.delete(cb);
      if (set.size === 0) {
        this.listeners.delete(event);
      }
    }
  }

  emit(event: string, payload?: Object): void {
    const set = this.listeners.get(event);
    if (set === undefined) {
      return;
    }
    // 拷贝一份，避免回调中修改监听器导致迭代异常
    const snapshot: Array<EventListenerFn> = Array.from(set);
    for (const cb of snapshot) {
      try {
        cb(payload);
      } catch (e) {
        // 单个监听器异常不影响其他监听器
      }
    }
  }

  removeAllListeners(event?: string): void {
    if (event === undefined) {
      this.listeners.clear();
    } else {
      this.listeners.delete(event);
    }
  }
}
