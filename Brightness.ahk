;====================================================================
; 亮度调节（硬件背光 / Gamma / 遮罩）  —— MyKeymap2 自定义函数
;
; 本文件由原 VistaCare.ahk（Gamma 方案）与 BrightAlt.ahk（备用方案）合并而成
; （2026-09-18）；2026-10-07 补上「按鼠标所在屏生效」「硬件背光优先」「两个入口分开」。
; 全部亮度逻辑只在这一个文件里。
;
; 两个入口（2026-10-07 起分开，别混着用）：
;   BrightAuto(delta)   **软件优先**：Gamma -> 遮罩，全程不碰显示器硬件。→ 滚轮（上/下/中键）
;   BrightHw(delta)     **硬件优先**：硬件背光 -> Gamma -> 遮罩。        → CapsLock + `-` / `=`
;   两者唯一区别就是有没有那一级硬件背光；硬件拿不到时行为完全一样。
;
; 作用范围：由开关 BR_PerMonitor 决定（默认 true = 只调鼠标所在那块屏）。
;   屏的定位走 BaMonAtCursor() / BaMonList()（EnumDisplayMonitors + GetMonitorInfoW），
;   坐标与 MouseGetPos、Gui Show 同为物理像素；false 时是「所有屏一起调」。
;   delta = 0 一律是**全部还原**（硬件回原始值 + Gamma 全清 + 遮罩全撤），不受开关影响。
;
; 硬件背光一级按屏选路（都是真·背光：不损色、不留半透明遮罩、不动显卡 LUT）：
;   内置屏（笔记本）：WMI root\wmi 的 WmiMonitorBrightnessMethods —— 就是 Win 的「系统亮度」。
;                     同一接口，所以系统亮度滑块和本脚本会互相覆盖读数（改完在别处调过，
;                     脚本记的当前值是旧的；只有 delta=0 的「回原始值」是准的）。
;   外接屏          ：DDC/CI（dxva2，VCP 0x10）。**要在显示器 OSD 里打开 DDC/CI 才有反应**；
;                     没开的话读取直接失败（本机实测 0ms 返回失败），会立刻退到 Gamma。
;
; 软件两级（硬件拿不到时才用）：
;
; 1) Gamma（写显卡 LUT）—— 原 VistaCare 方案，即 BrightGamma()
;    调 gdi32 SetDeviceGammaRamp 改显示器 Gamma 曲线。
;    优点：作用在**显示层**，屏幕上所有内容（含鼠标指针、开始菜单、任意窗口）
;          会一起变亮变暗。
;    缺点：WinPE / 只有 BasicDisplay 驱动时**不报错也不生效**（空操作，屏幕毫无反应）。
;
; 2) 遮罩（纯软件，每屏一个分层窗口）—— 原 BrightAlt 方案，即 BrightMask()
;    全屏黑色置顶分层窗口 + 全局 alpha，不碰任何显卡 / 显示器 API，WinPE 下最可能可用。
;    指针：分层窗口盖不住系统指针（指针叠在所有窗口之上），SetSystemCursor 把系统光标
;          全局换成全透明光标来「藏住」（ShowCursor 是线程级的，弃用，见 BaMaskCursor）。
;          藏之前会备份原光标，还原走备份而不是 SPI_SETCURSORS；WinPE 下默认**不藏**
;          （BA_MaskHideCursorInPE）—— PE 里还原不可靠，藏了可能再也拿不回来。
;          真被藏住又还原失败时，用 BrightCursorRestore() 急救。
;    边界：只能变暗；开始菜单是 DWM 直接合成的 XAML 表面，用户态窗口盖不住（09-18 实测）；
;          安全桌面（UAC / Ctrl+Alt+Del）、独占全屏程序同理。
;          补充：WinPE 里本就没有开始菜单，而正常 Windows 下用 Gamma 方案连指针一起暗，
;          故这两条边界不影响实际使用。
;
; 对外函数（都不自带热键，全部由 keymap 调用；delta 语义统一）：
;   delta < 0 变暗 / delta > 0 变亮 / delta = 0 还原；默认 +5；都返回 true / false
;   提示统一写成 `亮度(方案):NN%`（方案 = 硬件 / DDC / WMI / Gamma / 遮罩），一眼看出这次走的是哪一级。
;
;   BrightAuto(delta := 5)      **软件优先**（滚轮接线）
;   BrightHw(delta := 5)        **硬件优先**（CapsLock + `-` / `=` 接线）
;   BrightDdc(delta := 5)       只用 DDC/CI（当前屏，外接屏才有）
;   BrightWmi(delta := 5)       只用 WMI 系统亮度（内置屏，且鼠标得在那块屏上）
;   BrightGamma(delta := 5)     Gamma 方案（原 BrightAdjust，本文件里的「我原本的方式」）
;   BrightGammaReset(*)         还原到 100%，等价 BrightGamma(0)
;   BrightRefreshGamma(*)       显示器插拔 / 改分辨率后重刷 Gamma（由 custom_functions 调用）
;   BrightMask(delta := 5)      纯软件遮罩
;   BrightCursorRestore(*)      急救：把遮罩藏起来的系统指针还回来
;
; 命名约定：
;   对外函数 PascalCase 不带前缀；
;   内部辅助：Gamma / 显示器 / 背光相关走 Bg 前缀，遮罩相关走 Ba 前缀；
;   模块级变量：BG_ / BA_ 前缀；模块级开关：BR_ 前缀。
;   坑：AHK v2 函数内**要赋值**的全局量必须逐个写进 global，漏一个就静默变局部。
;
; 坑（Gui）：窗口「构造选项」不认 x/y/w/h，尺寸位置只能交给 Show("x.. y.. w.. h..")。
; 坑（Mouse）：本环境 MouseClick/MouseMove 的 Speed 不能填 0（本文件不用，备忘）。
; 编码：UTF-8 无 BOM + CRLF + 末尾换行。改完必须重载 MyKeymap（设置界面保存）才生效。
;====================================================================

; ====================================================================
; 配置参数
; ====================================================================
; --- Gamma 方案 ---
minGammaUI  := 0.1      ; 用户层下限：亮度再按也不会低于 10%
minGammaApi := 0.05     ; API 硬下限：低于此值部分显示器会黑屏
; 每块屏各自的当前 Gamma 记在 BG_GammaMap 里，见「方案 1」开头

