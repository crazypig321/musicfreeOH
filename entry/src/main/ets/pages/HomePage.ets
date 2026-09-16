import { TimeTipUtils } from '../utils/TimeTipUtils'
import { CommonNav, titleBarOf } from '../view/CommonNav'
import { HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { CommonLoading, CommonNull, CommonSearch } from '../view/CommonCom';
import { NavPathUtils } from '../utils/NavPathUtils';
import { SheetGroupItem } from '../common/model/SheetTypes';
import { appState } from '../entryability/AppState';

@ComponentV2
export struct HomePage{
  @Param bootReady: boolean = false;

  @Local topListGroups: Array<SheetGroupItem> = [];
  private scroller: Scroller = new Scroller();

  /** 主体build */
  build() {
    CommonNav({
      titleBarOp: titleBarOf(TimeTipUtils(), $r('app.string.home_subtitle'), this.titleMenus(), { builder: (): void => { this.search() } }),
      isHideBackButton: true,
      scroller: this.scroller
    }) {
      List({scroller: this.scroller}) {
        if (this.topListGroups.length === 0) {
          ListItem() {
            CommonNull({ message: $r('app.string.home_no_plugin') })
          }
        } else {
          if (!this.bootReady){
            CommonLoading()
          }else{

          }
        }
      }.ListStyle()
    }
  }

  /** 搜索框 */
  @Builder
  search(){
    CommonSearch({
      searchValue: '',
      placeholderValue: $r('app.string.home_search_placeholder'),
      isFocusable: false,
      click: () => {
        NavPathUtils.push('search')
      }
    }).padding({ left: 16, right: 16 })
  }

  /** titleBar 菜单按钮（选择插件） */
  private titleMenus(): Array<HdsNavigationMenuItemOptions> {
    const menu: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.AI_panels'),
        label: '选择插件',
        action: (): void => {

        }
      }
    };
    return [menu];
  }
}

@Extend(List)
function ListStyle(){
  .width('100%')
  .height('100%')
  .scrollBar(BarState.Off)
  .edgeEffect(EdgeEffect.Spring)
  .contentStartOffset(appState.topRect + 120)
  .contentEndOffset(appState.bottomRect + 60)
  .padding({ left: 16, right: 16 })
}