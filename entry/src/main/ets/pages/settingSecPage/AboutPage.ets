import { CommonNav, titleBarOf } from '../../view/CommonNav';
import { appState } from '../../entryability/AppState';
import { AppMeta } from '../../core/AppMeta';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';
import { DialogManager } from '../../utils/DialogUtils';
import { WebUtils } from '../../utils/WebUtils';
import { HttpClient } from '../../infra/HttpClient';
import { UpdateNotify } from '../../utils/UpdateNotify';
import { BackgroundTask } from '../../utils/BackgroundTask';
import { downloader } from '../../core/Downloader';
import { appConfig } from '../../core/AppConfig';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { ContextHolder } from '../../common/ContextHolder';
import { PathConst } from '../../common/PathConst';
import { FileUtils } from '../../utils/FileUtils';
import { ChangelogSheet } from '../../view/ChangelogSheet';
import { UpdateChecker, ReleaseAsset } from '../../utils/UpdateChecker';

/** 仓库地址常量 */
const REPO_OH: string = 'https://github.com/crazypig321/musicfreeOH.git';
const REPO_ORIGIN: string = 'https://github.com/maotoumao/MusicFree.git';
const DEV_HOME: string = 'https://github.com/crazypig321';
const DEP_DATE_URL: string = 'https://ohpm.openharmony.cn/#/cn/detail/@xiaoye%2Fdate';
const DEP_COLOR_PICKER_URL: string = 'https://ohpm.openharmony.cn/#/cn/detail/@keke%2Fcolor-picker';
const DEP_FREE_PCM_URL: string = 'https://ohpm.openharmony.cn/#/cn/detail/@ospark%2Ffree-pcm';

/** 关于页条目行：头像/图标 + 标题 + 右侧说明/开关 + chevron，可选点击行为 */
interface AboutRow {
  /** 头像图片（设置后优先于 icon 显示） */
  avatar?: Resource;
  /** SymbolGlyph 图标 */
  icon: Resource;
  title: string;
  /** 标题下方的小字说明 */
  subtitle?: string;
  /** 右侧说明文字 */
  trailing?: string;
  /** 右侧说明是否按长文本（地址）省略 */
  trailingEllipsis?: boolean;
  /** 右侧显示代理下载开关（代替 chevron/trailing） */
  trailingSwitch?: boolean;
  showChevron?: boolean;
  action?: () => void;
}

/** 关于页分组：标题 + 卡片内多行 */
interface AboutSection {
  title: string;
  rows: Array<AboutRow>;
}

/**
 * 关于页面：应用图标/名称/版本 + 开发者 + 项目地址 + 开源与条款 + 三方库
 * 从设置页「关于」条目进入
 */
@ComponentV2
export struct AboutPage {
  scroller: Scroller = new Scroller();
  /** GitHub 最新 release 版本号；为空表示无需更新（标签不展示），与 appState.latestVersion 同步 */
  @Local latestVersion: string = appState.latestVersion;
  /** 下载新版本时优先走国内代理加速（关闭时直连优先，代理仅作失败回退） */
  @Local proxyDownload: boolean = appConfig.getUpdateProxyDownload();
  /** 更新日志半模态 */
  @Local showChangelog: boolean = false;

  aboutToAppear(): void {
    this.checkUpdate();
  }

  /** 进入页面静默检查更新（与设置页共用会话内节流）：
   *  最新版本高于本地时记录，供版本号旁标签与设置页红点展示 */
  private async checkUpdate(): Promise<void> {
    await UpdateChecker.checkLatestSilently();
    this.latestVersion = appState.latestVersion;
  }

  /** 检查更新入口（新版本标签与「检查更新」条目共用）：无新版本时提示；有新版本时弹窗确认下载 */
  private async doCheckUpdate(): Promise<void> {
    this.showToast('正在检查更新…');
    const release = await UpdateChecker.fetchLatestRelease(this.proxyDownload);
    if (release === null) {
      this.showToast('检查更新失败，请稍后重试');
      return;
    }
    const tag = release.tag_name;
    if (tag === undefined || !UpdateChecker.isNewerVersion(tag, AppMeta.appVersion)) {
      appState.latestVersion = '';
      this.latestVersion = '';
      this.showToast('当前已是最新版本');
      return;
    }
    this.latestVersion = tag;
    appState.latestVersion = tag;
    const asset = UpdateChecker.pickReleaseAsset(release);
    if (asset === null) {
      this.showToast('发布页未提供软件包，请到发布页查看');
      return;
    }
    DialogManager.ConfirmUpdate('发现新版本 ' + tag + '，是否下载新版本安装包？', () => {
      UpdateNotify.ensureEnabled();
      this.pickSaveLocationAndDownload(asset);
    });
  }

  /** 弹出系统保存器选择存放位置（同备份导出），确认后下载软件包写入 */
  private pickSaveLocationAndDownload(asset: ReleaseAsset): void {
    try {
      const documentPicker = new picker.DocumentViewPicker(ContextHolder.get());
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [asset.name];
      documentPicker.save(options).then((uris: Array<string>) => {
        if (uris.length === 0) {
          return;
        }
        this.downloadUpdate(asset, uris[0]);
      }).catch((_e: Object): void => {
        this.showToast('保存文件失败');
      });
    } catch (error) {
      this.showToast('无法打开文件保存器');
    }
  }