; --- 遮罩方案 ---
BA_MaskStep := 14                            ; 遮罩每级 alpha（0~255），越小越细腻
BA_MaskMax  := 216                           ; 遮罩上限，留余量避免全黑到没法操作
BA_MaskHideCursor := true                    ; 遮罩期间藏起鼠标指针（系统指针遮不住只能藏）
BA_MaskHideCursorInPE := false               ; PE 下是否也藏：默认否 —— PE 里还原常失效、进程被强杀又不跑 OnExit，藏了可能拿不回来
BA_MaskRaiseMs    := 250                     ; 重申置顶间隔 ms；对普通置顶窗口有效，对开始菜单无效

; --- 作用范围 ---
BR_PerMonitor := true   ; true = 亮度只作用于鼠标所在那块屏；false = 所有屏一起调（2026-10-07）

; --- 通用 ---
BA_TipMs  := 1500                            ; 提示停留时长（ms）
BA_TipNo  := 5                               ; 专用 ToolTip 编号（各方案共用，避免提示互相清掉）
BA_ErrLog := A_Temp "\mykeymap_bright.err.log"   ; 失败时的完整异常文本（只排错用，可随时删）

; ====================================================================
; 公共小工具
; ====================================================================

;--------------------------------------------------------------------
; 内部：钳位（不覆盖 AHK 内置 Min / Max）
;--------------------------------------------------------------------
BaClamp(v, lo, hi) {
    return v < lo ? lo : (v > hi ? hi : v)
}

;--------------------------------------------------------------------
; 内部：把入参收敛成数字；不是数字（例如热键名）就用默认步进
;--------------------------------------------------------------------
BaNum(v, def) {
    return IsNumber(v) ? v : def
}

;--------------------------------------------------------------------
; 内部：短提示，贴在光标右下 16px；贴边自动翻转，避免跑出屏幕
;   text  提示文字，尽量短；统一形如「亮度(方案):NN%」，方案 = 硬件/DDC/WMI/Gamma/遮罩
;--------------------------------------------------------------------
BaTip(text) {
    global BA_TipMs, BA_TipNo
    CoordMode("ToolTip", "Screen")
    MouseGetPos(&mx, &my)
    x := (mx + 16 + 200 > A_ScreenWidth)  ? mx - 216 : mx + 16
    y := (my + 16 + 60  > A_ScreenHeight) ? my - 76  : my + 16
    ToolTip(text, x, y, BA_TipNo)
    SetTimer(BaClearTip, -BA_TipMs)
}

;--------------------------------------------------------------------
; 内部：清掉本文件专用编号的提示
;--------------------------------------------------------------------
BaClearTip(*) {
    global BA_TipNo
    ToolTip("", 0, 0, BA_TipNo)
}

;--------------------------------------------------------------------
; 内部：失败上报 —— 短提示给结论 + 原因摘要，完整异常落到日志
;   where  失败环节（很短，会出现在提示里）
;   e      捕获到的异常对象
;   失败的异常不往外抛：抛出去会弹 AHK 错误框，只说「某行出错」，不如提示 + 日志好定位
;--------------------------------------------------------------------
BaErr(where, e) {
    global BA_ErrLog
    try FileAppend(A_Now " " where ": " e.Message " | line " e.Line "`n", BA_ErrLog, "UTF-8")
    BaTip("亮度(遮罩):失败-" where " " SubStr(e.Message, 1, 16))
}

; ====================================================================
; 显示器定位（所有「只调当前屏」的方案共用）
;   全部走 EnumDisplayMonitors + GetMonitorInfoW，一次拿到 hMon / 矩形 / 设备名，
;   坐标与 MouseGetPos、Gui Show 同为物理像素。
; ====================================================================

;--------------------------------------------------------------------
; 内部：枚举所有显示器
;   返回 [{HMon, Name, X, Y, W, H, Primary}, ...]；Name 形如 \\.\DISPLAY1，
;   可直接喂给 CreateDCW；Primary = 是否主屏。
;--------------------------------------------------------------------
BaMonList() {
    global BA_EnumList
    BA_EnumList := []
    cb := CallbackCreate(BaEnumMonCollect, "Fast", 4)
    DllCall("user32\EnumDisplayMonitors", "Ptr",0, "Ptr",0, "Ptr",cb, "Ptr",0)
    CallbackFree(cb)
    return BA_EnumList
}

;--------------------------------------------------------------------
; 内部：EnumDisplayMonitors 回调，收 hMon + 矩形 + 设备名
;   MONITORINFOEXW 布局：cbSize(4) rcMonitor(16) rcWork(16) dwFlags(4) szDevice(WCHAR[32]) = 104
;   cbSize 必须写对，否则 GetMonitorInfoW 直接返回 FALSE（会安静地一台屏都拿不到）
;--------------------------------------------------------------------
BaEnumMonCollect(hMon, hdc, lprc, lParam) {
    global BA_EnumList
    mi := Buffer(104, 0)
    NumPut("UInt", 104, mi, 0)
    if DllCall("user32\GetMonitorInfoW", "Ptr",hMon, "Ptr",mi) {
        x := NumGet(mi, 4, "Int")
        y := NumGet(mi, 8, "Int")
        r := NumGet(mi, 12, "Int")
        b := NumGet(mi, 16, "Int")
        BA_EnumList.Push({
            HMon: hMon,
            Name: StrGet(mi.Ptr + 40, 32, "UTF-16"),
            X: x, Y: y, W: r - x, H: b - y,
            Primary: (NumGet(mi, 36, "UInt") & 1) != 0
        })
    }
    return 1                                      ; 返回 1 继续枚举
}

;--------------------------------------------------------------------
; 内部：鼠标现在在哪块屏上
;   命中就返回那块；鼠标落在屏幕之外的空隙时退回主屏；一台都没枚举到才返回 0。
;--------------------------------------------------------------------
BaMonAtCursor() {
    MouseGetPos(&mx, &my)
    list := BaMonList()
    if (list.Length = 0)
        return 0
    for m in list {
        if (mx >= m.X && mx < m.X + m.W && my >= m.Y && my < m.Y + m.H)
            return m
    }
    for m in list {
        if m.Primary
            return m
    }
    return list[1]
}

;--------------------------------------------------------------------
; 内部：这次该动哪几块屏
;   BR_PerMonitor（默认 true）= 只动鼠标所在那块；false = 所有屏一起动。
;   鼠标落在屏幕之间的空隙时 BaMonAtCursor 会退回主屏，所以返回的列表不会是空的。
;--------------------------------------------------------------------
BgTargets() {
    global BR_PerMonitor
    if !BR_PerMonitor
        return BaMonList()
    m := BaMonAtCursor()
    return m ? [m] : []
}

; ====================================================================
; 方案 1：Gamma（写显卡 LUT）—— 原 VistaCare 方案
; ====================================================================

