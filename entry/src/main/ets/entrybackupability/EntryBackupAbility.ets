import { BackupExtensionAbility } from '@kit.CoreFileKit';

/**
 * 备份恢复扩展能力（与应用数据备份/恢复相关，与后台播放无关）
 * 在 module.json5 extensionAbilities 中以 type: "backup" 声明，
 * 并通过 ohos.extension.backup 元数据指向 backup_config.json
 */
export default class EntryBackupAbility extends BackupExtensionAbility {
  onBackup() {
  }

  onRestore() {
  }
}
