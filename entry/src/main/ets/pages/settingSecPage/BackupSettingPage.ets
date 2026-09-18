import { picker, fileIo as fs } from '@kit.CoreFileKit';
import util from '@ohos.util';
import { CommonNav, titleBarOf } from '../../view/CommonNav';
import { appState } from '../../entryability/AppState';
import { ContextHolder } from '../../common/ContextHolder';
import { PathConst } from '../../common/PathConst';
import { FileUtils } from '../../utils/FileUtils';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';
import { NavPathUtils } from '../../utils/NavPathUtils';
import { ROUTE_WEBDAV_SETTING } from '../../common/model/NavModels';
import { Backup } from '../../core/Backup';
import { ResumeMode } from '../../common/Consts';

/**
 * 备份与恢复设置页面
 * 本地备份与恢复：备份（导出到本地文件）/ 恢复（从本地备份文件）
 * WebDAV 备份与恢复：WebDAV 服务器（云端备份与恢复入口）
 * 条目行 UI 同其他设置二级页面（图标 + 标题/小字说明 + chevron）
 */
@ComponentV2
export struct BackupSettingPage {
  scroller: Scroller = new Scroller();

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
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

  /** 恢复：选择本地备份文件并合并恢复 */
  private doRestore(): void {
    try {
      const documentPicker = new picker.DocumentViewPicker(ContextHolder.get());
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.json'];
      documentPicker.select(options).then((uris: Array<string>) => {
        if (uris.length === 0) {
          return;
        }
        this.restoreFrom(uris[0]);
      }).catch((_e: Object): void => {
        this.showToast('选择文件失败');
      });
    } catch (error) {
      this.showToast('无法打开文件选择器');
    }
  }

  /** 读取备份文件并恢复（歌单合并，插件同源且本地版本更高则跳过） */
  private restoreFrom(uri: string): void {
    // 经缓存目录中转读取（与插件导入一致的 URI 读取方式）
    const cachePath = PathConst.cachePath + 'backup_read_' + Date.now().toString() + '.json';
    try {
      const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const dst = fs.openSync(cachePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.copyFileSync(src.fd, dst.fd);
      fs.closeSync(src);
      fs.closeSync(dst);
    } catch (error) {
      this.showToast('读取备份文件失败');
      return;
    }
    const text = FileUtils.readFileText(cachePath);
    FileUtils.unlink(cachePath);
    if (text === null || text.length === 0) {
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
      doubleTapToTop: true
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 12 }) {
          // 小标题：本地备份与恢复
          ListItem() {
            Text('本地备份与恢复')
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
                  Text('将歌单、插件、设置与订阅源导出为 JSON 备份文件，保存到本地')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
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
                  Text('从本地备份文件恢复歌单、插件、设置与订阅源，与现有数据合并')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
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
                this.doRestore();
              })
            }
            .width('100%')
          }
          .ListItemStyle()

          // 小标题：WebDAV 备份与恢复
          ListItem() {
            Text('WebDAV 备份与恢复')
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
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
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
