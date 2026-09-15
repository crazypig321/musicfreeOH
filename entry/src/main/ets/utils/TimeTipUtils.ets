import date from '@xiaoye/date'

export function TimeTipUtils(): string {
const time = Number(date.format('H'))
if (time < 12 && time >= 6) {
return '早上好'
}else if (time >= 12 && time < 14) {
return '中午好'
}else if (time >= 14 && time < 18) {
return '下午好'
}else if (time >= 18 && time < 24) {
return '晚上好'
}else if (time >= 0 && time < 6) {
return '凌晨了，该休息了!'
}
return 'MusicFree'
}