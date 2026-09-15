import { JsonUtil, JsonRecord, JsonArray } from '../JsonUtil';
import { MusicItem, MusicItemSerializer } from './MediaTypes';

/** 支持的搜索/媒体类型 */
export enum SupportMediaType {
  Music = 'music',
  Album = 'album',
  Artist = 'artist',
  Sheet = 'sheet',
  Lyric = 'lyric',
}

/** 歌单项（对应 IMusic.IMusicSheetItemBase） */
export class SheetItem {
  id: string = '';
  platform: string = '';
  title: string = '';
  artist: string = '';
  coverImg: string = '';
  artwork: string = '';
  description: string = '';
  worksNum: number = 0;
  createAt: number = 0;
  extras: JsonRecord = {};

  static fromRecord(rec: JsonRecord): SheetItem {
    const s = new SheetItem();
    s.id = JsonUtil.recStr(rec, 'id');
    s.platform = JsonUtil.recStr(rec, 'platform');
    s.title = JsonUtil.recStr(rec, 'title');
    s.artist = JsonUtil.recStr(rec, 'artist');
    s.coverImg = JsonUtil.recStr(rec, 'coverImg');
    s.artwork = JsonUtil.recStr(rec, 'artwork');
    s.description = JsonUtil.recStr(rec, 'description');
    s.worksNum = JsonUtil.recNum(rec, 'worksNum');
    s.createAt = JsonUtil.recNum(rec, 'createAt');
    s.extras = JsonUtil.filterOutKnown(rec, ['id', 'platform', 'title', 'artist', 'coverImg', 'artwork', 'description', 'worksNum', 'createAt']);
    return s;
  }

  toRecord(): JsonRecord {
    const rec: JsonRecord = {
      'id': this.id,
      'platform': this.platform,
    };
    if (this.title.length > 0) { rec['title'] = this.title; }
    if (this.artist.length > 0) { rec['artist'] = this.artist; }
    if (this.coverImg.length > 0) { rec['coverImg'] = this.coverImg; }
    if (this.artwork.length > 0) { rec['artwork'] = this.artwork; }
    if (this.description.length > 0) { rec['description'] = this.description; }
    if (this.worksNum > 0) { rec['worksNum'] = this.worksNum; }
    if (this.createAt > 0) { rec['createAt'] = this.createAt; }
    for (const k of Object.keys(this.extras)) {
      rec[k] = this.extras[k];
    }
    return rec;
  }
}

/** 专辑项 */
export class AlbumItem {
  id: string = '';
  platform: string = '';
  title: string = '';
  artist: string = '';
  artwork: string = '';
  date: string = '';
  description: string = '';
  worksNum: number = 0;
  extras: JsonRecord = {};

  static fromRecord(rec: JsonRecord): AlbumItem {
    const a = new AlbumItem();
    a.id = JsonUtil.recStr(rec, 'id');
    a.platform = JsonUtil.recStr(rec, 'platform');
    a.title = JsonUtil.recStr(rec, 'title');
    a.artist = JsonUtil.recStr(rec, 'artist');
    a.artwork = JsonUtil.recStr(rec, 'artwork');
    a.date = JsonUtil.recStr(rec, 'date');
    a.description = JsonUtil.recStr(rec, 'description');
    a.worksNum = JsonUtil.recNum(rec, 'worksNum');
    a.extras = JsonUtil.filterOutKnown(rec, ['id', 'platform', 'title', 'artist', 'artwork', 'date', 'description', 'worksNum']);
    return a;
  }

  toRecord(): JsonRecord {
    const rec: JsonRecord = {
      'id': this.id,
      'platform': this.platform,
      'title': this.title,
    };
    if (this.artist.length > 0) { rec['artist'] = this.artist; }
    if (this.artwork.length > 0) { rec['artwork'] = this.artwork; }
    if (this.date.length > 0) { rec['date'] = this.date; }
    if (this.description.length > 0) { rec['description'] = this.description; }
    if (this.worksNum > 0) { rec['worksNum'] = this.worksNum; }
    for (const k of Object.keys(this.extras)) {
      rec[k] = this.extras[k];
    }
    return rec;
  }
}

/** 歌手项 */
export class ArtistItem {
  id: string = '';
  platform: string = '';
  name: string = '';
  avatar: string = '';
  description: string = '';
  fans: number = 0;
  worksNum: number = 0;
  extras: JsonRecord = {};

  static fromRecord(rec: JsonRecord): ArtistItem {
    const a = new ArtistItem();
    a.id = JsonUtil.recStr(rec, 'id');
    a.platform = JsonUtil.recStr(rec, 'platform');
    a.name = JsonUtil.recStr(rec, 'name');
    a.avatar = JsonUtil.recStr(rec, 'avatar');
    a.description = JsonUtil.recStr(rec, 'description');
    a.fans = JsonUtil.recNum(rec, 'fans');
    a.worksNum = JsonUtil.recNum(rec, 'worksNum');
    a.extras = JsonUtil.filterOutKnown(rec, ['id', 'platform', 'name', 'avatar', 'description', 'fans', 'worksNum']);
    return a;
  }

