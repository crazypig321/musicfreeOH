import { componentUtils, display } from '@kit.ArkUI';
import { AnimatorResult } from '@ohos.animator';
import { ContextHolder } from '../common/ContextHolder';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { appConfig } from '../core/AppConfig';
import { appState } from '../entryability/AppState';
import { useSidebarLayout } from './BreakpointUtils';

/** 展开/收起时长与曲线（官方 miniplayeranimation 案例） */
const ANIM_DURATION = 500;
const ANIM_EASING = 'cubic-bezier(0.22, 0.17, 0.07, 1)';
/** 拖拽松手回弹 */
const REBOUND_DURATION = 250;
const REBOUND_EASING = 'ease-out';
/** 关键进度阈值：0~30% 迷你条淡出，5%~30% 播放页淡入 */
const PROGRESS_30 = 0.3;
const PROGRESS_5 = 0.05;
const INTERIM_OPACITY = 0.5;

/** 圆角矩形 Path 指令（ArkUI Path 支持与 SVG 相同的 M/H/V/A/Z 命令） */
function roundedRectPath(x: number, y: number, w: number, h: number, r: number): string {
  const rr = Math.max(0, Math.min(r, w / 2, h / 2));
  if (rr < 1) {
    return `M ${x} ${y} H ${x + w} V ${y + h} H ${x} Z`;
  }
  return `M ${x + rr} ${y} H ${x + w - rr} A ${rr} ${rr} 0 0 1 ${x + w} ${y + rr}` +
    ` V ${y + h - rr} A ${rr} ${rr} 0 0 1 ${x + w - rr} ${y + h}` +
    ` H ${x + rr} A ${rr} ${rr} 0 0 1 ${x} ${y + h - rr}` +
    ` V ${y + rr} A ${rr} ${rr} 0 0 1 ${x + rr} ${y} Z`;
}

/**
 * 一镜到底动画状态（PlayBar ↔ PlayerPage）：
 * 播放页作为 Index 根 Stack 顶层覆盖层常驻，animator 逐帧驱动以下字段
 */
@ObservedV2
export class PlayerExpandAnimState {
  /** 展开态（播放页可见） */
  @Trace isExpand: boolean = false;
  /** 展开/收起动画进行中 */
  @Trace isAnimating: boolean = false;
  /** 飞行封面（Index 顶层，迷你条封面 ↔ 播放页大封面之间插值） */
  @Trace coverX: number = 0;
  @Trace coverY: number = 0;
  @Trace coverSize: number = 44;
  @Trace coverRadius: number = 100;
  @Trace coverOpacity: number = 0;
  /** 播放页大封面隐藏（动画/拖拽期间由飞行封面代替，保留布局占位） */
  @Trace bigCoverHidden: boolean = false;
  /** 播放页覆盖层：平移/透明度（平移仅在收起静止时把覆盖层挪到屏幕外） */
  @Trace pageTranslateY: number = 0;
  @Trace pageOpacity: number = 0;
  @Trace topBarOpacity: number = 1;
  /** 裁剪窗口：以迷你条封面为锚点生长到全屏（页面坐标 vp，覆盖层挂 .clipShape(Path)） */
  @Trace clipX: number = 0;
  @Trace clipY: number = 0;
  @Trace clipW: number = 0;
  @Trace clipH: number = 0;
  @Trace clipR: number = 22;
  /** 迷你条：整体与封面透明度 */
  @Trace miniBarOpacity: number = 1;
  @Trace miniCoverOpacity: number = 1;
  /** 收起完成回调（播放页用于重置歌词态等） */
  onCollapsed: (() => void) | null = null;
  /** 收起静止时覆盖层的平移量（屏幕外，Index 启动时按屏高初始化） */
  collapsedOffset: number = 0;
  /** 几何测量结果（展开瞬间测量，窗口坐标 vp） */
  screenWidth: number = 0;
  screenHeight: number = 0;
  /** 拖拽行程基准：封面视觉位置到窗口顶部的距离 */
  miniDistanceToTop: number = 0;
  /** 迷你条封面视觉位置与尺寸（点击事件提供，飞行封面用） */
  miniCoverX: number = 0;
  miniCoverY: number = 0;
  miniCoverSize: number = 44;
  /** 迷你条矩形锚点（视觉位置 + 布局尺寸，点击事件提供，裁剪窗口起点） */
  anchorX: number = 0;
  anchorY: number = 0;
  anchorW: number = 0;
  anchorH: number = 52;
  bigCoverX: number = 0;
  bigCoverY: number = 0;
  bigCoverSize: number = 280;
  /** 封面飞行距离：miniCoverY - bigCoverY */
  coverTravel: number = 0;
  /** 迷你条实例 id 前缀（展开时记录，窗口尺寸变化后按 id 重测迷你条几何） */
  miniBarIdPrefix: string = '';
  /** 屏幕像素密度：clipShape 的 Path 坐标单位是 px（官方 FAQ 要求 vp2px 转换），状态字段保持 vp */
  density: number = 1;

