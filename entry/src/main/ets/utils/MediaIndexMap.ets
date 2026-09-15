import { MediaRefLike } from '../common/model/MediaTypes';

/**
 * 媒体索引 Map：platform -> {id -> index}，O(1) 查找
 */
export class MediaIndexMap {
  private indexMap: Map<string, Map<string, number>> = new Map();

  constructor(items?: Array<MediaRefLike>) {
    if (items !== undefined) {
      this.build(items);
    }
  }

  build(items: Array<MediaRefLike>): void {
    this.indexMap.clear();
    items.forEach((item: MediaRefLike, index: number) => {
      let sub = this.indexMap.get(item.platform);
      if (sub === undefined) {
        sub = new Map<string, number>();
        this.indexMap.set(item.platform, sub);
      }
      sub.set(item.id, index);
    });
  }

  getIndex(mediaItem: MediaRefLike | null | undefined): number {
    if (mediaItem === null || mediaItem === undefined) {
      return -1;
    }
    const sub = this.indexMap.get(mediaItem.platform);
    if (sub === undefined) {
      return -1;
    }
    const idx = sub.get(mediaItem.id);
    return idx === undefined ? -1 : idx;
  }

  has(mediaItem: MediaRefLike | null | undefined): boolean {
    return this.getIndex(mediaItem) > -1;
  }
}
