import { appState } from "../entryability/AppState";
import { useSidebarLayout } from "./BreakpointUtils";


export class NavPathUtils{
  static push(key: string){
    if (useSidebarLayout(appState.WidthBp, appState.screenWidth, appState.displayWidth)) {
      appState.pageInfos.replacePath({name: key})
    }else{
      appState.pageInfos.pushPathByName(key, false);
    }
  }

  static pop(){
    appState.pageInfos.pop(false)
  }

  static clear(){
    appState.pageInfos.clear(false)
  }
}