  /** 覆盖层 .clipShape() 用的 Path 指令（vp → px 转换在此完成；方法内读取 @Trace 字段，V2 细粒度依赖追踪生效） */
  clipCommands(): string {
    return roundedRectPath(this.clipX * this.density, this.clipY * this.density,
      this.clipW * this.density, this.clipH * this.density, this.clipR * this.density);
  }
}

export const playerAnim: PlayerExpandAnimState = new PlayerExpandAnimState();

/**
 * 一镜到底控制器：animator 逐帧回调 apply(progress) 统一驱动展开/收起/拖拽回弹
 */
export class PlayerExpandAnimController {
  private static animatorObj: AnimatorResult | undefined = undefined;
  private static lastProgress: number = 0;
  private static playToken: number = 0;

  /** 从迷你条封面位置一镜到底展开播放页。
    * 锚点用点击事件的窗口坐标（真实视觉位置）：HdsTabs 对迷你条做过平移摆放，
    * getRectangleById 的 windowOffset 不含 translate，测到的是布局占位。
    * idPrefix：迷你条实例 id 前缀，供窗口尺寸变化后重测迷你条几何 */
  static expand(coverX: number, coverY: number, coverSize: number,
    barX: number, barY: number, barW: number, barH: number, idPrefix: string): void {
    if (playerAnim.isAnimating || playerAnim.isExpand) {
      return;
    }
    playerAnim.miniBarIdPrefix = idPrefix;
    playerAnim.miniCoverX = coverX;
    playerAnim.miniCoverY = coverY;
    playerAnim.miniCoverSize = coverSize;
    // 拖拽行程基准：封面视觉位置到屏幕顶部
    playerAnim.miniDistanceToTop = coverY;
    playerAnim.anchorX = barX;
    playerAnim.anchorY = barY;
    playerAnim.anchorW = barW;
    playerAnim.anchorH = barH;
    // 关闭动画：直达展开态（裁剪窗口放开到全屏，迷你条隐藏）
    if (!appConfig.getPlayerExpandAnim()) {
      PlayerExpandAnimController.expandDirect();
      return;
    }
    playerAnim.isAnimating = true;
    // 覆盖层平时平移在屏幕外：先跳回 translate=0（仍透明不可见），保证测量不受平移影响
    playerAnim.pageTranslateY = 0;
    PlayerExpandAnimController.measureAndPlay(0);
  }

  /** 测量成功后起展开动画（覆盖层常驻已布局完成，少量重试兜底） */
  private static measureAndPlay(attempt: number): void {
    setTimeout((): void => {
      if (!playerAnim.isAnimating || playerAnim.isExpand) {
        return;
      }
      if (!PlayerExpandAnimController.measure()) {
        if (attempt < 5) {
          PlayerExpandAnimController.measureAndPlay(attempt + 1);
        } else {
          PlayerExpandAnimController.resetCollapsed();
        }
        return;
      }
      playerAnim.bigCoverHidden = true;
      playerAnim.miniCoverOpacity = 0;
      playerAnim.coverOpacity = 1;
      PlayerExpandAnimController.apply(0);
      PlayerExpandAnimController.play(0, 1, ANIM_DURATION, ANIM_EASING, true, (value: number): void => {
        PlayerExpandAnimController.apply(value);
      }, (): void => {
        PlayerExpandAnimController.apply(1);
        playerAnim.isExpand = true;
        playerAnim.isAnimating = false;
        playerAnim.bigCoverHidden = false;
        playerAnim.coverOpacity = 0;
      });
    }, 30);
  }

  /** 同步屏幕/窗口尺寸：自由窗口模式下 display 是物理屏尺寸，必须优先用窗口尺寸（appState 随 windowSizeChange 更新） */
  private static syncScreenSize(): void {
    try {
      const d = display.getDefaultDisplaySync();
      playerAnim.density = d.densityPixels;
      if (appState.screenWidth > 0 && appState.screenHeight > 0) {
        playerAnim.screenWidth = appState.screenWidth;
        playerAnim.screenHeight = appState.screenHeight;
        return;
      }
      const ui = ContextHolder.getUiContext();
      playerAnim.screenWidth = ui.px2vp(d.width);
      playerAnim.screenHeight = ui.px2vp(d.height);
    } catch (error) {
      // 保留已有屏幕尺寸
    }
  }

