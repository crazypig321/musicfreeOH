import { appState } from "../entryability/AppState";
import { pluginManager } from "../plugin/PluginManager";
import { ButtonOptions } from "@kit.ArkUI";
import { MusicItem } from "../common/model/MediaTypes";


/** 插件用户变量字段（弹窗内编辑） */
export class PluginVarField {
  public key: string = '';
  public name: string = '';
  public value: string = '';
}


/** 「编辑信息」弹窗的单个标签输入字段 */
export class MetaEditFieldDesc {
  /** 输入框上方标签（标题/歌手/专辑） */
  public label: string = '';
  /** 输入框占位提示 */
  public placeholder: string = '';
  /** 输入框内容（弹窗内编辑，确认时读取） */
  public value: string = '';
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
  /** 「下载到文件夹」目标文件夹名（打开前赋初值，弹窗内编辑） */
  public static downloadFolderValue: string = '';
  /** 「下载到文件夹」确认回调（folder 为输入的文件夹名，弹窗关闭后自动清空） */
  public static downloadFolderConfirm: ((folder: string) => void) | null = null;
  /** 「选择器」标题 */
  public static pickerTitle: string = '';
  /** 「选择器」选项文本 */
  public static pickerOptions: Array<string> = [];
  /** 「选择器」当前选中下标（打开前赋初值，弹窗内跟随滚动更新） */
  public static pickerIndex: number = 0;
  /** 「选择器」确认回调（index 为选中下标，弹窗关闭后自动清空；取消/关闭弹窗不触发） */
  public static pickerConfirm: ((index: number) => void) | null = null;
  /** 「更换音源」目标歌曲（打开前赋值，弹窗内容组件据此搜索） */
  public static changeSourceItem: MusicItem | null = null;
  /** 「更换音源」候选结果（弹窗内容组件搜索完成后回填） */
  public static changeSourceCandidates: Array<MusicItem> = [];
  /** 「更换音源」选中下标（弹窗内点击候选更新） */
  public static changeSourceIndex: number = 0;
  /** 「更换音源」确认回调（弹窗关闭后自动清空；取消/关闭弹窗不触发） */
  public static changeSourceConfirm: ((index: number) => void) | null = null;
  /** 「选择封面」目标歌曲（打开前赋值，弹窗内容组件据此搜索） */
  public static coverPickItem: MusicItem | null = null;
  /** 「选择封面」候选结果（弹窗内容组件搜索完成后回填） */
  public static coverPickCandidates: Array<string> = [];
  /** 「选择封面」选中下标（弹窗内点击候选更新） */
  public static coverPickIndex: number = 0;
  /** 「选择封面」确认回调（弹窗关闭后自动清空；取消/关闭弹窗不触发） */
  public static coverPickConfirm: ((index: number) => void) | null = null;
  /** 「设置缓存」当前值（打开前赋初值，弹窗内编辑） */
  public static cacheInputValue: string = '';
  /** 「设置缓存」单位（'M' | 'G'，打开前赋初值，弹窗内切换） */
  public static cacheInputUnit: string = 'M';
  /** 「设置缓存」确认回调（text 为输入文本，弹窗关闭后自动清空） */
  public static cacheInputConfirm: ((text: string) => void) | null = null;
  /** 「均衡器增益」频段名（打开前赋值，用作弹窗标题） */
  public static eqGainBandLabel: string = '';
  /** 「均衡器增益」当前输入（打开前赋初值，弹窗内编辑） */
  public static eqGainValue: string = '';
  /** 「均衡器增益」确认回调（gain 为 -12 ~ 12 整数，弹窗关闭后自动清空；取消/关闭不触发） */
  public static eqGainConfirm: ((gain: number) => void) | null = null;
  /** 「编辑信息」标签输入字段（打开前由 EditMeta 赋初值，弹窗内编辑） */
  public static editMetaFields: Array<MetaEditFieldDesc> = [];
  /** 「编辑信息」确认回调（fields 为弹窗内编辑后的字段；校验/写入/关闭弹窗由回调负责；取消/关闭不触发） */
  public static editMetaConfirm: ((fields: Array<MetaEditFieldDesc>) => void) | null = null;
  /** 通用确认弹窗（清除缓存/确认删除/确认导入/发现新版本）正文（打开前由调用方赋值） */
  public static confirmMessage: string = '';
  /** 通用确认弹窗确认回调（弹窗关闭后自动清空；取消/关闭弹窗不触发） */
  public static confirmCallback: (() => void) | null = null;
  /** 「转换简洁命名」正文（打开前由调用方赋值） */
  public static simpleRenameMessage: string = '';
  /** 「转换简洁命名」确认回调（执行重命名耗时操作，完成后由回调自行关闭弹窗并提示） */
  public static simpleRenameConfirm: (() => void) | null = null;
  /** 「选择歌词音源」目标歌曲（打开前赋值） */
  public static lyricSourceItem: MusicItem | null = null;
  /** 「选择歌词音源」候选插件名（打开前赋值） */
  public static lyricSourceOptions: Array<string> = [];
  /** 「选择歌词音源」选中下标（打开前赋初值，弹窗内 Select 更新） */
  public static lyricSourceIndex: number = 0;
  /** 「选择歌词音源」确认回调（pluginName 为选中的插件名，弹窗关闭后自动清空） */
  public static lyricSourceConfirm: ((pluginName: string) => void) | null = null;

