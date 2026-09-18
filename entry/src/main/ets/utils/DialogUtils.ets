import { appState } from "../entryability/AppState";
import { pluginManager } from "../plugin/PluginManager";
import { ButtonOptions } from "@kit.ArkUI";
import { MarkdownView } from "../view/MarkdownView";


/** 插件用户变量字段（弹窗内编辑） */
export class PluginVarField {
  public key: string = '';
  public name: string = '';
  public value: string = '';
}


/** 「使用说明」弹窗内容（markdown 渲染，隐藏滚动条） */
@ComponentV2
export struct UsageDialogContent {
  build() {
    Scroll() {
      MarkdownView({ markdown: DialogManager.usageMessage })
    }
    .constraintSize({ maxHeight: 420 })
    .scrollBar(BarState.Off)
    .nestedScroll({
      scrollForward: NestedScrollMode.PARALLEL,
      scrollBackward: NestedScrollMode.PARALLEL
    })
    .width('100%')
  }
}


/** 「配置变量」弹窗内容：所有变量统一填写 */
@ComponentV2
export struct VarFieldsDialogContent {
  build() {
    Scroll() {
      Column({ space: 14 }) {
        ForEach(DialogManager.varFields, (f: PluginVarField) => {
          Column({ space: 6 }) {
            Text(f.name)
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            TextInput({ text: f.value, placeholder: f.key })
              .width('100%')
              .height(42)
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
              .placeholderColor($r('sys.color.font_tertiary'))
              .backgroundColor($r('sys.color.comp_background_tertiary'))
              .borderRadius(10)
              .onChange((v: string): void => {
                f.value = v;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }, (f: PluginVarField, index: number) => f.key + '_' + index.toString())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .constraintSize({ maxHeight: 360 })
    .nestedScroll({
      scrollForward: NestedScrollMode.PARALLEL,
      scrollBackward: NestedScrollMode.PARALLEL
    })
    .width('100%')
  }
}


/** 「重命名」弹窗内容：名称输入框 */
@ComponentV2
export struct RenameDialogContent {
  build() {
    TextInput({ text: DialogManager.renameValue, placeholder: '名称（清空则恢复默认）' })
      .width('100%')
      .height(44)
      .fontSize(14)
      .fontColor($r('sys.color.font_primary'))
      .placeholderColor($r('sys.color.font_tertiary'))
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .borderRadius(10)
      .onChange((v: string): void => {
        DialogManager.renameValue = v;
      })
  }
}


/** 「跳转排序」弹窗内容：目标序号输入框 */
@ComponentV2
export struct SortJumpDialogContent {
  build() {
    TextInput({ text: DialogManager.sortJumpValue, placeholder: '目标序号（1-' + DialogManager.sortJumpMax.toString() + '）' })
      .type(InputType.Number)
      .width('100%')
      .height(44)
      .fontSize(14)
      .fontColor($r('sys.color.font_primary'))
      .placeholderColor($r('sys.color.font_tertiary'))
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .borderRadius(10)
      .onChange((v: string): void => {
        DialogManager.sortJumpValue = v;
      })
  }
}


/** 「选择器」弹窗内容：TextPicker 滚轮选择 */
@ComponentV2
export struct TextPickerDialogContent {
  build() {
    TextPicker({ range: DialogManager.pickerOptions, selected: DialogManager.pickerIndex })
      .onChange((value: string | string[], index: number | number[]) => {
        if (typeof index === 'number') {
          DialogManager.pickerIndex = index;
        }
      })
      .width('100%')
  }
}


/**
 * 公共弹窗管理：各页面通过 OpenDialog(key) 打开 Index 的公共弹窗，
 * 标题 / 按钮 / 确认取消逻辑集中在这里
 */
export class DialogManager {
  /** 当前弹窗标识 */
  public static dialogChangeKey: string = '';

  // ===== 弹窗参数（打开前由调用方赋值） =====
  /** 「使用说明」标题 */
  public static usageTitle: string = '';
  /** 「使用说明」正文 */
  public static usageMessage: string = '';
  /** 「配置变量」对应的插件名 */
  public static varPluginName: string = '';
  /** 「配置变量」字段列表 */
  public static varFields: Array<PluginVarField> = [];
  /** 「重命名」当前名称（打开前赋初值，弹窗内编辑） */
  public static renameValue: string = '';
  /** 「重命名」确认回调（打开前由调用方赋值，弹窗关闭后自动清空） */
  public static renameConfirm: ((name: string) => void) | null = null;
  /** 「跳转排序」目标序号（打开前赋初值，弹窗内编辑） */
  public static sortJumpValue: string = '';
  /** 「跳转排序」允许的最大序号（打开前由调用方赋值） */
  public static sortJumpMax: number = 0;
  /** 「跳转排序」确认回调（target 为 0 基索引，弹窗关闭后自动清空） */
  public static sortJumpConfirm: ((target: number) => void) | null = null;
  /** 「选择器」标题 */
  public static pickerTitle: string = '';
  /** 「选择器」选项文本 */
  public static pickerOptions: Array<string> = [];
  /** 「选择器」当前选中下标（打开前赋初值，弹窗内跟随滚动更新） */
  public static pickerIndex: number = 0;
  /** 「选择器」确认回调（index 为选中下标，弹窗关闭后自动清空；取消/关闭弹窗不触发） */
  public static pickerConfirm: ((index: number) => void) | null = null;

  // ===== 由 Index 注册的宿主动作 =====
  private static opener: (() => void) | null = null;
  private static toaster: ((message: string) => void) | null = null;

  /** 注册弹窗宿主（打开动作 / 轻提示），由 Index 调用 */
  public static Register(opener: () => void, toaster: (message: string) => void): void {
    DialogManager.opener = opener;
    DialogManager.toaster = toaster;
  }

  /** 打开弹窗 */
  public static OpenDialog(key: string): void {
    DialogManager.dialogChangeKey = key;
    appState.isDialogOpen = true;
    appState.isForegroundBlur = true;
    if (DialogManager.opener !== null) {
      DialogManager.opener();
    }
  }

  /** 弹窗内轻提示 */
  public static Toast(message: string): void {
    if (DialogManager.toaster !== null) {
      DialogManager.toaster(message);
    }
  }

  /** 获取弹窗标题文本 */
  public static DialogTitle(key: string): ResourceStr {
    switch (key) {
      case '使用说明':
        return DialogManager.usageTitle;
      case '配置变量':
        return '配置变量';
      case '创建分组':
        return '创建分组';
      case '重命名':
        return '重命名';
      case '跳转排序':
        return '跳转排序';
      case '选择器':
        return DialogManager.pickerTitle;
    }
    return '';
  }

  /** 弹窗底部按钮（CustomContentDialog 点击后自动关闭） */
  public static DialogButtons(key: string): Array<ButtonOptions> {
    const buttons: Array<ButtonOptions> = [];
    switch (key) {
      case '使用说明': {
        const ok: ButtonOptions = {
          value: '知道了',
          buttonStyle: ButtonStyleMode.EMPHASIZED,
          action: (): void => {
          }
        };
        buttons.push(ok);
        break;
      }
      case '配置变量': {
        const cancel: ButtonOptions = {
          value: '取消',
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.CancelButtonDialog(key);
          }
        };
        const confirm: ButtonOptions = {
          value: '保存',
          buttonStyle: ButtonStyleMode.EMPHASIZED,
          action: (): void => {
            DialogManager.ConfirmButtonDialog(key);
          }
        };
        buttons.push(cancel, confirm);
        break;
      }
      case '创建分组': {
        const cancel: ButtonOptions = {
          value: '取消',
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.CancelButtonDialog(key);
          }
        };
        const confirm: ButtonOptions = {
          value: '确定',
          buttonStyle: ButtonStyleMode.EMPHASIZED,
          action: (): void => {
            DialogManager.ConfirmButtonDialog(key);
          }
        };
        buttons.push(cancel, confirm);
        break;
      }
      case '重命名': {
        const cancel: ButtonOptions = {
          value: '取消',
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.CancelButtonDialog(key);
          }
        };
        const confirm: ButtonOptions = {
          value: '确定',
          buttonStyle: ButtonStyleMode.EMPHASIZED,
          action: (): void => {
            DialogManager.ConfirmButtonDialog(key);
          }
        };
        buttons.push(cancel, confirm);
        break;
      }
      case '跳转排序': {
        const cancel: ButtonOptions = {
          value: '取消',
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.CancelButtonDialog(key);
          }
        };
        const confirm: ButtonOptions = {
          value: '确定',
          buttonStyle: ButtonStyleMode.EMPHASIZED,
          action: (): void => {
            DialogManager.ConfirmButtonDialog(key);
          }
        };
        buttons.push(cancel, confirm);
        break;
      }
      case '选择器': {
        const cancel: ButtonOptions = {
          value: '取消',
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.CancelButtonDialog(key);
          }
        };
        const confirm: ButtonOptions = {
          value: '确定',
          buttonStyle: ButtonStyleMode.EMPHASIZED,
          action: (): void => {
            DialogManager.ConfirmButtonDialog(key);
          }
        };
        buttons.push(cancel, confirm);
        break;
      }
    }
    return buttons;
  }