BG_GammaMap := Map()    ; 显示器设备名 -> 该屏当前 gamma（1.0 = 原始）。每屏独立记

;--------------------------------------------------------------------
; 内部：判断是否运行在 WinPE / WinRE 里
;   判据：注册表 HKLM\SYSTEM\CurrentControlSet\Control\MiniNT 存在
;   （WinPE 与 WinRE 都会建这个键，是业界通行的判定方式）
;   WinPE 下 Gamma LUT 是空操作，所以 BrightAuto 会直接跳过 Gamma 走遮罩。
;   结果缓存，避免每次滚轮都读注册表。
;--------------------------------------------------------------------
BgInWinPE() {
    static cached := -1
    if (cached >= 0)
        return (cached = 1)
    cached := 0
    hKey := 0
    ; HKEY_LOCAL_MACHINE=0x80000002, KEY_READ=0x20019；返回 0（ERROR_SUCCESS）= 键存在
    if !DllCall("advapi32\RegOpenKeyExW", "Ptr",0x80000002, "Str","SYSTEM\CurrentControlSet\Control\MiniNT", "UInt",0, "UInt",0x20019, "Ptr*",&hKey) {
        DllCall("advapi32\RegCloseKey", "Ptr",hKey)
        cached := 1
    }
    return (cached = 1)
}

;--------------------------------------------------------------------
; 内部：把 gamma 写进**一台**显示器的 Gamma LUT
;   deviceName  形如 \\.\DISPLAY1（BaMonAtCursor 给的 Name）
;   gamma       0.05 ~ 1.00，进来先钳位
;   取值公式沿用 VistaCare 原版：Round(n * 257.0 * gamma + 0.5)
;--------------------------------------------------------------------
BgSetOneGamma(deviceName, gamma) {
    global minGammaApi
    gamma := Max(minGammaApi, Min(1.00, gamma))   ; 先钳位，别把非法值丢给显卡驱动

    ramp := Buffer(256 * 3 * 2, 0)   ; 256 项 × RGB 三通道 × 2 字节
    loop 256 {
        n := A_Index - 1
        v := Round(n * 257.0 * gamma + 0.5)
        v := Max(0, Min(65535, v))   ; 数值边界保护，防越界
        NumPut("UShort", v, ramp, n * 2)             ; R 通道
        NumPut("UShort", v, ramp, (256 + n) * 2)     ; G 通道
        NumPut("UShort", v, ramp, (512 + n) * 2)     ; B 通道
    }

    hDC := DllCall("gdi32\CreateDCW", "Str","DISPLAY", "Str",deviceName, "Ptr",0, "Ptr",0)
    if hDC {
        ok := DllCall("gdi32\SetDeviceGammaRamp", "Ptr", hDC, "Ptr", ramp) ? true : false
        DllCall("gdi32\DeleteDC", "Ptr", hDC)   ; 必须释放，否则资源泄漏
        if ok
            return true
    }

    ; 单屏时驱动偶尔不认 CreateDCW，退回桌面 DC 再试一次；
    ; 多屏时**不能**退 —— 桌面 DC 只对应主屏，退回去就变成「调 B 屏结果动了 A 屏」
    if (MonitorGetCount() > 1)
        return false
    hdcGlobal := DllCall("user32\GetDC", "Ptr", 0)
    if hdcGlobal {
        ok := DllCall("gdi32\SetDeviceGammaRamp", "Ptr", hdcGlobal, "Ptr", ramp) ? true : false
        DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", hdcGlobal)
        return ok
    }
    return false
}

;--------------------------------------------------------------------
; 内部：读某台显示器当前记录的 gamma（没记录 = 1.0）
;--------------------------------------------------------------------
BgGammaOf(name) {
    global BG_GammaMap
    return BG_GammaMap.Has(name) ? BG_GammaMap[name] : 1.0
}

;--------------------------------------------------------------------
; 内部：按步进算出该屏的新 gamma 并写进 LUT（**不弹提示**）
;   delta  正数变亮、负数变暗、0 还原到 100%，单位 %
;   BrightGamma 与 BrightAuto 共用这一层，提示交给各自的调用方，避免弹两次
;--------------------------------------------------------------------
BgApplyGamma(name, delta) {
    global BG_GammaMap, minGammaUI
    if !IsNumber(delta)
        delta := 5
    cur := BgGammaOf(name)
    cur := (delta = 0) ? 1.0 : Max(minGammaUI, Min(1.00, cur + delta / 100.0))
    BG_GammaMap[name] := cur
    return BgSetOneGamma(name, cur)
}

;--------------------------------------------------------------------
; 内部：把所有动过的屏一次还原到 100%
;   extraName  顺手也刷这台一次（当前屏即便没记录也复位，防别处残留）
;   返回 true = 至少一屏刷成功
;--------------------------------------------------------------------
BgResetAllGamma(extraName := "") {
    global BG_GammaMap
    ok := false
    if extraName {
        if BgSetOneGamma(extraName, 1.0)
            ok := true
    }
    for name in BG_GammaMap {
        if (name = extraName)
            continue
        if BgSetOneGamma(name, 1.0)
            ok := true
    }
    BG_GammaMap.Clear()
    return ok
}

;--------------------------------------------------------------------
; 内部：把**一台**屏的 Gamma 回到 100% 并从记录里抹掉（这台屏不再用 Gamma 了）
;   硬件背光接管某屏时调它，免得「Gamma 暗 + 背光暗」叠在一起越调越黑
;--------------------------------------------------------------------
BgClearGammaOne(name) {
    global BG_GammaMap
    if !BG_GammaMap.Has(name)
        return false
    BG_GammaMap.Delete(name)
    return BgSetOneGamma(name, 1.0)
}

;--------------------------------------------------------------------
; 对外：Gamma 方案（本文件里「我原本的亮度调节方式」，原 BrightAdjust）
;   delta  正数变亮、负数变暗、0 还原（**所有屏一起复位**），默认 +5
;   动作落在 BgTargets() 给的屏上（默认只有鼠标所在那块，见 BR_PerMonitor）；各屏 gamma 独立记录
;--------------------------------------------------------------------
BrightGamma(delta := 5) {
    delta := BaNum(delta, 5)
    ts := BgTargets()
    if !ts.Length {
        BaTip("亮度(Gamma):未找到显示器")
        return false
    }
    if (delta = 0) {
        ok := BgResetAllGamma(ts[1].Name)
        BaTip(ok ? "亮度(Gamma):全屏还原" : "亮度(Gamma):不可用")
        return ok
    }
    ok := false
    last := ""
    for m in ts {
        if BgApplyGamma(m.Name, delta) {
            ok := true
            last := m.Name
        }
    }
    BaTip(ok ? "亮度(Gamma):" Round(BgGammaOf(last) * 100) "%" : "亮度(Gamma):不可用")
    return ok
}

