; =================================================================
; 应用层 - 备份管理服务
; 版本: 3.0
; 说明: 封装 BackupCore 基础设施层 API，供表现层调用
;       消除表现层对基础设施层的直接依赖（DDD 分层原则）
;       修复 I1: 表现层不应直接调用 BackupCore
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "../infrastructure/backup_core.ahk"

class BackupService {
    ; 暴露备份目录路径（表现层构建备份路径时需要）
    static backupDir {
        get => BackupCore.backupDir
    }

    ; 列出所有备份文件
    static ListBackups() {
        return BackupCore.ListBackups()
    }

    ; 创建备份
    static CreateBackup(configData, label := "") {
        return BackupCore.CreateBackup(configData, label)
    }

    ; 恢复备份
    static RestoreBackup(backupPath) {
        return BackupCore.RestoreBackup(backupPath)
    }

    ; 删除备份
    static DeleteBackup(backupPath) {
        return BackupCore.DeleteBackup(backupPath)
    }

    ; 记录配置变更（带防抖）
    static RecordConfigChange(configData) {
        return BackupCore.RecordConfigChange(configData)
    }
}