  /** 弹窗关闭回调（一次性，关闭后自动清空） */
  public static onDialogClosed: (() => void) | null = null;

  // ===== 由 Index 注册的宿主动作 =====
  private static opener: (() => void) | null = null;
  private static toaster: ((message: string) => void) | null = null;
  private static closer: (() => void) | null = null;

  /** 注册弹窗宿主（打开动作 / 轻提示 / 关闭动作），由 Index 调用 */
  public static Register(opener: () => void, toaster: (message: string) => void, closer: () => void): void {
    DialogManager.opener = opener;
    DialogManager.toaster = toaster;
    DialogManager.closer = closer;
  }

  /** 打开弹窗 */
  public static OpenDialog(key: string): void {
    DialogManager.dialogChangeKey = key;
    appState.isDialogOpen = true;
    //appState.isForegroundBlur = true;
    if (DialogManager.opener !== null) {
      DialogManager.opener();
    }
  }

  /** 关闭弹窗（由内容区域自定义按钮在异步保存完成后调用） */
  public static CloseDialog(): void {
    if (DialogManager.closer !== null) {
      DialogManager.closer();
    }
  }

  /** 通用清除缓存确认弹窗：message 提示文案，onConfirm 点击「确定」后才执行（取消不执行） */
  public static ClearCache(message: string, onConfirm: () => void): void {
    DialogManager.confirmMessage = message;
    DialogManager.confirmCallback = onConfirm;
    DialogManager.OpenDialog('清除缓存');
  }

  /** 通用删除确认弹窗：message 提示文案，onConfirm 点击「删除」后才执行（取消不执行） */
  public static ConfirmDelete(message: string, onConfirm: () => void): void {
    DialogManager.confirmMessage = message;
    DialogManager.confirmCallback = onConfirm;
    DialogManager.OpenDialog('确认删除');
  }

  /** 通用导入确认弹窗：message 提示文案，onConfirm 点击「导入」后才执行（取消不执行） */
  public static ConfirmImport(message: string, onConfirm: () => void): void {
    DialogManager.confirmMessage = message;
    DialogManager.confirmCallback = onConfirm;
    DialogManager.OpenDialog('确认导入');
  }

  /** 版本更新确认弹窗：message 提示文案，onConfirm 点击「下载」后才执行（取消不执行） */
  public static ConfirmUpdate(message: string, onConfirm: () => void): void {
    DialogManager.confirmMessage = message;
    DialogManager.confirmCallback = onConfirm;
    DialogManager.OpenDialog('发现新版本');
  }

