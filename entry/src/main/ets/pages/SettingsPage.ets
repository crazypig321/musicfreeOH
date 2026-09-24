import { CommonNav, titleBarOf } from '../view/CommonNav';
import { appState } from '../entryability/AppState';
import { BarScrollHelper, IsApiVersion_24 } from '../utils/BarScrollHelper';
import { NavPathUtils } from '../utils/NavPathUtils';
import { ROUTE_ABOUT, ROUTE_CACHE, ROUTE_PLAY_SETTING, ROUTE_DOWNLOAD_SETTING, ROUTE_LYRIC_SETTING, ROUTE_PLUGIN_SETTING, ROUTE_BACKUP_SETTING, ROUTE_APPEARANCE_SETTING } from '../common/model/NavModels';

/** 设置条目 */
interface SettingRow {
  icon: Resource;
  title: string;
  subtitle: string;
}

/**
 * 设置页面：外观 / 播放 / 下载 / 歌词 / 插件 / 缓存 / 备份与恢复 / 关于
 * 条目行 UI 同插件管理页（图标 + 标题/副标题 + chevron），子页面后续逐步补充
 */
@ComponentV2
export struct SettingsPage {
  scroller: Scroller = new Scroller();

  /** 设置条目数据 */
  private static rows(): Array<SettingRow> {
    return [
      { icon: $r('sys.symbol.paintpalette'), title: '外观', subtitle: '主题与显示' },
      { icon: $r('sys.symbol.play_fill'), title: '播放', subtitle: '播放行为与控制' },
      { icon: $r('sys.symbol.download'), title: '下载', subtitle: '下载相关设置' },
      { icon: $r('sys.symbol.doc_plaintext'), title: '歌词', subtitle: '歌词显示与缓存' },
      { icon: $r('sys.symbol.AI_panels'), title: '插件', subtitle: '插件与订阅源' },
      { icon: $r('sys.symbol.archivebox'), title: '缓存', subtitle: '清理缓存数据' },
      { icon: $r('sys.symbol.externaldrive'), title: '备份与恢复', subtitle: '数据备份与恢复' },
      { icon: $r('sys.symbol.info_circle'), title: '关于', subtitle: '版本与说明' }
    ];
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf($r('app.string.tab_settings')),
      isHideBackButton: true,
      embedded: true,
      scroller: this.scroller,
      doubleTapToTop: true
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 16 }) {
          ForEach(SettingsPage.rows(), (row: SettingRow) => {
            ListItem() {
              Row({ space: 12 }) {
                Column() {
                  SymbolGlyph(row.icon)
                    .fontSize(22)
                    .fontColor([$r('sys.color.icon_secondary')])
                }
                .width(40)
                .height(40)
                .borderRadius(10)
                .backgroundColor($r('sys.color.comp_background_tertiary'))
                .justifyContent(FlexAlign.Center)

                Column({ space: 2 }) {
                  Text(row.title)
                    .fontSize(15)
                    .fontColor($r('sys.color.font_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(row.subtitle)
                    .fontSize(12)
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
              .height(56)
            }.ListItemStyle()
            .onClick(() => {
              if (row.title === '关于') {
                NavPathUtils.push(ROUTE_ABOUT);
              } else if (row.title === '缓存') {
                NavPathUtils.push(ROUTE_CACHE);
              } else if (row.title === '外观') {
                NavPathUtils.push(ROUTE_APPEARANCE_SETTING);
              } else if (row.title === '播放') {
                NavPathUtils.push(ROUTE_PLAY_SETTING);
              } else if (row.title === '下载') {
                NavPathUtils.push(ROUTE_DOWNLOAD_SETTING);
              } else if (row.title === '歌词') {
                NavPathUtils.push(ROUTE_LYRIC_SETTING);
              } else if (row.title === '插件') {
                NavPathUtils.push(ROUTE_PLUGIN_SETTING);
              } else if (row.title === '备份与恢复') {
                NavPathUtils.push(ROUTE_BACKUP_SETTING);
              } else {
                this.showToast('「' + row.title + '」开发中');
              }
            })
          }, (row: SettingRow) => row.title)
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
