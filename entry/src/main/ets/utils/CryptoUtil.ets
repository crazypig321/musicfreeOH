import cryptoFramework from '@ohos.security.cryptoFramework';
import util from '@ohos.util';

/**
 * 哈希工具（替代 crypto-js 的 MD5/SHA-256 应用侧需求）
 * 插件内部的哈希需求由 WebView 中的 crypto-js 完成
 */
export class CryptoUtil {
  /** sha256 hex */
  static async sha256(text: string): Promise<string> {
    try {
      const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
      md.update({ data: CryptoUtil.strToU8(text) });
      const digest = await md.digest();
      return CryptoUtil.u8ToHex(digest.data);
    } catch (e) {
      return CryptoUtil.fallbackHash(text);
    }
  }

  /** md5 hex */
  static async md5(text: string): Promise<string> {
    try {
      const md: cryptoFramework.Md = cryptoFramework.createMd('MD5');
      md.update({ data: CryptoUtil.strToU8(text) });
      const digest = await md.digest();
      return CryptoUtil.u8ToHex(digest.data);
    } catch (e) {
      return CryptoUtil.fallbackHash(text);
    }
  }

  /** md5 hex（字节输入，供封面缓存等内容寻址使用） */
  static async md5Bytes(data: Uint8Array): Promise<string> {
    try {
      const md: cryptoFramework.Md = cryptoFramework.createMd('MD5');
      md.update({ data: data });
      const digest = await md.digest();
      return CryptoUtil.u8ToHex(digest.data);
    } catch (e) {
      return CryptoUtil.fallbackHashBytes(data);
    }
  }

  /** 失败时退化为简单hash，保证有唯一性 */
  private static fallbackHash(text: string): string {
    let h = 5381;
    for (let i = 0; i < text.length; ++i) {
      h = ((h << 5) + h + text.charCodeAt(i)) & 0x7fffffff;
    }
    return 'fallback' + h.toString(16) + text.length.toString(16);
  }

  /** 字节版退化hash */
  private static fallbackHashBytes(data: Uint8Array): string {
    let h = 5381;
    for (let i = 0; i < data.length; ++i) {
      h = ((h << 5) + h + data[i]) & 0x7fffffff;
    }
    return 'fallback' + h.toString(16) + data.length.toString(16);
  }

  private static strToU8(text: string): Uint8Array {
    const encoder = new util.TextEncoder();
    return encoder.encodeInto(text);
  }

  private static u8ToHex(data: Uint8Array): string {
    let hex = '';
    for (let i = 0; i < data.length; ++i) {
      let h = data[i].toString(16);
      if (h.length < 2) {
        h = '0' + h;
      }
      hex += h;
    }
    return hex;
  }

  /** 随机唯一 id（替代 nanoid） */
  static nanoid(): string {
    return util.generateRandomUUID(true);
  }
}
