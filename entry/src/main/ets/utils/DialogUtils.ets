import { appState } from "../entryability/AppState";


export class DialogManager {
  public static dialogChangeKey: string = ''

  /**
   * 打开弹窗
   * @param key 弹窗类型标识
   */
  public static OpenDialog(key: string) {
    DialogManager.dialogChangeKey = key;
    appState.isDialogOpen = true;
    appState.isForegroundBlur = true
  }

  /**
   * 获取弹窗标题文本
   * @param key 弹窗类型标识
   * @returns 标题文本
   */
  public static DialogTitle(key: string): ResourceStr {
    switch (key) {
      case '创建分组':
        return '';
    }
    return '';
  }

  /**
   * 弹窗确定键回调
   * @param key 弹窗类型标识
   */
  public static async ConfirmButtonDialog(key: string) {
    switch (key) {
      case '创建分组':

        break;
    }
  }

  /**
   * 弹窗取消键回调
   * @param key 弹窗类型标识
   */
  public static CancelButtonDialog(key: string) {
    switch (key) {
      case '创建分组':
        break;
    }
  }

  /**
   * 弹窗出现回调
   * @param key 弹窗类型标识
   */
  public static AppearDialog(key: string) {
    appState.isForegroundBlur = true;
    switch (key) {
      case '速度调节':

        break;
    }
  }

  /**
   * 弹窗消失回调
   * @param key 弹窗类型标识
   */
  public static DisappearDialog(key: string) {
    appState.isForegroundBlur = false;
    appState.isDialogOpen = false;
    DialogManager.dialogChangeKey = '';

    switch (key) {
      case '创建分组':

        break;
    }
  }
}