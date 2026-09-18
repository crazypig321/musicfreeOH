import { CommonNav, titleBarOf } from '../../view/CommonNav';
import { appState } from '../../entryability/AppState';
import { AppMeta } from '../../core/AppMeta';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';
import { DialogManager } from '../../utils/DialogUtils';
import { WebUtils } from '../../utils/WebUtils';

/** 仓库地址常量 */
const REPO_OH: string = 'https://github.com/crazypig321/musicfreeOH.git';
const REPO_ORIGIN: string = 'https://github.com/maotoumao/MusicFree.git';
const DEV_HOME: string = 'https://github.com/crazypig321';
const DEP_DATE_URL: string = 'https://ohpm.openharmony.cn/#/cn/detail/@xiaoye%2Fdate';

/**
 * 关于页面：应用图标/名称/版本 + 开发者 + 项目地址 + 开源与条款
 * 从设置页「关于」条目进入
 */
@ComponentV2
export struct AboutPage {
  scroller: Scroller = new Scroller();

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
              Text('当前版本 ' + AppMeta.appVersion)
                .fontSize(12)
                .fontColor($r('sys.color.font_tertiary'))
            }
            .width('100%')
            .margin({ top: 24, bottom: 8 })
            .alignItems(HorizontalAlign.Center)
          }

          // 开发者
          ListItem() {
            Text('开发者')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }
          ListItem() {
            Row({ space: 12 }) {
              Image($r('app.media.crazypig321'))
                .width(44)
                .height(44)
                .borderRadius(22)
              Text('crazypig321')
                .fontSize(15)
                .fontColor($r('sys.color.font_primary'))
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(14)
                .fontColor([$r('sys.color.icon_tertiary')])
            }
            .width('100%')
            .height(60)
          }
          .ListItemStyle()
          .onClick(() => {
            this.openWeb(DEV_HOME);
          })

          // 项目地址
          ListItem() {
            Text('项目地址')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }
          ListItem() {
            Column() {
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.store'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('项目仓库')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Text(REPO_OH)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: '50%' })
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.openWeb(REPO_OH);
              })

              Divider()
                .DividerStyle()

              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.store'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('原项目仓库')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Text(REPO_ORIGIN)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: '50%' })
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                this.openWeb(REPO_ORIGIN);
              })
            }
            .width('100%')
          }
          .ListItemStyle()

          // 开源与条款
          ListItem() {
            Text('开源与条款')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }
          ListItem() {
            Column() {
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.doc_plaintext'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('开源许可')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                Text('AGPL-3.0 协议')
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
              }
              .width('100%')
              .height(52)

              Divider()
                .DividerStyle()

              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.info_circle'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_secondary')])
                Text('免责声明')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([$r('sys.color.icon_tertiary')])
              }
              .width('100%')
              .height(52)
              .onClick(() => {
                DialogManager.OpenDialog('免责声明');
              })
            }
            .width('100%')
          }
          .ListItemStyle()

          // 三方库
          ListItem() {
            Text('三方库')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }
          ListItem() {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.store'))
                .fontSize(20)
                .fontColor([$r('sys.color.icon_secondary')])
              Text('@xiaoye/date')
                .fontSize(15)
                .fontColor($r('sys.color.font_primary'))
                .layoutWeight(1)
              Text('1.0.1')
                .fontSize(11)
                .fontColor($r('sys.color.font_tertiary'))
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(14)
                .fontColor([$r('sys.color.icon_tertiary')])
            }
            .width('100%')
            .height(52)
            .onClick(() => {
              this.openWeb(DEP_DATE_URL);
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
