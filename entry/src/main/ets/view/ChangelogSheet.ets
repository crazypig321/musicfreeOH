import { MarkdownView } from './MarkdownView';
import { CHANGELOGS, ChangelogEntry } from '../common/Changelog';
import { sheetTopAvoidVp } from '../utils/BreakpointUtils';

/**
 * 更新日志半模态内容：List + ListItemGroup + ListItem，
 * 每个版本一个分组，点击分组头部展开/收起该版本的 markdown 日志（手风琴，同时只展开一个）；
 * 供关于页与 Index（升级后首次冷启动自动弹出）通过 bindSheet 使用
 */
@ComponentV2
export struct ChangelogSheet {
  /** 打开时自动展开的版本（空 = 全部收起，点开分组后才显示内容） */
  @Param focusVersion: string = '';
  /** 当前展开的版本号（空 = 全部收起） */
  @Local expandedVersion: string = '';

  aboutToAppear(): void {
    this.expandedVersion = this.focusVersion;
  }

  private toggle(version: string): void {
    this.getUIContext().animateTo({ duration: 250, curve: Curve.Linear }, (): void => {
      this.expandedVersion = this.expandedVersion === version ? '' : version;
    });
  }

  @Builder
  GroupHeaderBuilder(entry: ChangelogEntry) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text('v' + entry.version)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Text(entry.date)
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([$r('sys.color.icon_tertiary')])
        .rotate({ angle: this.expandedVersion === entry.version ? 90 : 0 })
        .animation({ duration: 200, curve: Curve.Smooth })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => {
      this.toggle(entry.version);
    })
    .geometryTransition('update')
  }

  build() {
    Column() {
      // 固定头部：不随列表滚动
      Column({ space: 2 }) {
        Text('更新日志')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Text('MusicFreeOH 版本变更记录')
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, top: 12 + sheetTopAvoidVp(), bottom: 10 })
      .backgroundColor($r('sys.color.background_secondary'))

      List({ space: 10 }) {
        ForEach(CHANGELOGS, (entry: ChangelogEntry) => {
          ListItemGroup({ header: this.GroupHeaderBuilder(entry) }) {
            if (this.expandedVersion === entry.version) {
              ListItem() {
                MarkdownView({ markdown: entry.markdown })
              }.padding({ left: 16, right: 16, top: 4, bottom: 12 })
              .geometryTransition('update', { follow: true })
              .transition(TransitionEffect.OPACITY.animation({duration: 200}))
            }
          }
          .backgroundColor($r('sys.color.comp_background_list_card'))
          .borderRadius(14)
        }, (entry: ChangelogEntry) => entry.version)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, bottom: 32 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_secondary'))
    .alignItems(HorizontalAlign.Start)
  }
}