;--------------------------------------------------------------------
; 对外：还原到 100%（兼容旧接线的外壳，等价 BrightGamma(0)）
;   (*) 让它可以将来直接当 Hotkey 回调绑定，收下传进来的热键名
;--------------------------------------------------------------------
BrightGammaReset(*) {
    BrightGamma(0)
}

;--------------------------------------------------------------------
; 对外：显示器插拔 / 改分辨率后重刷当前内存里的 Gamma
;   新显示器需要重新写 LUT（记录值本身不变）；每台屏按各自记的值重刷一遍。
;   由 custom_functions.ahk 的 WM_DISPLAYCHANGE 处理器调用 —— 不在这里注册
;   OnMessage(0x007E)：同一个消息号只能挂一个回调，重复注册会把原有的顶掉
;   （这是合并前 VistaCare 顶掉自动重载处理器的老问题）。
;--------------------------------------------------------------------
BrightRefreshGamma(*) {
    global BG_GammaMap, BG_WmiTarget, BG_WmiTried
    BG_WmiTried := false, BG_WmiTarget := ""      ; 屏可能换了，WMI 定位缓存作废
    ok := false
    for name in BG_GammaMap {
        if BgSetOneGamma(name, BgGammaOf(name))
            ok := true
    }
    return ok
}

;--------------------------------------------------------------------
; 对外：**软件优先**接线 —— 先 Gamma，不可用才退遮罩（滚轮这一路）
;   delta  正数变亮、负数变暗、0 还原（Gamma 全清 + 遮罩全撤），默认 +5
;   全程**不碰显示器硬件**（DDC / WMI 都不试），要硬件档请用 BrightHw。
;   动作落在 BgTargets() 给的屏上（默认只有鼠标所在那块）。
;   判「Gamma 不可用」的两种情况：在 WinPE / WinRE 里（LUT 是空操作，连试都不用试）、
;   或写入失败（CreateDCW + SetDeviceGammaRamp 没成功）。
;--------------------------------------------------------------------
BrightAuto(delta := 5) {
    delta := BaNum(delta, 5)
    ts := BgTargets()

    if (delta = 0) {                              ; 还原：Gamma 全复位 + 遮罩全撤
        gOk := BgInWinPE() ? false : BgResetAllGamma(ts.Length ? ts[1].Name : "")
        BaMaskOff()
        BaTip(gOk ? "亮度:全屏还原" : "亮度:已还原")
        return true
    }

    if !ts.Length {
        BaTip("亮度:未找到显示器")
        return false
    }

    if !BgInWinPE() {                             ; 一级：Gamma
        last := ""
        for m in ts {
            if BgApplyGamma(m.Name, delta)
                last := m.Name
        }
        if last {
            for m in ts
                BaMaskOffOne(m.Name)              ; Gamma 接管这屏了，撤掉这屏的残留遮罩
            BaTip("亮度(Gamma):" Round(BgGammaOf(last) * 100) "%")
            return true
        }
    }
    return BrightMask(delta)                      ; 二级：遮罩兜底
}

;--------------------------------------------------------------------
; 对外：**硬件优先**接线 —— 硬件背光 -> Gamma -> 遮罩（CapsLock + `-` / `=` 这一路）
;   delta  正数变亮、负数变暗、0 还原（硬件回原始值 + Gamma 全清 + 遮罩全撤），默认 +5
;   一级硬件背光按屏选路：外接屏走 DDC/CI，内置屏走 WMI「系统亮度」；
;   两者都拿不到才退 Gamma，再不行退遮罩。
;   硬件接管某屏时会撤掉同屏的软件残留（Gamma 回 100% + 遮罩撤掉），免得叠着用越调越黑。
;--------------------------------------------------------------------
BrightHw(delta := 5) {
    delta := BaNum(delta, 5)
    ts := BgTargets()

    if (delta = 0) {                              ; 还原：硬件回原始 + Gamma 全清 + 遮罩全撤
        hOk := BgWmiReset()
        dOk := BgDdcResetAll()
        gOk := BgInWinPE() ? false : BgResetAllGamma(ts.Length ? ts[1].Name : "")
        BaMaskOff()
        BaTip((hOk || dOk || gOk) ? "亮度:全屏还原" : "亮度:已还原")
        return true
    }

    if !ts.Length {
        BaTip("亮度:未找到显示器")
        return false
    }

    got := 0
    for m in ts {                                 ; 一级：硬件背光
        r := BgDdcSet(m, delta)                   ; 外接屏：DDC/CI
        if !r
            r := BgWmiSet(m, delta)               ; 内置屏：WMI 系统亮度
        if r {
            BgClearGammaOne(m.Name)               ; 硬件接管这屏了 -> 撤掉同屏的软件残留
            BaMaskOffOne(m.Name)
            got := r.Pct
        }
    }
    if got {
        BaTip("亮度(硬件):" got "%")
        return true
    }

    if !BgInWinPE() {                             ; 二级：Gamma
        last := ""
        for m in ts {
            if BgApplyGamma(m.Name, delta)
                last := m.Name
        }
        if last {
            for m in ts
                BaMaskOffOne(m.Name)
            BaTip("亮度(Gamma):" Round(BgGammaOf(last) * 100) "%")
            return true
        }
    }
    return BrightMask(delta)                      ; 三级：遮罩兜底
}
; ====================================================================
; 方案 2：纯软件遮罩（不依赖显卡 / 显示器 API，WinPE 兜底）
;   每块显示器各挂一个独立遮罩窗口、各自记 alpha：A 屏暗着不影响 B 屏。
;   调哪块屏同样只看鼠标在哪。
; ====================================================================

; ========== 遮罩运行态（跨函数共享，必须放模块级） ==========
;   key = 显示器设备名（\\.\DISPLAY1 这种），value = {Gui, Hwnd, Alpha}
BA_Mask         := Map()
BA_CursorHidden := false                      ; 指针是否已被我们藏起（决定要不要还原）
; 系统光标资源 id（OCR_*，即 USER 资源 id 的低 16 位）：
; 32512 普通箭头 / 32513 文本 / 32514 忙 / 32515 十字 / 32516 向上 /
; 32642~32646 各方向缩放 / 32648 禁止 / 32649 手型 /
; 32650 后台忙 / 32651 帮助 / 32671 定位 / 32672 人员
BA_CursorIds    := [32512,32513,32514,32515,32516,32642,32643,32644,32645,32646,32648,32649,32650,32651,32671,32672]
BA_CursorBak    := []                         ; 藏之前的原光标私有副本，与 BA_CursorIds 同序（0 = 该形态没取到）
BG_Blank        := Buffer(4, 0)               ; 4 字节全零：CreateCursor 的 AND/XOR 掩码（全透明）