  /** 弹窗确定键回调 */
  public static ConfirmButtonDialog(key: string): void {
    switch (key) {
      case '配置变量':
        DialogManager.savePluginVars();
        break;
      case '创建分组':
        break;
      case '重命名':
        if (DialogManager.renameConfirm !== null) {
          DialogManager.renameConfirm(DialogManager.renameValue);
        }
        break;
      case '跳转排序': {
        const n = parseInt(DialogManager.sortJumpValue, 10);
        if (isNaN(n) || n < 1 || n > DialogManager.sortJumpMax) {
          DialogManager.Toast('请输入 1-' + DialogManager.sortJumpMax.toString() + ' 之间的序号');
          break;
        }
        if (DialogManager.sortJumpConfirm !== null) {
          DialogManager.sortJumpConfirm(n - 1);
        }
        break;
      }
      case '选择器':
        if (DialogManager.pickerConfirm !== null) {
          DialogManager.pickerConfirm(DialogManager.pickerIndex);
        }
        break;
    }
  }

  /** 弹窗取消键回调 */
  public static CancelButtonDialog(key: string): void {
    switch (key) {
      case '配置变量':
        break;
      case '创建分组':
        break;
    }
  }

  /** 弹窗出现回调 */
  public static AppearDialog(key: string): void {
    appState.isForegroundBlur = true;
    switch (key) {
      case '速度调节':
        break;
    }
  }

