import { harmonyShare, systemShare } from '@kit.ShareKit';
import { fileUri } from '@kit.CoreFileKit';
import { PathConst } from '../common/PathConst';
import { FileUtils } from '../utils/FileUtils';
import { Log } from '../utils/Log';
import { ExternalOpen } from '../core/ExternalOpen';
import { SONG_UTD, SHEETS_UTD, PLUGIN_UTD, SUB_UTD } from '../utils/ShareUtils';

/**
 * 华为分享跨设备沙箱接收（碰一碰/轻贴直达，API 23+ 支持 Tablet 接收端）
 * 手机轻贴平板屏幕触发 dataReceive，文件直接传输进应用沙箱暂存目录，
 * 完成后按扩展名走 ExternalOpen 统一分发（.js 插件 / .json 订阅或备份 / 音频导入播放）。
 * 注册能力与发送端类型对应：音频 / 插件 js / 订阅 json。
 * 常规「华为分享」面板传输不走此通道（系统固定存入文件管理"华为分享"目录，
 * 需用户在文件管理中点开文件经 FileOpen 关联导入）。
 */
export class HarmonyShareRecv {
  /** 沙箱接收暂存目录（相对 dataPath，处理完成后清理） */
  private static readonly RECV_REL: string = 'harmonyshare_recv/';
  private static registry: harmonyShare.RecvCapabilityRegistry | null = null;

  /** 主窗口创建后注册（windowId 为主窗口 id）；设备/系统不支持时静默失败 */
  static register(windowId: number): void {
    if (HarmonyShareRecv.registry !== null) {
      return;
    }
    try {
      const capabilities: Array<harmonyShare.RecvCapability> = [
        { utd: 'general.audio', maxSupportedCount: 10 },
        { utd: 'general.mp3', maxSupportedCount: 10 },
        { utd: 'general.flac', maxSupportedCount: 10 },
        { utd: 'general.wav', maxSupportedCount: 10 },
        { utd: 'general.ogg', maxSupportedCount: 10 },
        { utd: 'general.text', maxSupportedCount: 10 },
        { utd: 'general.plain-text', maxSupportedCount: 10 },
        { utd: 'general.java-script', maxSupportedCount: 10 },
        { utd: 'general.json', maxSupportedCount: 10 },
        { utd: SONG_UTD, maxSupportedCount: 10 },
        { utd: SHEETS_UTD, maxSupportedCount: 10 },
        { utd: PLUGIN_UTD, maxSupportedCount: 10 },
        { utd: SUB_UTD, maxSupportedCount: 10 }
      ];
      const registry: harmonyShare.RecvCapabilityRegistry = {
        windowId: windowId,
        capabilities: capabilities
      };
      harmonyShare.on('dataReceive', registry, (target: harmonyShare.ReceivableTarget): void => {
        HarmonyShareRecv.onTarget(target);
      });
      HarmonyShareRecv.registry = registry;
      Log.info('华为分享沙箱接收已注册 windowId=' + windowId);
    } catch (e) {
      const detail = e instanceof Error ? e.message : '';
      Log.error('华为分享沙箱接收注册失败: ' + detail);
    }
  }

  /** 主窗口销毁后注销 */
  static unregister(): void {
    const registry = HarmonyShareRecv.registry;
    if (registry === null) {
      return;
    }
    try {
      harmonyShare.off('dataReceive', registry);
    } catch (e) {
      const detail = e instanceof Error ? e.message : '';
      Log.error('华为分享沙箱接收注销失败: ' + detail);
    }
    HarmonyShareRecv.registry = null;
  }

  /** 收到传输请求：指定沙箱暂存目录接收文件 */
  private static onTarget(target: harmonyShare.ReceivableTarget): void {
    try {
      const dir: string = PathConst.dataPath + HarmonyShareRecv.RECV_REL;
      FileUtils.checkAndCreateDir(dir);
      const callback: harmonyShare.ReceiveCallback = {
        onDataReceived: (data: systemShare.SharedData): void => {
          HarmonyShareRecv.onData(data);
        },
        onResult: (code: harmonyShare.ShareResultCode): void => {
          if (code === harmonyShare.ShareResultCode.SHARE_SUCCESS) {
            Log.info('华为分享沙箱接收完成');
          } else {
            Log.error('华为分享沙箱接收失败 code=' + code);
          }
        }
      };
      target.receive(fileUri.getUriFromPath(dir), callback).catch((_e: Object): void => {
        Log.error('华为分享沙箱接收启动失败');
      });
    } catch (e) {
      const detail = e instanceof Error ? e.message : '';
      Log.error('华为分享沙箱接收异常: ' + detail);
      target.reject(harmonyShare.ReceivableErrorCode.NO_RECEIVABLE_ERROR).catch((_e: Object): void => {
      });
    }
  }

  /** 传输完成：逐个文件按扩展名分发导入，处理后清理暂存文件 */
  private static onData(data: systemShare.SharedData): void {
    const records: Array<systemShare.SharedRecord> = data.getRecords();
    const run = async (): Promise<void> => {
      for (const record of records) {
        const uri = record.uri;
        if (typeof uri !== 'string' || uri.length === 0) {
          continue;
        }
        const path = FileUtils.normalizePath(uri);
        try {
          await ExternalOpen.deliverFile(uri);
        } finally {
          if (path.length > 0) {
            FileUtils.unlink(path);
          }
        }
      }
    };
    run().catch((_e: Object): void => {
      Log.error('华为分享接收数据处理失败');
    });
  }
}
