;====================================================================
; 亮度调节（Gamma / 遮罩 / 硬件背光）  —— MyKeymap2 自定义函数
;
; 本文件由原 VistaCare.ahk（Gamma 方案）与 BrightAlt.ahk（备用方案）合并而成
; （2026-09-18）。合并原因：两文件各注册各的提示与消息处理器、配置散在两处，
; 且 VistaCare 的 OnMessage(0x007E) 会把 custom_functions.ahk 里的同名注册顶掉。
; 现在全部亮度逻辑只在这一个文件里。
;
; 三层方案，从「最自然」到「最兜底」：
;
; 1) Gamma（写显卡 LUT）—— 原 VistaCare 方案，即 BrightGamma()
;    调 gdi32 SetDeviceGammaRamp 改显示器 Gamma 曲线。
;    优点：作用在**显示层**，屏幕上所有内容（含鼠标指针、开始菜单、任意窗口）
;          会一起变亮变暗。
;    缺点：WinPE / 只有 BasicDisplay 驱动时**不报错也不生效**（空操作，屏幕毫无反应）。
;
; 2) 遮罩（纯软件，全屏分层窗口）—— 原 BrightAlt 方案，即 BrightMask()
;    全屏黑色置顶分层窗口 + 全局 alpha，不碰任何显卡 / 显示器 API，WinPE 下最可能可用。
;    指针：分层窗口盖不住系统指针（指针叠在所有窗口之上），SetSystemCursor 把系统光标
;          全局换成全透明光标来「藏住」（ShowCursor 是线程级的，弃用，见 BaMaskCursor）。
;    边界：只能变暗；开始菜单是 DWM 直接合成的 XAML 表面，用户态窗口盖不住（09-18 实测）；
;          安全桌面（UAC / Ctrl+Alt+Del）、独占全屏程序同理。
;          补充：WinPE 里本就没有开始菜单，而正常 Windows 下用 Gamma 方案连指针一起暗，
;          故这两条边界不影响实际使用。
;
; 3) 硬件背光（与上面两条互不干扰）—— BrightDdc() / BrightWmi()
;    直接改显示器背光，不走 Gamma 也不走遮罩。
;
; 对外函数（都不自带热键，全部由 keymap 调用；delta 语义统一）：
;   delta < 0 变暗 / delta > 0 变亮 / delta = 0 还原；默认 +5；都返回 true / false
;
;   BrightAuto(delta := 5)      **推荐接线**：先试 Gamma，不可用就退到遮罩
;   BrightGamma(delta := 5)     Gamma 方案（原 BrightAdjust，本文件里的「我原本的方式」）
;   BrightGammaReset(*)         还原到 100%，等价 BrightGamma(0)
;   BrightRefreshGamma(*)       显示器插拔 / 改分辨率后重刷 Gamma（由 custom_functions 调用）
;   BrightMask(delta := 5)      纯软件遮罩
;   BrightDdc(delta := 5)       DDC/CI 硬件背光（外接屏）
;   BrightWmi(delta := 5)       ACPI 背光（笔记本内置屏）
;
; 命名约定：
;   对外函数 PascalCase 不带前缀；
;   内部辅助：Gamma / 显示器相关走 Bg 前缀，遮罩相关走 Ba 前缀；
;   模块级变量：BG_ / BA_ 前缀。
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
gammaLevel  := 1.0      ; 当前 Gamma（内存态，脚本重启回到 1.0）

; --- 遮罩方案 ---
BA_MaskStep := 14                            ; 遮罩每级 alpha（0~255），越小越细腻
BA_MaskMax  := 216                           ; 遮罩上限，留余量避免全黑到没法操作
BA_MaskHideCursor := true                    ; 遮罩期间藏起鼠标指针（系统指针遮不住只能藏）
BA_MaskRaiseMs    := 250                     ; 重申置顶间隔 ms；对普通置顶窗口有效，对开始菜单无效

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
;   text  提示文字，尽量短（量级参考：遮罩:50% / Gamma:不可用）
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
    BaTip("遮罩:失败-" where " " SubStr(e.Message, 1, 16))
}

; ====================================================================
; 方案 1：Gamma（写显卡 LUT）—— 原 VistaCare 方案
; ====================================================================

