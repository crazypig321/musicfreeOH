import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import fs from '@ohos.file.fs';
import { JsonUtil } from '../common/JsonUtil';
import { FileUtils } from '../utils/FileUtils';
import { CoverColorUtils } from '../utils/CoverColorUtils';
import { CARD_BG_ALPHA_HEX, CARD_MAX_QUEUE_ITEMS, MusicCardData } from '../widget/MusicCardData';
import { Log } from '../utils/Log';

/** 持久化播放状态存储名 / 键（与主进程 KVStore PersistStatus 一致，跨进程只读） */
const PERSIST_STORE_NAME = 'App.PersistStatus';
const PERSIST_KEY_MUSIC_ITEM = 'music.musicItem';
const PERSIST_KEY_REPEAT_MODE = 'music.repeatMode';
const PERSIST_KEY_PLAY_LIST = 'music.playList';
/** 封面缓存索引文件（与主进程 ArtworkCache 落盘位置一致） */
const ARTWORK_DIR = '/artwork/';
const ARTWORK_INDEX_FILE = 'index.json';
/** 主色异步补推延迟（onAddForm 需同步返回，主色提取为异步操作） */
const COLOR_PUSH_DELAY_MS = 300;

/** 持久化状态解析结果：卡片数据 + 封面路径/fd（供主色提取与 fd 关闭） */
class PersistedCardState {
  data: MusicCardData = new MusicCardData();
  coverPath: string = '';
  coverFd: number = -1;
}

/**
 * 桌面音乐卡片生命周期
 * 卡片进程与主应用进程隔离：本类只负责回填「上次持久化」的初始状态；
 * 应用运行期间的实时状态由主进程 MusicWidgetManager 通过 formProvider.updateForm 推送
 */
