let storageMusicCard = new LocalStorage();

/**
 * 2*2 桌面音乐卡片
 * 第一排：封面 + 收藏按钮；第二排：歌名；第三排：歌手；第四排：上一曲/播放暂停/下一曲
 * 控制按钮通过 postCardAction call 事件拉起 EntryAbility 后台执行，
 * 应用侧处理命令后通过 formProvider.updateForm 回推最新状态
 */
@Entry(storageMusicCard)
@Component
struct MusicCard {
  @LocalStorageProp('formId') formId: string = '';
  @LocalStorageProp('title') title: string = '';
  @LocalStorageProp('artist') artist: string = '';
  @LocalStorageProp('isPlaying') isPlaying: boolean = false;
  @LocalStorageProp('isFavorite') isFavorite: boolean = false;
  @LocalStorageProp('hasCover') hasCover: boolean = false;
  /** 当前封面的 memory key（封面变化时由应用侧更换，强制 Image 重载） */
  @LocalStorageProp('coverKey') coverKey: string = 'cover';
  /** 封面主色背景 '#AARRGGBB'（应用侧提取，空串表示透明） */
  @LocalStorageProp('bgColor') bgColor: string = '';

  private postCommand(command: string): void {
    postCardAction(this, {
      'action': 'call',
      'abilityName': 'EntryAbility',
      'params': {
        'formId': this.formId,
        'method': 'mediaControl',
        'command': command
      }
    });
  }

  /** 收藏图标颜色（卡片环境 SymbolGlyph fontColor 仅接受数组） */
  private favoriteColor(): ResourceColor {
    return this.isFavorite ? '#E84057' : $r('sys.color.font_tertiary');
  }

  /** 点击封面/文本区域打开应用 */
  private openApp(): void {
    postCardAction(this, {
      'action': 'router',
      'abilityName': 'EntryAbility'
    });
  }

  build() {
    Column() {
      Row() {
        if (this.hasCover) {
          Image('memory://' + this.coverKey).ImageStyle()
        } else {
          Image($r('app.media.altImage')).ImageStyle()
        }
        Blank()
        SymbolGlyph(this.isFavorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
          .fontSize(24)
          .fontColor([this.favoriteColor()])
          .padding(4)
          .onClick(() => {
            this.postCommand('favorite');
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .onClick(()=>{
        this.openApp()
      })

      Column({ space: 2 }){
        Text(this.title.length > 0 ? this.title : $r('app.string.playbar_no_music'))
          .TextUI(13, FontWeight.Medium, $r('sys.color.font'))

        Text(this.artist.length > 0 ? this.artist : ' ')
          .TextUI(11, FontWeight.Normal, $r('sys.color.font_tertiary'))
      }.width('100%').alignItems(HorizontalAlign.Start).margin({ top: 5, bottom: 5})
      .onClick(()=>{
        this.openApp()
      })

      Row({space: 16}) {
        ForEach([$r('sys.symbol.backward_end_fill'), $r('sys.symbol.play_circle_fill'), $r('sys.symbol.forward_end_fill')],
          (v: Resource, i: number)=>{
            SymbolGlyph(i === 1 ? (this.isPlaying ? $r('sys.symbol.pause_circle_fill') : $r('sys.symbol.play_circle_fill')) : v)
              .fontSize(i === 1 ? 38 : 28)
              .fontColor([$r('sys.color.font')])
              .onClick(() => {
                if (i === 0) {// 上一曲
                  this.postCommand('previous');
                }else if (i === 1) { // 播放暂停
                  this.postCommand('playPause');
                }else{
                  this.postCommand('next');
                }
              })
          })
      }
      .padding({ right: 10, left: 10 })
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor(this.bgColor.length > 0 ? this.bgColor : Color.Transparent)
  }
}

@Extend(Image)
function ImageStyle(){
  .width(56)
  .aspectRatio(1)
  .borderRadius(14)
  .objectFit(ImageFit.Cover)
}

@Extend(Text)
function TextUI(size: number | string | Resource, fontWeight: FontWeight, color: ResourceColor){
  .fontSize(size)
  .fontWeight(fontWeight)
  .fontColor(color)
  .maxLines(1)
  .textOverflow({ overflow: TextOverflow.Ellipsis })
}