  /** 关闭动画时的直达展开态（不经 animator，屏幕尺寸缺失时退回动画路径） */
  private static expandDirect(): void {
    PlayerExpandAnimController.syncScreenSize();
    if (playerAnim.screenWidth <= 0 || playerAnim.screenHeight <= 0) {
      playerAnim.isAnimating = true;
      playerAnim.pageTranslateY = 0;
      PlayerExpandAnimController.measureAndPlay(0);
      return;
    }
    playerAnim.pageTranslateY = 0;
    playerAnim.pageOpacity = 1;
    playerAnim.topBarOpacity = 1;
    playerAnim.miniBarOpacity = 0;
    playerAnim.bigCoverHidden = false;
    playerAnim.coverOpacity = 0;
    playerAnim.clipX = 0;
    playerAnim.clipY = 0;
    playerAnim.clipW = playerAnim.screenWidth;
    playerAnim.clipH = playerAnim.screenHeight;
    playerAnim.clipR = 0;
    playerAnim.isAnimating = false;
    playerAnim.isExpand = true;
  }

  /** 收起播放页，一镜到底退回迷你条 */
  static collapse(): void {
    if (playerAnim.isAnimating || !playerAnim.isExpand) {
      return;
    }
    // 关闭动画：直接复位收起态
    if (!appConfig.getPlayerExpandAnim()) {
      PlayerExpandAnimController.resetCollapsed();
      return;
    }
    playerAnim.bigCoverHidden = true;
    playerAnim.miniCoverOpacity = 0;
    playerAnim.coverOpacity = 1;
    PlayerExpandAnimController.play(0, 1, ANIM_DURATION, ANIM_EASING, false, (value: number): void => {
      PlayerExpandAnimController.apply(1 - value);
    }, (): void => {
      PlayerExpandAnimController.resetCollapsed();
    });
  }

  /** 展开态下拉跟手（offsetY：下拉距离，单位 vp） */
  static updateDrag(offsetY: number): void {
    if (playerAnim.isAnimating || !playerAnim.isExpand) {
      return;
    }
    // 窗口可能在上次展开后变化过：拖拽前重测几何，避免用过期坐标导致封面跳变
    PlayerExpandAnimController.refreshGeometry();
    const travel = playerAnim.miniDistanceToTop;
    if (travel <= 0) {
      return;
    }
    const clamped = Math.max(0, Math.min(offsetY, travel));
    playerAnim.bigCoverHidden = true;
    playerAnim.miniCoverOpacity = 0;
    playerAnim.coverOpacity = 1;
    PlayerExpandAnimController.apply(1 - clamped / travel);
  }

  /** 拖拽松手：进度过半回弹展开，不足半屏收起（锚点模式下页面不平移，按进度判定） */
  static endDrag(): void {
    if (playerAnim.isAnimating || !playerAnim.isExpand) {
      return;
    }
    const shouldExpand = PlayerExpandAnimController.lastProgress >= 0.5;
    const from = PlayerExpandAnimController.lastProgress;
    const to = shouldExpand ? 1 : 0;
    PlayerExpandAnimController.play(from, to, REBOUND_DURATION, REBOUND_EASING, shouldExpand,
      (value: number): void => {
        PlayerExpandAnimController.apply(value);
      }, (): void => {
        if (shouldExpand) {
          PlayerExpandAnimController.apply(1);
          playerAnim.isExpand = true;
          playerAnim.isAnimating = false;
          playerAnim.bigCoverHidden = false;
          playerAnim.coverOpacity = 0;
        } else {
          PlayerExpandAnimController.resetCollapsed();
        }
      });
  }

