import { CommonNav, ScrollToTopYOffset, titleBarOf } from '../../view/CommonNav';
import { appState } from '../../entryability/AppState';
import { appConfig, ConfigKeys } from '../../core/AppConfig';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';
import { WebDav, WebDavBackupEntry } from '../../core/WebDav';
import { Backup } from '../../core/Backup';
import { ResumeMode } from '../../common/Consts';
import { DialogManager } from '../../utils/DialogUtils';
import { showUiToast } from '../../utils/UiUtils';

/** 连通性状态点颜色（无系统语义绿 token，状态色为固定色值）：连通绿 / 未连通红 */
const DOT_CONNECTED: string = '#FF64BB5C';
const DOT_DISCONNECTED: string = '#FFF44336';

/**
 * WebDAV 备份与恢复页面
 * 服务器地址 / 备份路径 / 用户名 / 密码（实时保存）+ 退出时自动备份开关 + 备份保留数量 +
 * 备份到 WebDAV / 从 WebDAV 恢复
 * 每次备份生成独立文件 musicfree-backup_yyyyMMdd_HHmmss_设备名.json（互不覆盖），
 * 超出保留数量时删除最老备份；恢复时拉取远端备份列表弹窗选择文件
 * 恢复走 Backup.resume：musicfreeOH 备份与原版 MusicFree 备份均可（原版自动转换）
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
  /** 备份保留数量展示文本（设置成功后刷新） */
  @Local maxBackupCountText: string = appConfig.getWebdavMaxBackupCount().toString() + ' 个';
  /** 连通性状态：0 检测中 / 1 已连通 / 2 未连通（探测失败或未配置） */
  @Local reachState: number = 0;
  /** 输入防抖定时器句柄 */
  private reachTimer: number = -1;

  aboutToAppear(): void {
    this.refreshReachable();
  }

  aboutToDisappear(): void {
    if (this.reachTimer >= 0) {
      clearTimeout(this.reachTimer);
      this.reachTimer = -1;
    }
  }

  /** 服务器配置变更后防抖重新探测连通性 */
  @Monitor('url', 'path', 'username', 'password')
  onWebdavConfigChanged(): void {
    if (this.reachTimer >= 0) {
      clearTimeout(this.reachTimer);
    }
    this.reachTimer = setTimeout((): void => {
      this.reachTimer = -1;
      this.refreshReachable();
    }, 800);
  }

  /** 立即探测服务器连通性并刷新状态点 */
  private refreshReachable(): void {
    this.reachState = 0;
    WebDav.checkConnectivity().then((ok: boolean): void => {
      this.reachState = ok ? 1 : 2;
    }).catch((): void => {
      this.reachState = 2;
    });
  }

  /** 连通性状态文本：检测中 / 已连通 / 未连通 */
  private get reachStateText(): string {
    if (this.reachState === 1) {
      return '已连通';
    }
    if (this.reachState === 2) {
      return '未连通';
    }
    return '检测中';
  }

  /** 连通性状态点颜色：连通绿 / 未连通红 / 检测中灰 */
  private get reachDotColor(): ResourceColor {
    if (this.reachState === 1) {
      return DOT_CONNECTED;
    }
    if (this.reachState === 2) {
      return DOT_DISCONNECTED;
    }
    return $r('sys.color.icon_tertiary');
  }

  /** 备份目录相对服务器地址的路径（随配置实时刷新，备份文件名含时间戳与设备名不再固定展示） */
  get backupFileDisplay(): string {
    return WebDav.folderUrl().substring(WebDav.serverUrl().length);
  }

  private showToast(message: string): void {
    showUiToast(this.getUIContext(), message);
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
      this.reachState = ok ? 1 : 2;
      this.showToast(ok ? '备份成功' : '备份失败，请检查地址与账号');
    });
  }

  /** 从 WebDAV 恢复：先拉取远端备份列表，弹窗选择文件后恢复（原版 MusicFree 备份自动转换） */
  private doRestore(): void {
    if (this.working) {
      return;
    }
    if (!WebDav.isConfigured()) {
      this.showToast('请先填写 WebDAV 服务器地址');
      return;
    }
    this.working = true;
    WebDav.listBackups().then((entries): void => {
      this.working = false;
      if (entries === null) {
        this.showToast('获取备份列表失败，请检查地址与账号');
        return;
      }
      if (entries.length === 0) {
        this.showToast('WebDAV 上没有备份文件');
        return;
      }
      DialogManager.SelectWebDavBackup(entries, (fileName: string): void => {
        this.restoreFrom(fileName);
      });
    });
  }

  /** 备份保留数量：弹窗输入 1-50 整数，超出保留数量时备份后自动删除最老备份 */
  private showBackupCountDialog(): void {
    DialogManager.InputWebDavBackupCount(appConfig.getWebdavMaxBackupCount(), (count: number): void => {
      appConfig.setConfig(ConfigKeys.WEBDAV_MAX_BACKUP_COUNT, count);
      this.maxBackupCountText = count.toString() + ' 个';
      this.showToast('设置成功');
    });
  }

  /** 拉取选中的备份文件并恢复（歌单合并，插件同源且本地版本更高则跳过） */
  private restoreFrom(fileName: string): void {
    this.working = true;
    this.showToast('正在从 WebDAV 恢复…');
    WebDav.restore(fileName).then((result): void => {
      if (result.notFound) {
        this.working = false;
        this.showToast('备份文件不存在');
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
      doubleTapToTop: true,
      scrollToTopYOffset: ScrollToTopYOffset()
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 12 }) {
          // 小标题：服务器配置（右侧连通性状态点：绿=连通 / 红=未连通 / 灰=检测中）
          ListItem() {
            Row() {
              Text('服务器配置')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_secondary'))
                .layoutWeight(1)
              Text(this.reachStateText)
                .fontSize(12)
                .fontColor($r('sys.color.font_tertiary'))
              Circle({ width: 8, height: 8 })
                .fill(this.reachDotColor)
                .margin({ left: 6 })
            }
            .width('100%')
          }

          ListItem() {
            Column() {
              // 服务器地址（智感握姿左手：输入框镜像到行首，标签镜像到行尾右对齐）
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  TextInput({ text: this.url, placeholder: 'https://dav.example.com/dav/' })
                    .layoutWeight(1)
                    .fontSize(14)
                    .backgroundColor($r('sys.color.comp_background_tertiary'))
                    .onChange((value: string) => {
                      this.url = value;
                      appConfig.setConfig(ConfigKeys.WEBDAV_URL, value);
                    })
                }
                Text('服务器地址')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .width(80)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  TextInput({ text: this.url, placeholder: 'https://dav.example.com/dav/' })
                    .layoutWeight(1)
                    .fontSize(14)
                    .backgroundColor($r('sys.color.comp_background_tertiary'))
                    .onChange((value: string) => {
                      this.url = value;
                      appConfig.setConfig(ConfigKeys.WEBDAV_URL, value);
                    })
                }
              }
              .width('100%')
              .height(52)

              Divider()
                .DividerStyle('config')

              // 备份路径（智感握姿左手：输入框镜像到行首，标签镜像到行尾右对齐）
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  TextInput({ text: this.path, placeholder: '可选，如 /backups' })
                    .layoutWeight(1)
                    .fontSize(14)
                    .backgroundColor($r('sys.color.comp_background_tertiary'))
                    .onChange((value: string) => {
                      this.path = value;
                      appConfig.setConfig(ConfigKeys.WEBDAV_PATH, value);
                    })
                }
                Text('备份路径')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .width(80)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  TextInput({ text: this.path, placeholder: '可选，如 /backups' })
                    .layoutWeight(1)
                    .fontSize(14)
                    .backgroundColor($r('sys.color.comp_background_tertiary'))
                    .onChange((value: string) => {
                      this.path = value;
                      appConfig.setConfig(ConfigKeys.WEBDAV_PATH, value);
                    })
                }
              }
              .width('100%')
              .height(52)

              Divider()
                .DividerStyle('config')

              // 用户名（智感握姿左手：输入框镜像到行首，标签镜像到行尾右对齐）
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  TextInput({ text: this.username, placeholder: '可选' })
                    .layoutWeight(1)
                    .fontSize(14)
                    .backgroundColor($r('sys.color.comp_background_tertiary'))
                    .onChange((value: string) => {
                      this.username = value;
                      appConfig.setConfig(ConfigKeys.WEBDAV_USERNAME, value);
                    })
                }
                Text('用户名')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .width(80)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  TextInput({ text: this.username, placeholder: '可选' })
                    .layoutWeight(1)
                    .fontSize(14)
                    .backgroundColor($r('sys.color.comp_background_tertiary'))
                    .onChange((value: string) => {
                      this.username = value;
                      appConfig.setConfig(ConfigKeys.WEBDAV_USERNAME, value);
                    })
                }
              }
              .width('100%')
              .height(52)

              Divider()
                .DividerStyle('config')

              // 密码（智感握姿左手：输入框镜像到行首，标签镜像到行尾右对齐）
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
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
                Text('密码')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .width(80)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
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
              // 备份到 WebDAV（智感握姿左手：路径文本镜像到行首，标题右对齐，图标镜像到行尾）
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Text(this.backupFileDisplay)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                    .maxLines(1)
                    .width('50%')
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.arrow_up_circle'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('备份到 WebDAV')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Text(this.backupFileDisplay)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                    .maxLines(1)
                    .width('50%')
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.arrow_up_circle'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.doBackup();
              })

              Divider()
                .DividerStyle('do')

              // 从 WebDAV 恢复（智感握姿左手：标题右对齐，图标镜像到行尾）
              Row({ space: 12 }) {
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.arrow_down_circle'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('从 WebDAV 恢复')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.arrow_down_circle'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.doRestore();
              })

              Divider()
                .DividerStyle('do')

              // 退出应用前自动备份（智感握姿左手：开关镜像到行首，文本右对齐，图标镜像到行尾）
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.autoBackupOnExit })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.autoBackupOnExit = isOn;
                      appConfig.setConfig(ConfigKeys.WEBDAV_AUTO_BACKUP_ON_EXIT, isOn);
                    })
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('退出时自动备份')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Toggle({ type: ToggleType.Switch, isOn: this.autoBackupOnExit })
                    .selectedColor(appState.accentColor)
                    .onChange((isOn: boolean) => {
                      this.autoBackupOnExit = isOn;
                      appConfig.setConfig(ConfigKeys.WEBDAV_AUTO_BACKUP_ON_EXIT, isOn);
                    })
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)

              Divider()
                .DividerStyle('do')

              // 备份保留数量（智感握姿左手：数值镜像到行首，标题右对齐，图标镜像到行尾）
              Row({ space: 12 }) {
                if (appState.holdingHand === 'left') {
                  Text(this.maxBackupCountText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                }
                if (appState.holdingHand !== 'left') {
                  SymbolGlyph($r('sys.symbol.doc_text_on_doc_text'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                Text('备份保留数量')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(appState.holdingHand === 'left' ? TextAlign.End : TextAlign.Start)
                if (appState.holdingHand !== 'left') {
                  Text(this.maxBackupCountText)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                }
                if (appState.holdingHand === 'left') {
                  SymbolGlyph($r('sys.symbol.doc_text_on_doc_text'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.showBackupCountDialog();
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
function DividerStyle(key: 'config' | 'do') {
  .color($r('sys.color.comp_divider'))
  .margin(appState.holdingHand === 'left' ?
    { left: key === 'config' ? 4 : 4, right: key === 'config' ? 4 : 32 } :
    { left: key === 'config' ? 4 : 32, right: 4 })
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
