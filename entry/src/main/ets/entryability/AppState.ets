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

}

export const appState: AppState = new AppState()