  /** progress：0 收起 → 1 展开，统一计算各节点姿态（公式参考官方案例） */
  private static apply(progress: number): void {
    const p = Math.max(0, Math.min(1, progress));
    PlayerExpandAnimController.lastProgress = p;
    // 飞行封面：位置/尺寸/圆角线性插值
    playerAnim.coverSize = playerAnim.miniCoverSize +
      (playerAnim.bigCoverSize - playerAnim.miniCoverSize) * p;
    playerAnim.coverRadius = 100 + (24 - 100) * p;
    playerAnim.coverX = playerAnim.miniCoverX + (playerAnim.bigCoverX - playerAnim.miniCoverX) * p;
    playerAnim.coverY = playerAnim.miniCoverY - playerAnim.coverTravel * p;
    // 裁剪窗口：以迷你条矩形为锚点（形状同迷你条、位置为视觉位置）生长到全屏
    playerAnim.clipX = playerAnim.anchorX * (1 - p);
    playerAnim.clipY = playerAnim.anchorY * (1 - p);
    playerAnim.clipW = playerAnim.anchorW + (playerAnim.screenWidth - playerAnim.anchorW) * p;
    playerAnim.clipH = playerAnim.anchorH + (playerAnim.screenHeight - playerAnim.anchorH) * p;
    playerAnim.clipR = playerAnim.anchorH / 2 * (1 - p);
    // 迷你条：前 30% 淡出
    playerAnim.miniBarOpacity = Math.max(0, 1 - p / PROGRESS_30);
    // 播放页：0~5% 淡至半透明，5~30% 淡至全透
    if (p <= PROGRESS_5) {
      playerAnim.pageOpacity = p / PROGRESS_5 * INTERIM_OPACITY;
    } else if (p < PROGRESS_30) {
      playerAnim.pageOpacity = INTERIM_OPACITY +
        (p - PROGRESS_5) / (PROGRESS_30 - PROGRESS_5) * (1 - INTERIM_OPACITY);
    } else {
      playerAnim.pageOpacity = 1;
    }
    // 顶部栏由裁剪窗口负责显隐，无需单独淡入淡出
    playerAnim.topBarOpacity = 1;
  }

  /** 测量播放页大封面与屏幕尺寸（迷你条锚点已由点击事件提供，无需再测迷你条） */
  private static measure(): boolean {
    try {
      const ui = ContextHolder.getUiContext();
      PlayerExpandAnimController.syncScreenSize();
      const big = componentUtils.getRectangleById('player_page_cover');
      playerAnim.bigCoverX = ui.px2vp(big.windowOffset.x);
      playerAnim.bigCoverY = ui.px2vp(big.windowOffset.y);
      playerAnim.bigCoverSize = ui.px2vp(big.size.width);
      playerAnim.coverTravel = playerAnim.miniCoverY - playerAnim.bigCoverY;
      hilog.info(0x0000, 'PlayerExpandAnim',
        `measure anchor=(${playerAnim.anchorX.toFixed(1)},${playerAnim.anchorY.toFixed(1)},` +
        `${playerAnim.anchorW.toFixed(1)},${playerAnim.anchorH.toFixed(1)}) ` +
        `cover=(${playerAnim.miniCoverX.toFixed(1)},${playerAnim.miniCoverY.toFixed(1)},` +
        `${playerAnim.miniCoverSize.toFixed(1)}) big=(${playerAnim.bigCoverX.toFixed(1)},` +
        `${playerAnim.bigCoverY.toFixed(1)},${playerAnim.bigCoverSize.toFixed(1)}) ` +
        `screen=${playerAnim.screenWidth.toFixed(1)}x${playerAnim.screenHeight.toFixed(1)}`);
      // 布局有效性校验：大封面应约 280、迷你封面 30~44，防止未布局完成时拿到全 0 矩形
      return playerAnim.coverTravel > 0 && playerAnim.miniDistanceToTop > 0 &&
        playerAnim.bigCoverSize > 100 && playerAnim.miniCoverSize >= 28 &&
        playerAnim.screenHeight > 0;
    } catch (error) {
      return false;
    }
  }

  /** 重测几何（窗口尺寸变化后调用）：播放页大封面始终重测；
    * 悬浮迷你条（侧边栏布局）无平移摆放，可按 id 重测视觉位置与锚点；
    * HdsTabs 模式 windowOffset 不含 translate，保持点击事件提供的视觉值 */
  private static refreshGeometry(): void {
    PlayerExpandAnimController.syncScreenSize();
    try {
      const ui = ContextHolder.getUiContext();
      const big = componentUtils.getRectangleById('player_page_cover');
      playerAnim.bigCoverX = ui.px2vp(big.windowOffset.x);
      playerAnim.bigCoverY = ui.px2vp(big.windowOffset.y);
      playerAnim.bigCoverSize = ui.px2vp(big.size.width);
      if (playerAnim.miniBarIdPrefix.length > 0 &&
        useSidebarLayout(appState.WidthBp, appState.screenWidth, appState.displayWidth)) {
        const cover = componentUtils.getRectangleById(playerAnim.miniBarIdPrefix + '_cover');
        const root = componentUtils.getRectangleById(playerAnim.miniBarIdPrefix + '_root');
        playerAnim.miniCoverX = ui.px2vp(cover.windowOffset.x);
        playerAnim.miniCoverY = ui.px2vp(cover.windowOffset.y);
        playerAnim.miniCoverSize = ui.px2vp(cover.size.width);
        playerAnim.miniDistanceToTop = playerAnim.miniCoverY;
        playerAnim.anchorX = ui.px2vp(root.windowOffset.x);
        playerAnim.anchorY = ui.px2vp(root.windowOffset.y);
        playerAnim.anchorW = ui.px2vp(root.size.width);
        playerAnim.anchorH = ui.px2vp(root.size.height);
      }
      playerAnim.coverTravel = playerAnim.miniCoverY - playerAnim.bigCoverY;
    } catch (error) {
      // 封面组件未挂载（如歌词模式）时保留旧值
    }
  }

