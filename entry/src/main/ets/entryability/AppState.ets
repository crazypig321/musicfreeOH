import { HdsBarStyle, hdsMaterial } from "@kit.UIDesignKit";

/** 主题色预设（value 为空串表示跟随系统强调色） */
export class ThemeColorOption {
  readonly name: string;
  readonly value: string;

  constructor(name: string, value: string) {
    this.name = name;
    this.value = value;
  }
}

export const THEME_COLOR_OPTIONS: Array<ThemeColorOption> = [
  new ThemeColorOption('跟随系统', ''),
  new ThemeColorOption('蔚蓝', '#0A84FF'),
  new ThemeColorOption('青碧', '#00B8A9'),
  new ThemeColorOption('松石绿', '#34C759'),
  new ThemeColorOption('紫罗兰', '#7C5CFF'),
  new ThemeColorOption('樱花粉', '#FF6482'),
  new ThemeColorOption('绯红', '#FF453A'),
  new ThemeColorOption('暖橙', '#FF9F0A'),
  new ThemeColorOption('琥珀金', '#C99A2E')
];

/** 配置值 → 强调色（空串回落系统色） */
export function themeColorOf(value: string): ResourceColor {
  return value.length > 0 ? value : $r('sys.color.icon_emphasize');
}

@ObservedV2
class AppState{
  // nav页面控制
  @Trace pageInfos: NavPathStack = new NavPathStack();
  // tabs索引
  @Trace currTabsIndex: number = 0
  // tabs和mini折叠还是展开
  @Trace miniBarStyle: HdsBarStyle = HdsBarStyle.COLLAPSE
  // 沉浸光感参数
  @Trace materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE;
  @Trace materialType: hdsMaterial.MaterialType = hdsMaterial.MaterialType.IMMERSIVE;

  // tabs和mini排列模式：1 = VERTICAL 上下两排 / 0 = HORIZONTAL 单排（API>=6.1.1(24) 生效）
  @Trace hdsBarLayoutMode: number = 1

  // 全局强调色（主题色；空 = 跟随系统 icon_emphasize）
  @Trace accentColor: ResourceColor = $r('sys.color.icon_emphasize');
  // Tab 切换过渡动画开关
  @Trace tabSwitchAnim: boolean = true;
  // 智感握姿：握持手（left / right；未开启或未识别时为 right 即常规布局）
  @Trace holdingHand: string = 'right';

  // 是否开启模糊
  @Trace isForegroundBlur: boolean = false;
  // 弹窗是否开启
  @Trace isDialogOpen: boolean = false;
  // 批量操作模式（隐藏 tab 栏，返回键退出该模式）
  @Trace isBatchMode: boolean = false;

  /**
   * 屏幕避让及断点
   */
  // 顶部避让
  @Trace topRect: number = 0;
  // 底部避让
  @Trace bottomRect: number = 0;

  // 横断点
  @Trace WidthBp: number = 0;
  // 竖断点
  @Trace HeightBp: number = 0;
}

export const appState: AppState = new AppState()