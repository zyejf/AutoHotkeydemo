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
; TD-047：降级默认值必须是**合法的出厂默认**，不能是空壳 —— 详见 LoadFromFile 的注释。
#Include "config_store.ahk"

class ConfigIO {
    ; 安全写入配置到文件（带重试 + 原子写入）
    static ExportToFile(filePath, config) {
        exportFn := () => ConfigIO._WriteFileInner(filePath, config)
        return ErrorHandler.RetryWithPolicy(exportFn, 3, 200, ErrorHandler.CATEGORY_IO)
    }

    ; 安全读取配置文件（带降级默认值）
    ;
    ; ⚠️ TD-047：降级值**必须是能通过 ConfigValidator 的合法配置**，不能是空壳。
    ;
    ; 原实现的降级值是 `Map("version","3.0","GroupSettings",Map(),"CONTROL_HOTKEYS",Map(),
    ; "HoldSettings",Map())` —— CONTROL_HOTKEYS 是**空 Map**，而 `ConfigValidator._ValidateHotkeys`
    ; 要求 emergency / toggleAll / showStatus / toggleHoldMode / releaseAllHolds 五个键齐全，
    ; 于是产生 **5 条 ERROR**；`ConfigService.SaveConfig()` 见 ERROR 就**拒绝保存整份配置**。
    ; 后果：配置文件不存在（首次启动）或被损坏时，用户**建任何分组都存不下**，且界面上
    ; 只看到「保存失败」，看不出真因。与 TD-035 同类（校验错误放大成「整份配置存不下」），
    ; 但根因不同 —— 那次是校验器查错字段名，这次是降级默认值本身就不合法。
    ;
    ; 另外：这里走的是 `ErrorHandler.SafeExecute`，失败时**不抛异常**，所以
    ; `ConfigService.LoadConfig()` 的 catch 分支（那份会调用 `_GetDefaultConfig()`，内容是完整的）
    ; **永远不会被触发** —— 完整的默认值写在那里等于没写，这也是这个缺陷长期没被发现的原因。
    ;
    ; 默认值一律取自 `ConfigStore` 的构造器（出厂默认的单一真值源），
    ; **不在本文件里抄一份字面量** —— 抄一份就一定会漂移。
    static LoadFromFile(filePath) {
        return ErrorHandler.SafeExecute(
            () => JSONParser.LoadFile(filePath),
            () => Map(
                "version", "3.0",
                "lastModified", A_Now,
                "GroupSettings", Map(),
                "CONTROL_HOTKEYS", ConfigStore._BuildDefaultControlHotkeys(),
                "HoldSettings", ConfigStore._BuildDefaultHoldSettings()
            ),
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