  /** 转换简洁命名确认弹窗：message 提示文案，onConfirm 点击「转换」后执行（取消/关闭不触发；
   *  回调内部负责显示 loading、执行重命名并手动关闭弹窗） */
  public static ConfirmSimpleRename(message: string, onConfirm: () => void): void {
    DialogManager.simpleRenameMessage = message;
    DialogManager.simpleRenameConfirm = onConfirm;
    DialogManager.OpenDialog('转换简洁命名');
  }

  /** 手动选择封面弹窗：item 目标歌曲，onConfirm(artwork) 选中封面后执行（取消/关闭不触发） */
  public static PickCover(item: MusicItem, onConfirm: (artwork: string) => void): void {
    DialogManager.coverPickItem = item;
    DialogManager.coverPickIndex = 0;
    DialogManager.coverPickCandidates = [];
    DialogManager.coverPickConfirm = (index: number): void => {
      const list = DialogManager.coverPickCandidates;
      onConfirm(index >= 0 && index < list.length ? list[index] : '');
    };
    DialogManager.OpenDialog('选择封面');
  }

  /** 选择歌词音源弹窗：item 目标歌曲，pluginNames 候选插件名（首项通常为「自动」，默认选中），
   *  onConfirm(pluginName) 点击「搜索」后才执行（取消/关闭不触发） */
  public static SelectLyricSource(item: MusicItem, pluginNames: Array<string>,
    onConfirm: (pluginName: string) => void): void {
    DialogManager.lyricSourceItem = item;
    DialogManager.lyricSourceOptions = pluginNames;
    DialogManager.lyricSourceIndex = 0;
    DialogManager.lyricSourceConfirm = onConfirm;
    DialogManager.OpenDialog('选择歌词音源');
  }

  /** 弹窗内轻提示 */
  public static Toast(message: string): void {
    if (DialogManager.toaster !== null) {
      DialogManager.toaster(message);
    }
  }

  /** 均衡器频段增益输入弹窗：bandLabel 频段名（标题），currentGain 当前增益，
   *  onConfirm(gain) 输入合法（-12 ~ 12 整数）点击「确定」后执行（取消/关闭不触发） */
  public static InputEqGain(bandLabel: string, currentGain: number, onConfirm: (gain: number) => void): void {
    DialogManager.eqGainBandLabel = bandLabel;
    DialogManager.eqGainValue = currentGain.toString();
    DialogManager.eqGainConfirm = onConfirm;
    DialogManager.OpenDialog('均衡器增益');
  }

