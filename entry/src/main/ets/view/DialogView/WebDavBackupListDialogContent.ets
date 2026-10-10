import { DialogManager } from '../../utils/DialogUtils';
import { appState } from '../../entryability/AppState';
import { WebDav, WebDavBackupEntry } from '../../core/WebDav';

/**
 * 「选择备份文件」弹窗内容：WebDAV 远端备份列表（新备份在前），
 * 每条列出时间/设备与文件名/大小，右侧 Radio 单选；先选中条目，点「确认」后恢复
 */
@ComponentV2
export struct WebDavBackupListDialogContent {
  @Local selectedIndex: number = 0;

  build() {
    List({ space: 10 }){
        ForEach(DialogManager.webdavBackupEntries, (entry: WebDavBackupEntry, index: number) => {
          ListItem(){
            Row({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.archivebox'))
                .fontSize(20)
                .fontColor([$r('sys.color.icon_secondary')])
              Text(WebDav.displayTitle(entry.fileName))
                .fontSize(15)
                .layoutWeight(1)
                .fontColor($r('sys.color.font_primary'))
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Radio({ value: entry.fileName, group: 'webdavBackup' })
                .checked(index === this.selectedIndex)
                .radioStyle({ checkedBackgroundColor: appState.accentColor })
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.selectedIndex = index;
                    DialogManager.webdavBackupIndex = index;
                  }
                })
            }.width('100%')
          }
          .width('100%')
          .padding(12)
          .onClick(() => {
            this.selectedIndex = index;
            DialogManager.webdavBackupIndex = index;
          })
          .borderRadius(16)
          .backgroundColor( this.selectedIndex === index ? $r('sys.color.comp_background_list_card') : Color.Transparent)
        }, (entry: WebDavBackupEntry, index: number) => entry.fileName + '_' + index.toString())
      }
    .constraintSize({ maxHeight: 320 })
    .scrollBar(BarState.Off)
    .width('100%')
  }
}