;--------------------------------------------------------------------
; 内部：枚举显示器设备（DISPLAY_DEVICEA 结构，424 字节）
;   i     显示器索引，从 0 开始
;   返回  {DeviceName, StateFlags}；没有更多设备时返回 false
;--------------------------------------------------------------------
BgEnumDisp(i) {
    static buf := Buffer(424, 0)   ; 静态缓冲复用，不每轮分配
    NumPut("UInt", 424, buf, 0)    ; 结构体 cb 字段
    res := DllCall("user32\EnumDisplayDevicesA", "Ptr",0, "UInt",i, "Ptr",buf, "UInt",0)
    if !res
        return false
    devName := StrGet(buf.Ptr + 4, 32, "CP0")   ; 偏移 4：设备名
    stateFlags := NumGet(buf, 164, "UInt")      ; 偏移 164：状态标志
    return {DeviceName:devName, StateFlags:stateFlags}
}

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
; 内部：把 gamma 写进所有已连接显示器的 Gamma LUT
;   gamma  0.05 ~ 1.00，进来先钳位
;   取值公式沿用 VistaCare 原版：Round(n * 257.0 * gamma + 0.5)
;   返回 true = 至少有一台显示器写成功（注意：WinPE 下可能返回 true 但实际不生效）
;--------------------------------------------------------------------
BgSetAllGamma(gamma) {
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

    anySuccess := false   ; 是否至少有一台显示器设置成功
    i := 0
    while (disp := BgEnumDisp(i)) {
        i++
        isAttached := (disp.StateFlags & 0x1) != 0   ; 已连接
        isMirror := (disp.StateFlags & 0x8) != 0     ; 镜像屏跳过（会和主屏互相覆盖）
        if (isAttached && !isMirror) {
            hDC := DllCall("gdi32\CreateDCW", "Str","DISPLAY", "Str",disp.DeviceName, "Ptr",0, "Ptr",0)
            if (hDC) {
                if DllCall("gdi32\SetDeviceGammaRamp", "Ptr", hDC, "Ptr", ramp)
                    anySuccess := true
                DllCall("gdi32\DeleteDC", "Ptr", hDC)   ; 必须释放，否则资源泄漏
            }
        }
    }

    ; 上面全失败时，退回桌面 DC 再试一次
    if !anySuccess {
        hdcGlobal := DllCall("user32\GetDC", "Ptr", 0)
        if (hdcGlobal) {
            anySuccess := DllCall("gdi32\SetDeviceGammaRamp", "Ptr", hdcGlobal, "Ptr", ramp) ? true : false
            DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", hdcGlobal)
        }
    }
    return anySuccess
}

;--------------------------------------------------------------------
; 内部：按步进算出新 gammaLevel 并写入 LUT（**不弹提示**）
;   delta  正数变亮、负数变暗、0 还原到 100%，单位 %
;   返回 BgSetAllGamma 的结果（是否至少一台写成功）
;   BrightGamma 与 BrightAuto 共用这一层，提示交给各自的调用方，避免弹两次
;--------------------------------------------------------------------
BgApplyGamma(delta) {
    global gammaLevel, minGammaUI
    if !IsNumber(delta)
        delta := 5
    gammaLevel := (delta = 0) ? 1.0 : Max(minGammaUI, Min(1.00, gammaLevel + delta / 100.0))
    return BgSetAllGamma(gammaLevel)
}

;--------------------------------------------------------------------
; 对外：Gamma 方案（本文件里「我原本的亮度调节方式」，原 BrightAdjust）
;   delta  正数变亮、负数变暗、0 还原，默认 +5
;   返回 true = 已写入；false = 一台显示器都没写成（多半是 WinPE / 只有 BasicDisplay）
;--------------------------------------------------------------------
BrightGamma(delta := 5) {
    global gammaLevel
    ok := BgApplyGamma(delta)
    if ok
        BaTip("亮度:" Round(gammaLevel * 100) "%")
    else
        BaTip("Gamma:不可用")
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
;   新显示器需要重新写 LUT（内存值本身不变）。
;   由 custom_functions.ahk 的 WM_DISPLAYCHANGE 处理器调用 —— 不在这里注册
;   OnMessage(0x007E)：同一个消息号只能挂一个回调，重复注册会把原有的顶掉
;   （这是合并前 VistaCare 顶掉自动重载处理器的老问题）。
;--------------------------------------------------------------------
BrightRefreshGamma(*) {
    global gammaLevel
    return BgSetAllGamma(gammaLevel)
}

;--------------------------------------------------------------------
; 对外：**推荐接线** —— 先试 Gamma，不可用就退到遮罩
;   delta  正数变亮、负数变暗、0 还原，默认 +5
;   判定「Gamma 不可用」的两种情况：
;     a) 在 WinPE / WinRE 里 —— Gamma LUT 是空操作，连试都不用试
;     b) 一台显示器都没写成功（BgSetAllGamma 返回 false）
;   Gamma 可用时若发现还残留着遮罩，顺手撤掉，免得两套状态打架。
;--------------------------------------------------------------------
BrightAuto(delta := 5) {
    global gammaLevel, BA_MaskHwnd
    if (!BgInWinPE() && BgApplyGamma(delta)) {
        if BA_MaskHwnd                        ; Gamma 接管了，把可能残留的遮罩撤掉
            BaMaskOff()
        BaTip("亮度:" Round(gammaLevel * 100) "%")
        return true
    }
    return BrightMask(delta)
}

