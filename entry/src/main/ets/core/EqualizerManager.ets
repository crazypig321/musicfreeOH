import { appConfig } from './AppConfig';
import { JsonUtil, JsonRecord } from '../utils/JsonUtil';

/** 均衡器预设定义 */
export class EqPresetDef {
  readonly key: string;
  readonly label: string;
  readonly gains: Array<number>;

  constructor(key: string, label: string, gains: Array<number>) {
    this.key = key;
    this.label = label;
    this.gains = gains;
  }
}

/** 用户保存的均衡器预设 */
export class EqUserPreset {
  readonly name: string;
  readonly gains: Array<number>;
  constructor(name: string, gains: Array<number>) {
    this.name = name;
    this.gains = gains;
  }
}

/** 10 段频段标签（对应 31Hz ~ 16kHz） */
export const EQ_BAND_LABELS: Array<string> = ['31', '62', '125', '250', '500', '1K', '2K', '4K', '8K', '16K'];

/** 增益范围（dB） */
export const EQ_GAIN_MIN: number = -12;
export const EQ_GAIN_MAX: number = 12;

/**
 * 均衡器中心（@ospark/free-pcm 10 段均衡器）
 * 负责：开关/预设/增益的持久化与变更通知；
 * 增益实时下发给 PlayerEngine 的 PCM 解码器，开关切换由 PlayerEngine 换引擎承接
 */
