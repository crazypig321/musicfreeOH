/**
 * 桌面音乐卡片数据（卡片侧通过 @LocalStorageProp 同名字段接收）
 * formImages 键固定为 cover，卡片侧使用 Image('memory://cover') 引用；
 * hasCover 为 false 时卡片侧渲染本地兜底封面，不引用 memory://
 */
export class MusicCardData {
  formId: string = '';
  title: string = '';
  artist: string = '';
  isPlaying: boolean = false;
  isFavorite: boolean = false;
  hasCover: boolean = false;
  formImages: Record<string, number> = {};
}