  toRecord(): JsonRecord {
    const rec: JsonRecord = {
      'id': this.id,
      'platform': this.platform,
      'name': this.name,
    };
    if (this.avatar.length > 0) { rec['avatar'] = this.avatar; }
    if (this.description.length > 0) { rec['description'] = this.description; }
    if (this.fans > 0) { rec['fans'] = this.fans; }
    if (this.worksNum > 0) { rec['worksNum'] = this.worksNum; }
    for (const k of Object.keys(this.extras)) {
      rec[k] = this.extras[k];
    }
    return rec;
  }
}

/** 歌单分组（榜单） */
export class SheetGroupItem {
  title: string = '';
  data: Array<SheetItem> = [];

  static fromRecord(rec: JsonRecord): SheetGroupItem {
    const g = new SheetGroupItem();
    g.title = JsonUtil.recStr(rec, 'title');
    const arr = JsonUtil.recArray(rec, 'data');
    if (arr !== null) {
      for (const o of arr) {
        const r = JsonUtil.objToRecord(o);
        if (r !== null) {
          g.data.push(SheetItem.fromRecord(r));
        }
      }
    }
    return g;
  }
}

/** 推荐歌单 tag（对应 ICommon.IUnique） */
export class MediaTag {
  id: string = '';
  title: string = '';
  extras: JsonRecord = {};

  static fromRecord(rec: JsonRecord): MediaTag {
    const t = new MediaTag();
    t.id = JsonUtil.recStr(rec, 'id');
    t.title = JsonUtil.recStr(rec, 'title');
    t.extras = JsonUtil.filterOutKnown(rec, ['id', 'title']);
    return t;
  }

  toRecord(): JsonRecord {
    const rec: JsonRecord = { 'id': this.id };
    if (this.title.length > 0) { rec['title'] = this.title; }
    for (const k of Object.keys(this.extras)) {
      rec[k] = this.extras[k];
    }
    return rec;
  }
}

/** 评论 */
export class CommentItem {
  id: string = '';
  nickName: string = '';
  avatar: string = '';
  comment: string = '';
  likeCount: number = 0;
  createAt: number = 0;
  location: string = '';

  static fromRecord(rec: JsonRecord): CommentItem {
    const c = new CommentItem();
    c.id = JsonUtil.recStr(rec, 'id');
    c.nickName = JsonUtil.recStr(rec, 'nickName');
    c.avatar = JsonUtil.recStr(rec, 'avatar');
    c.comment = JsonUtil.recStr(rec, 'comment');
    c.likeCount = JsonUtil.recNum(rec, 'like');
    c.createAt = JsonUtil.recNum(rec, 'createAt');
    c.location = JsonUtil.recStr(rec, 'location');
    return c;
  }
}

/** 分页结果 */
export class PageResult<T> {
  isEnd: boolean = false;
  data: Array<T> = [];
}

/** 搜索结果（多态数据） */
export class SearchResult {
  isEnd: boolean = false;
  musicData: Array<MusicItem> = [];
  albumData: Array<AlbumItem> = [];
  artistData: Array<ArtistItem> = [];
  sheetData: Array<SheetItem> = [];
  lyricData: Array<MusicItem> = [];

  static fromJson(v: Object | null, type: SupportMediaType): SearchResult {
    const result = new SearchResult();
    const rec = JsonUtil.objToRecord(v);
    if (rec === null) {
      // RN 语义：结果为空时 ?? {}，isEnd ?? true → true
      result.isEnd = true;
      return result;
    }
    result.isEnd = JsonUtil.recBool(rec, 'isEnd', true);
    const arr = JsonUtil.recArray(rec, 'data');
    if (arr === null) {
      return result;
    }
    for (const o of arr) {
      const r = JsonUtil.objToRecord(o);
      if (r === null) {
        continue;
      }
      if (type === SupportMediaType.Music) {
        result.musicData.push(MusicItem.fromRecord(r));
      } else if (type === SupportMediaType.Album) {
        result.albumData.push(AlbumItem.fromRecord(r));
      } else if (type === SupportMediaType.Artist) {
        result.artistData.push(ArtistItem.fromRecord(r));
      } else if (type === SupportMediaType.Sheet) {
        result.sheetData.push(SheetItem.fromRecord(r));
      } else {
        result.lyricData.push(MusicItem.fromRecord(r));
      }
    }
    return result;
  }
}

/** 专辑信息结果 */
export class AlbumInfoResult {
  isEnd: boolean = false;
  albumItem: AlbumItem | null = null;
  musicList: Array<MusicItem> = [];

  static fromJson(v: Object | null): AlbumInfoResult {
    const result = new AlbumInfoResult();
    const rec = JsonUtil.objToRecord(v);
    if (rec === null) {
      return result;
    }
    result.isEnd = JsonUtil.recBool(rec, 'isEnd', true);
    const albumRec = JsonUtil.recRecord(rec, 'albumItem');
    if (albumRec !== null) {
      result.albumItem = AlbumItem.fromRecord(albumRec);
    }
    result.musicList = MusicItemSerializer.fromArray(rec['musicList']);
    return result;
  }
}

