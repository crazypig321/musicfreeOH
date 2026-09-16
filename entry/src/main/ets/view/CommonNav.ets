import { BlurStrategy,
  HdsNavDestination,
  HdsNavigationTitle,
  HdsNavigationMenuItemOptions,
  HdsTabs,
  HdsTabsController,
  ScrollEffectType,
  TitleBarContentOptions,
  BottomBuilderParams,
  HideMode} from "@kit.UIDesignKit";
import { appState } from "../entryability/AppState";
import { LengthMetrics } from "@kit.ArkUI";
import { PlayBar } from "./PlayBar";
import { themeUtils } from "../utils/ThemeUtils";

export function titleBarOf(mainTitle: ResourceStr, subTitle?: ResourceStr,
  menus?: Array<HdsNavigationMenuItemOptions>, bottomBuilder?: BottomBuilderParams): TitleBarContentOptions {
  const title: HdsNavigationTitle = {
    mainTitle: mainTitle,
    subTitle: subTitle
  };
  const options: TitleBarContentOptions = {
    title: title
  };
  if (menus !== undefined && menus.length > 0) {
    options.menu = {
      value: menus
    };
  }
  options.bottomBuilder = bottomBuilder
  return options;
}

@ComponentV2
export struct CommonNav{
  private tabsController: HdsTabsController = new HdsTabsController();
  @Param titleBarOp?: TitleBarContentOptions = undefined
  @Param isHideBackButton: boolean = false // 返回 true 拦截系统返回
  @Param avoidLayoutSafeArea: boolean = true
  @Param isShowPlayBar: boolean = false
  @Param scroller: Scroller | undefined = undefined
  @Event backPressed: () => boolean = (): boolean => false

  @BuilderParam content: () => void;

  build() {
    HdsNavDestination() {
      if (this.isShowPlayBar){
        HdsTabs({ controller: this.tabsController }) {
          TabContent(){
            this.content()
          }.tabBar(this.playBar()).align(Alignment.Top)
        }
        .barOverlap(true)
        .vertical(false)
        .scrollable(false)
        .barPosition(BarPosition.End)
        .barFloatingStyle({
          barWidth: {smallWidth: 330},
          barBottomMargin: 28,
          systemMaterialEffect: {
            materialType: appState.materialType,
            materialLevel: appState.materialLevel
          },
          adaptToHandedness: true,
         // gradientMask: { maskColor: appConfig.maskColor },
        })
      }else{
        this.content()
      }
    }
    .titleBar({
      content: this.titleBarOp,
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR, // 设置模糊类型
          blurEffectiveStartOffset: LengthMetrics.vp(0), // 动态样式线性过渡的起始位置
          blurEffectiveEndOffset: LengthMetrics.vp(80) // 动态样式线性过渡的终点位置
        },
        blurStrategy: BlurStrategy.ADAPTIVE,
        originalStyle: {
          backgroundStyle: { backgroundColor: '#00ffffff', maskExtraHeight: 0, blurRadius: 50 },
          contentStyle: {
            // 深浅模式切换时由 themeUtils 触发重渲染（HDS 不会自动刷新系统色）
            titleStyle: { mainTitleColor: themeUtils.textColor, subTitleColor: themeUtils.terTextColor },
            backIconStyle: { iconColor: themeUtils.textColor },
            menuStyle: {
              iconColor: themeUtils.textColor
            },
            subIconStyle: {
              iconColor: themeUtils.textColor
            }
          },
        },
        scrollEffectStyle: { backgroundStyle: { backgroundColor: '#19ffffff', maskExtraHeight: 0, blurRadius: 80 } },
        systemMaterialEffect: {
          materialType: appState.materialType,
          materialLevel: appState.materialLevel
        },
      },
      avoidLayoutSafeArea: this.avoidLayoutSafeArea,
    })
    .bindToScrollable(this.scroller ? [this.scroller] : [])
    .hideBackButton(this.isHideBackButton)
    .backgroundColor($r('sys.color.background_secondary'))
    .width('100%')
    .height('100%')
    .transition(
      TransitionEffect.asymmetric(
        TransitionEffect.OPACITY,
        TransitionEffect.OPACITY
      ).animation({duration: 300, curve: Curve.Smooth})
    )
    .onBackPressed(() => {
      return this.backPressed()
    })
    .dynamicHideTitleBar({
      hideBottomBuilder: true,
      mode: HideMode.SCROLL_UP_TO
    })
  }

  @Builder
  playBar(){
    PlayBar()
  }
}
