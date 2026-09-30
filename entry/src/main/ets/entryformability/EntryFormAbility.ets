import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import fs from '@ohos.file.fs';
import { JsonUtil } from '../common/JsonUtil';
import { FileUtils } from '../utils/FileUtils';
import { MusicCardData } from '../widget/MusicCardData';
import { Log } from '../utils/Log';

/** 持久化播放状态存储名 / 键（与主进程 KVStore PersistStatus 一致，跨进程只读） */
const PERSIST_STORE_NAME = 'App.PersistStatus';
const PERSIST_KEY_MUSIC_ITEM = 'music.musicItem';
/** 封面缓存索引文件（与主进程 ArtworkCache 落盘位置一致） */
const ARTWORK_DIR = '/artwork/';
const ARTWORK_INDEX_FILE = 'index.json';

/**
 * 桌面音乐卡片生命周期
 * 卡片进程与主应用进程隔离：本类只负责回填「上次持久化」的初始状态；
 * 应用运行期间的实时状态由主进程 MusicWidgetManager 通过 formProvider.updateForm 推送
 */
export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const data = this.readPersistedCardData(want);
    return formBindingData.createFormBindingData(data);
  }

  onUpdateForm(formId: string): void {
    // 定时/定点刷新未启用，仅系统主动请求（如恢复可见）时回填持久化状态
    const data = this.readPersistedCardData(undefined);
    formProvider.updateForm(formId, formBindingData.createFormBindingData(data)).catch((_e: Object): void => {
      Log.warn('桌面卡片 onUpdateForm 刷新失败: ' + formId);
    });
  }

  onRemoveForm(_formId: string): void {
    // 卡片被删除：无需处理（应用侧通过 getPublishedRunningFormInfos 枚举现存卡片）
  }

  /** 读取持久化的最近歌曲 + 封面缓存，构造卡片初始数据 */
  private readPersistedCardData(want: Want | undefined): MusicCardData {
    const data = new MusicCardData();
    if (want !== undefined && want.parameters !== undefined) {
      const idVal: Object | undefined = want.parameters[formInfo.FormParam.IDENTITY_KEY];
      if (typeof idVal === 'string') {
        data.formId = idVal;
      }
    }

    let title = '';
    let artist = '';
    let artwork = '';
    try {
      const pref = preferences.getPreferencesSync(this.context, { name: PERSIST_STORE_NAME });
      const v: preferences.ValueType = pref.getSync(PERSIST_KEY_MUSIC_ITEM, '');
      if (typeof v === 'string' && v.length > 0) {
        const rec = JsonUtil.parseRecord(v);
        if (rec !== null) {
          title = JsonUtil.recStr(rec, 'title');
          artist = JsonUtil.recStr(rec, 'artist');
          artwork = JsonUtil.recStr(rec, 'artwork');
        }
      }
    } catch (e) {
      // 持久化数据不可读时保持空白初始状态
    }
    data.title = title;
    data.artist = artist;

    const coverPath = this.resolveCachedCover(artwork);
    if (coverPath !== null) {
      try {
        const file = fs.openSync(coverPath, fs.OpenMode.READ_ONLY);
        data.formImages['cover'] = file.fd;
        data.hasCover = true;
      } catch (e) {
        data.hasCover = false;
      }
    }
    return data;
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
