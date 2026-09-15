import { BlurStrategy,
  HdsNavDestination,
  HdsTabs,
  HdsTabsController,
  ScrollEffectType,
  TitleBarContentOptions } from "@kit.UIDesignKit";
import { appState } from "../entryability/AppState";
import { LengthMetrics } from "@kit.ArkUI";

@ComponentV2
export struct CommonNav{
  private scrollerForScroll: Scroller = new Scroller();
  private tabsController: HdsTabsController = new HdsTabsController();
  @Param titleBarOp?: TitleBarContentOptions = undefined
  @Param isHideBackButton: boolean = false // 返回 true 拦截系统返回
  @Param avoidLayoutSafeArea: boolean = true
  @Param isShowPlayBar: boolean = false
  @Event backPressed:() => boolean

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
           // titleStyle: { mainTitleColor: appConfig.textColor, subTitleColor: appConfig.terTextColor },
          //  backIconStyle: { iconColor: appConfig.textColor },
            menuStyle: {
             // iconColor: appConfig.textColor
            },
            subIconStyle: {
            //  iconColor: appConfig.textColor
            }
          },
        },
        scrollEffectStyle: { backgroundStyle: { backgroundColor: '#19ffffff', maskExtraHeight: 0, blurRadius: 100 } },
        systemMaterialEffect: {
          materialType: appState.materialType,
          materialLevel: appState.materialLevel
        },
      },
      avoidLayoutSafeArea: this.avoidLayoutSafeArea,
    })
    .bindToScrollable([this.scrollerForScroll])
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
  }

  @Builder
  playBar(){

  }
}