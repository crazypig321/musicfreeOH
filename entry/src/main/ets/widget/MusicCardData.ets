/**
 * 桌面音乐卡片数据（卡片侧通过 @LocalStorageProp 同名字段接收）
 * 封面通过 formImages 传 fd，卡片侧使用 Image('memory://' + coverKey) 引用；
 * coverKey 在封面变化时更换（同名 key 的图片数据更新不会触发卡片重载，必须换 key 强制刷新）
 * hasCover 为 false 时卡片侧渲染本地兜底封面，不引用 memory://
 */
/** 卡片背景主色透明度（两位十六进制，'40' 约 25%，应用侧与卡片进程需保持一致） */
export const CARD_BG_ALPHA_HEX = '40';
/** 卡片播放队列最大条目数（超出时以当前曲为中心截取窗口） */
export const CARD_MAX_QUEUE_ITEMS = 50;

export class MusicCardData {
  formId: string = '';
  title: string = '';
  artist: string = '';
  isPlaying: boolean = false;
  isFavorite: boolean = false;
  hasCover: boolean = false;
  coverKey: string = 'cover';
  /** 封面主色背景 '#AARRGGBB'，空串表示不设置 */
  bgColor: string = '';
  formImages: Record<string, number> = {};
  /** 当前歌词行（无歌词/未播放为空串） */
  lyric: string = '';
  /** 循环模式：'QUEUE' | 'SHUFFLE' | 'SINGLE' */
  repeatMode: string = 'QUEUE';
  /** 播放队列标题/歌手（并行数组，最多 CARD_MAX_QUEUE_ITEMS 条） */
  queueTitles: Array<string> = [];
  queueArtists: Array<string> = [];
  /** 队列窗口在完整播放队列中的起始下标（playIndex 命令需加回） */
  queueStart: number = 0;
  /** 当前曲在队列窗口中的下标（-1 表示无/不在窗口内） */
  queueIndex: number = -1;
}