export class EqualizerManager {
  private static instance: EqualizerManager | null = null;
  /** 内置预设（增益值与库内 EqPreset 一致） */
  static readonly PRESETS: Array<EqPresetDef> = [
    new EqPresetDef('default', '默认', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    new EqPresetDef('pop', '流行', [5, 2, 1, -1, -5, -5, -2, 1, 2, 4]),
    new EqPresetDef('rock', '摇滚', [6, 4, 4, 2, 0, 1, 3, 3, 5, 4]),
    new EqPresetDef('chinese', '华语流行', [0, 0, 2, 0, 0, 4, 4, 2, 2, 5]),
    new EqPresetDef('ballads', '民谣', [3, 5, 2, -4, 1, 2, -3, 1, 4, 5]),
    new EqPresetDef('classical', '古典', [2, 3, 2, 1, 0, 0, -5, -5, -5, -6]),
    new EqPresetDef('dance', '舞曲', [4, 3, 2, -3, 0, 0, 5, 4, 2, 0]),
    new EqPresetDef('jazz', '爵士', [2, 0, 2, 3, 6, 5, -1, 3, 4, 4]),
    new EqPresetDef('rnb', 'R&B', [1, 4, 5, 3, -2, -2, 2, 3, 5, 5])
  ];
  static readonly PRESET_CUSTOM: string = 'custom';

  private enabledInternal: boolean = false;
  private gainsInternal: Array<number> = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  private presetKeyInternal: string = 'default';
  private enabledListeners: Array<(enabled: boolean) => void> = [];
  private gainsListeners: Array<(gains: Array<number>) => void> = [];

  static getInstance(): EqualizerManager {
    if (EqualizerManager.instance === null) {
      EqualizerManager.instance = new EqualizerManager();
    }
    return EqualizerManager.instance;
  }

  private constructor() {
    this.enabledInternal = appConfig.getEqEnabled();
    this.gainsInternal = appConfig.getEqGains();
    this.presetKeyInternal = appConfig.getEqPreset();
  }

  get enabled(): boolean {
    return this.enabledInternal;
  }

  get presetKey(): string {
    return this.presetKeyInternal;
  }

  /** 当前预设展示名（自定义时返回「自定义」） */
  get presetLabel(): string {
    if (this.presetKeyInternal === EqualizerManager.PRESET_CUSTOM) {
      return '自定义';
    }
    const preset = EqualizerManager.findPreset(this.presetKeyInternal);
    return preset !== null ? preset.label : '自定义';
  }

  /** 当前增益副本 */
  getGains(): Array<number> {
    const copy: Array<number> = [];
    for (const g of this.gainsInternal) {
      copy.push(g);
    }
    return copy;
  }

  /** 是否为平直增益（全 0） */
  isFlat(): boolean {
    for (const g of this.gainsInternal) {
      if (g !== 0) {
        return false;
      }
    }
    return true;
  }

  /** 是否应使用 free-pcm PCM 播放管线（EQ 生效的前提） */
  shouldUsePcmEngine(): boolean {
    return this.enabledInternal;
  }

  /** 开关 EQ：持久化并通知引擎切换 */
  setEnabled(enabled: boolean): void {
    if (this.enabledInternal === enabled) {
      return;
    }
    this.enabledInternal = enabled;
    appConfig.setEqEnabled(enabled);
    for (const cb of this.enabledListeners) {
      cb(enabled);
    }
  }

  /** 应用预设 */
  applyPreset(key: string): void {
    const preset = EqualizerManager.findPreset(key);
    if (preset === null) {
      return;
    }
    this.presetKeyInternal = key;
    appConfig.setEqPreset(key);
    this.updateGains(preset.gains);
  }

  /** 设置单段增益（自动转为自定义） */
  setBandGain(index: number, gainDb: number): void {
    if (index < 0 || index >= this.gainsInternal.length) {
      return;
    }
    this.previewBandGain(index, gainDb);
    this.commitGains();
  }

  /** 拖动中的实时预览：即时下发解码器但不落盘（高频调用） */
  previewBandGain(index: number, gainDb: number): void {
    if (index < 0 || index >= this.gainsInternal.length) {
      return;
    }
    const clamped = Math.max(EQ_GAIN_MIN, Math.min(EQ_GAIN_MAX, gainDb));
    const next = this.getGains();
    next[index] = clamped;
    this.gainsInternal = next;
    for (const cb of this.gainsListeners) {
      cb(next);
    }
  }

  /** 提交当前增益：更新预设名并落盘（拖动结束时调用） */
  commitGains(): void {
    this.presetKeyInternal = this.matchPresetKey(this.gainsInternal);
    appConfig.setEqPreset(this.presetKeyInternal);
    appConfig.setEqGains(this.gainsInternal);
  }

  /** 重置为默认（全 0） */
  resetToDefault(): void {
    this.applyPreset('default');
  }

  /** 读取用户保存的预设列表 */
  getUserPresets(): Array<EqUserPreset> {
    const raw = appConfig.getEqUserPresets();
    const arr = JsonUtil.parseRecordArray(raw);
    if (arr === null) {
      return [];
    }
    const out: Array<EqUserPreset> = [];
    for (const rec of arr) {
      const name = JsonUtil.recStr(rec, 'name');
      if (name.length === 0) {
        continue;
      }
      const gainsRaw = JsonUtil.recArray(rec, 'gains');
      if (gainsRaw === null) {
        continue;
      }
      const gains: Array<number> = [];
      for (const g of gainsRaw) {
        if (typeof g === 'number') {
          gains.push(g);
        } else {
          gains.push(0);
        }
      }
      if (gains.length !== 10) {
        continue;
      }
      out.push(new EqUserPreset(name, gains));
    }
    return out;
  }

  /** 保存增益为用户预设（同名覆盖） */
  saveUserPreset(name: string, gains: Array<number>): void {
    const presets = this.getUserPresets();
    const records: Array<JsonRecord> = [];
    let replaced = false;
    for (const p of presets) {
      if (p.name === name) {
        records.push(EqualizerManager.userPresetToRecord(name, gains));
        replaced = true;
      } else {
        records.push(EqualizerManager.userPresetToRecord(p.name, p.gains));
      }
    }
    if (!replaced) {
      records.push(EqualizerManager.userPresetToRecord(name, gains));
    }
    appConfig.setEqUserPresets(JsonUtil.safeStringify(records));
  }

  /** 删除用户预设 */
  deleteUserPreset(name: string): void {
    const presets = this.getUserPresets();
    const records: Array<JsonRecord> = [];
    for (const p of presets) {
      if (p.name !== name) {
        records.push(EqualizerManager.userPresetToRecord(p.name, p.gains));
      }
    }
    appConfig.setEqUserPresets(JsonUtil.safeStringify(records));
  }

  /** 重命名用户预设（新名称与其他已有预设同名则不执行，返回是否成功） */
  renameUserPreset(oldName: string, newName: string): boolean {
    const presets = this.getUserPresets();
    for (const p of presets) {
      if (p.name === newName && p.name !== oldName) {
        return false;
      }
    }
    const records: Array<JsonRecord> = [];
    for (const p of presets) {
      if (p.name === oldName) {
        records.push(EqualizerManager.userPresetToRecord(newName, p.gains));
      } else {
        records.push(EqualizerManager.userPresetToRecord(p.name, p.gains));
      }
    }
    appConfig.setEqUserPresets(JsonUtil.safeStringify(records));
    return true;
  }

  /** 应用用户预设（设置增益并落盘，预设名置为自定义） */
  applyUserPreset(name: string): boolean {
    const presets = this.getUserPresets();
    for (const p of presets) {
      if (p.name === name) {
        this.presetKeyInternal = EqualizerManager.PRESET_CUSTOM;
        appConfig.setEqPreset(EqualizerManager.PRESET_CUSTOM);
        this.updateGains(p.gains);
        return true;
      }
    }
    return false;
  }

  private static userPresetToRecord(name: string, gains: Array<number>): JsonRecord {
    const rec: JsonRecord = {};
    rec['name'] = name;
    rec['gains'] = gains;
    return rec;
  }

  /** 增益是否与预设完全一致（一致时预设高亮，否则为自定义） */
  isPresetActive(key: string): boolean {
    if (key === EqualizerManager.PRESET_CUSTOM) {
      return this.presetKeyInternal === EqualizerManager.PRESET_CUSTOM;
    }
    return this.presetKeyInternal === key;
  }

  /** 注册开关变化监听（返回解绑函数） */
  onEnabledChanged(cb: (enabled: boolean) => void): () => void {
    this.enabledListeners.push(cb);
    return (): void => {
      const idx = this.enabledListeners.indexOf(cb);
      if (idx >= 0) {
        this.enabledListeners.splice(idx, 1);
      }
    };
  }

  /** 注册增益变化监听（返回解绑函数） */
  onGainsChanged(cb: (gains: Array<number>) => void): () => void {
    this.gainsListeners.push(cb);
    return (): void => {
      const idx = this.gainsListeners.indexOf(cb);
      if (idx >= 0) {
        this.gainsListeners.splice(idx, 1);
      }
    };
  }

  private updateGains(gains: Array<number>): void {
    this.gainsInternal = gains;
    appConfig.setEqGains(gains);
    for (const cb of this.gainsListeners) {
      cb(gains);
    }
  }

  private matchPresetKey(gains: Array<number>): string {
    for (const preset of EqualizerManager.PRESETS) {
      if (EqualizerManager.sameGains(preset.gains, gains)) {
        return preset.key;
      }
    }
    return EqualizerManager.PRESET_CUSTOM;
  }

  private static sameGains(a: Array<number>, b: Array<number>): boolean {
    if (a.length !== b.length) {
      return false;
    }
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) {
        return false;
      }
    }
    return true;
  }

  private static findPreset(key: string): EqPresetDef | null {
    for (const preset of EqualizerManager.PRESETS) {
      if (preset.key === key) {
        return preset;
      }
    }
    return null;
  }
}
