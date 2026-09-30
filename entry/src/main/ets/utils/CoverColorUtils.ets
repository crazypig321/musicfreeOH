import image from '@ohos.multimedia.image';
import { FileUtils } from './FileUtils';
import { Log } from './Log';

/** 封面主色（RGB，0-255） */
export class DominantColor {
  r: number = 0;
  g: number = 0;
  b: number = 0;
}

/**
 * 封面主色提取工具
 * 流程：缩放解码（RGBA_8888）→ 像素按 16 级/通道分桶统计 → 取合格桶中占比最高者的均值
 * 合格桶：亮度适中且有一定饱和度（排除近黑/近白/纯灰）；全部不合格时回退全局占比最高桶
 * 结果按封面文件路径缓存，重复提取零开销
 */
export class CoverColorUtils {
  /** 缩放解码尺寸：主色统计无需原图分辨率 */
  private static readonly SAMPLE_SIZE = 48;
  /** 结果缓存上限（超出后整体清空重建） */
  private static readonly MAX_CACHE = 32;
  private static cache: Map<string, DominantColor> = new Map<string, DominantColor>();

  /** 提取封面主色（路径级缓存；文件不存在/解码失败返回 null） */
  static async extract(path: string): Promise<DominantColor | null> {
    if (path.length === 0 || !FileUtils.exists(path)) {
      return null;
    }
    const hit = CoverColorUtils.cache.get(path);
    if (hit !== undefined) {
      return hit;
    }
    const color = await CoverColorUtils.extractInternal(path);
    if (color !== null) {
      if (CoverColorUtils.cache.size >= CoverColorUtils.MAX_CACHE) {
        CoverColorUtils.cache.clear();
      }
      CoverColorUtils.cache.set(path, color);
    }
    return color;
  }

  /** 主色转 '#RRGGBB' */
  static toHex(color: DominantColor): string {
    return '#' + CoverColorUtils.hex2(color.r) + CoverColorUtils.hex2(color.g) + CoverColorUtils.hex2(color.b);
  }

  /** 主色转带透明度 '#AARRGGBB'（alphaHex 为两位十六进制，如 '40' 约 25%） */
  static toHexWithAlpha(color: DominantColor, alphaHex: string): string {
    return '#' + alphaHex + CoverColorUtils.hex2(color.r) + CoverColorUtils.hex2(color.g) + CoverColorUtils.hex2(color.b);
  }

  /** 解码并统计主色 */
  private static async extractInternal(path: string): Promise<DominantColor | null> {
    const source = image.createImageSource(path);
    try {
      const pixelMap = await source.createPixelMap({
        desiredSize: { width: CoverColorUtils.SAMPLE_SIZE, height: CoverColorUtils.SAMPLE_SIZE },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
      try {
        const info = await pixelMap.getImageInfo();
        const byteCount = info.size.width * info.size.height * 4;
        if (byteCount <= 0) {
          return null;
        }
        const buffer = new ArrayBuffer(byteCount);
        await pixelMap.readPixelsToBuffer(buffer);
        return CoverColorUtils.pickDominant(new Uint8Array(buffer));
      } finally {
        pixelMap.release().catch((_e: Object): void => {
        });
      }
    } catch (e) {
      Log.warn('封面主色提取失败: ' + path);
      return null;
    } finally {
      source.release().catch((_e: Object): void => {
      });
    }
  }

  /** 分桶统计像素，取主色桶均值 */
  private static pickDominant(pixels: Uint8Array): DominantColor | null {
    // 16 级/通道 → 4096 桶：每桶累计出现次数与 RGB 通道和
    const counts: Uint32Array = new Uint32Array(4096);
    const sumR: Uint32Array = new Uint32Array(4096);
    const sumG: Uint32Array = new Uint32Array(4096);
    const sumB: Uint32Array = new Uint32Array(4096);
    let total = 0;
    for (let i = 0; i + 3 < pixels.length; i += 4) {
      if (pixels[i + 3] < 128) {
        continue;
      }
      const r = pixels[i];
      const g = pixels[i + 1];
      const b = pixels[i + 2];
      const bucket = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
      counts[bucket] += 1;
      sumR[bucket] += r;
      sumG[bucket] += g;
      sumB[bucket] += b;
      total += 1;
    }
    if (total === 0) {
      return null;
    }
    let best = -1;
    let bestCount = 0;
    let fallback = -1;
    let fallbackCount = 0;
    for (let bucket = 0; bucket < 4096; bucket++) {
      const count = counts[bucket];
      if (count === 0) {
        continue;
      }
      if (count > fallbackCount) {
        fallbackCount = count;
        fallback = bucket;
      }
      const avgR = sumR[bucket] / count;
      const avgG = sumG[bucket] / count;
      const avgB = sumB[bucket] / count;
      if (CoverColorUtils.isEligible(avgR, avgG, avgB) && count > bestCount) {
        bestCount = count;
        best = bucket;
      }
    }
    const pick = best >= 0 ? best : fallback;
    if (pick < 0) {
      return null;
    }
    const pickedCount = counts[pick];
    const color = new DominantColor();
    color.r = Math.round(sumR[pick] / pickedCount);
    color.g = Math.round(sumG[pick] / pickedCount);
    color.b = Math.round(sumB[pick] / pickedCount);
    return color;
  }

  /** 候选主色判定：排除近黑/近白/低饱和灰色，避免背景过暗过亮或发灰 */
  private static isEligible(r: number, g: number, b: number): boolean {
    const maxC = Math.max(r, g, b);
    const minC = Math.min(r, g, b);
    const lum = 0.299 * r + 0.587 * g + 0.114 * b;
    const sat = maxC <= 0 ? 0 : (maxC - minC) / maxC;
    return lum >= 36 && lum <= 224 && sat >= 0.12;
  }

  /** 0-255 → 两位十六进制 */
  private static hex2(v: number): string {
    return ((v >> 4) & 0xf).toString(16) + (v & 0xf).toString(16);
  }
}