;--------------------------------------------------------------------
; 内部：藏 / 还原鼠标指针（全局）
;   系统指针由系统叠加在所有窗口之上，分层窗口也盖不住，只能让它「看不见」。
;   注意 ShowCursor 是**线程级**的显示计数：热键线程里藏了，指针一移到别的窗口，
;   别的线程一画就又冒出来 —— 实测「指针没藏住」就是这么回事（09-18），弃用。
;   正确做法 SetSystemCursor：把**系统级**各形态光标整批换成全透明光标，
;   对所有窗口、所有线程立即生效。
;   还原用 SystemParametersInfo(SPI_SETCURSORS=0x0057)：让系统按当前指针方案重新加载，
;   用户自定义的指针主题也能原样回来。
;   坑：每个 SetSystemCursor 会**销毁**传入的句柄，所以每次都要新建一个光标。
;--------------------------------------------------------------------
BaMaskCursor(hide) {
    global BA_CursorHidden, BG_Blank, BA_CursorIds, BA_CursorBak
    if (hide = BA_CursorHidden)
        return                                   ; 状态没变，别重复替换
    if hide {
        ; 换之前先把当前系统光标逐个备份：LoadCursor 给的是共享句柄，而 SetSystemCursor
        ; 会销毁传进去的句柄，所以必须 CopyIcon 出一份私有的存着，还原时才有的用。
        BA_CursorBak := []
        for id in BA_CursorIds {
            h := DllCall("user32\LoadCursorW", "Ptr",0, "Ptr",id, "Ptr")
            BA_CursorBak.Push(h ? DllCall("user32\CopyIcon", "Ptr",h, "Ptr") : 0)
        }
        ok := 0
        for id in BA_CursorIds {
            try {
                ; 末尾那个 "Ptr" 是返回类型：CreateCursor 返回 HCURSOR，省掉会被当 Int 截成 32 位
                hCur := DllCall("CreateCursor", "Ptr",0, "Int",0, "Int",0, "Int",1, "Int",1, "Ptr",BG_Blank, "Ptr",BG_Blank, "Ptr", "Ptr")
                if (hCur && DllCall("SetSystemCursor", "Ptr",hCur, "UInt",id))
                    ok++
            }
        }
        if !ok
            return                               ; 一个都没换成功就别标记「已藏」
    } else {
        ; 还原优先用备份逐个还回去，不碰注册表：SPI_SETCURSORS 要回注册表读指针方案，
        ; PE / 精简系统 / 用户配置单元没加载时会失败，光标就留在透明态再也回不来
        ;（WinPE 实测就是这个现象）。备份还原保证光标回到可见，主题再靠 SPI 兜。
        for id in BA_CursorIds {
            h := (A_Index <= BA_CursorBak.Length) ? BA_CursorBak[A_Index] : 0
            if !h
                continue
            try DllCall("SetSystemCursor", "Ptr",DllCall("user32\CopyIcon", "Ptr",h, "Ptr"), "UInt",id)
        }
        BA_CursorBak := []
        ; 再让系统按指针方案重载一次：自定义指针主题靠这一刀原样回来，失败也无害
        try DllCall("SystemParametersInfoW", "UInt",0x0057, "UInt",0, "Ptr",0, "UInt",0)
    }
    BA_CursorHidden := hide
    return
}

;--------------------------------------------------------------------
; 内部：按「现在还有没有遮罩」同步指针的藏 / 还
;   指针是系统级的：只要还剩任意一屏挂着遮罩就该藏，全撤了才还回来。
;--------------------------------------------------------------------
BaMaskCursorSync() {
    global BA_Mask, BA_MaskHideCursor, BA_MaskHideCursorInPE
    want := (BA_Mask.Count > 0) && BA_MaskHideCursor && (BA_MaskHideCursorInPE || !BgInWinPE())
    BaMaskCursor(want)
}

;--------------------------------------------------------------------
; 内部：定时重申置顶（遍历所有遮罩窗口）
;   普通置顶窗口打开时会把遮罩压下去，置顶带里没有「更置顶」，
;   只能周期性把自己重新插回带顶；点击穿透不受影响，NOACTIVATE 不抢焦点。
;   实测（09-18）：**对 Win11 开始菜单无效** —— 它是 DWM 直接合成的 XAML 表面，
;   经典窗口的 z-order 对它不起作用。而 WinPE 里本就没有开始菜单，故不必强求。
;--------------------------------------------------------------------
BaRaiseMask(*) {
    global BA_Mask
    for name in BA_Mask {
        hwnd := BA_Mask[name].Hwnd
        if !hwnd
            continue
        ; SWP_NOSIZE|SWP_NOMOVE|SWP_NOACTIVATE|SWP_NOOWNERZORDER = 0x0213
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", -1, "Int",0, "Int",0, "Int",0, "Int",0, "UInt",0x0213)
    }
}

;--------------------------------------------------------------------
; 内部：撤掉**某一块屏**的遮罩（窗口 + 该屏记录 + 指针状态）
;--------------------------------------------------------------------
BaMaskOffOne(name) {
    global BA_Mask
    if !BA_Mask.Has(name)
        return
    st := BA_Mask[name]
    BA_Mask.Delete(name)
    if st.Hwnd
        try DllCall("ShowWindow", "Ptr", st.Hwnd, "Int", 0)   ; SW_HIDE，对象丢了也能收
    if IsObject(st.Gui)
        try st.Gui.Destroy()
    if (BA_Mask.Count = 0)
        SetTimer(BaRaiseMask, 0)                  ; 全没了才停定时器
    BaMaskCursorSync()
}

;--------------------------------------------------------------------
; 内部：撤掉**所有屏**的遮罩（退出清理 / 一键还原用）
;--------------------------------------------------------------------
BaMaskOff() {
    global BA_Mask
    names := []
    for name in BA_Mask
        names.Push(name)                          ; 先抄一份 key，别边遍历边删
    for name in names
        BaMaskOffOne(name)
    SetTimer(BaRaiseMask, 0)
    BaMaskCursorSync()
}

; 退出前恢复现场，否则可能留下一个全局的隐形鼠标指针
OnExit(BaExitCleanup)

