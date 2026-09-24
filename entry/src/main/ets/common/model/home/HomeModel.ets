export interface IconTextItem{
  icon: Resource
  text1: ResourceStr
  text2?: ResourceStr
}

export const HomeList: Array<IconTextItem> = [
  { icon: $r('sys.symbol.star_trophy'), text1: $r('app.string.home_toplists') },
  { icon: $r('sys.symbol.waveform_path_ecg_heart'), text1: $r('app.string.home_recommend_sheets') },
  { icon: $r('sys.symbol.folder'), text1: $r('app.string.home_local_music') }
]

/** 播放控制按钮配置 */
export interface ControlButtonConfig {
  symbol: Resource
  fontSize: number
  fontColor: ResourceColor[]
  action: () => void
}
