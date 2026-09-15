import { KVStore } from '../infra/KVStore';
import { JsonUtil } from '../common/JsonUtil';
import { MusicItem, MusicItemSerializer, QualityKey, qualityFromStr } from '../common/model/MediaTypes';
import { MusicRepeatMode } from '../common/Consts';

/**
 * 持久化状态（移植自 persistStatus.ts）
 * 存储：播放器状态、语言、定时关闭等
 */
export class PersistStatusKeys {
  static readonly MUSIC_ITEM = 'music.musicItem';
  static readonly MUSIC_PROGRESS = 'music.progress';
  static readonly MUSIC_REPEAT_MODE = 'music.repeatMode';
  static readonly MUSIC_PLAY_LIST = 'music.playList';
  static readonly MUSIC_RATE = 'music.rate';
  static readonly MUSIC_QUALITY = 'music.quality';
  static readonly APP_LANGUAGE = 'app.language';
  static readonly APP_PLUGIN_UPDATE_TIME = 'app.pluginUpdateTime';
  static readonly APP_SCHEDULE_CLOSE_TIME = 'app.scheduleCloseTime';
  static readonly APP_SCHEDULE_CLOSE_TYPE = 'app.scheduleCloseType';
  static readonly LYRIC_SHOW_TRANSLATION = 'lyric.showTranslation';
  static readonly LYRIC_DETAIL_FONT_SIZE = 'lyric.detailFontSize';
}

export class PersistStatus {
  private static store(): KVStore {
    return KVStore.getOrCreate('App.PersistStatus');
  }

  // ---------- music ----------
  static getMusicItem(): MusicItem | null {
    const rec = JsonUtil.parseRecord(PersistStatus.store().get(PersistStatusKeys.MUSIC_ITEM));
    return rec === null ? null : MusicItem.fromRecord(rec);
  }

  static setMusicItem(item: MusicItem | null): void {
    if (item === null) {
      PersistStatus.store().delete(PersistStatusKeys.MUSIC_ITEM);
    } else {
      PersistStatus.store().set(PersistStatusKeys.MUSIC_ITEM, JsonUtil.safeStringify(item.toPersistRecord()));
    }
  }

  static getProgress(): number {
    return JsonUtil.parseNumber(PersistStatus.store().get(PersistStatusKeys.MUSIC_PROGRESS)) ?? 0;
  }

  static setProgress(progress: number): void {
    PersistStatus.store().set(PersistStatusKeys.MUSIC_PROGRESS, '' + progress);
  }

  static getRepeatMode(): MusicRepeatMode {
    const raw = JsonUtil.parseString(PersistStatus.store().get(PersistStatusKeys.MUSIC_REPEAT_MODE));
    if (raw === MusicRepeatMode.SHUFFLE || raw === MusicRepeatMode.QUEUE || raw === MusicRepeatMode.SINGLE) {
      return raw;
    }
    return MusicRepeatMode.QUEUE;
  }

  static setRepeatMode(mode: MusicRepeatMode): void {
    PersistStatus.store().set(PersistStatusKeys.MUSIC_REPEAT_MODE, '"' + mode + '"');
  }

  static getPlayList(): Array<MusicItem> {
    return MusicItemSerializer.deserialize(PersistStatus.store().get(PersistStatusKeys.MUSIC_PLAY_LIST));
  }

  static setPlayList(items: Array<MusicItem>): void {
    PersistStatus.store().set(PersistStatusKeys.MUSIC_PLAY_LIST, MusicItemSerializer.serialize(items));
  }

  static getRate(): number {
    return JsonUtil.parseNumber(PersistStatus.store().get(PersistStatusKeys.MUSIC_RATE)) ?? 1;
  }

  static setRate(rate: number): void {
    PersistStatus.store().set(PersistStatusKeys.MUSIC_RATE, '' + rate);
  }

  static getQuality(): QualityKey {
    return qualityFromStr(JsonUtil.parseString(PersistStatus.store().get(PersistStatusKeys.MUSIC_QUALITY)) ?? 'high');
  }

  static setQuality(quality: QualityKey): void {
    PersistStatus.store().set(PersistStatusKeys.MUSIC_QUALITY, '"' + quality + '"');
  }

  // ---------- app ----------
  static getLanguage(): string {
    return JsonUtil.parseString(PersistStatus.store().get(PersistStatusKeys.APP_LANGUAGE)) ?? '';
  }

  static setLanguage(lang: string): void {
    PersistStatus.store().set(PersistStatusKeys.APP_LANGUAGE, '"' + lang + '"');
  }

  static getPluginUpdateTime(): number {
    return JsonUtil.parseNumber(PersistStatus.store().get(PersistStatusKeys.APP_PLUGIN_UPDATE_TIME)) ?? 0;
  }

  static setPluginUpdateTime(t: number): void {
    PersistStatus.store().set(PersistStatusKeys.APP_PLUGIN_UPDATE_TIME, '' + t);
  }

  static getScheduleCloseTime(): number {
    return JsonUtil.parseNumber(PersistStatus.store().get(PersistStatusKeys.APP_SCHEDULE_CLOSE_TIME)) ?? 0;
  }

  static setScheduleCloseTime(t: number): void {
    PersistStatus.store().set(PersistStatusKeys.APP_SCHEDULE_CLOSE_TIME, '' + t);
  }

  // ---------- lyric ----------
  static getLyricShowTranslation(): boolean {
    return JsonUtil.parseBoolean(PersistStatus.store().get(PersistStatusKeys.LYRIC_SHOW_TRANSLATION)) ?? true;
  }

  static setLyricShowTranslation(v: boolean): void {
    PersistStatus.store().set(PersistStatusKeys.LYRIC_SHOW_TRANSLATION, v ? 'true' : 'false');
  }
}
