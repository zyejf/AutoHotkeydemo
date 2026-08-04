; =================================================================
; 基础设施层 - 备份管理器核心
; 版本: 3.0
; 说明: 配置文件备份与回滚的核心业务逻辑
;       不包含 GUI 交互面（GUI 面在 presentation/backup_ui.ahk）
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "json_logger.ahk"
#Include "json_serializer.ahk"
#Include "json_parser.ahk"
#Include "config_io.ahk"

class BackupCore {
    static backupDir := "backups"
    static maxBackups := 10
    static _lastRecordTime := 0
    static _recordDebounceMs := 3000
    static _recordTimer := 0
    static currentConfigPath := "config.json"

    static Init() {
        if !InStr(FileExist(BackupCore.backupDir), "D")
            DirCreate(BackupCore.backupDir)
    }

    static CreateBackup(configData, label := "") {
        BackupCore.Init()

        timestamp := FormatTime(, "yyyy-MM-dd_HH-mm-ss")
        sanitizedLabel := label != "" ? "_" RegExReplace(label, "[\\/:*?<>|]", "_") : ""
        fileName := "backup_" timestamp sanitizedLabel ".json"
        filePath := BackupCore.backupDir "\" fileName

        try {
            jsonStr := JSONSerializer.Stringify(configData)
            FileAppend(jsonStr, filePath, "UTF-8")
            JSONLogger.Log("DEBUG", "备份已创建: " fileName,
                          Map("module", "BackupCore", "code", JSONErrorType.DEBUG_BACKUP_CREATE))

            BackupCore._CleanupOldBackups()
            return Map("success", true, "file", fileName, "path", filePath)
        } catch as e {
            JSONLogger.Log("ERROR", "创建备份失败: " e.Message,
                          Map("module", "BackupCore"))
            return Map("success", false, "error", e.Message)
        }
    }

    static RestoreBackup(backupPath) {
        if !FileExist(backupPath) {
            JSONLogger.Log("ERROR", "备份文件不存在: " backupPath,
                          Map("module", "BackupCore"))
            return Map("success", false, "error", "备份文件不存在")
        }

        try {
            config := JSONParser.LoadFile(backupPath)

            if !(config is Map) || !config.Has("GroupSettings") {
                JSONLogger.Log("ERROR", "备份文件格式无效: 缺少 GroupSettings",
                              Map("module", "BackupCore"))
                return Map("success", false, "error", "备份文件格式无效")
            }

            exportResult := ConfigIO.ExportToFile(BackupCore.currentConfigPath, config)
            if !exportResult {
                JSONLogger.Log("ERROR", "恢复备份写入失败",
                              Map("module", "BackupCore"))
                return Map("success", false, "error", "写入配置失败")
            }

            JSONLogger.Log("DEBUG", "备份已恢复: " backupPath,
                          Map("module", "BackupCore", "code", JSONErrorType.DEBUG_BACKUP_RESTORE))

            return Map("success", true, "config", config)
        } catch as e {
            JSONLogger.Log("ERROR", "恢复备份失败: " e.Message,
                          Map("module", "BackupCore"))
            return Map("success", false, "error", e.Message)
        }
    }

    static ListBackups() {
        BackupCore.Init()

        backups := []
        try {
            Loop Files, BackupCore.backupDir "\*.json" {
                if InStr(A_LoopFileName, "backup_") {
                    backups.Push(Map(
                        "file", A_LoopFileName,
                        "path", A_LoopFileFullPath,
                        "time", FileGetTime(A_LoopFileFullPath),
                        "size", FileGetSize(A_LoopFileFullPath)
                    ))
                }
            }
        }

        return BackupCore._SortBackupsByTime(backups)
    }

    static DeleteBackup(backupPath) {
        try {
            absBackupPath := (StrLen(backupPath) > 1 && SubStr(backupPath, 2, 1) = ":") ? backupPath : A_ScriptDir "\" backupPath
            absBackupDir := (StrLen(BackupCore.backupDir) > 1 && SubStr(BackupCore.backupDir, 2, 1) = ":") ? BackupCore.backupDir : A_ScriptDir "\" BackupCore.backupDir
            ; C4 安全修复：路径遍历防护 - 检测到 .. 直接拒绝（拒绝式检查）
            ; 不使用 RegExReplace 删除式过滤（可被 .... 等输入绕过）
            if InStr(absBackupPath, "..") || InStr(absBackupDir, "..") {
                JSONLogger.Log("ERROR", "删除备份失败: 路径包含非法字符",
                              Map("module", "BackupCore"))
                return false
            }
            if SubStr(absBackupPath, 1, StrLen(absBackupDir)) != absBackupDir {
                JSONLogger.Log("ERROR", "删除备份失败: 路径不在备份目录内",
                              Map("module", "BackupCore"))
                return false
            }
            FileDelete(absBackupPath)
            return true
        } catch as e {
            JSONLogger.Log("ERROR", "删除备份失败: " e.Message,
                          Map("module", "BackupCore"))
            return false
        }
    }

    static _CleanupOldBackups() {
        backups := BackupCore.ListBackups()
        if backups.Length <= BackupCore.maxBackups
            return
        deleteCount := backups.Length - BackupCore.maxBackups
        deleted := 0
        idx := backups.Length
        while deleted < deleteCount && idx >= 1 {
            try {
                FileDelete(backups[idx]["path"])
                deleted++
            } catch as e {
                JSONLogger.Log("WARNING", "清理旧备份失败: " e.Message, Map("module", "BackupCore"))
            }
            idx--
        }
    }

    static RecordConfigChange(configData) {
        if BackupCore._recordTimer {
            try
                SetTimer(BackupCore._recordTimer, 0)
        }
        fn := () => (BackupCore._recordTimer := 0, BackupCore.CreateBackup(configData, "auto"))
        BackupCore._recordTimer := fn
        SetTimer(fn, -BackupCore._recordDebounceMs)
    }

    static _SortBackupsByTime(backups) {
        n := backups.Length
        loop n - 1 {
            i := A_Index + 1
            key := backups[i]
            j := i - 1
            while j >= 1 && backups[j]["time"] < key["time"] {
                backups[j + 1] := backups[j]
                j--
            }
            backups[j + 1] := key
        }
        return backups
    }
}
