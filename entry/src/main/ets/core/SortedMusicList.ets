import intl from '@ohos.intl';
import { SortType } from '../common/Consts';
import { MusicItem } from '../common/model/MediaTypes';
import { MediaUtils } from '../utils/MediaUtils';

/**
 * 带排序的音乐列表（移植自 musicSheet/sortedMusicList.ts）
 */
export class SortedMusicList {
  private static collator: intl.Collator | null = null;

  private static getCollator(): intl.Collator {
    if (SortedMusicList.collator === null) {
      SortedMusicList.collator = new intl.Collator('zh');
    }
    return SortedMusicList.collator;
  }

  private static compareTitle(a: MusicItem, b: MusicItem): number {
    return SortedMusicList.getCollator().compare(a.title, b.title);
  }

  private static compareArtist(a: MusicItem, b: MusicItem): number {
    return SortedMusicList.getCollator().compare(a.artist, b.artist);
  }

  private static compareAlbum(a: MusicItem, b: MusicItem): number {
    return SortedMusicList.getCollator().compare(a.album, b.album);
  }

  private static compareTimeNewToOld(b: MusicItem, a: MusicItem): number {
    const timestamp = a.timeStamp - b.timeStamp;
    if (timestamp === 0) {
      return a.sortIndex - b.sortIndex;
    }
    return timestamp;
  }

  private static compareTimeOldToNew(a: MusicItem, b: MusicItem): number {
    const timestamp = a.timeStamp - b.timeStamp;
    if (timestamp === 0) {
      return a.sortIndex - b.sortIndex;
    }
    return timestamp;
  }

  /** 排序类型 → 比较函数；None 无 */
  private static compareFnOf(sortType: SortType): ((a: MusicItem, b: MusicItem) => number) | null {
    if (sortType === SortType.Title) {
      return SortedMusicList.compareTitle;
    }
    if (sortType === SortType.Artist) {
      return SortedMusicList.compareArtist;
    }
    if (sortType === SortType.Album) {
      return SortedMusicList.compareAlbum;
    }
    if (sortType === SortType.Newest) {
      return SortedMusicList.compareTimeNewToOld;
    }
    if (sortType === SortType.Oldest) {
      return SortedMusicList.compareTimeOldToNew;
    }
    return null;
  }

  private array: Array<MusicItem> = [];
  private sortType: SortType = SortType.None;
  private countMap: Map<string, Set<string>> = new Map();

  constructor(musicItems: Array<MusicItem>, sortType: SortType = SortType.None, skipInitialSort: boolean = false) {
    this.array = musicItems.slice();
    this.addToCountMap(this.array);
    this.sortType = sortType;
    if (!skipInitialSort) {
      this.resort();
    }
  }

  get musicList(): Array<MusicItem> {
    return this.array;
  }

  get firstMusic(): MusicItem | null {
    return this.array.length > 0 ? this.array[0] : null;
  }

  get platforms(): Array<string> {
    const result: Array<string> = [];
    for (const k of this.countMap.keys()) {
      result.push(k);
    }
    return result;
  }

  get length(): number {
    return this.array.length;
  }

  get currentSortType(): SortType {
    return this.sortType;
  }

  at(index: number): MusicItem | null {
    if (index < 0 || index >= this.array.length) {
      return null;
    }
    return this.array[index];
  }

  has(musicItem: MusicItem | null): boolean {
    if (musicItem === null) {
      return false;
    }
    const set = this.countMap.get(musicItem.platform);
    if (set === undefined) {
      return false;
    }
    return set.has(musicItem.id);
  }

  /** 设置排序类型 */
  setSortType(sortType: SortType): void {
    if (this.sortType === sortType && this.sortType !== SortType.None) {
      return;
    }
    this.sortType = sortType;
    this.resort();
  }

  /** 手动排序（重置为 None） */
  manualSort(newMusicItems: Array<MusicItem>): void {
    this.array = newMusicItems.slice();
    this.sortType = SortType.None;
  }

