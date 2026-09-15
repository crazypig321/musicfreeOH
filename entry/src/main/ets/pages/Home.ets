import { HdsNavDestination } from "@kit.UIDesignKit";
import { NavTitleBarOp } from "../model/NavModels";

@ComponentV2
export struct Home{
  scroller: Scroller = new Scroller();

  build() {
    HdsNavDestination() {

    }
    .hideBackButton(true)
    .backgroundColor(Color.Transparent)
    .width('100%')
    .height('100%')
    .bindToScrollable([this.scroller])
    .titleBar(NavTitleBarOp())
    .transition(TransitionEffect.OPACITY)
  }
}