; ====================================================================
; 方案 2：纯软件遮罩（不依赖显卡 / 显示器 API，WinPE 兜底）
; ====================================================================

; ========== 遮罩运行态（跨函数共享，必须放模块级） ==========
BA_MaskGui      := 0                          ; Gui 对象（留住，被回收会连带销毁窗口）
BA_MaskHwnd     := 0                          ; 同一窗口的 hwnd，给定时器用
BA_MaskAlpha    := 0                          ; 当前遮罩 alpha
BA_CursorHidden := false                      ; 指针是否已被我们藏起（决定要不要还原）
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
    global BA_CursorHidden, BG_Blank
    if (hide = BA_CursorHidden)
        return                                   ; 状态没变，别重复替换
    if hide {
        ; 下面这些是系统光标的资源 id（OCR_*，即 USER 资源 id 的低 16 位）
        ; 32512 普通箭头 / 32513 文本 / 32514 忙 / 32515 十字 / 32516 向上 /
        ; 32642~32646 各方向缩放 / 32648 禁止 / 32649 手型 /
        ; 32650 后台忙 / 32651 帮助 / 32671 定位 / 32672 人员
        ok := 0
        for id in [32512,32513,32514,32515,32516,32642,32643,32644,32645,32646,32648,32649,32650,32651,32671,32672] {
            try {
                hCur := DllCall("CreateCursor", "Ptr",0, "Int",0, "Int",0, "Int",1, "Int",1, "Ptr",BG_Blank, "Ptr",BG_Blank, "Ptr")
                if (hCur && DllCall("SetSystemCursor", "Ptr",hCur, "UInt",id))
                    ok++
            }
        }
        if !ok
            return                               ; 一个都没换成功就别标记「已藏」
    } else {
        try DllCall("SystemParametersInfoW", "UInt",0x0057, "UInt",0, "Ptr",0, "UInt",0)
    }
    BA_CursorHidden := hide
    return
}

;--------------------------------------------------------------------
; 内部：定时重申置顶
;   普通置顶窗口打开时会把遮罩压下去，置顶带里没有「更置顶」，
;   只能周期性把自己重新插回带顶；点击穿透不受影响，NOACTIVATE 不抢焦点。
;   实测（09-18）：**对 Win11 开始菜单无效** —— 它是 DWM 直接合成的 XAML 表面，
;   经典窗口的 z-order 对它不起作用。而 WinPE 里本就没有开始菜单，故不必强求。
;--------------------------------------------------------------------
BaRaiseMask(*) {
    global BA_MaskHwnd
    if !BA_MaskHwnd
        return
    ; SWP_NOSIZE|SWP_NOMOVE|SWP_NOACTIVATE|SWP_NOOWNERZORDER = 0x0213
    DllCall("SetWindowPos", "Ptr", BA_MaskHwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x0213)
}

;--------------------------------------------------------------------
; 内部：撤掉遮罩，并把附带效果一起收回（窗口 / 定时器 / 藏起来的指针）
;--------------------------------------------------------------------
BaMaskOff() {
    global BA_MaskGui, BA_MaskHwnd, BA_MaskAlpha
    SetTimer(BaRaiseMask, 0)                        ; 先停定时器，免得对已销毁的窗口发 SetWindowPos
    if BA_MaskHwnd {
        try DllCall("ShowWindow", "Ptr", BA_MaskHwnd, "Int", 0)   ; SW_HIDE，对象丢了也能收
        BA_MaskHwnd := 0
    }
    if IsObject(BA_MaskGui) {
        try BA_MaskGui.Destroy()
        BA_MaskGui := 0
    }
    BA_MaskAlpha := 0
    BaMaskCursor(false)                             ; 系统指针还回来
    return
}