  /** 下载软件包：直连不通时依次走国内代理，经缓存目录中转写入保存位置；
   *  通知栏进度同歌曲下载（dataTransfer 长时任务实况进度条 + 完成摘要通知） */
  private async downloadUpdate(asset: ReleaseAsset, destUri: string): Promise<void> {
    this.showToast('正在下载新版本…');
    const version = this.latestVersion.length > 0 ? this.latestVersion : asset.name;
    const nameText = '新版本 ' + version;
    const tempPath = PathConst.cachePath + 'update_' + Date.now().toString() + '_' + asset.name;
    const urls = UpdateChecker.orderedUrls(asset.url, this.proxyDownload);
    const headers: Record<string, string> = { 'User-Agent': 'musicfreeOH' };
    // 无歌曲下载批次运行时接管数据传输长时任务（进度实况通知 + 后台保活）；
    // 有批次运行时不接管，避免抢占/提前取消歌曲下载的任务与进度通知
    const holdTransfer = !downloader.isBatchActive();
    UpdateNotify.ensureEnabled();
    UpdateNotify.resetProgress();
    if (holdTransfer) {
      BackgroundTask.startTransfer((notificationId: number): void => {
        UpdateNotify.setSystemNotificationId(notificationId);
      });
    }
    let ok = false;
    try {
      for (const url of urls) {
        ok = await HttpClient.downloadToFile(url, tempPath, headers,
          (downloaded: number, total: number): void => {
            const percent = total > 0 ? Math.floor(downloaded * 100 / total) : 0;
            const sizeText = total > 0
              ? (downloaded / 1024 / 1024).toFixed(1) + 'MB/' + (total / 1024 / 1024).toFixed(1) + 'MB'
              : (downloaded / 1024 / 1024).toFixed(1) + 'MB';
            UpdateNotify.updateProgress(nameText, percent, sizeText);
          }, undefined, undefined, 300000);
        if (ok) {
          break;
        }
      }
    } finally {
      if (holdTransfer) {
        BackgroundTask.stopTransfer();
      }
    }
    if (!ok) {
      FileUtils.unlink(tempPath);
      UpdateNotify.showFailed();
      this.showToast('下载失败，请稍后重试');
      return;
    }
    try {
      const src = fs.openSync(tempPath, fs.OpenMode.READ_ONLY);
      const dst = fs.openSync(destUri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.copyFileSync(src.fd, dst.fd);
      } finally {
        fs.closeSync(src);
        fs.closeSync(dst);
      }
      UpdateNotify.showDone(asset.name);
      this.showToast('新版本 ' + asset.name + ' 已保存');
    } catch (e) {
      this.showToast('保存文件失败');
    } finally {
      FileUtils.unlink(tempPath);
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  /** 拉起系统浏览器打开网址 */
  private openWeb(url: string): void {
    WebUtils.open(url, (message: string): void => {
      this.showToast(message);
    });
  }

  /** 分组数据 */
  private sections(): Array<AboutSection> {
    return [
      {
        title: '开发者',
        rows: [
          {
            avatar: $r('app.media.crazypig321'),
            icon: $r('sys.symbol.person'),
            title: 'crazypig321',
            showChevron: true,
            action: (): void => {
              this.openWeb(DEV_HOME);
            }
          }
        ]
      },
      {
        title: '项目地址',
        rows: [
          {
            icon: $r('sys.symbol.store'),
            title: '项目仓库',
            trailing: REPO_OH,
            trailingEllipsis: true,
            action: (): void => {
              this.openWeb(REPO_OH);
            }
          },
          {
            icon: $r('sys.symbol.store'),
            title: '原项目仓库',
            trailing: REPO_ORIGIN,
            trailingEllipsis: true,
            action: (): void => {
              this.openWeb(REPO_ORIGIN);
            }
          }
        ]
      },
      {
        title: '软件版本',
        rows: [
          {
            icon: $r('sys.symbol.list_bullet'),
            title: '更新日志',
            trailing: undefined,
            showChevron: true,
            action: (): void => {
              this.showChangelog = true;
            }
          },
          {
            icon: $r('sys.symbol.download'),
            title: '检查更新',
            trailing: '当前 ' + AppMeta.appVersion,
            showChevron: true,
            action: (): void => {
              this.doCheckUpdate();
            }
          },
          {
            icon: $r('sys.symbol.paperplane'),
            title: '代理下载新版本',
            subtitle: '经国内代理加速下载新版本安装包，开启后优先走代理',
            trailingSwitch: true
          }
        ]
      },
      {
        title: '开源与条款',
        rows: [
          {
            icon: $r('sys.symbol.doc_plaintext'),
            title: '开源许可',
            trailing: 'AGPL-3.0 协议'
          },
          {
            icon: $r('sys.symbol.info_circle'),
            title: '免责声明',
            showChevron: true,
            action: (): void => {
              DialogManager.OpenDialog('免责声明');
            }
          }
        ]
      },
      {
        title: '三方库',
        rows: [
          {
            icon: $r('sys.symbol.store'),
            title: '@xiaoye/date',
            trailing: '1.0.1',
            showChevron: true,
            action: (): void => {
              this.openWeb(DEP_DATE_URL);
            }
          },
          {
            icon: $r('sys.symbol.store'),
            title: '@keke/color-picker',
            trailing: '1.0.4',
            showChevron: true,
            action: (): void => {
              this.openWeb(DEP_COLOR_PICKER_URL);
            }
          },
          {
            icon: $r('sys.symbol.store'),
            title: '@ospark/free-pcm',
            trailing: '1.0.4',
            showChevron: true,
            action: (): void => {
              this.openWeb(DEP_FREE_PCM_URL);
            }
          }
        ]
      },
      {
        title: '其他',
        rows: [
          {
            icon: $r('sys.symbol.star_hexagon_fill'),
            title: '支持作者',
            showChevron: true,
            action: (): void => {
              DialogManager.OpenDialog('捐赠')
            }
          },
        ]
      }
    ];
  }

  /** 单行条目：头像/图标 + 标题 + 右侧说明 + chevron */
  @Builder
  private RowItem(row: AboutRow) {
    Row({ space: 12 }) {
      if (row.avatar) {
        Image(row.avatar)
          .width(44)
          .height(44)
          .borderRadius(22)
      } else {
        SymbolGlyph(row.icon)
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
      }
      Column({ space: 2 }) {
        Text(row.title)
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
        if (row.subtitle) {
          Text(row.subtitle)
            .fontSize(11)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(2)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (row.trailing) {
        Text(row.trailing)
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: row.trailingEllipsis ? '50%' : '100%' })
      }
      if (row.trailingSwitch) {
        Toggle({ type: ToggleType.Switch, isOn: this.proxyDownload })
          .selectedColor(appState.accentColor)
          .onChange((isOn: boolean) => {
            this.proxyDownload = isOn;
            appConfig.setUpdateProxyDownload(isOn);
          })
      }
      if (row.showChevron) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('sys.color.icon_tertiary')])
      }
    }
    .width('100%')
    .height(row.subtitle ? 60 : 52)
    .onClick(() => {
      const action = row.action;
      if (action) {
        action();
      }
    })
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf('关于'),
      scroller: this.scroller,
      doubleTapToTop: true
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 12 }) {
          // 头部：应用图标 + 软件名 + 版本
          ListItem() {
            Column({ space: 10 }) {
              Stack() {
                Image($r('app.media.background'))
                  .width(76)
                  .height(76)
                Image($r('app.media.foreground'))
                  .width(76)
                  .height(76)
              }
              .width(76)
              .height(76)
              .borderRadius(18)
              .clip(true)

              Text('MusicFreeOH')
                .fontSize(20)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_primary'))
              Row({ space: 6 }) {
                Text('当前版本 ' + AppMeta.appVersion)
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
                if (this.latestVersion.length > 0) {
                  Text('新版本 ' + this.latestVersion)
                    .fontSize(10)
                    .fontColor($r('sys.color.font_tertiary'))
                    .maxLines(1)
                    .padding({ top: 3, bottom: 3, left: 5, right: 5 })
                    .borderRadius(3)
                    .backgroundColor($r('sys.color.comp_background_tertiary'))
                    .onClick(() => {
                      this.doCheckUpdate();
                    })
                }
              }
              Text('移植自猫头猫的开源项目 MusicFree')
                .fontSize(11)
                .fontColor($r('sys.color.font_tertiary'))
            }
            .width('100%')
            .margin({ top: 24, bottom: 8 })
            .alignItems(HorizontalAlign.Center)
          }

          // 分组：标题 + 卡片
          ForEach(this.sections(), (section: AboutSection) => {
            ListItem() {
              Text(section.title)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_secondary'))
                .width('100%')
            }
            ListItem() {
              Column() {
                ForEach(section.rows, (row: AboutRow, index: number) => {
                  Column() {
                    this.RowItem(row)
                    if (index < section.rows.length - 1) {
                      Divider()
                        .DividerStyle()
                    }
                  }
                  .width('100%')
                }, (row: AboutRow) => row.title)
              }
              .width('100%')
            }
            .ListItemStyle()
          }, (section: AboutSection) => section.title)
        }
        .ListStyle()
        .onScrollFrameBegin((offset: number) => {
          BarScrollHelper.notifyScrollDelta(this.getUIContext(), offset)
          return { offsetRemain: offset }
        })
        .bindSheet(!!this.showChangelog, this.ChangelogSheetBuilder(), {
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          dragBar: true,
          backgroundColor: $r('sys.color.background_secondary'),
          onWillAppear: () => {
           appState.isForegroundBlur = true
          },
          onWillDisappear: () => {
            this.showChangelog = false;
            appState.isForegroundBlur = false
          }
        })
      }
    }
  }

  @Builder
  private ChangelogSheetBuilder() {
    ChangelogSheet({ focusVersion: '' })
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
