import { picker, fileIo as fs } from '@kit.CoreFileKit';
import util from '@ohos.util';
import { CommonNav, ScrollToTopYOffset, titleBarOf } from '../../view/CommonNav';
import { appState } from '../../entryability/AppState';
import { ContextHolder } from '../../common/ContextHolder';
import { PathConst } from '../../common/PathConst';
import { FileUtils } from '../../utils/FileUtils';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';
import { NavPathUtils } from '../../utils/NavPathUtils';
import { ROUTE_WEBDAV_SETTING } from '../../common/model/NavModels';
import { Backup } from '../../core/Backup';
import { ResumeMode } from '../../common/Consts';
import { showUiToast } from '../../utils/UiUtils';
import { appConfig } from '../../core/AppConfig';
import { DialogManager } from '../../utils/DialogUtils';

/**
 * 备份与恢复设置页面
 * 本地备份与恢复：备份（导出到本地文件）/ 恢复（从本地备份文件，原版 MusicFree 备份自动转换）
 * WebDAV 备份与恢复：WebDAV 服务器（云端备份与恢复入口，恢复同样支持原版备份自动转换）
 * 其他：同时备份插件配置数据开关（开启需弹窗确认——备份文件将包含账号等敏感信息，勿外传）
 * 条目行 UI 同其他设置二级页面（图标 + 标题/小字说明 + chevron）
 */
@ComponentV2
export struct BackupSettingPage {
  scroller: Scroller = new Scroller();
  @Local includePluginData: boolean = appConfig.getBackupIncludePluginData();

  private showToast(message: string): void {
    showUiToast(this.getUIContext(), message);
  }

