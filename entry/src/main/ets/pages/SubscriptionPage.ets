import { HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { picker } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { CommonNav, titleBarOf } from '../view/CommonNav';
import { MenuItemParams } from '../view/CommonCom';
import { MenuUtils } from '../utils/MenuUtils';
import { appState } from '../entryability/AppState';
import { JsonUtil } from '../common/JsonUtil';
import { ContextHolder } from '../common/ContextHolder';
import { PathConst } from '../common/PathConst';
import { FileUtils } from '../utils/FileUtils';
import { HttpClient } from '../infra/HttpClient';
import { Subscriptions } from '../plugin/Subscriptions';
import { PluginImport } from '../plugin/PluginImport';
import { DialogManager } from '../utils/DialogUtils';
import { BarScrollHelper, IsApiVersion_24 } from '../utils/BarScrollHelper';

/** 导入菜单锚点（标题栏下方右上角） */
const IMPORT_ANCHOR_ID = 'subscription_import_anchor';

/**
 * 订阅源页面：管理聚合插件地址（.json 为插件列表，.js 为单个插件）
 * 导入方式：右上角「导入」菜单（网络导入 / 本地导入），同步即安装/更新其中的插件
 */
@ComponentV2
export struct SubscriptionPage {
  scroller: Scroller = new Scroller();
  @Local sources: Array<string> = [];
  @Local importUrl: string = '';
  @Local importName: string = '';
  @Local showImportSheet: boolean = false;
  @Local showDetailSheet: boolean = false;
  @Local detailUrl: string = '';
  @Local updating: boolean = false;
  @Local statusText: string = '';
  /** 状态行自动隐藏定时器 */
  private statusTimer: number = -1;

  aboutToAppear(): void {
    this.sources = Subscriptions.getSources();
  }

  aboutToDisappear(): void {
    if (this.statusTimer !== -1) {
      clearTimeout(this.statusTimer);
      this.statusTimer = -1;
    }
  }

  /** 设置状态行文本；autoClear 为 true 时 30 秒后自动清除 */
  private setStatusText(text: string, autoClear: boolean): void {
    this.statusText = text;
    if (this.statusTimer !== -1) {
      clearTimeout(this.statusTimer);
      this.statusTimer = -1;
    }
    if (autoClear) {
      this.statusTimer = setTimeout(() => {
        this.statusText = '';
        this.statusTimer = -1;
      }, 30000);
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  /** 订阅源标题：自定义名称优先，否则取 URL 最后一段文件名（去掉查询参数） */
  private static sourceTitle(url: string): string {
    const custom = Subscriptions.getSourceName(url);
    if (custom.length > 0) {
      return custom;
    }
    const clean = url.split('?')[0];
    const idx = clean.lastIndexOf('/');
    const name = idx === -1 ? clean : clean.substring(idx + 1);
    return name.length > 0 ? name : url;
  }

  /** titleBar 菜单：导入 + 更新全部 */
  private titleMenus(): Array<HdsNavigationMenuItemOptions> {
    const add: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.plus'),
        label: '导入',
        action: (): void => {
          this.openImportMenu();
        }
      }
    };
    const updateAll: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.arrow_clockwise'),
        label: '更新全部',
        action: (): void => {
          this.updateAllSources();
        }
      }
    };
    return [add, updateAll];
  }

  /** 导入菜单：网络导入 / 本地导入 */
  private openImportMenu(): void {
    const netItem = new MenuItemParams();
    netItem.icon = $r('sys.symbol.dot_radiowaves_left_and_right');
    netItem.label = '网络导入';
    netItem.onAction = (): void => {
      MenuUtils.Dismiss();
      this.importUrl = '';
      this.importName = '';
      this.showImportSheet = true;
    };
    const localItem = new MenuItemParams();
    localItem.icon = $r('sys.symbol.folder');
    localItem.label = '本地导入';
    localItem.onAction = (): void => {
      MenuUtils.Dismiss();
      this.pickLocalFiles();
    };
    MenuUtils.Open(this.getUIContext(), IMPORT_ANCHOR_ID, [netItem, localItem], {
      placement: Placement.BottomRight
    });
  }

  /** 网络导入：添加订阅源（可填自定义名称）并立即同步 */
  private confirmImportUrl(): void {
    const url = this.importUrl.trim();
    if (url.length === 0) {
      this.showToast('请输入订阅源 URL');
      return;
    }
    if (!Subscriptions.isValidSourceUrl(url)) {
      this.showToast('订阅地址必须以 .js 或 .json 结尾');
      return;
    }
    if (!Subscriptions.addSource(url)) {
      this.showToast('该订阅源已存在');
    } else {
      const name = this.importName.trim();
      if (name.length > 0) {
        Subscriptions.setSourceName(url, name);
      }
    }
    this.sources = Subscriptions.getSources();
    this.showImportSheet = false;
    this.importUrl = '';
    this.importName = '';
    this.updateSource(url);
  }

  /** 本地导入：.json 解析为订阅源，.js 直接安装插件 */
  private pickLocalFiles(): void {
    try {
      const ctx = ContextHolder.get();
      const documentPicker = new picker.DocumentViewPicker(ctx);
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 20;
      options.fileSuffixFilters = ['.js', '.json'];
      documentPicker.select(options).then((uris: Array<string>) => {
        if (uris.length === 0) {
          return;
        }
        this.importLocalFiles(uris);
      }).catch((_e: Object): void => {
        this.showToast('选择文件失败');
      });
    } catch (error) {
      this.showToast('无法打开文件选择器');
    }
  }

  /** 批量处理本地文件：.json 添加为订阅源，.js 安装为插件 */
  private async importLocalFiles(uris: Array<string>): Promise<void> {
    if (this.updating) {
      this.showToast('正在处理中，请稍候');
      return;
    }
    this.updating = true;
    let addedSources = 0;
    let dupSources = 0;
    const jsUris: Array<string> = [];
    for (const uri of uris) {
      if (uri.split('?')[0].endsWith('.json')) {
        const text = PluginImport.readUriText(uri, 'json');
        const rec = text !== null ? JsonUtil.parseRecord(text) : null;
        const plugins = rec !== null ? JsonUtil.recArray(rec, 'plugins') : null;
        if (plugins === null) {
          dupSources++;
          continue;
        }
        for (const item of plugins) {
          const itemRec = JsonUtil.objToRecord(item);
          const u = itemRec !== null ? JsonUtil.recStr(itemRec, 'url') : '';
          if (u.length === 0) {
            continue;
          }
          if (Subscriptions.addSource(u)) {
            addedSources++;
          } else {
            dupSources++;
          }
        }
      } else {
        jsUris.push(uri);
      }
    }
    let summary = '新增 ' + addedSources.toString() + ' 个订阅源' +
      (dupSources > 0 ? '，' + dupSources.toString() + ' 个已存在' : '');
    if (jsUris.length > 0) {
      const r = await PluginImport.installLocalJsFiles(jsUris);
      summary += '；安装 ' + r.success.toString() + ' 个插件' +
        (r.failed > 0 ? '，' + r.failed.toString() + ' 个失败' : '');
    }
    this.sources = Subscriptions.getSources();
    this.updating = false;
    this.showToast(summary);
    // 有新增订阅源时自动同步（安装其中的插件）
    if (addedSources > 0) {
      this.updateAllSources();
    }
  }

  /** 更新单个订阅源 */
  private async updateSource(url: string): Promise<void> {
    if (this.updating) {
      this.showToast('正在更新中，请稍候');
      return;
    }
    this.updating = true;
    this.setStatusText('正在更新订阅源...', false);
    const message = await Subscriptions.syncSource(url);
    this.setStatusText(message, true);
    this.updating = false;
  }

  /** 更新全部订阅源 */
  private async updateAllSources(): Promise<void> {
    if (this.updating) {
      this.showToast('正在更新中，请稍候');
      return;
    }
    this.updating = true;
    const message = await Subscriptions.syncAll((done: number, total: number): void => {
      this.setStatusText('正在更新 ' + done.toString() + '/' + total.toString() + ' ...', false);
    });
    this.setStatusText(message, true);
    this.updating = false;
  }

  /** 删除订阅源 */
  private removeSource(url: string): void {
    Subscriptions.removeSource(url);
    this.sources = Subscriptions.getSources();
    this.showToast('已删除订阅源');
  }

  /** 打开订阅源详情半模态 */
  private openDetailSheet(url: string): void {
    this.detailUrl = url;
    this.showDetailSheet = true;
  }

  /** 详情内更新订阅源（先关闭半模态以便查看页面状态行） */
  private updateFromSheet(): void {
    const url = this.detailUrl;
    this.showDetailSheet = false;
    this.updateSource(url);
  }

  /** 分享订阅源地址（复制到剪贴板） */
  private shareDetailUrl(): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.detailUrl);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      this.showToast('已复制源地址，可粘贴分享');
    }).catch((_e: Object): void => {
      this.showToast('复制失败');
    });
  }

  /** 导出订阅源文件到 下载目录/订阅源 文件夹（拉取源内容后保存） */
  private async exportDetailFile(): Promise<void> {
    if (this.updating) {
      this.showToast('正在处理中，请稍候');
      return;
    }
    this.updating = true;
    this.showToast('正在获取订阅源...');
    const text = await HttpClient.downloadText(this.detailUrl);
    this.updating = false;
    if (text === null) {
      this.showToast('订阅源获取失败');
      return;
    }
    // downloadPath 可能无结尾斜杠（公共目录），先补齐再拼接，避免目录名黏连
    const base = PathConst.downloadPath.endsWith('/') ? PathConst.downloadPath : PathConst.downloadPath + '/';
    const destPath = base + '订阅源/' + FileUtils.escapeCharacter(SubscriptionPage.sourceTitle(this.detailUrl));
    if (FileUtils.writeFileText(destPath, text)) {
      this.showToast('已导出到 ' + destPath);
    } else {
      this.showToast('导出失败');
    }
  }

  /** 详情内删除订阅源 */
  private removeDetailSource(): void {
    const url = this.detailUrl;
    this.showDetailSheet = false;
    this.removeSource(url);
  }

  /** 详情内重命名（弹窗：公共「重命名」弹窗，确认后保存并刷新） */
  private startRename(): void {
    DialogManager.renameValue = SubscriptionPage.sourceTitle(this.detailUrl);
    DialogManager.renameConfirm = (name: string): void => {
      Subscriptions.setSourceName(this.detailUrl, name);
      this.sources = Subscriptions.getSources();
      this.showToast('已重命名');
    };
    DialogManager.OpenDialog('重命名');
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf($r('app.string.tab_subscription'), '共 ' + this.sources.length.toString() + ' 个订阅源', this.titleMenus()),
      isHideBackButton: true,
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 12 }) {
          // 状态行（更新进度/结果）
          if (this.statusText.length > 0) {
            ListItem() {
              Row({ space: 8 }) {
                if (this.updating) {
                  LoadingProgress()
                    .width(16)
                    .height(16)
                    .color($r('sys.color.icon_emphasize'))
                }
                Text(this.statusText)
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
                  .layoutWeight(1)
                  .maxLines(2)
              }
              .width('100%')
              .margin({ top: 4 })
            }
          }
          // 订阅源列表
          if (this.sources.length > 0) {
            ForEach(this.sources, (url: string, index: number) => {
              ListItem() {
                Row({ space: 12 }) {
                  Column() {
                    SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right'))
                      .fontSize(22)
                      .fontColor([$r('sys.color.icon_secondary')])
                  }
                  .width(40)
                  .height(40)
                  .borderRadius(10)
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  .justifyContent(FlexAlign.Center)

                  Column({ space: 2 }) {
                    Text(SubscriptionPage.sourceTitle(url))
                      .fontSize(15)
                      .fontColor($r('sys.color.font_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(url)
                      .fontSize(12)
                      .fontColor($r('sys.color.font_tertiary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .height(56)
              }
              .width('100%')
              .borderRadius(16)
              .padding(12)
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .onClick(() => {
                this.openDetailSheet(url);
              })
            }, (url: string, index: number) =>
              url + '_' + index.toString() + '_' + Subscriptions.getSourceName(url))
          } else {
            // 空态说明
            ListItem() {
              Column({ space: 8 }) {
                Text('暂无订阅源')
                  .fontSize(14)
                  .fontColor($r('sys.color.font_secondary'))
                Text('订阅源是聚合插件地址：.json 为插件列表，.js 为单个插件。点击右上角「导入」添加。')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
                  .textAlign(TextAlign.Center)
                  .padding({ left: 24, right: 24 })
              }
              .width('100%')
              .margin({ top: 32 })
              .alignItems(HorizontalAlign.Center)
            }
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .contentStartOffset(appState.topRect + 66)
        // 上下两排时底栏更高，末尾内容需多留滚动空间
        .contentEndOffset(appState.bottomRect + (IsApiVersion_24() && appState.hdsBarLayoutMode === 1 ? 130 : 60))
        .onScrollFrameBegin((offset: number) => {
          BarScrollHelper.notifyScrollDelta(this.getUIContext(), offset)
          return { offsetRemain: offset }
        })
        .padding({ left: 16, right: 16 })

        // openMenu 锚点（位于标题栏下方右上角，菜单在锚点处弹出）
        Row({ space: 12 }) {
          Column()
            .id(IMPORT_ANCHOR_ID)
            .width(24)
            .height(24)
          Column()
            .width(24)
            .height(24)
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: 16 })
        .margin({ top: appState.topRect + 20 })
        .bindSheet(!!this.showImportSheet, this.ImportSheetBuilder(), {
          scrollSizeMode: ScrollSizeMode.CONTINUOUS, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          dragBar: true,
          onWillDisappear: () => {
            this.showImportSheet = false;
            appState.isForegroundBlur = false
          },
          onWillAppear: () => {
            appState.isForegroundBlur = true
          }
        })
      }
      .width('100%')
      .height('100%')
      .bindSheet(!!this.showDetailSheet, this.DetailSheetBuilder(), {
        scrollSizeMode: ScrollSizeMode.CONTINUOUS, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        dragBar: true,
        onWillDisappear: () => {
          this.showDetailSheet = false;
          appState.isForegroundBlur = false
        },
        onWillAppear: () => {
          appState.isForegroundBlur = true
        }
      })
    }
  }

  /** 订阅源详情半模态（UI 参考插件详情） */
  @Builder
  DetailSheetBuilder() {
    Column() {
      // 头部：源文件名 + 完整 URL
      Text(SubscriptionPage.sourceTitle(this.detailUrl))
        .fontSize(19)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 4 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.detailUrl)
        .fontSize(12)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
        .margin({ top: 4, bottom: 12 })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // 操作分组：更新 / 重命名 / 分享 / 导出 / 删除（卡片内以分割线隔开）
      Text('操作')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .margin({ top: 8, bottom: 6 })
      Column() {
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
          Text('更新订阅源')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.updateFromSheet();
        })

        Divider()
          .DividerStyle()
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
          Text('重命名')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.startRename();
        })

        Divider()
          .DividerStyle()
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.share'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
          Text('分享源地址')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          Text(this.detailUrl)
            .fontSize(11)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '45%' })
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.shareDetailUrl();
        })

        Divider()
          .DividerStyle()
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
          Text('导出订阅源')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.exportDetailFile();
        })

        Divider()
          .DividerStyle()
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
          Text('删除订阅源')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.removeDetailSource();
        })
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor($r('sys.color.comp_background_list_card'))
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 网络导入：订阅源 URL 输入 */
  @Builder
  ImportSheetBuilder() {
    Column() {
      Text('网络导入订阅源')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 4, bottom: 16 })
      TextInput({ text: this.importUrl, placeholder: '订阅源 URL（.js 或 .json）' })
        .width('100%')
        .height(44)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(12)
        .onChange((v: string) => {
          this.importUrl = v;
        })
      TextInput({ text: this.importName, placeholder: '名称（可选，默认取文件名）' })
        .width('100%')
        .height(44)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(12)
        .margin({ top: 12 })
        .onChange((v: string) => {
          this.importName = v;
        })
        .onSubmit((_enterKey: EnterKeyType) => {
          this.confirmImportUrl();
        })
      Button('添加')
        .width('100%')
        .height(42)
        .fontSize(15)
        .margin({ top: 20 })
        .backgroundColor($r('sys.color.background_emphasize'))
        .onClick(() => {
          this.confirmImportUrl();
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }
}

@Extend(Divider)
function DividerStyle(){
  .color($r('sys.color.comp_divider'))
  .margin({ left: 48, right: 12 })
}
