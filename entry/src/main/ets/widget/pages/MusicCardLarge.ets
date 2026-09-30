let storageMusicCardLarge = new LocalStorage();

/**
 * 4*4 桌面音乐卡片
 * 第一排：封面 + 歌名 + 当前歌词；第二排：循环模式/上一曲/播放暂停/下一曲/收藏；
 * 第三排（占剩余 2 排高度）：播放队列（样式对齐应用内 QueueSheet：序号 + 标题 + 歌手，当前曲高亮，可滚动，点击切歌）
 * 控制按钮通过 postCardAction call 事件拉起 EntryAbility 后台执行，
 * 应用侧处理命令后通过 formProvider.updateForm 回推最新状态
 */
@Entry(storageMusicCardLarge)
@Component
struct MusicCardLarge {
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
  /** 当前歌词行 */
  @LocalStorageProp('lyric') lyric: string = '';
  /** 下一句歌词 */
  @LocalStorageProp('lyricNext') lyricNext: string = '';
  /** 循环模式：'QUEUE' | 'SHUFFLE' | 'SINGLE' */
  @LocalStorageProp('repeatMode') repeatMode: string = 'QUEUE';
  /** 播放队列（窗口）标题/歌手 */
  @LocalStorageProp('queueTitles') queueTitles: Array<string> = [];
  @LocalStorageProp('queueArtists') queueArtists: Array<string> = [];
  /** 队列窗口起始下标（playIndex 命令需加回为完整队列下标） */
  @LocalStorageProp('queueStart') queueStart: number = 0;
  /** 当前曲在队列窗口中的下标 */
  @LocalStorageProp('queueIndex') queueIndex: number = -1;

  private postCommand(command: string, index: number): void {
    postCardAction(this, {
      'action': 'call',
      'abilityName': 'EntryAbility',
      'params': {
        'formId': this.formId,
        'method': 'mediaControl',
        'command': command,
        'index': index
      }
    });
  }

  /** 点击封面/文本区域打开应用 */
  private openApp(): void {
    postCardAction(this, {
      'action': 'router',
      'abilityName': 'EntryAbility'
    });
  }

  /** 收藏图标颜色（卡片环境 SymbolGlyph fontColor 仅接受数组） */
  private favoriteColor(): ResourceColor {
    return this.isFavorite ? '#E84057' : $r('sys.color.font');
  }

  /** 循环模式图标：随机 / 单曲循环 / 列表循环（与应用内播放队列一致） */
  private repeatIcon(): Resource {
    if (this.repeatMode === 'SHUFFLE') {
      return $r('sys.symbol.shuffle');
    }
    if (this.repeatMode === 'SINGLE') {
      return $r('sys.symbol.repeat_1');
    }
    return $r('sys.symbol.repeat');
  }

  /** 歌词文案（无歌曲时空白占位，有歌无词显示暂无歌词） */
  private lyricText(): string {
    if (this.title.length === 0) {
      return ' ';
    }
    return this.lyric.length > 0 ? this.lyric : '暂无歌词';
  }

  /** 下一句歌词文案（无歌曲/无歌词时空白占位，保持两行高度稳定） */
  private nextLyricText(): string {
    if (this.title.length === 0 || this.lyric.length === 0) {
      return ' ';
    }
    return this.lyricNext.length > 0 ? this.lyricNext : ' ';
  }

  /** 队列条目文字颜色（当前曲高亮） */
  private queueRowColor(index: number): ResourceColor {
    return index === this.queueIndex ? $r('sys.color.icon_emphasize') : $r('sys.color.font');
  }

  build() {
    Column() {
      // 第一排：封面 + 歌名 + 歌词
      Row({ space: 10 }) {
        if (this.hasCover) {
          Image('memory://' + this.coverKey).ImageUI()
        } else {
          Image($r('app.media.altImage')).ImageUI()
        }
        Column({ space: 4 }) {
          Text(this.title.length > 0 ? this.title : $r('app.string.playbar_no_music'))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          // 两行歌词：当前句 + 下一句
          Text(this.lyricText())
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .animation({ duration: 200, curve: Curve.EaseInOut })
          Text(this.nextLyricText())
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .onClick(() => {
        this.openApp();
      })

      // 第二排：循环模式 + 上一曲 + 播放/暂停 + 下一曲 + 收藏
      Row() {
        SymbolGlyph(this.repeatIcon())
          .fontSize(22)
          .fontColor([$r('sys.color.font')])
          .onClick(() => {
            this.postCommand('repeat', -1);
          })
        SymbolGlyph($r('sys.symbol.backward_end_fill'))
          .fontSize(26)
          .fontColor([$r('sys.color.font')])
          .onClick(() => {
            this.postCommand('previous', -1);
          })
        SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_circle_fill') : $r('sys.symbol.play_circle_fill'))
          .fontSize(38)
          .fontColor([$r('sys.color.font')])
          .onClick(() => {
            this.postCommand('playPause', -1);
          })
        SymbolGlyph($r('sys.symbol.forward_end_fill'))
          .fontSize(26)
          .fontColor([$r('sys.color.font')])
          .onClick(() => {
            this.postCommand('next', -1);
          })
        SymbolGlyph(this.isFavorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
          .fontSize(22)
          .fontColor([this.favoriteColor()])
          .onClick(() => {
            this.postCommand('favorite', -1);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .padding({ left: 8, right: 8 })
      .margin({ top: 10, bottom: 6 })

      Divider().margin({ top: 10, bottom: 6 })

      // 第三排：播放队列（占剩余 2 排高度，列表限高可滚动）
      if (this.queueTitles.length === 0) {
        Column() {
          Text('播放队列为空')
            .fontSize(13)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
          ForEach(this.queueTitles, (item: string, index: number) => {
            ListItem() {
              Row({ space: 8 }) {
                Text((this.queueStart + index + 1).toString())
                  .fontSize(11)
                  .fontColor(this.queueRowColor(index))
                  .textAlign(TextAlign.End)
                Text(item)
                  .fontSize(13)
                  .fontWeight(index === this.queueIndex ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(this.queueRowColor(index))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(this.queueArtists.length > index ? this.queueArtists[index] : '')
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: 96 })
              }
              .width('100%')
              .height(34)
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.postCommand('playIndex', this.queueStart + index);
              })
            }
          }, (item: string, index: number) => (this.queueStart + index).toString() + '_' + item)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor(this.bgColor.length > 0 ? this.bgColor : Color.Transparent)
  }
}

@Extend(Image)
function ImageUI(){
  .width(64)
  .aspectRatio(1)
  .borderRadius(14)
  .objectFit(ImageFit.Cover)
}