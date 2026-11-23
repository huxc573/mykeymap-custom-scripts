;====================================================================
; 音频输出设备切换 —— MyKeymap2 自定义函数
;
; 只用 Windows CoreAudio（IMMDeviceEnumerator + 未公开的 IPolicyConfig），
; 不依赖任何外部 exe / PowerShell 模块。
;
; 对外函数（不自带热键，由 keymap 调用）：
;   AudioSwitch(*)           在所有 ACTIVE 播放设备之间循环切换；每按一次切到下一个
;   AudioSwitchSet(name)     按名字直达指定设备，如 AudioSwitchSet("耳机")；不区分大小写
;   AudioSwitchList(*)       列出可用设备与当前默认（配 Set 时查名字 / 排错用）
;
; 行为：切 eConsole / eMultimedia / eCommunications 三个角色（与系统「默认设备」一致），
;       切完重新读一次默认设备做校验，不信返回值。
; 提示：ToolTip 通道 7（1=连点器前台 5=亮度 6=连点器后台），文案 `音频:设备名` / `音频:失败-环节`。
;
; 坑：
;   1. 只枚举 DEVICE_STATE_ACTIVE(1)；禁用/拔掉的端点不参与循环。
;   2. IPolicyConfig 是未公开接口，vtable 13 号是 SetDefaultEndpoint（Win7~Win11 一致，
;      SoundSwitch / AudioDeviceCmdlets / EdifierGuard 都用它）。
;   3. 设备名读的是 PKEY_Device_FriendlyName，去掉尾部括号里的驱动名再显示。
;   4. CoInitializeEx 返回 S_FALSE(1) 是正常的（线程已初始化）。
;
; 编码：UTF-8 无 BOM + CRLF + 末尾换行。改完必须重载 MyKeymap（设置界面保存）才生效。
;====================================================================

AS_TipNo := 7

AS_G_Enum      := 0
AS_G_IidEnum   := 0
AS_G_Policy    := 0
AS_G_IidUnk    := 0
AS_G_IidPolicy := 0
AS_PKEY_Name   := 0

AsInitOnce() {
    global AS_G_Enum, AS_G_IidEnum, AS_G_Policy, AS_G_IidUnk, AS_G_IidPolicy, AS_PKEY_Name
    if AS_G_Enum
        return
    AS_G_Enum := Buffer(16, 0)
    DllCall("ole32\CLSIDFromString", "WStr", "{BCDE0395-E52F-467C-8E3D-C4579291692E}", "Ptr", AS_G_Enum, "Int")
    AS_G_IidEnum := Buffer(16, 0)
    DllCall("ole32\CLSIDFromString", "WStr", "{A95664D2-9614-4F35-A746-DE8DB63617E6}", "Ptr", AS_G_IidEnum, "Int")
    AS_G_Policy := Buffer(16, 0)
    DllCall("ole32\CLSIDFromString", "WStr", "{870AF99C-171D-4F9E-AF0D-E63DF40C2BC9}", "Ptr", AS_G_Policy, "Int")
    AS_G_IidUnk := Buffer(16, 0)
    DllCall("ole32\CLSIDFromString", "WStr", "{00000000-0000-0000-C000-000000000046}", "Ptr", AS_G_IidUnk, "Int")
    AS_G_IidPolicy := Buffer(16, 0)
    DllCall("ole32\CLSIDFromString", "WStr", "{F8679F50-850A-41CF-9C72-430F290290C8}", "Ptr", AS_G_IidPolicy, "Int")
    AS_PKEY_Name := Buffer(20, 0)
    g := Buffer(16, 0)
    DllCall("ole32\CLSIDFromString", "WStr", "{a45c254e-df1c-4efd-8020-67d146a850e0}", "Ptr", g, "Int")
    DllCall("RtlMoveMemory", "Ptr", AS_PKEY_Name, "Ptr", g, "UPtr", 16)
    NumPut("UInt", 14, AS_PKEY_Name, 16)
    DllCall("ole32\CoInitializeEx", "Ptr", 0, "UInt", 0x2)
}

; 显示名：去掉 " (High Definition Audio Device)" 这类尾巴
AsShortName(name) {
    s := RegExReplace(name, "\s*\([^()]*\)\s*$", "")
    return s = "" ? name : s
}

AsTip(text, ms := 1100) {
    global AS_TipNo
    old := A_CoordModeToolTip
    CoordMode("ToolTip", "Screen")
    MouseGetPos(&mx, &my)
    ToolTip(text, mx + 18, my + 18, AS_TipNo)
    CoordMode("ToolTip", old)
    SetTimer(() => ToolTip("", 0, 0, AS_TipNo), -ms)
}

; 读一个 IMMDevice 的 FriendlyName
AsNameOf(pDev) {
    global AS_PKEY_Name
    pStore := 0
    ComCall(4, pDev, "Int", 0, "Ptr*", &pStore)
    if !pStore
        return ""
    pv := Buffer(32, 0)
    ComCall(5, pStore, "Ptr", AS_PKEY_Name, "Ptr", pv)
    name := ""
    if (NumGet(pv, 0, "UShort") = 31)
        name := StrGet(NumGet(pv, 8, "Ptr"))
    ComCall(2, pStore)
    return name
}

