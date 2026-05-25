; =================================================================
; 表现层 - 备份管理器 GUI
; 版本: 3.0
; 说明: 管理配置备份的图形界面
;       依赖基础设施层的 BackupCore
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "../infrastructure/backup_core.ahk"
#Include "../application/config_service.ahk"
#Include "../infrastructure/error_system.ahk"

class BackupUI {
    static gui := ""
    static controls := Map()

    static Show() {
        try {
            if BackupUI.gui {
                BackupUI.gui.Show("w500 h400")
                return
            }

            BackupUI.gui := Gui("+Resize +MinSize400x300", "备份管理")
            BackupUI.gui.SetFont("s10", "Segoe UI")

            BackupUI.controls["LV"] := BackupUI.gui.Add("ListView", "x10 y10 w480 h300", ["备份文件", "时间", "大小"])

            btnRestore := BackupUI.gui.Add("Button", "x10 y320 w100 h35", "恢复选中")
            btnRestore.OnEvent("Click", (*) => BackupUI._RestoreSelected())

            btnDelete := BackupUI.gui.Add("Button", "x120 y320 w100 h35", "删除选中")
            btnDelete.OnEvent("Click", (*) => BackupUI._DeleteSelected())

            btnCreate := BackupUI.gui.Add("Button", "x280 y320 w100 h35", "创建备份")
            btnCreate.OnEvent("Click", (*) => BackupUI._CreateBackup())

            btnRefresh := BackupUI.gui.Add("Button", "x390 y320 w100 h35", "刷新")
            btnRefresh.OnEvent("Click", (*) => BackupUI._RefreshList())

            BackupUI.gui.OnEvent("Close", (*) => BackupUI.gui.Hide())
            BackupUI.gui.OnEvent("Escape", (*) => BackupUI.gui.Hide())

            BackupUI._RefreshList()
            BackupUI.gui.Show("w500 h400")
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static _RefreshList() {
        try {
            LV := BackupUI.controls["LV"]
            LV.Delete()

            backups := BackupCore.ListBackups()
            for b in backups {
                timeFormatted := FormatTime(b["time"], "yyyy-MM-dd HH:mm:ss")
                sizeKB := Round(b["size"] / 1024, 1) " KB"
                LV.Add(, b["file"], timeFormatted, sizeKB)
            }

            LV.ModifyCol(1, "180")
            LV.ModifyCol(2, "160")
            LV.ModifyCol(3, "100")
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static _RestoreSelected() {
        try {
            LV := BackupUI.controls["LV"]
            selected := LV.GetNext()
            if selected = 0 {
                ErrorSystem.LogError("请选择要恢复的备份", "WARNING", A_ThisFunc, A_LineNumber)
                return
            }

            backupFile := LV.GetText(selected, 1)
            backups := BackupCore.ListBackups()
            backupPath := ""
            for b in backups {
                if b["file"] = backupFile {
                    backupPath := b["path"]
                    break
                }
            }

            if backupPath = "" {
                ErrorSystem.LogError("找不到备份文件", "ERROR", A_ThisFunc, A_LineNumber)
                return
            }

            result2 := BackupCore.RestoreBackup(backupPath)
            if result2["success"] {
                try {
                    ConfigService.LoadConfig()
                } catch as loadErr {
                    ErrorSystem.LogError("恢复后加载配置失败: " loadErr.Message, "ERROR", A_ThisFunc, A_LineNumber)
                }
                MsgBox("备份已恢复并加载", "恢复成功", "Iconi")
            } else {
                ErrorSystem.LogError("恢复失败: " result2["error"], "ERROR", A_ThisFunc, A_LineNumber)
            }
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static _DeleteSelected() {
        try {
            LV := BackupUI.controls["LV"]
            selected := LV.GetNext()
            if selected = 0 {
                ErrorSystem.LogError("请选择要删除的备份", "WARNING", A_ThisFunc, A_LineNumber)
                return
            }

            backupFile := LV.GetText(selected, 1)
            backups := BackupCore.ListBackups()
            backupPath := ""
            for b in backups {
                if b["file"] = backupFile {
                    backupPath := b["path"]
                    break
                }
            }

            if backupPath = "" {
                ErrorSystem.LogError("找不到备份文件", "ERROR", A_ThisFunc, A_LineNumber)
                return
            }

            result := MsgBox("确定要删除备份 '" backupFile "' 吗？", "确认删除", "YesNo Icon?")
            if result = "Yes" {
                BackupCore.DeleteBackup(backupPath)
                BackupUI._RefreshList()
            }
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static _CreateBackup() {
        try {
            config := ConfigService.ConfigStore.Load()
            result := BackupCore.CreateBackup(config)
            if result["success"] {
                BackupUI._RefreshList()
                MsgBox("备份已创建: " result["file"], "备份成功", "Iconi")
            } else {
                ErrorSystem.LogError("备份失败: " result["error"], "ERROR", A_ThisFunc, A_LineNumber)
            }
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }
}