  /** 弹窗消失回调 */
  public static DisappearDialog(key: string): void {
    appState.isForegroundBlur = false;
    appState.isDialogOpen = false;
    DialogManager.dialogChangeKey = '';
    // 重命名是一次性交互，关闭后清理回调与内容
    if (key === '重命名') {
      DialogManager.renameValue = '';
      DialogManager.renameConfirm = null;
    }
    // 跳转排序同理
    if (key === '跳转排序') {
      DialogManager.sortJumpValue = '';
      DialogManager.sortJumpMax = 0;
      DialogManager.sortJumpConfirm = null;
    }
    // 选择器同理（取消或关闭弹窗不触发确认回调）
    if (key === '选择器') {
      DialogManager.pickerTitle = '';
      DialogManager.pickerOptions = [];
      DialogManager.pickerIndex = 0;
      DialogManager.pickerConfirm = null;
    }

    switch (key) {
      case '创建分组':
        break;
    }
  }

  /** 保存「配置变量」到插件 */
  private static savePluginVars(): void {
    const plugin = pluginManager.getByName(DialogManager.varPluginName);
    if (plugin === null) {
      DialogManager.Toast('插件不存在');
      return;
    }
    const vars: Record<string, string> = {};
    for (const f of DialogManager.varFields) {
      vars[f.key] = f.value;
    }
    pluginManager.setUserVariables(plugin, vars);
    DialogManager.Toast('配置已保存');
  }
}