BaExitCleanup(*) {
    try BgWmiReset()                                ; 系统亮度是脚本改的，退出前还给系统
    try BgDdcResetAll()                             ; 显示器背光同理：重载会清记录，不还就一直暗
    try
        BaMaskOff()
    catch as e
        BaMaskCursor(false)
    return 0                                        ; 非零会取消退出，必须显式给 0
}

;--------------------------------------------------------------------
; 内部：给**一台**屏加减遮罩（不弹提示），delta ≠ 0
;   返回 {Alpha: 新 alpha}；建窗失败返回 0
;--------------------------------------------------------------------
BaMaskOne(m, delta) {
    global BA_Mask, BA_MaskStep, BA_MaskMax, BA_MaskRaiseMs

    st := BA_Mask.Has(m.Name) ? BA_Mask[m.Name] : 0
    cur := st ? st.Alpha : 0
    alpha := BaClamp(cur - delta * BA_MaskStep, 0, BA_MaskMax)

    if (alpha = 0) {                              ; 减到 0 -> 撤掉这屏
        BaMaskOffOne(m.Name)
        return {Alpha: 0}
    }

    ; 首次碰这块屏才建窗：置顶 + 无边框 + 点击穿透 + 不抢焦点
    if !st {
        try {
            ; 坑：Gui 窗口的「构造选项」不认 x/y/w/h —— v2 的窗口选项解析器只认
            ; Owner/AlwaysOnTop/Caption/ToolWindow/DPIScale/E<hex> 之类，冒出个 x0
            ; 就直接 ERR_INVALID_OPTION 报错；尺寸位置必须交给 Show() 才生效。
            ; -DPIScale：x/y/w/h 一律按物理像素算，与显示器矩形同一量纲。
            g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x20 +E0x08000000", "")
            g.BackColor := "000000"
            WinSetTransparent(alpha, g.Hwnd)          ; 先设透明度再显示，否则会闪一下全黑
            g.Show("NA x" m.X " y" m.Y " w" m.W " h" m.H)   ; NA = 显示但不激活，别抢前台焦点
            st := {Gui: g, Hwnd: g.Hwnd, Alpha: alpha}
            BA_Mask[m.Name] := st
            SetTimer(BaRaiseMask, BA_MaskRaiseMs)     ; 开始抢置顶：开始菜单等会把遮罩压下去
        } catch as e {
            BaErr("建窗", e)
            BaMaskOffOne(m.Name)                      ; 半途失败也要把窗口 / 定时器 / 指针收干净
            return 0
        }
    } else {
        try WinSetTransparent(alpha, st.Hwnd)
        catch as e {
            BaErr("调透明度", e)
            return 0
        }
        st.Alpha := alpha
    }

    BaMaskCursorSync()                                ; 有遮罩就藏指针（PE 下默认不藏）
    return {Alpha: alpha}
}

;--------------------------------------------------------------------
; 对外：遮罩方案（默认**只作用于鼠标所在的那块屏**，看 BR_PerMonitor）
;   delta < 0 变暗 / > 0 变亮 / = 0 撤掉遮罩（受开关影响的那几屏）
;   每屏一个窗口、各自 alpha；返回 true = 至少有一屏建出了遮罩
;--------------------------------------------------------------------
BrightMask(delta := 5) {
    delta := BaNum(delta, 5)
    ts := BgTargets()

    if (delta = 0) {                              ; 归零：一律全撤（delta=0 = 全部还原）
        BaMaskOff()
        BaTip("亮度(遮罩):关")
        return true
    }

    if !ts.Length {
        BaTip("亮度(遮罩):未找到显示器")
        return false
    }

    any := false, pct := 0
    for m in ts {
        r := BaMaskOne(m, delta)
        if (IsObject(r) && r.Alpha > 0) {
            any := true
            pct := Round(r.Alpha / 255 * 100)
        }
    }
    BaTip(any ? "亮度(遮罩):" pct "%" : "亮度(遮罩):关")
    return any
}

;--------------------------------------------------------------------
; 对外：急救 —— 把被遮罩藏起来的系统指针还回来
;   指针已经不见了、又没人自动还原（脚本被强杀 / 还原调用失败）时，键盘触发本函数即可，
;   不必重启。先把遮罩全撤掉（否则撤完指针又被逻辑藏回去），再强制走还原分支。
;--------------------------------------------------------------------
BrightCursorRestore(*) {
    global BA_CursorHidden
    BaMaskOff()
    BA_CursorHidden := true
    BaMaskCursor(false)
    BaTip("指针:已恢复")
    return true
}
; ====================================================================
; 方案 3：DDC/CI 硬件背光（dxva2.dll，VCP 0x10 = 亮度）—— BrightAuto 的第一优先
;   直接改显示器背光，不动 Gamma、不留遮罩。
;   只对**鼠标所在那台显示器**设置；delta 是「最大值百分比」步进（外接屏一般 0~100）。
;   delta = 0 -> 把**本会话调过的**屏还回原始背光（BG_DdcMap 记着），不是无脑拉满。
;
;   为什么要有「不支持」缓存：没开 DDC/CI 的屏，读 VCP 要走 I2C 等超时（几百 ms），
;   每次按键都等一遍整个热键就卡住了。所以一台屏判定取不到就记进 BG_DdcDead，
;   本会话内直接短路。代价：驱动偶发超时也会被一起记住，想再试就重载 MyKeymap。
; ====================================================================
BG_DdcMap  := Map()     ; 设备名 -> {Orig, Max, Cur}：原始背光 / 最大值 / 当前值
BG_DdcDead := Map()     ; 设备名 -> true：本会话已判定这台屏 DDC 不可用

;--------------------------------------------------------------------
; 内部：取某台屏的物理显示器句柄（dxva2）
;   m      至少要有 .Name 与 .HMon
;   返回 {N, Size, Buf}；失败返回 0 并把它记进 BG_DdcDead
;   调用方用完必须自己 DllCall("dxva2\DestroyPhysicalMonitors", "UInt",N, "Ptr",Buf.Ptr)
;--------------------------------------------------------------------
BgDdcPhys(m) {
    global BG_DdcDead
    static MAXPHYS := 8              ; 单个输出最多取多少个物理显示器

    ; dxva2.dll 不存在时直接判定不可用（WinPE 常见）
    if (!DllCall("GetModuleHandle", "Str", "dxva2.dll", "Ptr")
     && !DllCall("LoadLibrary", "Str", "dxva2.dll", "Ptr")) {
        BG_DdcDead[m.Name] := true
        return 0
    }

    n := 0
    if (!DllCall("dxva2\GetNumberOfPhysicalMonitorsFromHMONITOR", "Ptr",m.HMon, "UInt*",&n) || (n = 0)) {
        BG_DdcDead[m.Name] := true
        return 0
    }
    n := Min(n, MAXPHYS)

    size := A_PtrSize + 256          ; PHYSICAL_MONITOR：HANDLE + WCHAR 描述[128]
    buf := Buffer(size * n, 0)
    if !DllCall("dxva2\GetPhysicalMonitorsFromHMONITOR", "Ptr",m.HMon, "UInt",n, "Ptr",buf.Ptr) {
        BG_DdcDead[m.Name] := true
        return 0
    }
    return {N: n, Size: size, Buf: buf}
}

