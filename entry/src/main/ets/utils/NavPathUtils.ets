import { appState } from "../entryability/AppState";


export class NavPathUtils{
  static push(key: string){
    appState.pageInfos.pushPathByName(key, false);
  }

  static pop(){
    appState.pageInfos.pop(false)
  }

  static clear(){
    appState.pageInfos.clear(false)
  }
}