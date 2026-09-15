import { hdsMaterial } from "@kit.UIDesignKit";

@ObservedV2
class AppState{
  // nav页面控制
  @Trace pageInfos: NavPathStack = new NavPathStack();
  // 沉浸光感参数
  @Trace materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE;
  @Trace materialType: hdsMaterial.MaterialType = hdsMaterial.MaterialType.IMMERSIVE;
  
  // tabs和mini排列模式
  @Trace hdsBarLayoutMode: number = 1

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