;--------------------------------------------------------------------
; 内部：对**一台**屏做 DDC 步进（不弹提示），delta ≠ 0
;   返回 {Pct: 新亮度百分比} 或 false
;   一台屏挂多个物理输出时全都设一遍（少见），提示取最后一个成功的
;--------------------------------------------------------------------
BgDdcSet(m, delta) {
    global BG_DdcMap, BG_DdcDead
    static VCP_BRIGHTNESS := 0x10

    if BG_DdcDead.Has(m.Name)
        return false
    phys := BgDdcPhys(m)
    if !phys
        return false

    st := BG_DdcMap.Has(m.Name) ? BG_DdcMap[m.Name] : 0
    done := 0, pct := -1
    loop phys.N {
        hPhys := NumGet(phys.Buf, (A_Index - 1) * phys.Size, "Ptr")   ; 结构体偏移 0
        if !hPhys
            continue
        typ := 0, cur := 0, mx := 0
        if (!DllCall("dxva2\GetVCPFeatureAndVCPFeatureReply", "Ptr",hPhys, "UChar",VCP_BRIGHTNESS, "UInt*",&typ, "UInt*",&cur, "UInt*",&mx) || (mx = 0))
            continue                                ; 这个输出不认 0x10
        newVal := BaClamp(cur + Round(mx * delta / 100.0), 0, mx)
        if DllCall("dxva2\SetVCPFeature", "Ptr",hPhys, "UChar",VCP_BRIGHTNESS, "UInt",newVal) {
            if !st
                st := {Orig: cur}                   ; 第一次碰这屏：记下原始背光，delta=0 时还它
            st.Max := mx
            st.Cur := newVal
            done++
            pct := Round(newVal * 100 / mx)
        }
    }
    DllCall("dxva2\DestroyPhysicalMonitors", "UInt", phys.N, "Ptr", phys.Buf.Ptr)

    if (done = 0) {
        BG_DdcDead[m.Name] := true                  ; 整屏都取不到 -> 别再重复等超时了
        return false
    }
    BG_DdcMap[m.Name] := st
    return {Pct: pct}
}

;--------------------------------------------------------------------
; 内部：把**本会话调过的**屏的背光还回原始值（BrightAuto(0) 与退出清理共用）
;   屏已拔掉 / 取不到的跳过；返回 true = 至少还了一台
;--------------------------------------------------------------------
BgDdcResetAll() {
    global BG_DdcMap
    static VCP_BRIGHTNESS := 0x10

    if (BG_DdcMap.Count = 0)
        return false

    hmon := Map()                                   ; 设备名 -> HMONITOR，重新枚举（屏可能变了）
    for mm in BaMonList()
        hmon[mm.Name] := mm.HMon

    done := 0
    for name, st in BG_DdcMap {
        if !hmon.Has(name)
            continue
        phys := BgDdcPhys({Name: name, HMon: hmon[name]})
        if !phys
            continue
        loop phys.N {
            hPhys := NumGet(phys.Buf, (A_Index - 1) * phys.Size, "Ptr")
            if !hPhys
                continue
            typ := 0, cur := 0, mx := 0
            if (!DllCall("dxva2\GetVCPFeatureAndVCPFeatureReply", "Ptr",hPhys, "UChar",VCP_BRIGHTNESS, "UInt*",&typ, "UInt*",&cur, "UInt*",&mx) || (mx = 0))
                continue
            if DllCall("dxva2\SetVCPFeature", "Ptr",hPhys, "UChar",VCP_BRIGHTNESS, "UInt",BaClamp(st.Orig, 0, mx))
                done++
        }
        DllCall("dxva2\DestroyPhysicalMonitors", "UInt", phys.N, "Ptr", phys.Buf.Ptr)
    }
    BG_DdcMap.Clear()
    return (done > 0)
}

;--------------------------------------------------------------------
; 对外：DDC/CI 硬件亮度（作用屏由 BgTargets() 决定：默认鼠标所在那块，见 BR_PerMonitor）
;   delta < 0 变暗 / > 0 变亮 / = 0 把调过的屏还回原始背光；默认 +5
;   返回 true = 设置成功（false 表示这屏 DDC 不可用，BrightAuto 会往后退）
;--------------------------------------------------------------------
BrightDdc(delta := 5) {
    delta := BaNum(delta, 5)
    if (delta = 0) {
        ok := BgDdcResetAll()
        BaTip(ok ? "亮度(DDC):已还原" : "亮度(DDC):无记录")
        return ok
    }
    ts := BgTargets()
    if !ts.Length {
        BaTip("亮度(DDC):未找到显示器")
        return false
    }
    ok := false
    pct := 0
    for m in ts {
        r := BgDdcSet(m, delta)
        if IsObject(r) {
            ok := true
            pct := r.Pct
        }
    }
    if !ok {
        BaTip("亮度(DDC):屏不支持")
        return false
    }
    BaTip("亮度(DDC):" pct "%")
    return true
}
; ====================================================================
; 方案 4：WMI / ACPI 背光（root\wmi）—— 笔记本内置屏的「系统亮度」
;   就是 Win 亮度滑块那条路。WMI 只暴露**内置屏**一个实例，所以必须先把内置屏
;   认到某个 \\.\DISPLAYn 上（BgWmiTargetName），否则多屏下会调错屏。
;   delta 正数变亮、负数变暗、0 还原；默认 +5；返回 true = 设置成功
; ====================================================================
BG_WmiSvc    := 0        ; 缓存的 SWbemServices（首次用时建，省得每次按键都 ConnectServer）
BG_WmiMeth   := 0        ; 缓存的 WmiMonitorBrightnessMethods 集合
BG_WmiOrig   := -1       ; 首次触碰前的原始亮度；-1 = 没记过（delta=0 还它）
BG_WmiCur    := -1       ; 脚本自己记的当前亮度
BG_WmiTarget := ""       ; WMI 能控的那块屏的设备名；空 = 没有 / 解析不出来
BG_WmiTried  := false    ; 是否已尝试解析过（含「解析不出来」）

