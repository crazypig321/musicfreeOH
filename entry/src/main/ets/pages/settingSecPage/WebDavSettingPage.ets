import { CommonNav, titleBarOf } from '../../view/CommonNav';
import { appState } from '../../entryability/AppState';
import { appConfig, ConfigKeys } from '../../core/AppConfig';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';
import { WebDav } from '../../core/WebDav';
import { Backup } from '../../core/Backup';
import { ResumeMode } from '../../common/Consts';

/**
 * WebDAV 备份与恢复页面
 * 服务器地址 / 用户名 / 密码（实时保存）+ 退出时自动备份开关 + 备份到 WebDAV / 从 WebDAV 恢复
 * 备份文件固定为 musicfree-backup.json（覆盖式，保留最新一份）
 */
@ComponentV2
export struct WebDavSettingPage {
  scroller: Scroller = new Scroller();
  @Local url: string = appConfig.getWebdavUrl();
  @Local path: string = appConfig.getWebdavPath();
  @Local username: string = appConfig.getWebdavUsername();
  @Local password: string = appConfig.getWebdavPassword();
  @Local autoBackupOnExit: boolean = appConfig.getWebdavAutoBackupOnExit();
  @Local working: boolean = false;

  /** 备份文件相对服务器地址的完整路径（随配置实时刷新） */
  get backupFileDisplay(): string {
    return WebDav.folderUrl().substring(WebDav.serverUrl().length) + WebDav.BACKUP_FILENAME;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  /** 备份到 WebDAV */
  private doBackup(): void {
    if (this.working) {
      return;
    }
    if (!WebDav.isConfigured()) {
      this.showToast('请先填写 WebDAV 服务器地址');
      return;
    }
    this.working = true;
    this.showToast('正在备份到 WebDAV…');
    WebDav.backup().then((ok: boolean): void => {
      this.working = false;
      this.showToast(ok ? '备份成功' : '备份失败，请检查地址与账号');
    });
  }

  /** 从 WebDAV 恢复 */
  private doRestore(): void {
    if (this.working) {
      return;
    }
    if (!WebDav.isConfigured()) {
      this.showToast('请先填写 WebDAV 服务器地址');
      return;
    }
    this.working = true;
    this.showToast('正在从 WebDAV 恢复…');
    WebDav.restore().then((result): void => {
      if (result.notFound) {
        this.working = false;
        this.showToast('WebDAV 上没有备份文件');
        return;
      }
      if (!result.ok) {
        this.working = false;
        this.showToast('恢复失败，请检查地址与账号');
        return;
      }
      Backup.resume(result.data, ResumeMode.Append).then((): void => {
        this.working = false;
        this.showToast('恢复成功');
      }).catch((e: Object): void => {
        this.working = false;
        this.showToast('恢复失败：' + (e instanceof Error ? e.message : '备份文件格式无效'));
      });
    });
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf('WebDAV 备份与恢复'),
      scroller: this.scroller,
      doubleTapToTop: true
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 12 }) {
          // 小标题：服务器配置
          ListItem() {
            Text('服务器配置')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }

          ListItem() {
            Column() {
              // 服务器地址
              Row({ space: 12 }) {
                Text('服务器地址')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .width(80)
                TextInput({ text: this.url, placeholder: 'https://dav.example.com/dav/' })
                  .layoutWeight(1)
                  .fontSize(14)
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  .onChange((value: string) => {
                    this.url = value;
                    appConfig.setConfig(ConfigKeys.WEBDAV_URL, value);
                  })
              }
              .width('100%')
              .height(52)

              Divider()
                .DividerStyle('config')

              // 备份路径
              Row({ space: 12 }) {
                Text('备份路径')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .width(80)
                TextInput({ text: this.path, placeholder: '可选，如 /backups' })
                  .layoutWeight(1)
                  .fontSize(14)
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  .onChange((value: string) => {
                    this.path = value;
                    appConfig.setConfig(ConfigKeys.WEBDAV_PATH, value);
                  })
              }
              .width('100%')
              .height(52)

              Divider()
                .DividerStyle('config')

              // 用户名
              Row({ space: 12 }) {
                Text('用户名')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .width(80)
                TextInput({ text: this.username, placeholder: '可选' })
                  .layoutWeight(1)
                  .fontSize(14)
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  .onChange((value: string) => {
                    this.username = value;
                    appConfig.setConfig(ConfigKeys.WEBDAV_USERNAME, value);
                  })
              }
              .width('100%')
              .height(52)

              Divider()
                .DividerStyle('config')

              // 密码
              Row({ space: 12 }) {
                Text('密码')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .width(80)
                TextInput({ text: this.password, placeholder: '可选' })
                  .layoutWeight(1)
                  .fontSize(14)
                  .type(InputType.Password)
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  .onChange((value: string) => {
                    this.password = value;
                    appConfig.setConfig(ConfigKeys.WEBDAV_PASSWORD, value);
                  })
              }
              .width('100%')
              .height(52)
            }
            .width('100%')
          }
          .ListItemStyle()

          // 小标题：操作
          ListItem() {
            Text('操作')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }

          ListItem() {
            Column() {
              // 备份到 WebDAV
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.arrow_up_circle'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('备份到 WebDAV')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Text(this.backupFileDisplay)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                  .maxLines(1)
                  .width('50%')
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.doBackup();
              })

              Divider()
                .DividerStyle('do')

              // 从 WebDAV 恢复
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.arrow_down_circle'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('从 WebDAV 恢复')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.doRestore();
              })

              Divider()
                .DividerStyle('do')

              // 退出应用前自动备份
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('退出时自动备份')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.autoBackupOnExit })
                  .selectedColor(appState.accentColor)
                  .onChange((isOn: boolean) => {
                    this.autoBackupOnExit = isOn;
                    appConfig.setConfig(ConfigKeys.WEBDAV_AUTO_BACKUP_ON_EXIT, isOn);
                  })
              }
              .width('100%')
              .height(52)
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
function DividerStyle(key: 'config' | 'do') {
  .color($r('sys.color.comp_divider'))
  .margin({ left: key === 'config' ? 4 : 32, right: 4 })
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
