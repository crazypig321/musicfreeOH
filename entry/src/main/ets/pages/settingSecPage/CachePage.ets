import { CommonNav, ScrollToTopYOffset, titleBarOf } from '../../view/CommonNav';
import { appState } from '../../entryability/AppState';
import { appConfig, ConfigKeys } from '../../core/AppConfig';
import { ContextHolder } from '../../common/ContextHolder';
import { PathConst } from '../../common/PathConst';
import { FileUtils } from '../../utils/FileUtils';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';
import { DialogManager } from '../../utils/DialogUtils';
import { ArtworkCache } from '../../utils/ArtworkCache';
import { DataReset } from '../../core/DataReset';
import { Delay } from '../../utils/Delay';
import { showUiToast, thickImmersiveMaterial } from '../../utils/UiUtils';
import { MenuOptionEntry, OptionsMenuBuilder } from '../../view/OptionsMenu';

/**
 * 缓存页面：音乐缓存上限 / 清除音乐缓存 / 清除图片缓存 / 清除歌词缓存 / 清除全部缓存 /
 * 本地音乐：本地音乐自动匹配音乐封面开关 / 应用数据：清空所有数据
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
  /** 匹配封面后写入音频文件开关 */
  @Local writeCoverToFile: boolean = false;
  /** 缓存上限菜单手动弹出开关 */
  @Local showCacheLimitMenu: boolean = false;
  /** 缓存上限候选值（对齐 RN 版 MusicFree 预设选项） */
  private static readonly CACHE_LIMIT_VALUES: Array<number> = [
    256 * 1024 * 1024,
    512 * 1024 * 1024,
    1024 * 1024 * 1024,
    2 * 1024 * 1024 * 1024,
    4 * 1024 * 1024 * 1024,
    8 * 1024 * 1024 * 1024
  ];

  aboutToAppear(): void {
    this.refreshSizes();
    this.maxCacheLimitText = CachePage.formatLimit(appConfig.getMaxCacheSize());
    this.autoMatchCover = appConfig.getLocalMusicAutoMatchCover();
    this.writeCoverToFile = appConfig.getCoverWriteToFile();
  }

  private showToast(message: string): void {
    showUiToast(this.getUIContext(), message);
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

  /** 菜单弹出位置：智感握姿开启且左手握持 → 左下（拇指可达），否则条目右下 */
  private menuPlacement(): Placement {
    return appConfig.getSmartReachEnabled() && appState.holdingHand === 'left'
      ? Placement.BottomLeft : Placement.BottomRight;
  }

  /** 缓存上限菜单选项 */
  private cacheLimitEntries(): Array<MenuOptionEntry> {
    const cur = appConfig.getMaxCacheSize();
    const entries: Array<MenuOptionEntry> = [];
    for (const bytes of CachePage.CACHE_LIMIT_VALUES) {
      entries.push(new MenuOptionEntry(bytes.toString(), CachePage.formatLimit(bytes), bytes === cur));
    }
    return entries;
  }

  /** 选中缓存上限 */
  private applyCacheLimit(value: string): void {
    const bytes = parseInt(value, 10);
    if (Number.isFinite(bytes) && bytes > 0) {
      appConfig.setConfig(ConfigKeys.MAX_CACHE_SIZE, bytes);
      this.maxCacheLimitText = CachePage.formatLimit(bytes);
    }
  }

  /** 缓存上限菜单 */
  @Builder
  private cacheLimitMenu(): void {
    OptionsMenuBuilder(this.cacheLimitEntries(), (value: string): void => {
      this.applyCacheLimit(value);
    }, (): void => {
      this.showCacheLimitMenu = true;
    })
  }

  /** 清除确认弹窗（对齐 RN 的 SimpleDialog 确认流程） */
  private confirmClear(message: string, onConfirm: () => void): void {
    DialogManager.ClearCache(message, onConfirm);
  }

  /** 清空所有数据：弹窗确认后清空全部应用数据并重启应用（内存态已不可信，重启拉起全新状态） */
  private doClearAll(): void {
    DialogManager.ConfirmClearData(
      '将清空歌单、插件、设置、订阅源、播放历史与全部缓存，此操作不可恢复；已下载的音乐文件不会被删除。确定继续吗？',
      (): void => {
        DataReset.clearAll();
        this.showToast('已清空所有数据，应用即将重启');
        Delay.wait(2000).then((): void => {
          this.restartApp();
        });
      }
    );
  }

  /**
   * 重启应用；restartApp 失败（如未获焦）时退化为退出应用
   * restartApp 不触发 onDestroy：清空后若走退出自动备份会把空数据覆盖云端 WebDAV 备份，此路径天然规避
   */
  private restartApp(): void {
    const context = ContextHolder.get();
    try {
      context.getApplicationContext().restartApp({
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name
      });
    } catch (_e) {
      context.terminateSelf().catch((_e2: Object): void => {
      });
    }
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf('缓存'),
      scroller: this.scroller,
      doubleTapToTop: true,
      scrollToTopYOffset: ScrollToTopYOffset()
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
              // 音乐缓存上限（智感握姿左手：值+chevron 镜像到行首，文本右对齐，图标镜像到行尾）
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Text(this.maxCacheLimitText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.icon_tertiary')])
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.music'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('音乐缓存上限')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Text(this.maxCacheLimitText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.icon_tertiary')])
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.music'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.showCacheLimitMenu = true;
              })
              .bindMenu(this.showCacheLimitMenu, this.cacheLimitMenu, {
                placement: this.menuPlacement(),
                systemMaterial: thickImmersiveMaterial(),
                onDisappear: (): void => {
                  this.showCacheLimitMenu = false;
                }
              })

              Divider()
                .DividerStyle()

              // 清除音乐缓存
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.music_note_phone'))
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
              .margin({ top: 16, bottom: 16 })

              Divider()
                .DividerStyle()

              // 匹配封面后写入音频文件（智感握姿左手：开关镜像到行首，文本右对齐，图标镜像到行尾）
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.writeCoverToFile })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.writeCoverToFile = isOn;
                      appConfig.setConfig(ConfigKeys.COVER_WRITE_TO_FILE, isOn);
                    })
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.text_below_photo_rectangle_portrait'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Column({ space: 2 }) {
                  Text('匹配封面后写入本地音频文件元数据')
                    .fontSize(15)
                    .fontColor($r('sys.color.font_primary'))
                  Text('下载歌曲与手动/自动/批量匹配封面时同步写入音频文件内嵌标签，正在播放与不可写文件跳过')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                    .maxLines(2)
                }
                .layoutWeight(1)
                .alignItems(appState.holdingHand === 'left' ? HorizontalAlign.End : HorizontalAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.writeCoverToFile })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.writeCoverToFile = isOn;
                      appConfig.setConfig(ConfigKeys.COVER_WRITE_TO_FILE, isOn);
                    })
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.text_below_photo_rectangle_portrait'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .margin({ top: 16, bottom: 16 })
            }
            .width('100%')
          }
          .ListItemStyle()

          // 小标题：应用数据
          ListItem() {
            Text('应用数据')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }

          // 清空所有数据（独立卡片，红色条目）
          ListItem() {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(20)
                .fontColor([Color.Red])
              Column({ space: 2 }) {
                Text('清空所有数据')
                  .fontSize(15)
                  .fontColor(Color.Red)
                Text('清空歌单、插件、设置、订阅源、播放历史与缓存，不可恢复；下载的音乐文件保留')
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                  .maxLines(2)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(14)
                .fontColor([$r('sys.color.icon_tertiary')])
            }
            .width('100%')
            .height(60)
            .onClick(() => {
              this.doClearAll();
            })
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