  /** 备份文件名时间戳（yyyyMMdd_HHmmss） */
  private static timestamp(): string {
    const d = new Date();
    const p = (n: number): string => n < 10 ? '0' + n.toString() : n.toString();
    return d.getFullYear().toString() + p(d.getMonth() + 1) + p(d.getDate()) + '_' +
      p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds());
  }

  /** 备份：生成 JSON 并通过系统保存器存到本地 */
  private doBackup(): void {
    try {
      const documentPicker = new picker.DocumentViewPicker(ContextHolder.get());
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = ['musicfree_backup_' + BackupSettingPage.timestamp() + '.json'];
      documentPicker.save(options).then((uris: Array<string>) => {
        if (uris.length === 0) {
          return;
        }
        this.writeBackup(uris[0]);
      }).catch((_e: Object): void => {
        this.showToast('保存文件失败');
      });
    } catch (error) {
      this.showToast('无法打开文件保存器');
    }
  }

  /** 将备份 JSON 写入保存器返回的文件 */
  private writeBackup(uri: string): void {
    const text = Backup.backup();
    let ok = false;
    try {
      const file = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        const encoder = new util.TextEncoder();
        const u8 = encoder.encodeInto(text);
        fs.writeSync(file.fd, u8.buffer);
        ok = true;
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      ok = false;
    }
    this.showToast(ok ? '备份成功' : '备份失败');
  }

  /** 选择本地 JSON 备份文件（单选），选中后回调 */
  private pickJsonFile(onPicked: (uri: string) => void): void {
    try {
      const documentPicker = new picker.DocumentViewPicker(ContextHolder.get());
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.json'];
      documentPicker.select(options).then((uris: Array<string>) => {
        if (uris.length === 0) {
          return;
        }
        onPicked(uris[0]);
      }).catch((_e: Object): void => {
        this.showToast('选择文件失败');
      });
    } catch (error) {
      this.showToast('无法打开文件选择器');
    }
  }

  /** 读取备份文件文本（经缓存目录中转读取，与插件导入一致的 URI 读取方式） */
  private readBackupText(uri: string): string | null {
    const cachePath = PathConst.cachePath + 'backup_read_' + Date.now().toString() + '.json';
    try {
      const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const dst = fs.openSync(cachePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.copyFileSync(src.fd, dst.fd);
      fs.closeSync(src);
      fs.closeSync(dst);
    } catch (error) {
      return null;
    }
    const text = FileUtils.readFileText(cachePath);
    FileUtils.unlink(cachePath);
    if (text === null || text.length === 0) {
      return null;
    }
    return text;
  }

  /** 恢复：选择本地备份文件并合并恢复 */
  private doRestore(): void {
    this.pickJsonFile((uri: string): void => {
      this.restoreFrom(uri);
    });
  }

  /** 读取备份文件并恢复（歌单合并，插件同源且本地版本更高则跳过；原版备份自动转换） */
  private restoreFrom(uri: string): void {
    const text = this.readBackupText(uri);
    if (text === null) {
      this.showToast('读取备份文件失败');
      return;
    }
    this.showToast('正在恢复…');
    Backup.resume(text, ResumeMode.Append).then((): void => {
      this.showToast('恢复成功');
    }).catch((e: Object): void => {
      this.showToast('恢复失败：' + (e instanceof Error ? e.message : '备份文件格式无效'));
    });
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf('备份与恢复'),
      scroller: this.scroller,
      doubleTapToTop: true,
      scrollToTopYOffset: ScrollToTopYOffset()
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 12 }) {
          // 小标题：本地备份与恢复
          ListItem() {
            Text('本地')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }

          ListItem() {
            Column() {
              // 备份
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.arrow_up_circle'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Column({ space: 2 }) {
                  Text('备份')
                    .fontSize(15)
                    .fontColor($r('sys.color.font_primary'))
                  Text('将歌单、插件（含本地插件源码）、设置与订阅源导出为 JSON 备份文件，保存到本地')
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
                this.doBackup();
              })

              Divider()
                .DividerStyle()

              // 恢复
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.arrow_down_circle'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Column({ space: 2 }) {
                  Text('恢复')
                    .fontSize(15)
                    .fontColor($r('sys.color.font_primary'))
                  Text('从本地备份文件恢复歌单、插件、设置与订阅源，与现有数据合并；支持原版 MusicFree 备份（原版备份的本地插件无法正常恢复，需要重新导入）')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                    .maxLines(3)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([$r('sys.color.icon_tertiary')])
              }
              .width('100%')
              .padding({ top: 10, bottom: 8 })
              .onClick(() => {
                this.doRestore();
              })
            }
            .width('100%')
          }
          .ListItemStyle()

          // 小标题：WebDAV 备份与恢复
          ListItem() {
            Text('WebDAV')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }

          ListItem() {
            Column() {
              // WebDAV 备份与恢复
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.externaldrive'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Column({ space: 2 }) {
                  Text('WebDAV 备份与恢复')
                    .fontSize(15)
                    .fontColor($r('sys.color.font_primary'))
                  Text('通过 WebDAV 服务器在云端备份与恢复数据')
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
                NavPathUtils.push(ROUTE_WEBDAV_SETTING);
              })
            }
            .width('100%')
          }
          .ListItemStyle()

          // 小标题：其他
          ListItem() {
            Text('其他')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }

          ListItem() {
            Column() {
              // 同时备份插件配置数据
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.gearshape'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Column({ space: 2 }) {
                  Text('同时备份插件配置数据')
                    .fontSize(15)
                    .fontColor($r('sys.color.font_primary'))
                  Text('备份时将插件的配置变量（含账号、Cookie 等登录信息）一并写入备份文件，恢复时自动写回。开启后请勿将备份文件发送给他人，以免造成账号泄露')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                    .maxLines(4)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.includePluginData })
                  .selectedColor(appState.accentColor)
                  // 拦截触摸使开关状态仅由状态变量驱动（点击不会立即翻转）：
                  // 已开启直接关闭；未开启弹窗提醒账号泄露风险，确认后才开启，取消保持关闭
                  .onTouchIntercept((): HitTestMode => {
                    if (this.includePluginData) {
                      this.includePluginData = false;
                      appConfig.setBackupIncludePluginData(false);
                      return HitTestMode.None;
                    }
                    DialogManager.ConfirmBackupPluginData(
                      '开启后，备份文件将包含插件的配置变量，其中可能含有账号、Cookie 等登录信息。请勿将备份文件发送给他人，以免造成账号泄露。',
                      (): void => {
                        this.includePluginData = true;
                        appConfig.setBackupIncludePluginData(true);
                      });
                    return HitTestMode.None;
                  })
              }
              .width('100%')
              .padding({ top: 14, bottom: 14 })
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
