import { BlurStrategy, HdsNavigationTitleBarOptions, ScrollEffectType } from "@kit.UIDesignKit";
import { LengthMetrics } from "@kit.ArkUI";
import { TimeTipUtils } from "../../utils/TimeTipUtils";
import { appState } from "../../entryability/AppState";

export const ROUTE_SEARCH: string = 'search';

export function NavTitleBarOp() : HdsNavigationTitleBarOptions {
return {
content: {
title: {
mainTitle: TimeTipUtils(),
},
menu: {
value: [{
  content: {
    icon: $r('sys.symbol.magnifyingglass'),
    label: 'search',
    action: () => {
      // 搜索操作
    },
  }
}]
},
},
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
  titleStyle: { mainTitleColor: $r('sys.color.font'), subTitleColor: $r('sys.color.font_tertiary') },
  menuStyle: {
    iconColor: $r('sys.color.icon')
  },
},
},
scrollEffectStyle: { backgroundStyle: { backgroundColor: '#00ffffff', maskExtraHeight: 0, blurRadius: 100 } },
systemMaterialEffect: {
materialType: appState.materialType,
materialLevel: appState.materialLevel
},
},
avoidLayoutSafeArea: true,
}
}