; 退出前恢复现场，否则可能留下一个全局的隐形鼠标指针
OnExit(BaExitCleanup)

BaExitCleanup(*) {
    try
        BaMaskOff()
    catch as e
        BaMaskCursor(false)
    return 0                                        ; 非零会取消退出，必须显式给 0
}

;--------------------------------------------------------------------
; 对外：遮罩方案
;   delta < 0 变暗 / > 0 变亮 / = 0 撤掉遮罩
;   返回 true（本方案只看能否建出窗口）
;--------------------------------------------------------------------
BrightMask(delta := 5) {
    global BA_MaskStep, BA_MaskMax, BA_MaskAlpha, BA_MaskGui, BA_MaskHwnd
    global BA_MaskHideCursor, BA_MaskRaiseMs

    delta := BaNum(delta, 5)
    alpha := (delta = 0) ? 0 : BaClamp(BA_MaskAlpha - delta * BA_MaskStep, 0, BA_MaskMax)

    ; 归零 -> 撤窗口 + 停抢置顶 + 指针还回来
    if (alpha = 0) {
        BaMaskOff()
        BaTip("遮罩:关")
        return true
    }

    ; 首次调用时建全屏遮罩：置顶 + 无边框 + 点击穿透 + 不抢焦点
    if (!BA_MaskHwnd) {
        try {
            x := SysGet(76)          ; 虚拟桌面左上（多屏合并）
            y := SysGet(77)
            w := SysGet(78)          ; 虚拟桌面宽高
            h := SysGet(79)
            if (w <= 0 || h <= 0) {  ; 取不到就退回主屏，不让窗口退化成一个点
                x := 0
                y := 0
                w := A_ScreenWidth
                h := A_ScreenHeight
            }
            ; 坑：Gui 窗口的「构造选项」不认 x/y/w/h —— v2 的窗口选项解析器只认
            ; Owner/AlwaysOnTop/Caption/ToolWindow/DPIScale/E<hex> 之类，冒出个 x0
            ; 就直接 ERR_INVALID_OPTION 报错；而尺寸位置必须交给 Show() 才生效，
            ; 只在构造里写尺寸更糟：不报错，但首次 Show 会按「无控件」缩成屏幕中央一个小方块
            g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x20 +E0x08000000", "")
            g.BackColor := "000000"
            WinSetTransparent(alpha, g.Hwnd)          ; 先设透明度再显示，否则会闪一下全黑
            g.Show("NA x" x " y" y " w" w " h" h)     ; NA = 显示但不激活，别抢前台焦点
            BA_MaskGui := g
            BA_MaskHwnd := g.Hwnd
            SetTimer(BaRaiseMask, BA_MaskRaiseMs)     ; 开始抢置顶：开始菜单等会把遮罩压下去
            if BA_MaskHideCursor
                BaMaskCursor(true)                    ; 系统指针遮不住，只能藏
        } catch as e {
            BaErr("建窗", e)
            BaMaskOff()                               ; 半途失败也要把窗口 / 定时器 / 指针收干净
            return false
        }
    }

    try WinSetTransparent(alpha, BA_MaskHwnd)
    catch as e {
        BaErr("调透明度", e)
        return false
    }
    BA_MaskAlpha := alpha
    BaTip("遮罩:" Round(alpha / 255 * 100) "%")
    return true
}