  /** 编辑信息弹窗（标题/歌手/专辑写回音频文件标签）：item 目标歌曲（预填当前元信息），
   *  onConfirm(fields) 点击「保存」后执行（fields 顺序为标题/歌手/专辑；
   *  校验/异步写入/关闭弹窗由回调负责；取消/关闭不触发） */
  public static EditMeta(item: MusicItem, onConfirm: (fields: Array<MetaEditFieldDesc>) => void): void {
    const title = new MetaEditFieldDesc();
    title.label = '标题';
    title.placeholder = '请输入标题';
    title.value = item.title;
    const artist = new MetaEditFieldDesc();
    artist.label = '歌手';
    artist.placeholder = '请输入歌手（留空清除）';
    artist.value = item.artist;
    const album = new MetaEditFieldDesc();
    album.label = '专辑';
    album.placeholder = '请输入专辑（留空清除）';
    album.value = item.album;
    const fields: Array<MetaEditFieldDesc> = [title, artist, album];
    DialogManager.editMetaFields = fields;
    DialogManager.editMetaConfirm = onConfirm;
    DialogManager.OpenDialog('编辑信息');
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
      case '歌单说明':
        return '歌单说明';
      case '下载到文件夹':
        return '下载到文件夹';
      case '移动到文件夹':
        return '移动到文件夹';
      case '添加标签':
        return '添加标签';
      case '编辑标签':
        return '编辑标签';
      case '选择器':
        return DialogManager.pickerTitle;
      case '更换音源':
        return '更换音源';
      case '选择封面':
        return '选择封面';
      case '选择歌词音源':
        return '选择歌词音源';
      case '设置缓存':
        return '设置缓存';
      case '清除缓存':
        return '清除缓存';
      case '确认导入':
        return '导入歌单';
      case '确认删除':
        return '删除';
      case '发现新版本':
        return '发现新版本';
      case '免责声明':
        return '免责声明';
      case '转换简洁命名':
        return '转换简洁命名';
      case '均衡器增益':
        return DialogManager.eqGainBandLabel + 'Hz 频段增益';
      case '编辑信息':
        return '编辑音频文件元数据';
      case '捐赠':
        return '支持作者';
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
          fontColor: Color.White,
          background: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
          }
        };
        buttons.push(ok);
        break;
      }
      case '歌单说明': {
        const ok: ButtonOptions = {
          value: '知道了',
          fontColor: Color.White,
          background: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
          }
        };
        buttons.push(ok);
        break;
      }
      case '配置变量': {
        const cancel: ButtonOptions = {
          value: '取消',
          fontColor: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.CancelButtonDialog(key);
          }
        };
        const confirm: ButtonOptions = {
          value: '保存',
          fontColor: Color.White,
          background: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
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
          fontColor: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.CancelButtonDialog(key);
          }
        };
        const confirm: ButtonOptions = {
          value: '确定',
          fontColor: Color.White,
          background: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
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
          fontColor: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.CancelButtonDialog(key);
          }
        };
        const confirm: ButtonOptions = {
          value: '确定',
          fontColor: Color.White,
          background: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
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
          fontColor: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.CancelButtonDialog(key);
          }
        };
        const confirm: ButtonOptions = {
          value: '确定',
          fontColor: Color.White,
          background: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.ConfirmButtonDialog(key);
          }
        };
        buttons.push(cancel, confirm);
        break;
      }
      case '下载到文件夹': {
        const cancel: ButtonOptions = {
          value: '取消',
          fontColor: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.CancelButtonDialog(key);
          }
        };
        const confirm: ButtonOptions = {
          value: '下载',
          fontColor: Color.White,
          background: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.ConfirmButtonDialog(key);
          }
        };
        buttons.push(cancel, confirm);
        break;
      }
      case '移动到文件夹': {
        const cancel: ButtonOptions = {
          value: '取消',
          fontColor: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.CancelButtonDialog(key);
          }
        };
        const confirm: ButtonOptions = {
          value: '移动',
          fontColor: Color.White,
          background: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.ConfirmButtonDialog(key);
          }
        };
        buttons.push(cancel, confirm);
        break;
      }
      case '添加标签': {
        const cancel: ButtonOptions = {
          value: '取消',
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.CancelButtonDialog(key);
          }
        };
        const confirm: ButtonOptions = {
          value: '创建',
          fontColor: Color.White,
          background: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.ConfirmButtonDialog(key);
          }
        };
        buttons.push(cancel, confirm);
        break;
      }
      case '编辑标签': {
        // 按钮在内容区域渲染（自定义按钮支持 loading 态，异步保存完成后手动关闭弹窗）
        break;
      }
      case '转换简洁命名': {
        // 按钮在内容区域渲染（自定义按钮支持 loading 态，重命名完成后手动关闭弹窗）
        break;
      }
      case '选择器': {
        const cancel: ButtonOptions = {
          value: '取消',
          fontColor: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.CancelButtonDialog(key);
          }
        };
        const confirm: ButtonOptions = {
          value: '确定',
          fontColor: Color.White,
          background: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.ConfirmButtonDialog(key);
          }
        };
        buttons.push(cancel, confirm);
        break;
      }
      case '更换音源': {
        const cancel: ButtonOptions = {
          value: '取消',
          fontColor: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.CancelButtonDialog(key);
          }
        };
        const confirm: ButtonOptions = {
          value: '确定',
          fontColor: Color.White,
          background: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.ConfirmButtonDialog(key);
          }
        };
        buttons.push(cancel, confirm);
        break;
      }
      case '选择封面': {
        const cancel: ButtonOptions = {
          value: '取消',
          fontColor: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.CancelButtonDialog(key);
          }
        };
        const confirm: ButtonOptions = {
          value: '确定',
          fontColor: Color.White,
          background: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.ConfirmButtonDialog(key);
          }
        };
        buttons.push(cancel, confirm);
        break;
      }
      case '选择歌词音源': {
        const cancel: ButtonOptions = {
          value: '取消',
          fontColor: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.CancelButtonDialog(key);
          }
        };
        const confirm: ButtonOptions = {
          value: '搜索',
          fontColor: Color.White,
          background: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.ConfirmButtonDialog(key);
          }
        };
        buttons.push(cancel, confirm);
        break;
      }
      case '设置缓存': {
        const cancel: ButtonOptions = {
          value: '取消',
          fontColor: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.CancelButtonDialog(key);
          }
        };
        const confirm: ButtonOptions = {
          value: '确定',
          fontColor: Color.White,
          background: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.ConfirmButtonDialog(key);
          }
        };
        buttons.push(cancel, confirm);
        break;
      }
      case '均衡器增益': {
        // 按钮在内容区域渲染（校验失败提示错误并保持弹窗打开）
        break;
      }
      case '编辑信息': {
        // 按钮在内容区域渲染（校验失败提示错误并保持弹窗打开，保存中显示 loading）
        break;
      }
      case '清除缓存':
      case '确认删除':
      case '确认导入':
      case '发现新版本': {
        const cancel: ButtonOptions = {
          value: '取消',
          fontColor: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.CancelButtonDialog(key);
          }
        };
        const confirm: ButtonOptions = {
          value: DialogManager.confirmLabelOf(key),
          fontColor: Color.White,
          background: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            DialogManager.ConfirmButtonDialog(key);
          }
        };
        buttons.push(cancel, confirm);
        break;
      }
      case '免责声明': {
        const ok: ButtonOptions = {
          value: '我知道了',
          fontColor: Color.White,
          background: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
          }
        };
        buttons.push(ok);
        break;
      }
      case '捐赠': {
        const ok: ButtonOptions = {
          value: '🙏感谢你的支持!',
          fontColor: Color.White,
          background: appState.accentColor,
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: (): void => {
            appState.isForegroundBlur = false
          }
        };
        buttons.push(ok);
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
      case '下载到文件夹':
      case '移动到文件夹':
      case '添加标签':
      case '编辑标签':
        if (DialogManager.downloadFolderConfirm !== null) {
          DialogManager.downloadFolderConfirm(DialogManager.downloadFolderValue.trim());
        }
        break;
      case '选择器':
        if (DialogManager.pickerConfirm !== null) {
          DialogManager.pickerConfirm(DialogManager.pickerIndex);
        }
        break;
      case '更换音源':
        if (DialogManager.changeSourceCandidates.length > 0 && DialogManager.changeSourceConfirm !== null) {
          DialogManager.changeSourceConfirm(DialogManager.changeSourceIndex);
        }
        break;
      case '选择封面':
        if (DialogManager.coverPickCandidates.length > 0 && DialogManager.coverPickConfirm !== null) {
          DialogManager.coverPickConfirm(DialogManager.coverPickIndex);
        }
        break;
      case '选择歌词音源':
        if (DialogManager.lyricSourceOptions.length > 0 && DialogManager.lyricSourceConfirm !== null) {
          const idx = DialogManager.lyricSourceIndex;
          DialogManager.lyricSourceConfirm(
            idx >= 0 && idx < DialogManager.lyricSourceOptions.length ? DialogManager.lyricSourceOptions[idx] : '');
        }
        break;
      case '设置缓存':
        if (DialogManager.cacheInputConfirm !== null) {
          DialogManager.cacheInputConfirm(DialogManager.cacheInputValue);
        }
        break;
      case '清除缓存':
      case '确认导入':
      case '确认删除':
      case '发现新版本':
        if (DialogManager.confirmCallback !== null) {
          DialogManager.confirmCallback();
        }
        break;
      case '编辑信息':
        if (DialogManager.editMetaConfirm !== null) {
          DialogManager.editMetaConfirm(DialogManager.editMetaFields);
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
   // appState.isForegroundBlur = true;
    switch (key) {
      case '速度调节':
        break;
      case '添加标签':
        appState.isForegroundBlur = true
        break
      case '捐赠':
        appState.isForegroundBlur = true
        break
    }
  }

  /** 弹窗消失回调 */
  public static DisappearDialog(key: string): void {
   // appState.isForegroundBlur = false;
    appState.isDialogOpen = false;
    appState.isDialogSaving = false;
    DialogManager.dialogChangeKey = '';
    if (DialogManager.onDialogClosed !== null) {
      const cb = DialogManager.onDialogClosed;
      DialogManager.onDialogClosed = null;
      cb();
    }
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
    // 下载/移动到文件夹、添加/编辑标签同理（取消或关闭弹窗不触发动作）
    if (key === '下载到文件夹' || key === '移动到文件夹' ||
      key === '添加标签' || key === '编辑标签') {
      DialogManager.downloadFolderValue = '';
      DialogManager.downloadFolderConfirm = null;
    }
    if (key === '添加标签') {
      appState.isForegroundBlur = false
    }
    // 选择器同理（取消或关闭弹窗不触发确认回调）
    if (key === '选择器') {
      DialogManager.pickerTitle = '';
      DialogManager.pickerOptions = [];
      DialogManager.pickerIndex = 0;
      DialogManager.pickerConfirm = null;
    }
    // 更换音源同理（取消或关闭弹窗不触发确认回调）
    if (key === '更换音源') {
      DialogManager.changeSourceItem = null;
      DialogManager.changeSourceCandidates = [];
      DialogManager.changeSourceIndex = 0;
      DialogManager.changeSourceConfirm = null;
    }
    // 选择封面同理（取消或关闭弹窗不触发确认回调）
    if (key === '选择封面') {
      DialogManager.coverPickItem = null;
      DialogManager.coverPickCandidates = [];
      DialogManager.coverPickIndex = 0;
      DialogManager.coverPickConfirm = null;
    }
    // 选择歌词音源同理（取消或关闭弹窗不触发确认回调）
    if (key === '选择歌词音源') {
      DialogManager.lyricSourceItem = null;
      DialogManager.lyricSourceOptions = [];
      DialogManager.lyricSourceIndex = 0;
      DialogManager.lyricSourceConfirm = null;
    }
    // 设置缓存同理
    if (key === '设置缓存') {
      DialogManager.cacheInputValue = '';
      DialogManager.cacheInputUnit = 'M';
      DialogManager.cacheInputConfirm = null;
    }
    // 四个通用确认弹窗同理（取消或关闭弹窗不触发确认回调）
    if (key === '清除缓存' || key === '确认删除' || key === '确认导入' ||
      key === '发现新版本') {
      DialogManager.confirmMessage = '';
      DialogManager.confirmCallback = null;
    }
    // 转换简洁命名同理（取消或关闭弹窗不触发转换）
    if (key === '转换简洁命名') {
      DialogManager.simpleRenameMessage = '';
      DialogManager.simpleRenameConfirm = null;
    }
    // 均衡器增益同理（取消或关闭弹窗不触发确认回调）
    if (key === '均衡器增益') {
      DialogManager.eqGainBandLabel = '';
      DialogManager.eqGainValue = '';
      DialogManager.eqGainConfirm = null;
    }
    // 编辑信息同理（取消或关闭弹窗不触发写入）
    if (key === '编辑信息') {
      DialogManager.editMetaFields = [];
      DialogManager.editMetaConfirm = null;
    }
    // 捐赠回调
    if (key === '捐赠') {
      appState.isForegroundBlur = false
    }
  }

  /** 通用确认弹窗（清除缓存/确认删除/确认导入/发现新版本）的确认按钮文案 */
  private static confirmLabelOf(key: string): string {
    if (key === '确认删除') {
      return '删除';
    }
    if (key === '确认导入') {
      return '导入';
    }
    if (key === '发现新版本') {
      return '下载';
    }
    return '确定';
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