/** 歌单信息结果 */
export class SheetInfoResult {
  isEnd: boolean = false;
  sheetItem: SheetItem | null = null;
  musicList: Array<MusicItem> = [];

  static fromJson(v: Object | null): SheetInfoResult {
    const result = new SheetInfoResult();
    const rec = JsonUtil.objToRecord(v);
    if (rec === null) {
      return result;
    }
    result.isEnd = JsonUtil.recBool(rec, 'isEnd', true);
    const sheetRec = JsonUtil.recRecord(rec, 'sheetItem');
    if (sheetRec !== null) {
      result.sheetItem = SheetItem.fromRecord(sheetRec);
    }
    result.musicList = MusicItemSerializer.fromArray(rec['musicList']);
    return result;
  }
}

/** 榜单详情结果 */
export class TopListInfoResult {
  isEnd: boolean = false;
  topListItem: SheetItem | null = null;
  musicList: Array<MusicItem> = [];

  static fromJson(v: Object | null): TopListInfoResult {
    const result = new TopListInfoResult();
    const rec = JsonUtil.objToRecord(v);
    if (rec === null) {
      return result;
    }
    result.isEnd = JsonUtil.recBool(rec, 'isEnd', true);
    const sheetRec = JsonUtil.recRecord(rec, 'topListItem');
    if (sheetRec !== null) {
      result.topListItem = SheetItem.fromRecord(sheetRec);
    }
    result.musicList = MusicItemSerializer.fromArray(rec['musicList']);
    return result;
  }
}

/** 推荐歌单 tag 结果 */
export class RecommendSheetTagsResult {
  pinned: Array<SheetItem> = [];
  data: Array<SheetGroupItem> = [];

  static fromJson(v: Object | null): RecommendSheetTagsResult {
    const result = new RecommendSheetTagsResult();
    const rec = JsonUtil.objToRecord(v);
    if (rec === null) {
      return result;
    }
    const pinnedArr = JsonUtil.recArray(rec, 'pinned');
    if (pinnedArr !== null) {
      for (const o of pinnedArr) {
        const r = JsonUtil.objToRecord(o);
        if (r !== null) {
          result.pinned.push(SheetItem.fromRecord(r));
        }
      }
    }
    const dataArr = JsonUtil.recArray(rec, 'data');
    if (dataArr !== null) {
      for (const o of dataArr) {
        const r = JsonUtil.objToRecord(o);
        if (r !== null) {
          result.data.push(SheetGroupItem.fromRecord(r));
        }
      }
    }
    return result;
  }
}

/** 评论分页结果 */
export class CommentsResult {
  isEnd: boolean = false;
  data: Array<CommentItem> = [];

  static fromJson(v: Object | null): CommentsResult {
    const result = new CommentsResult();
    const rec = JsonUtil.objToRecord(v);
    if (rec === null) {
      return result;
    }
    result.isEnd = JsonUtil.recBool(rec, 'isEnd', true);
    const arr = JsonUtil.recArray(rec, 'data');
    if (arr !== null) {
      for (const o of arr) {
        const r = JsonUtil.objToRecord(o);
        if (r !== null) {
          result.data.push(CommentItem.fromRecord(r));
        }
      }
    }
    return result;
  }
}

/** 歌单（本地）基信息 */
export class MusicSheetBase {
  id: string = '';
  title: string = '';
  /** 创建时间戳 */
  createTime: number = 0;
  /** 封面 */
  coverImg: string = '';

  static fromRecord(rec: JsonRecord): MusicSheetBase {
    const b = new MusicSheetBase();
    b.id = JsonUtil.recStr(rec, 'id');
    b.title = JsonUtil.recStr(rec, 'title');
    b.createTime = JsonUtil.recNum(rec, 'createTime');
    b.coverImg = JsonUtil.recStr(rec, 'coverImg');
    return b;
  }

  toRecord(): JsonRecord {
    const rec: JsonRecord = {
      'id': this.id,
      'title': this.title,
      'createTime': this.createTime,
    };
    if (this.coverImg.length > 0) {
      rec['coverImg'] = this.coverImg;
    }
    return rec;
  }
}

export class SheetSerializer {
  static serializeSheets(sheets: Array<MusicSheetBase>): string {
    const arr: JsonArray = [];
    for (const s of sheets) {
      arr.push(s.toRecord());
    }
    return JSON.stringify(arr);
  }

  static deserializeSheets(raw: string | null | undefined): Array<MusicSheetBase> {
    const arr = JsonUtil.parseRecordArray(raw);
    if (arr === null) {
      return [];
    }
    const result: Array<MusicSheetBase> = [];
    for (const rec of arr) {
      result.push(MusicSheetBase.fromRecord(rec));
    }
    return result;
  }
}