; ====================================================================
; 方案 3：DDC/CI 硬件亮度（dxva2.dll，VCP 0x10 = 亮度）
;   直接改显示器背光，与 Gamma、遮罩都无关，可独立接线做对比
;   delta 为百分比步进 / = 0 恢复到 100%
;   返回 true = 至少一台显示器设置成功
; ====================================================================
BrightDdc(delta := 5) {
    global BA_Mons
    static VCP_BRIGHTNESS := 0x10
    static MAXPHYS := 8           ; 单个输出最多取多少个物理显示器

    delta := BaNum(delta, 5)

    ; dxva2.dll 不存在时直接报出来（WinPE 常见）
    dllPtr := DllCall("GetModuleHandle", "Str", "dxva2.dll", "Ptr")
    if (!dllPtr && !DllCall("LoadLibrary", "Str", "dxva2.dll", "Ptr")) {
        BaTip("DDC:无 dxva2.dll")
        return false
    }

    ; 收集显示输出句柄
    BA_Mons := []
    cb := CallbackCreate(BaEnumMon, "Fast", 4)
    DllCall("user32\EnumDisplayMonitors", "Ptr", 0, "Ptr", 0, "Ptr", cb, "Ptr", 0)
    CallbackFree(cb)
    if (BA_Mons.Length = 0) {
        BaTip("DDC:未找到显示器")
        return false
    }

    monSize := A_PtrSize + 256    ; PHYSICAL_MONITOR：HANDLE + WCHAR 描述[128]
    buf := Buffer(monSize * MAXPHYS, 0)
    done := 0, fail := 0, pct := -1

    for hMon in BA_Mons {
        n := 0
        gotN := DllCall("dxva2\GetNumberOfPhysicalMonitorsFromHMONITOR", "Ptr", hMon, "UInt*", &n)
        if (!gotN || (n = 0))
            continue
        n := Min(n, MAXPHYS)
        if !DllCall("dxva2\GetPhysicalMonitorsFromHMONITOR", "Ptr", hMon, "UInt", n, "Ptr", buf.Ptr)
            continue

        loop n {
            hPhys := NumGet(buf, (A_Index - 1) * monSize, "Ptr")   ; 结构体偏移 0
            if !hPhys
                continue
            typ := 0, cur := 0, mx := 0
            gotVcp := DllCall("dxva2\GetVCPFeatureAndVCPFeatureReply", "Ptr", hPhys, "UChar", VCP_BRIGHTNESS, "UInt*", &typ, "UInt*", &cur, "UInt*", &mx)
            if (!gotVcp || (mx = 0)) {
                fail++
                continue
            }
            newVal := (delta = 0) ? mx : BaClamp(cur + Round(mx * delta / 100.0), 0, mx)
            if DllCall("dxva2\SetVCPFeature", "Ptr", hPhys, "UChar", VCP_BRIGHTNESS, "UInt", newVal) {
                done++
                pct := Round(newVal * 100 / mx)
            } else
                fail++
        }
        DllCall("dxva2\DestroyPhysicalMonitors", "UInt", n, "Ptr", buf.Ptr)
    }

    if (done = 0) {
        BaTip(fail ? "DDC:屏不支持" : "DDC:无物理屏")
        return false
    }
    BaTip("亮度(DDC):" pct "%")
    return true
}

;--------------------------------------------------------------------
; 内部：EnumDisplayMonitors 回调，收集显示器句柄
;--------------------------------------------------------------------
BaEnumMon(hMon, hdc, lprc, lParam) {
    global BA_Mons
    BA_Mons.Push(hMon)
    return 1     ; 返回 1 继续枚举
}

; ====================================================================
; 方案 4：ACPI 背光（root\wmi，笔记本内置屏）
;   delta 为百分比步进 / = 0 恢复到 100%
;   返回 true = 设置成功
; ====================================================================
BrightWmi(delta := 5) {
    static cur := -1              ; 缓存读到的当前亮度，-1 表示未知

    delta := BaNum(delta, 5)

    try {
        loc := ComObject("WbemScripting.SWbemLocator")
        svc := loc.ConnectServer(".", "root\wmi")
        methods := svc.ExecQuery("SELECT * FROM WmiMonitorBrightnessMethods")
    } catch as e {
        BaTip("WMI:不可用")
        return false
    }
    if !IsObject(methods) || (methods.Count = 0) {
        BaTip("WMI:无背光接口")
        return false
    }

    ; 读当前亮度；读到的可能是非数字（老驱动 / PE 下常见），一律当未知处理
    if !IsNumber(cur) || (cur < 0) {
        try {
            q := svc.ExecQuery("SELECT CurrentBrightness FROM WmiMonitorBrightness")
            if (q.Count > 0)
                cur := q.ItemIndex(0).CurrentBrightness
        }
    }
    if !IsNumber(cur) || (cur < 0)
        cur := 50                 ; 读不到就从中间值起步

    target := (delta = 0) ? 100 : BaClamp(cur + delta, 0, 100)

    ok := 0
    loop methods.Count {
        try {
            methods.ItemIndex(A_Index - 1).WmiSetBrightness(1, target)
            ok++
        }
    }
    if (ok = 0) {
        BaTip("WMI:设置失败")
        return false
    }
    cur := target
    BaTip("亮度(WMI):" target "%")
    return true
}
