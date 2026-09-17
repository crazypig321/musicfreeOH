import { trackPlayer } from '../core/TrackPlayer';
import { PlayState } from '../core/PlayerEngine';

/** 柱形常量：固定柱数，Row 用 SpaceBetween 自动铺满整排（间距随宽度自适应） */
const BAR_COUNT: number = 40;
const BAR_WIDTH: number = 5;

/** 静止时的高度（错落的固定样式） */
function staticHeightOf(index: number): number {
  return 10 + (index % 4) * 4;
}

/** 初始/静止高度数组 */
function makeStaticHeights(): Array<number> {
  const arr: Array<number> = [];
  for (let i = 0; i < BAR_COUNT; i++) {
    arr.push(staticHeightOf(i));
  }
  return arr;
}

/**
 * 播放中视觉组件：跳动的柱形 + 上升粒子，柱形占满整排。
 * 仅播放中跳动/发射粒子，暂停/停止时柱形静止、粒子隐藏。
 * 注意：柱形必须硬编码引用 this.heights[n]（参考 QueueSheet PlayingBars），
 * 不能用 ForEach——index 作 key 时数组替换不会触发 itemBuilder 重建。
 */
@ComponentV2
export struct PlayingVisual {
  /** 每根柱的高度 */
  @Local heights: Array<number> = makeStaticHeights();
  @Local isPlaying: boolean = false;
  /** 组件实际宽度（vp），用于粒子发射区域 */
  @Local viewWidth: number = 0;
  private timerId: number = -1;
  private offState: () => void = (): void => {
  };

  aboutToAppear(): void {
    this.isPlaying = trackPlayer.playState === PlayState.Playing;
    this.offState = trackPlayer.onPlayStateChanged((state: PlayState): void => {
      const playing: boolean = state === PlayState.Playing;
      if (playing) {
        this.startTimer();
      } else {
        this.stopTimer();
      }
      this.isPlaying = playing;
    });
    if (this.isPlaying) {
      this.startTimer();
    }
  }

  aboutToDisappear(): void {
    this.stopTimer();
    this.offState();
  }

  private startTimer(): void {
    if (this.timerId !== -1) {
      return;
    }
    this.timerId = setInterval((): void => {
      const next: Array<number> = [];
      for (let i = 0; i < BAR_COUNT; i++) {
        next.push(5 + Math.random() * 25);
      }
      this.getUIContext().animateTo({ duration: 380, curve: Curve.EaseInOut }, (): void => {
        this.heights = next;
      });
    }, 400);
  }

  private stopTimer(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    // 暂停/停止时恢复静止高度
    this.heights = makeStaticHeights();
  }

  /** 粒子效果：柱形上方持续升起、渐隐的圆点，发射区域与整排同宽 */
  private buildParticles(width: number): Particles<ParticleType.POINT,
    ParticleUpdater.NONE, ParticleUpdater.CURVE, ParticleUpdater.NONE,
    ParticleUpdater.NONE, ParticleUpdater.NONE, ParticleUpdater.NONE> {
    return {
      particles: [
        {
          emitter: {
            particle: {
              type: ParticleType.POINT,
              config: {
                radius: 2
              },
              count: -1,
              lifetime: 2200,
              lifetimeRange: 800
            },
            emitRate: 16,
            shape: ParticleEmitterShape.RECTANGLE,
            position: [0, 134],
            size: [width, 3]
          },
          color: {
            range: ['#ffffffff', '#ff9cc3ff']
          },
          opacity: {
            range: [0.9, 1.0],
            updater: {
              type: ParticleUpdater.CURVE,
              config: [
                { from: 1.0, to: 0.0, startMillis: 0, endMillis: 2200, curve: Curve.EaseOut }
              ]
            }
          },
          scale: {
            range: [0.5, 1.0]
          },
          velocity: {
            speed: [25, 55],
            angle: [250, 290]
          }
        }
      ]
    };
  }

  @Builder
  Bar(index: number) {
    Column()
      .width(BAR_WIDTH)
      .height(this.heights[index])
      .borderRadius(2.5)
      .backgroundColor($r('sys.color.icon'))
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.isPlaying && this.viewWidth > 0) {
        Particle(this.buildParticles(this.viewWidth))
          .width('100%')
          .height(140)
      }
    }
    .width('100%')
    .height(140)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const w = newArea.width;
      if (typeof w === 'number') {
        this.viewWidth = w;
      }
    })
  }
}