  /** 添加音乐，返回实际添加数量 */
  add(musicItems: Array<MusicItem>): number {
    const filtered: Array<MusicItem> = [];
    for (const it of musicItems) {
      if (!this.has(it)) {
        filtered.push(it);
      }
    }
    if (filtered.length === 0) {
      return 0;
    }
    this.addToCountMap(filtered);

    const compareFn = SortedMusicList.compareFnOf(this.sortType);
    if (compareFn === null) {
      this.array = filtered.concat(this.array);
      return filtered.length;
    }

    // 如果歌单内歌曲比较少
    if (this.array.length + filtered.length < 500 ||
      filtered.length / (this.array.length + 1) > 10) {
      this.array = filtered.concat(this.array);
      this.resort();
      return filtered.length;
    }
    // 如果歌单内歌曲比较多
    filtered.sort(compareFn);
    this.array = this.mergeArray(filtered, this.array, this.sortType);
    return filtered.length;
  }

  /** 移除指定音乐 */
  remove(musicItems: Array<MusicItem>): void {
    const removeMap: Map<string, Set<string>> = new Map();
    for (const it of musicItems) {
      let set = removeMap.get(it.platform);
      if (set === undefined) {
        set = new Set<string>();
        removeMap.set(it.platform, set);
      }
      set.add(it.id);
    }
    const result: Array<MusicItem> = [];
    for (const it of this.array) {
      const set = removeMap.get(it.platform);
      if (set !== undefined && set.has(it.id)) {
        continue;
      }
      result.push(it);
    }
    this.array = result;
    this.removeFromCountMap(musicItems);
  }

  /** 按下标移除 */
  removeByIndex(indices: Array<number>): void {
    const indicesSet = new Set<number>();
    for (const i of indices) {
      indicesSet.add(i);
    }
    const removedItems: Array<MusicItem> = [];
    const result: Array<MusicItem> = [];
    for (let i = 0; i < this.array.length; ++i) {
      if (indicesSet.has(i)) {
        removedItems.push(this.array[i]);
        continue;
      }
      result.push(this.array[i]);
    }
    this.array = result;
    this.removeFromCountMap(removedItems);
  }

  clearAll(): void {
    this.array = [];
  }

  /** 查找音乐下标；未找到返回 -1 */
  findIndex(musicItem: MusicItem): number {
    const compareFn = SortedMusicList.compareFnOf(this.sortType);
    if (compareFn === null) {
      for (let i = 0; i < this.array.length; ++i) {
        if (MediaUtils.isSameMediaItem(this.array[i], musicItem)) {
          return i;
        }
      }
      return -1;
    }
    let left = 0;
    let right = this.array.length;
    while (left < right) {
      const mid = Math.floor((left + right) / 2);
      const compareResult = compareFn(this.array[mid], musicItem);
      if (compareResult < 0) {
        left = mid + 1;
      } else if (compareResult === 0) {
        left = mid;
        break;
      } else {
        right = mid;
      }
    }
    return left === right ? -1 : left;
  }

  private addToCountMap(musicItems: Array<MusicItem>): void {
    for (const musicItem of musicItems) {
      let set = this.countMap.get(musicItem.platform);
      if (set === undefined) {
        set = new Set<string>();
        this.countMap.set(musicItem.platform, set);
      }
      set.add(musicItem.id);
    }
  }

  private removeFromCountMap(musicItems: Array<MusicItem>): void {
    for (const musicItem of musicItems) {
      const set = this.countMap.get(musicItem.platform);
      if (set !== undefined) {
        set.delete(musicItem.id);
        if (set.size === 0) {
          this.countMap.delete(musicItem.platform);
        }
      }
    }
  }

  /** 合并两个有序列表 */
  private mergeArray(musicList1: Array<MusicItem>, musicList2: Array<MusicItem>,
    sortType: SortType): Array<MusicItem> {
    const compareFn = SortedMusicList.compareFnOf(sortType);
    if (compareFn === null) {
      return musicList1.concat(musicList2);
    }
    let p1 = 0;
    let p2 = 0;
    const resultArray: Array<MusicItem> = [];
    while (p1 < musicList1.length && p2 < musicList2.length) {
      const peek1 = musicList1[p1];
      const peek2 = musicList2[p2];
      if (compareFn(peek1, peek2) < 0) {
        resultArray.push(peek1);
        ++p1;
      } else {
        resultArray.push(peek2);
        ++p2;
      }
    }
    if (p1 < musicList1.length) {
      return resultArray.concat(musicList1.slice(p1));
    }
    if (p2 < musicList2.length) {
      return resultArray.concat(musicList2.slice(p2));
    }
    return resultArray;
  }

  private resort(): void {
    const compareFn = SortedMusicList.compareFnOf(this.sortType);
    if (compareFn === null) {
      return;
    }
    this.array.sort(compareFn);
    this.array = this.array.slice();
  }
}
