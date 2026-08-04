; =================================================================
; 基础设施层 - 配置文件 IO
; 版本: 3.0
; 说明: 配置文件的原子写入与安全读取
;       修复 I6: 将配置写入逻辑下沉到基础设施层
;       消除 BackupCore 对应用层 ExportConfigToFile 的反向依赖
;       原逻辑来自 application/config_service.ahk 的全局函数
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "json_logger.ahk"
#Include "json_serializer.ahk"
#Include "json_parser.ahk"
#Include "error_handler.ahk"

class ConfigIO {
    ; 安全写入配置到文件（带重试 + 原子写入）
    static ExportToFile(filePath, config) {
        exportFn := () => ConfigIO._WriteFileInner(filePath, config)
        return ErrorHandler.RetryWithPolicy(exportFn, 3, 200, ErrorHandler.CATEGORY_IO)
    }

    ; 安全读取配置文件（带降级默认值）
    static LoadFromFile(filePath) {
        return ErrorHandler.SafeExecute(
            () => JSONParser.LoadFile(filePath),
            () => Map("version", "3.0", "GroupSettings", Map(),
                      "CONTROL_HOTKEYS", Map(), "HoldSettings", Map()),
            ErrorHandler.CATEGORY_IO
        )
    }

    ; 原子写入内部实现（临时文件 + safety 备份，保证写入原子性）
    static _WriteFileInner(filePath, config) {
        if !InStr(FileExist(filePath), "A") {
            dir := ""
            SplitPath(filePath, , &dir)
            if dir != "" && !InStr(FileExist(dir), "D")
                DirCreate(dir)
        }

        jsonStr := JSONSerializer.Stringify(config)
        tempPath := filePath ".tmp"
        safetyPath := filePath ".safety"
        try
            FileDelete(tempPath)
        catch as e {
            OutputDebug("ASD [WARN] ConfigIO._WriteFileInner: FileDelete(tempPath) 失败: " e.Message " at line " e.Line)
        }
        FileAppend(jsonStr, tempPath, "UTF-8")
        try
            FileMove(filePath, safetyPath, 1)
        catch as e {
            OutputDebug("ASD [WARN] ConfigIO._WriteFileInner: FileMove(filePath→safetyPath) 失败: " e.Message " at line " e.Line)
        }
        try {
            FileMove(tempPath, filePath)
            try
                FileDelete(safetyPath)
            catch as e {
                OutputDebug("ASD [WARN] ConfigIO._WriteFileInner: FileDelete(safetyPath) 失败: " e.Message " at line " e.Line)
            }
        } catch as moveErr {
            try
                FileMove(safetyPath, filePath)
            catch as e {
                OutputDebug("ASD [WARN] ConfigIO._WriteFileInner: FileMove(safetyPath→filePath) 回滚失败: " e.Message " at line " e.Line)
            }
            throw moveErr
        }
        JSONLogger.Log("DEBUG", "配置已保存: " filePath,
                      Map("module", "ConfigIO"))
        return true
    }
}
