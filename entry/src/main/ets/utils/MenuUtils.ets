import { ComponentContent, UIContext } from '@kit.ArkUI';
import { MenuItemParams, MenuParams, commonMenuWrapped } from '../view/CommonCom';

/**
 * openMenu 公共工具：封装下拉菜单的打开/关闭
 * 页面只需组装菜单项（MenuItemParams）后在锚点处调用 MenuUtils.Open 即可
 */
export class MenuUtils {
  /** 当前打开的菜单内容（同一时刻只允许一个菜单） */
  private static content: ComponentContent<MenuParams> | null = null;
  /** 打开菜单时使用的 UIContext（关闭菜单时需要） */
  private static uiContext: UIContext | null = null;

  /**
   * 在锚点组件处打开菜单
   * @param uiContext 页面 UIContext
   * @param anchorId 锚点组件 id（菜单弹出的定位组件）
   * @param items 菜单项列表
   * @param options 菜单选项（placement/offset 等定位参数）
   */
  public static Open(uiContext: UIContext, anchorId: string, items: Array<MenuItemParams>,
    options: MenuOptions): void {
    MenuUtils.Dismiss();
    const params = new MenuParams();
    params.items = items;
    const content = new ComponentContent<MenuParams>(uiContext, commonMenuWrapped, params);
    MenuUtils.content = content;
    MenuUtils.uiContext = uiContext;
    uiContext.getPromptAction().openMenu(content, { id: anchorId }, options)
      .then((): void => {
        if (MenuUtils.content === content) {
          MenuUtils.content = null;
          MenuUtils.uiContext = null;
        }
      })
      .catch((_e: Object): void => {
        if (MenuUtils.content === content) {
          MenuUtils.content = null;
          MenuUtils.uiContext = null;
        }
        try {
          uiContext.getPromptAction().showToast({ message: '菜单弹出失败', duration: 1500 });
        } catch (_err) {
          // TODO: Implement error handling.
        }
      });
  }

  /**
   * 关闭当前打开的菜单
   */
  public static Dismiss(): void {
    const content = MenuUtils.content;
    MenuUtils.content = null;
    const uiContext = MenuUtils.uiContext;
    MenuUtils.uiContext = null;
    if (content !== null && uiContext !== null) {
      uiContext.getPromptAction().closeMenu(content).catch((_e: Object): void => {
      });
    }
  }
}
