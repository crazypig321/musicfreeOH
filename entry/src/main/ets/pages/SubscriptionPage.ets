import { HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { picker } from '@kit.CoreFileKit';
import { CommonNav, titleBarOf } from '../view/CommonNav';
import { MenuItemParams } from '../view/CommonCom';
import { MenuUtils } from '../utils/MenuUtils';
import { appState } from '../entryability/AppState';
import { JsonUtil } from '../common/JsonUtil';
import { ContextHolder } from '../common/ContextHolder';
import { Subscriptions } from '../plugin/Subscriptions';
import { PluginImport } from '../plugin/PluginImport';

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
  @Local showImportSheet: boolean = false;
  @Local updating: boolean = false;
  @Local statusText: string = '';

  aboutToAppear(): void {
    this.sources = Subscriptions.getSources();
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  /** 订阅源标题：取 URL 最后一段文件名 */
  private static sourceTitle(url: string): string {
    const idx = url.lastIndexOf('/');
    const name = idx === -1 ? url : url.substring(idx + 1);
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

  /** 网络导入：添加订阅源并立即同步 */
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
    }
    this.sources = Subscriptions.getSources();
    this.showImportSheet = false;
    this.importUrl = '';
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
    this.statusText = '正在更新订阅源...';
    const message = await Subscriptions.syncSource(url);
    this.statusText = message;
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
      this.statusText = '正在更新 ' + done.toString() + '/' + total.toString() + ' ...';
    });
    this.statusText = message;
    this.updating = false;
  }

  /** 删除订阅源 */
  private removeSource(url: string): void {
    Subscriptions.removeSource(url);
    this.sources = Subscriptions.getSources();
    this.showToast('已删除订阅源');
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf($r('app.string.tab_subscription'), undefined, this.titleMenus()),
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

                  SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                    .onClick(() => {
                      this.updateSource(url);
                    })
                  SymbolGlyph($r('sys.symbol.trash'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.icon_secondary')])
                    .onClick(() => {
                      this.removeSource(url);
                    })
                }
                .width('100%')
                .height(56)
              }
              .width('100%')
              .borderRadius(16)
              .padding(12)
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .onClick(() => {
                this.updateSource(url);
              })
            }, (url: string, index: number) => url + '_' + index.toString())
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
        .contentEndOffset(appState.bottomRect + 60)
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
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
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
    }
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