  /** 展开静止态下窗口尺寸变化：重测几何并把裁剪窗口对齐新窗口，防止后续收起/拖拽用过期坐标 */
  static refreshIfExpanded(): void {
    if (!playerAnim.isExpand || playerAnim.isAnimating) {
      return;
    }
    PlayerExpandAnimController.refreshGeometry();
    playerAnim.clipX = 0;
    playerAnim.clipY = 0;
    playerAnim.clipW = playerAnim.screenWidth;
    playerAnim.clipH = playerAnim.screenHeight;
    playerAnim.clipR = 0;
  }

  /** towardExpand：动画目标方向（看门狗自愈用），不可从 begin/end 推断——收起时值域同样是 0→1 */
  private static play(begin: number, end: number, duration: number, easing: string,
    towardExpand: boolean, onFrame: (value: number) => void, onFinish: () => void): void {
    PlayerExpandAnimController.stop();
    playerAnim.isAnimating = true;
    // 必须用 UIContext.createAnimator：全局 Animator.create 未绑定 UI 实例，onFrame 不会触发
    let anim: AnimatorResult;
    try {
      anim = ContextHolder.getUiContext().createAnimator({
        duration: duration,
        easing: easing,
        fill: 'none',
        delay: 0,
        direction: 'normal',
        iterations: 1,
        begin: begin,
        end: end
      });
    } catch (error) {
      // 创建失败：回到收起静止态，避免卡死在动画中
      PlayerExpandAnimController.resetCollapsed();
      return;
    }
    const token = ++PlayerExpandAnimController.playToken;
    // token 防串扰：新动画开启后，旧动画迟到的帧/结束回调一律丢弃
    anim.onFrame = (value: number): void => {
      if (PlayerExpandAnimController.playToken !== token) {
        return;
      }
      onFrame(value);
    };
    anim.onFinish = (): void => {
      if (PlayerExpandAnimController.playToken !== token) {
        return;
      }
      onFinish();
    };
    PlayerExpandAnimController.animatorObj = anim;
    anim.play();
    // 看门狗：动画异常中断（onFinish 未按时触发）时按目标方向自愈，杜绝卡死在中间态
    setTimeout((): void => {
      if (PlayerExpandAnimController.playToken !== token || !playerAnim.isAnimating) {
        return;
      }
      // 自愈前先取消 animator，避免其迟到的 onFrame 覆盖归位结果
      PlayerExpandAnimController.stop();
      if (towardExpand) {
        PlayerExpandAnimController.apply(1);
        playerAnim.isExpand = true;
        playerAnim.isAnimating = false;
        playerAnim.bigCoverHidden = false;
        playerAnim.coverOpacity = 0;
      } else {
        PlayerExpandAnimController.resetCollapsed();
      }
    }, duration + 1000);
  }

  private static stop(): void {
    if (PlayerExpandAnimController.animatorObj !== undefined) {
      PlayerExpandAnimController.animatorObj.cancel();
      PlayerExpandAnimController.animatorObj = undefined;
    }
  }

  /** 收起静止态：覆盖层平移回屏幕外，迷你条完全恢复 */
  private static resetCollapsed(): void {
    playerAnim.isExpand = false;
    playerAnim.isAnimating = false;
    playerAnim.coverOpacity = 0;
    playerAnim.bigCoverHidden = false;
    playerAnim.miniCoverOpacity = 1;
    playerAnim.miniBarOpacity = 1;
    playerAnim.pageOpacity = 0;
    playerAnim.pageTranslateY = playerAnim.collapsedOffset;
    playerAnim.topBarOpacity = 1;
    // 裁剪窗口复位回迷你条矩形锚点
    playerAnim.clipX = playerAnim.anchorX;
    playerAnim.clipY = playerAnim.anchorY;
    playerAnim.clipW = playerAnim.anchorW;
    playerAnim.clipH = playerAnim.anchorH;
    playerAnim.clipR = playerAnim.anchorH / 2;
    if (playerAnim.onCollapsed !== null) {
      playerAnim.onCollapsed();
    }
  }
}
