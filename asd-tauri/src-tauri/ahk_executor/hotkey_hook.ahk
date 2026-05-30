; =================================================================
; 热键钩子 - IPC 指令驱动的热键注册/注销
; 版本: 1.0
; 说明: 收到 Rust 侧 IPC 指令时注册/注销热键
;       热键触发时通过 IPC 上报事件
;       支持组合键（^=Ctrl, +=Shift, !=Alt）
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

class HotkeyHook {
    ; 已注册热键映射: hotkeyStr => { groupId, enabled }
    static _registered := Map()

    ; 录制回调
    static OnKeyRecorded := ""

    ; =================================================================
    ; 公开方法
    ; =================================================================

    static Init() {
        OutputDebug("HotkeyHook: 已初始化")
    }

    ; 注册热键
    ; hotkeyStr: AHK 热键字符串（如 "F1", "^1", "+a", "!F2"）
    ; groupId: 技能组 ID
    static Register(hotkeyStr, groupId) {
        try {
            if hotkeyStr = "" {
                OutputDebug("HotkeyHook: 热键字符串为空，跳过注册")
                return false
            }

            normalizedKey := HotkeyHook._NormalizeHotkey(hotkeyStr)

            if HotkeyHook._registered.Has(normalizedKey) {
                existing := HotkeyHook._registered[normalizedKey]
                existing["groupId"] := groupId
                OutputDebug("HotkeyHook: 热键已存在，更新 groupId=" groupId " key=" normalizedKey)
                return true
            }

            HotkeyHook._registered[normalizedKey] := Map("groupId", groupId, "enabled", true)

            capturedKey := normalizedKey
            Hotkey(normalizedKey, (*) => HotkeyHook._OnHotkeyPress(capturedKey), "On")

            OutputDebug("HotkeyHook: 已注册 key=" normalizedKey " groupId=" groupId)
            return true
        } catch as e {
            OutputDebug("HotkeyHook: 注册失败 key=" hotkeyStr " err=" e.Message)
            return false
        }
    }

    ; 注销热键
    static Unregister(hotkeyStr) {
        try {
            normalizedKey := HotkeyHook._NormalizeHotkey(hotkeyStr)

            if !HotkeyHook._registered.Has(normalizedKey) {
                OutputDebug("HotkeyHook: 热键未注册，跳过注销 key=" normalizedKey)
                return true
            }

            Hotkey(normalizedKey, "Off")
            HotkeyHook._registered.Delete(normalizedKey)

            OutputDebug("HotkeyHook: 已注销 key=" normalizedKey)
            return true
        } catch as e {
            OutputDebug("HotkeyHook: 注销失败 key=" hotkeyStr " err=" e.Message)
            return false
        }
    }

    ; 注销所有热键
    static UnregisterAll() {
        for key, info in HotkeyHook._registered {
            try
                Hotkey(key, "Off")
            catch as e
                OutputDebug("HotkeyHook: 注销失败 key=" key " err=" e.Message)
        }
        HotkeyHook._registered := Map()
        OutputDebug("HotkeyHook: 已注销所有热键")
    }

    ; 获取已注册热键数量
    static GetCount() {
        return HotkeyHook._registered.Count
    }

    ; 检查热键是否已注册
    static IsRegistered(hotkeyStr) {
        normalizedKey := HotkeyHook._NormalizeHotkey(hotkeyStr)
        return HotkeyHook._registered.Has(normalizedKey)
    }

    ; =================================================================
    ; 内部方法
    ; =================================================================

    static _OnHotkeyPress(normalizedKey) {
        if !HotkeyHook._registered.Has(normalizedKey) {
            OutputDebug("HotkeyHook: 未注册热键被触发 key=" normalizedKey)
            return
        }

        info := HotkeyHook._registered[normalizedKey]
        if !info["enabled"] {
            OutputDebug("HotkeyHook: 热键已禁用 key=" normalizedKey)
            return
        }

        OutputDebug("HotkeyHook: 热键触发 key=" normalizedKey)

        ; 通过 IPC 上报热键事件
        IpcClient.SendHotkeyEvent(normalizedKey)

        ; 录制回调
        if HotkeyHook.OnKeyRecorded
            HotkeyHook.OnKeyRecorded.Call(normalizedKey)
    }

    ; 规范化热键字符串
    ; 确保修饰符顺序一致：^!+# （Ctrl, Alt, Shift, Win）
    static _NormalizeHotkey(hotkeyStr) {
        h := hotkeyStr

        ; 提取修饰符
        hasCtrl := false
        hasAlt := false
        hasShift := false
        hasWin := false

        while StrLen(h) > 0 {
            c := SubStr(h, 1, 1)
            if c = "^" {
                hasCtrl := true
                h := SubStr(h, 2)
            } else if c = "!" {
                hasAlt := true
                h := SubStr(h, 2)
            } else if c = "+" {
                hasShift := true
                h := SubStr(h, 2)
            } else if c = "#" {
                hasWin := true
                h := SubStr(h, 2)
            } else
                break
        }

        ; 按标准顺序重建修饰符
        result := ""
        if hasCtrl
            result .= "^"
        if hasAlt
            result .= "!"
        if hasShift
            result .= "+"
        if hasWin
            result .= "#"
        result .= h

        return result
    }
}
