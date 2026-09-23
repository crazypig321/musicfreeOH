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
const DEP_COLOR_PICKER_URL: string = 'https://ohpm.openharmony.cn/#/cn/detail/@keke%2Fcolor-picker';

/** 关于页条目行：头像/图标 + 标题 + 右侧说明 + chevron，可选点击行为 */
interface AboutRow {
  /** 头像图片（设置后优先于 icon 显示） */
  avatar?: Resource;
  /** SymbolGlyph 图标 */
  icon: Resource;
  title: string;
  /** 右侧说明文字 */
  trailing?: string;
  /** 右侧说明是否按长文本（地址）省略 */
  trailingEllipsis?: boolean;
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
          }
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
      Text(row.title)
        .fontSize(15)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
      if (row.trailing) {
        Text(row.trailing)
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: row.trailingEllipsis ? '50%' : '100%' })
      }
      if (row.showChevron) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('sys.color.icon_tertiary')])
      }
    }
    .width('100%')
    .height(52)
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
              Text('当前版本 ' + AppMeta.appVersion)
                .fontSize(12)
                .fontColor($r('sys.color.font_tertiary'))
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