;--------------------------------------------------------------------
; 内部：列出「适配器 -> 它挂的显示器」对应关系
;   DISPLAY_DEVICEW 布局（840 字节）：cb(4) DeviceName(32W) DeviceString(128W)
;                                    StateFlags(4) DeviceID(128W) DeviceKey(128W)
;   没挂显示器的虚拟适配器（MuMu / GameViewer 那些）自动跳过。
;--------------------------------------------------------------------
BgEnumDevices() {
    static SIZE := 840
    out := []
    i := 0
    loop {
        dd := Buffer(SIZE, 0)
        NumPut("UInt", SIZE, dd, 0)
        if !DllCall("user32\EnumDisplayDevicesW", "Ptr",0, "UInt",i, "Ptr",dd.Ptr, "UInt",0)
            break
        adp := StrGet(dd.Ptr + 4, 32, "UTF-16")
        mon := Buffer(SIZE, 0)
        NumPut("UInt", SIZE, mon, 0)
        if DllCall("user32\EnumDisplayDevicesW", "Str",adp, "UInt",0, "Ptr",mon.Ptr, "UInt",0)
            out.Push({Name: adp, MonId: StrGet(mon.Ptr + 328, 128, "UTF-16")})
        i++
    }
    return out
}

;--------------------------------------------------------------------
; 内部：WMI 能控的那块屏是哪个 \\.\DISPLAYn（结果缓存，另见 BrightRefreshGamma 里的失效）
;   WMI 的 InstanceName 形如 DISPLAY\CSO1402\5&23eb3c47&2&UID256_0，第二段就是硬件 ID；
;   拿它去比 EnumDisplayDevices 给的 MONITOR\CSO1402\{GUID}\0003 —— 这样才分得清内外屏。
;   解析不出来就回 ""：此时**不要瞎猜**，宁可不走 WMI（多屏猜错会把别的屏调了）。
;--------------------------------------------------------------------
BgWmiTargetName() {
    global BG_WmiTarget, BG_WmiTried
    if BG_WmiTried
        return BG_WmiTarget
    BG_WmiTried := true

    hw := ""
    try {
        loc := ComObject("WbemScripting.SWbemLocator")
        svc := loc.ConnectServer(".", "root\wmi")
        q := svc.ExecQuery("SELECT InstanceName FROM WmiMonitorBrightness")
        if (q.Count > 0) {
            p := StrSplit(q.ItemIndex(0).InstanceName, "\")
            if (p.Length >= 2)
                hw := p[2]
        }
    } catch {
        return BG_WmiTarget
    }

    if hw {
        for d in BgEnumDevices() {
            if InStr(d.MonId, "MONITOR\" hw "\") {
                BG_WmiTarget := d.Name
                break
            }
        }
    }
    return BG_WmiTarget
}

;--------------------------------------------------------------------
; 内部：对**一台**屏设 WMI 亮度（不弹提示），delta ≠ 0；返回 {Pct} 或 false
;   只有「鼠标这块屏 == WMI 能控的屏」才动手，别的屏一律 false（防止调错屏）
;--------------------------------------------------------------------
BgWmiSet(m, delta) {
    global BG_WmiSvc, BG_WmiMeth, BG_WmiOrig, BG_WmiCur

    if (BgWmiTargetName() != m.Name)
        return false

    if !IsObject(BG_WmiMeth) {
        try {
            loc := ComObject("WbemScripting.SWbemLocator")
            BG_WmiSvc := loc.ConnectServer(".", "root\wmi")
            q := BG_WmiSvc.ExecQuery("SELECT * FROM WmiMonitorBrightnessMethods")
            if (!IsObject(q) || (q.Count = 0))
                return false
            BG_WmiMeth := q
            b := BG_WmiSvc.ExecQuery("SELECT CurrentBrightness FROM WmiMonitorBrightness")
            if (b.Count > 0)
                BG_WmiCur := b.ItemIndex(0).CurrentBrightness
        } catch {
            return false
        }
    }

    if (!IsNumber(BG_WmiCur) || (BG_WmiCur < 0))
        BG_WmiCur := 50                           ; 读不到就从中间值起步
    if (BG_WmiOrig < 0)
        BG_WmiOrig := BG_WmiCur                   ; 第一次碰它：记下原始亮度，delta=0 时还它

    target := BaClamp(BG_WmiCur + delta, 0, 100)
    ok := 0
    loop BG_WmiMeth.Count {
        try {
            BG_WmiMeth.ItemIndex(A_Index - 1).WmiSetBrightness(1, target)
            ok++
        }
    }
    if !ok
        return false
    BG_WmiCur := target
    return {Pct: target}
}

;--------------------------------------------------------------------
; 内部：把 WMI 亮度还回原始值；返回 true = 还成功
;--------------------------------------------------------------------
BgWmiReset() {
    global BG_WmiMeth, BG_WmiOrig, BG_WmiCur
    if (BG_WmiOrig < 0) || !IsObject(BG_WmiMeth)
        return false
    ok := 0
    loop BG_WmiMeth.Count {
        try {
            BG_WmiMeth.ItemIndex(A_Index - 1).WmiSetBrightness(1, BG_WmiOrig)
            ok++
        }
    }
    BG_WmiCur := BG_WmiOrig
    BG_WmiOrig := -1
    return (ok > 0)
}

;--------------------------------------------------------------------
; 对外：WMI 系统亮度（**只对内置屏有效**；作用屏由 BgTargets() 决定，默认鼠标所在那块）
;   delta < 0 变暗 / > 0 变亮 / = 0 还回原始亮度；默认 +5
;--------------------------------------------------------------------
BrightWmi(delta := 5) {
    delta := BaNum(delta, 5)
    if (delta = 0) {
        ok := BgWmiReset()
        BaTip(ok ? "亮度(WMI):已还原" : "亮度(WMI):无记录")
        return ok
    }
    ts := BgTargets()
    if !ts.Length {
        BaTip("亮度(WMI):未找到显示器")
        return false
    }
    ok := false
    pct := 0
    for m in ts {
        r := BgWmiSet(m, delta)
        if IsObject(r) {
            ok := true
            pct := r.Pct
        }
    }
    if !ok {
        BaTip(BgWmiTargetName() ? "亮度(WMI):非内置屏" : "亮度(WMI):不可用")
        return false
    }
    BaTip("亮度(WMI):" pct "%")
    return true
}