export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = this.resolveFormId(want);
    const state = this.readPersistedCardData(formId);
    if (state.data.hasCover) {
      this.scheduleColorPush(formId);
    }
    return formBindingData.createFormBindingData(state.data);
  }

  onUpdateForm(formId: string): void {
    // 定时/定点刷新未启用，仅系统主动请求（如恢复可见）时回填持久化状态
    const state = this.readPersistedCardData(formId);
    formProvider.updateForm(formId, formBindingData.createFormBindingData(state.data)).then((): void => {
      this.closeCoverFd(state);
    }).catch((_e: Object): void => {
      this.closeCoverFd(state);
      Log.warn('桌面卡片 onUpdateForm 刷新失败: ' + formId);
    });
    if (state.data.hasCover) {
      this.scheduleColorPush(formId);
    }
  }

  onRemoveForm(_formId: string): void {
    // 卡片被删除：无需处理（应用侧通过 getPublishedRunningFormInfos 枚举现存卡片）
  }

  /** 从 want 中解析卡片 id */
  private resolveFormId(want: Want): string {
    if (want.parameters !== undefined) {
      const idVal: Object | undefined = want.parameters[formInfo.FormParam.IDENTITY_KEY];
      if (typeof idVal === 'string') {
        return idVal;
      }
    }
    return '';
  }

  /** 主色提取为异步，onAddForm/onUpdateForm 需尽快返回：延迟后补推带背景色的完整数据 */
  private scheduleColorPush(formId: string): void {
    setTimeout((): void => {
      this.pushWithDominantColor(formId).catch((_e: Object): void => {
        Log.warn('桌面卡片主色补推异常: ' + formId);
      });
    }, COLOR_PUSH_DELAY_MS);
  }

  /**
   * 提取封面主色后全量补推（必须携带完整数据含 formImages fd，否则 hasCover=false 会回退兜底图）。
   * 补推完成后不再重新调度，无循环。
   */
  private async pushWithDominantColor(formId: string): Promise<void> {
    const state = this.readPersistedCardData(formId);
    if (!state.data.hasCover || state.coverPath.length === 0) {
      this.closeCoverFd(state);
      return;
    }
    try {
      const color = await CoverColorUtils.extract(state.coverPath);
      if (color !== null) {
        state.data.bgColor = CoverColorUtils.toHexWithAlpha(color, CARD_BG_ALPHA_HEX);
        await formProvider.updateForm(formId, formBindingData.createFormBindingData(state.data));
      }
    } catch (e) {
      Log.warn('桌面卡片主色补推失败: ' + formId);
    } finally {
      this.closeCoverFd(state);
    }
  }

  private closeCoverFd(state: PersistedCardState): void {
    if (state.coverFd >= 0) {
      try {
        fs.closeSync(state.coverFd);
      } catch (e) {
        // 关闭失败忽略
      }
    }
  }

  /** 读取持久化的最近歌曲 + 封面缓存，构造卡片初始数据 */
  private readPersistedCardData(formId: string): PersistedCardState {
    const state = new PersistedCardState();
    state.data.formId = formId;

    let title = '';
    let artist = '';
    let artwork = '';
    let platform = '';
    let id = '';
    try {
      const pref = preferences.getPreferencesSync(this.context, { name: PERSIST_STORE_NAME });
      const v: preferences.ValueType = pref.getSync(PERSIST_KEY_MUSIC_ITEM, '');
      if (typeof v === 'string' && v.length > 0) {
        const rec = JsonUtil.parseRecord(v);
        if (rec !== null) {
          title = JsonUtil.recStr(rec, 'title');
          artist = JsonUtil.recStr(rec, 'artist');
          artwork = JsonUtil.recStr(rec, 'artwork');
          platform = JsonUtil.recStr(rec, 'platform');
          id = JsonUtil.recStr(rec, 'id');
        }
      }
      // 循环模式（持久化为 JSON 字符串 '"QUEUE"'）
      const modeRaw: preferences.ValueType = pref.getSync(PERSIST_KEY_REPEAT_MODE, '');
      const modeStr = typeof modeRaw === 'string' ? JsonUtil.parseString(modeRaw) : null;
      if (modeStr === 'SHUFFLE' || modeStr === 'SINGLE') {
        state.data.repeatMode = modeStr;
      }
      // 播放队列（与主进程 fillQueue 相同的窗口截取规则）
      const listRaw: preferences.ValueType = pref.getSync(PERSIST_KEY_PLAY_LIST, '');
      if (typeof listRaw === 'string' && listRaw.length > 0) {
        const listArr = JsonUtil.parseRecordArray(listRaw);
        if (listArr !== null && listArr.length > 0) {
          let currentIdx = -1;
          for (let i = 0; i < listArr.length; i++) {
            if (JsonUtil.recStr(listArr[i], 'platform') === platform && JsonUtil.recStr(listArr[i], 'id') === id) {
              currentIdx = i;
              break;
            }
          }
          const half = Math.floor(CARD_MAX_QUEUE_ITEMS / 2);
          let start = 0;
          if (currentIdx > half) {
            start = Math.min(currentIdx - half, Math.max(0, listArr.length - CARD_MAX_QUEUE_ITEMS));
          }
          const end = Math.min(listArr.length, start + CARD_MAX_QUEUE_ITEMS);
          const titles: Array<string> = [];
          const artists: Array<string> = [];
          for (let i = start; i < end; i++) {
            titles.push(JsonUtil.recStr(listArr[i], 'title'));
            artists.push(JsonUtil.recStr(listArr[i], 'artist'));
          }
          state.data.queueTitles = titles;
          state.data.queueArtists = artists;
          state.data.queueStart = start;
          state.data.queueIndex = currentIdx >= start && currentIdx < end ? currentIdx - start : -1;
        }
      }
    } catch (e) {
      // 持久化数据不可读时保持空白初始状态
    }
    state.data.title = title;
    state.data.artist = artist;

    const coverPath = this.resolveCachedCover(artwork);
    if (coverPath !== null) {
      try {
        const file = fs.openSync(coverPath, fs.OpenMode.READ_ONLY);
        state.coverFd = file.fd;
        state.coverPath = coverPath;
        state.data.formImages['cover'] = file.fd;
        state.data.hasCover = true;
      } catch (e) {
        state.data.hasCover = false;
      }
    }
    return state;
  }

  /** 仅读取主进程封面磁盘缓存（URL → 文件名索引），不做网络下载 */
  private resolveCachedCover(artwork: string): string | null {
    if (!artwork.startsWith('http://') && !artwork.startsWith('https://')) {
      return null;
    }
    const baseDir = this.context.cacheDir + ARTWORK_DIR;
    const raw = FileUtils.readFileText(baseDir + ARTWORK_INDEX_FILE);
    if (raw === null) {
      return null;
    }
    const rec = JsonUtil.parseRecord(raw);
    if (rec === null) {
      return null;
    }
    const fileName = rec[artwork];
    if (typeof fileName !== 'string' || fileName.length === 0) {
      return null;
    }
    const path = baseDir + fileName;
    return FileUtils.exists(path) ? path : null;
  }
}
