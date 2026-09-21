import { CommonNav, titleBarOf } from '../../view/CommonNav';
import { appState } from '../../entryability/AppState';
import { appConfig, ConfigKeys } from '../../core/AppConfig';
import { PathConst } from '../../common/PathConst';
import { FileUtils } from '../../utils/FileUtils';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';
import { DialogManager } from '../../utils/DialogUtils';
import { ArtworkCache } from '../../utils/ArtworkCache';

/**
 * 缓存页面：音乐缓存上限 / 清除音乐缓存 / 清除图片缓存 / 清除歌词缓存 / 清除全部缓存 /
 * 本地音乐：本地音乐自动匹配音乐封面开关
 * 从设置页「缓存」条目进入；条目行 UI 同关于页
 */
@ComponentV2
export struct CachePage {
  scroller: Scroller = new Scroller();
  @Local musicCacheSize: number = 0;
  @Local imageSize: number = 0;
  @Local lyricSize: number = 0;
  /** 音乐缓存上限展示文本（值 + 单位，设置成功后刷新） */
  @Local maxCacheLimitText: string = '';
  /** 本地音乐自动匹配音乐封面开关 */
  @Local autoMatchCover: boolean = true;

  aboutToAppear(): void {
    this.refreshSizes();
    this.maxCacheLimitText = CachePage.formatLimit(appConfig.getMaxCacheSize());
    this.autoMatchCover = appConfig.getLocalMusicAutoMatchCover();
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  /** 重新统计各缓存目录大小 */
  private refreshSizes(): void {
    this.musicCacheSize = FileUtils.getFolderSize(PathConst.musicCachePath);
    this.imageSize = FileUtils.getFolderSize(PathConst.artworkCachePath);
    this.lyricSize = FileUtils.getFolderSize(PathConst.lrcCachePath);
  }

  /** 字节数格式化（对齐 RN sizeFormatter） */
  private static formatSize(bytes: number): string {
    if (bytes <= 0) {
      return '0B';
    }
    const k = 1024;
    const sizes: Array<string> = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.min(Math.floor(Math.log(bytes) / Math.log(k)), sizes.length - 1);
    return (bytes / Math.pow(k, i)).toFixed(1) + sizes[i];
  }

  /** 清空目录内容并重建（目录不存在时仅重建） */
  private clearCacheDir(dir: string): void {
    FileUtils.removeDir(dir);
    FileUtils.checkAndCreateDir(dir);
  }

  /** 缓存上限格式化：整数 + 单位（如 512MB / 2GB） */
  private static formatLimit(bytes: number): string {
    const MB = 1024 * 1024;
    const GB = MB * 1024;
    if (bytes >= GB && bytes % GB === 0) {
      return (bytes / GB).toString() + 'GB';
    }
    return Math.round(bytes / MB).toString() + 'MB';
  }

  /** 音乐缓存上限：输入数值并选择单位（MB/GB），范围 100M-8G，存 basic.maxCacheSize */
  private showCacheLimitDialog(): void {
    const MB = 1024 * 1024;
    const GB = MB * 1024;
    const cur = appConfig.getMaxCacheSize();
    // 按当前值预选单位与数值
    if (cur >= GB && cur % GB === 0) {
      DialogManager.cacheInputUnit = 'G';
      DialogManager.cacheInputValue = (cur / GB).toString();
    } else {
      DialogManager.cacheInputUnit = 'M';
      DialogManager.cacheInputValue = Math.round(cur / MB).toString();
    }
    DialogManager.cacheInputConfirm = (text: string): void => {
      const val = parseInt(text, 10);
      if (isNaN(val)) {
        DialogManager.Toast('请输入 100M-8G 范围内的数字');
        return;
      }
      const unit = DialogManager.cacheInputUnit;
      const unitBytes = unit === 'G' ? GB : MB;
      // 越界自动收敛到边界（100M-8G，与 RN 行为一致）
      const clamped = Math.min(Math.max(val * unitBytes, 100 * MB), 8 * GB);
      appConfig.setConfig(ConfigKeys.MAX_CACHE_SIZE, clamped);
      // 条目右侧展示设置的值 + 单位
      this.maxCacheLimitText = (clamped / unitBytes).toString() + (unit === 'G' ? 'GB' : 'MB');
      this.showToast('设置成功');
    };
    DialogManager.OpenDialog('设置缓存');
  }

  /** 清除确认弹窗（对齐 RN 的 SimpleDialog 确认流程） */
  private confirmClear(message: string, onConfirm: () => void): void {
    DialogManager.clearCacheMessage = message;
    DialogManager.clearCacheConfirm = onConfirm;
    DialogManager.OpenDialog('清除缓存');
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf('缓存'),
      scroller: this.scroller,
      doubleTapToTop: true
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 12 }) {
          // 小标题
          ListItem() {
            Text('缓存管理')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }

          ListItem() {
            Column() {
              // 音乐缓存上限
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.music'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('音乐缓存上限')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Text(this.maxCacheLimitText)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([$r('sys.color.icon_tertiary')])
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.showCacheLimitDialog();
              })

              Divider()
                .DividerStyle()

              // 清除音乐缓存
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('清除音乐缓存')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Text(CachePage.formatSize(this.musicCacheSize))
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.confirmClear('确定清除音乐缓存吗？', (): void => {
                  this.clearCacheDir(PathConst.musicCachePath);
                  this.showToast('已清除音乐缓存');
                  this.refreshSizes();
                });
              })

              Divider()
                .DividerStyle()

              // 清除图片缓存
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.picture'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('清除图片缓存')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Text(CachePage.formatSize(this.imageSize))
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.confirmClear('确定清除图片缓存吗？', (): void => {
                  this.clearCacheDir(PathConst.artworkCachePath);
                  ArtworkCache.reset();
                  this.showToast('已清除图片缓存');
                  this.refreshSizes();
                });
              })

              Divider()
                .DividerStyle()

              // 清除歌词缓存
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.doc_plaintext'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('清除歌词缓存')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Text(CachePage.formatSize(this.lyricSize))
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.confirmClear('确定清除歌词缓存吗？', (): void => {
                  this.clearCacheDir(PathConst.lrcCachePath);
                  this.showToast('已清除歌词缓存');
                  this.refreshSizes();
                });
              })

              Divider()
                .DividerStyle()

              // 清除全部缓存
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.trash_fill'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('清除全部缓存')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Text(CachePage.formatSize(this.musicCacheSize + this.imageSize + this.lyricSize))
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.confirmClear('确定清除全部缓存吗？将删除音乐、图片、歌词缓存。', (): void => {
                  this.clearCacheDir(PathConst.musicCachePath);
                  this.clearCacheDir(PathConst.artworkCachePath);
                  ArtworkCache.reset();
                  this.clearCacheDir(PathConst.lrcCachePath);
                  this.showToast('已清除全部缓存');
                  this.refreshSizes();
                });
              })
            }
            .width('100%')
          }
          .ListItemStyle()

          // 小标题：本地音乐
          ListItem() {
            Text('本地音乐')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }

          ListItem() {
            Column() {
              // 本地音乐自动匹配音乐封面（智感握姿左手：开关镜像到行首，文本右对齐，图标镜像到行尾）
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.autoMatchCover })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.autoMatchCover = isOn;
                      appConfig.setConfig(ConfigKeys.LOCAL_MUSIC_AUTO_MATCH_COVER, isOn);
                    })
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.wand_and_stars'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Column({ space: 2 }) {
                  Text('本地音乐自动匹配音乐封面')
                    .fontSize(15)
                    .fontColor($r('sys.color.font_primary'))
                  Text('导入本地音乐后自动匹配内嵌封面，无内嵌封面时回填网络封面')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                    .maxLines(2)
                }
                .layoutWeight(1)
                .alignItems(appState.holdingHand === 'left' ? HorizontalAlign.End : HorizontalAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.autoMatchCover })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.autoMatchCover = isOn;
                      appConfig.setConfig(ConfigKeys.LOCAL_MUSIC_AUTO_MATCH_COVER, isOn);
                    })
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.wand_and_stars'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(60)
            }
            .width('100%')
          }
          .ListItemStyle()
        }
        .ListStyle()
        .onScrollFrameBegin((offset: number) => {
          BarScrollHelper.notifyScrollDelta(this.getUIContext(), offset)
          return { offsetRemain: offset }
        })
      }
    }
  }
}

@Extend(ListItem)
function ListItemStyle() {
  .width('100%')
  .borderRadius(16)
  .padding(12)
  .backgroundColor($r('sys.color.comp_background_list_card'))
}

@Extend(Divider)
function DividerStyle() {
  .color($r('sys.color.comp_divider'))
  .margin({ left: 32, right: 4 })
}

@Extend(List)
function ListStyle() {
  .width('100%')
  .height('100%')
  .scrollBar(BarState.Off)
  .edgeEffect(EdgeEffect.Spring)
  .contentStartOffset(appState.topRect + 66)
  .contentEndOffset(appState.bottomRect + (IsApiVersion_24() && appState.hdsBarLayoutMode === 1 ? 130 : 60))
  .padding({ left: 16, right: 16 })
}