AsOpenEnum() {
    global AS_G_Enum, AS_G_IidEnum
    pEnum := 0
    hr := DllCall("ole32\CoCreateInstance", "Ptr", AS_G_Enum, "Ptr", 0, "UInt", 0x17
        , "Ptr", AS_G_IidEnum, "Ptr*", &pEnum, "Int")
    if (hr != 0 || !pEnum)
        throw Error("枚举器 hr=" hr)
    return pEnum
}

; 返回 [{id, name}]，只含 ACTIVE
AsDevices() {
    AsInitOnce()
    pEnum := AsOpenEnum()
    pColl := 0
    ComCall(3, pEnum, "Int", 0, "UInt", 1, "Ptr*", &pColl)
    if !pColl {
        ComCall(2, pEnum)
        throw Error("ACTIVE 集合为空")
    }
    cnt := 0
    ComCall(3, pColl, "UInt*", &cnt)
    out := []
    loop cnt {
        pDev := 0
        ComCall(4, pColl, "UInt", A_Index - 1, "Ptr*", &pDev)
        if !pDev
            continue
        pwsz := 0
        ComCall(5, pDev, "Ptr*", &pwsz)
        id := StrGet(pwsz)
        name := AsNameOf(pDev)
        ComCall(2, pDev)
        out.Push({ id: id, name: name })
    }
    ComCall(2, pColl)
    ComCall(2, pEnum)
    return out
}

; 当前默认（eConsole）设备 id
AsDefaultId() {
    AsInitOnce()
    pEnum := AsOpenEnum()
    pDef := 0
    ComCall(4, pEnum, "Int", 0, "Int", 0, "Ptr*", &pDef)
    id := ""
    if pDef {
        pwsz := 0
        ComCall(5, pDef, "Ptr*", &pwsz)
        id := StrGet(pwsz)
        ComCall(2, pDef)
    }
    ComCall(2, pEnum)
    return id
}

; SetDefaultEndpoint：vtable 13，三个 role 各来一次
AsSetDefault(devId) {
    global AS_G_Policy, AS_G_IidUnk, AS_G_IidPolicy
    AsInitOnce()
    pUnk := 0
    hr := DllCall("ole32\CoCreateInstance", "Ptr", AS_G_Policy, "Ptr", 0, "UInt", 0x17
        , "Ptr", AS_G_IidUnk, "Ptr*", &pUnk, "Int")
    if (hr != 0 || !pUnk)
        throw Error("PolicyConfig hr=" hr)
    pPol := 0
    ComCall(0, pUnk, "Ptr", AS_G_IidPolicy, "Ptr*", &pPol)
    ComCall(2, pUnk)
    if !pPol
        throw Error("QI IPolicyConfig 失败")
    loop 3
        ComCall(13, pPol, "WStr", devId, "Int", A_Index - 1)
    ComCall(2, pPol)
}

; ---------------------------------------------------------------
; 对外
; ---------------------------------------------------------------

; 循环切到下一个播放设备
AudioSwitch(*) {
    try {
        devs := AsDevices()
        if (devs.Length = 0) {
            AsTip("音频:失败-无可用设备")
            return false
        }
        cur := AsDefaultId()
        idx := 0
        for i, d in devs {
            if (d.id = cur) {
                idx := i
                break
            }
        }
        next := devs[Mod(idx, devs.Length) + 1]
        AsSetDefault(next.id)
        ; 校验：不信返回值，重读一次
        if (AsDefaultId() != next.id) {
            AsTip("音频:失败-未生效")
            return false
        }
        AsTip("音频:" AsShortName(next.name))
        return true
    } catch as e {
        AsTip("音频:失败-" SubStr(e.Message, 1, 24))
        return false
    }
}

; 按名字模糊匹配切（不区分大小写的子串匹配）
AudioSwitchSet(name, *) {
    try {
        devs := AsDevices()
        for d in devs {
            if InStr(d.name, name) {
                AsSetDefault(d.id)
                if (AsDefaultId() != d.id) {
                    AsTip("音频:失败-未生效")
                    return false
                }
                AsTip("音频:" AsShortName(d.name))
                return true
            }
        }
        AsTip("音频:失败-无匹配 " name)
        return false
    } catch as e {
        AsTip("音频:失败-" SubStr(e.Message, 1, 24))
        return false
    }
}

; 列出可用设备 + 当前默认（排错用，提示 3 秒）
AudioSwitchList(*) {
    try {
        devs := AsDevices()
        cur := AsDefaultId()
        lines := "音频设备:"
        for i, d in devs {
            mark := (d.id = cur) ? " *" : ""
            lines .= "`n" i ". " AsShortName(d.name) mark
            lines .= "`n    " d.id
        }
        AsTip(lines, 3000)
        return true
    } catch as e {
        AsTip("音频:失败-" SubStr(e.Message, 1, 24))
        return false
    }
}
