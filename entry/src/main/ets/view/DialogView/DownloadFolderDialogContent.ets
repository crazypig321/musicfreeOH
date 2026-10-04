import { DialogManager } from '../../utils/DialogUtils';
import { appState } from '../../entryability/AppState';
import { PathConst } from '../../common/PathConst';
import { FileUtils } from '../../utils/FileUtils';

/**
 * 「下载/移动到文件夹/添加标签/编辑标签」弹窗内容：目标文件夹名输入框 + 已有文件夹选择列表
 * 下载留空 = 默认目录；移动留空 = 根目录；点选已有文件夹自动填入输入框
 */
@ComponentV2
export struct DownloadFolderDialogContent {
  /** 输入框内容（本地状态驱动选中态高亮；确认时已同步到 DialogManager.downloadFolderValue） */
  @Local inputValue: string = DialogManager.downloadFolderValue;
  /** 下载目录下已有的子文件夹（弹窗打开时扫描；添加/编辑标签场景不显示列表） */
  @Local existFolders: Array<string> = [];

  aboutToAppear(): void {
    if (DialogManager.dialogChangeKey === '添加标签' || DialogManager.dialogChangeKey === '编辑标签') {
      return;
    }
    const base = PathConst.downloadPath.endsWith('/') ?
      PathConst.downloadPath : PathConst.downloadPath + '/';
    const names = FileUtils.listDir(base);
    for (const n of names) {
      if (FileUtils.isDirectory(base + n) &&
        PathConst.RESERVED_DOWNLOAD_FOLDERS.indexOf(n) === -1) {
        this.existFolders.push(n);
      }
    }
  }

  build() {
    Column({ space: 12 }) {
      TextInput({
        text: this.inputValue,
        placeholder: DialogManager.dialogChangeKey === '移动到文件夹'
          ? '目标文件夹名（留空则移到根目录）'
          : (DialogManager.dialogChangeKey === '添加标签' ? '标签名称' : (
            DialogManager.dialogChangeKey === '编辑标签' ? '新标签名称' : '文件夹名称（留空则下载到默认目录）'))
      })
        .width('100%')
        .height(44)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(10)
        .enabled(!appState.isDialogSaving)
        .onChange((v: string): void => {
          this.inputValue = v;
          DialogManager.downloadFolderValue = v;
        })
      // 已有文件夹选择列表（点击填入输入框并高亮；Flex 换行自适应高度，样式同页面标签条）
      if (this.existFolders.length > 0) {
        Text('或选择已有文件夹')
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.existFolders, (folder: string) => {
            Text(folder)
              .fontSize(13)
              .maxLines(1)
              .fontColor(this.inputValue === folder ?
              $r('sys.color.font_on') : $r('sys.color.font_secondary'))
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .borderRadius(16)
              .backgroundColor(this.inputValue === folder ?
              $r('sys.color.font_secondary') : $r('sys.color.comp_background_tertiary'))
              .margin({ right: 8, bottom: 8 })
              .onClick(() => {
                this.inputValue = folder;
                DialogManager.downloadFolderValue = folder;
              })
          }, (folder: string) => folder + (this.inputValue === folder ? '_on' : '_off'))
        }
        .width('100%')
      }
      // 编辑标签：自定义按钮（支持 loading 态，异步保存完成后手动关闭弹窗）
      if (DialogManager.dialogChangeKey === '编辑标签') {
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .fontColor(appState.accentColor)
            .backgroundColor(Color.Transparent)
            .borderRadius(100)
            .enabled(!appState.isDialogSaving)
            .onClick(() => {
              DialogManager.CloseDialog();
            })
          if (appState.isDialogSaving) {
            Column() {
              LoadingProgress()
                .width(24)
                .height(24)
                .color(Color.White)
            }
            .layoutWeight(1)
            .height(40)
            .justifyContent(FlexAlign.Center)
            .borderRadius(100)
            .backgroundColor(appState.accentColor)
          } else {
            Button('保存')
              .layoutWeight(1)
              .height(40)
              .fontSize(15)
              .fontColor(Color.White)
              .backgroundColor(appState.accentColor)
              .borderRadius(100)
              .onClick(() => {
                DialogManager.ConfirmButtonDialog('编辑标签');
              })
          }
        }
        .width('100%')
        .margin({ top: 4 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
