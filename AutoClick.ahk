;====================================================================
; 自动连点 AHK v2   —— MyKeymap2 自定义函数
;
; 一个文件，两套实现：
;   front（前台）  用 MouseClick 真挪光标去点。什么程序都能点，代价是连点期间鼠标被占。
;   bg   （后台）  用 PostMessage 往目标窗口投鼠标消息。光标一动不动、焦点不变，
;                  但只对「自己处理鼠标消息」的程序有效 —— 限制见后半段开头。
;
; 对外 5 个入口 + 1 个旧名兼容：
;   AutoClickToggle()                 按「设置界面」存下来的参数 开 / 停（主入口）
;   AutoClickSettings()               弹设置界面；改完写盘，下次 AutoClickToggle 就按新的来
;   AutoClick(followCursor, button, interval, cancelOnMove, target, backend, tipMode)
;       开/关连点，再调一次 = 停（哪个后端在跑就停哪个）。
;   AutoClickStop(reason)             显式停止，两个后端都停
;   AutoClickProbe(button, target)    bg 的单发试针：按一次只发一组消息，并把
;                                     命中窗口信息写进日志，用来判断"窗口选错了"
;                                     还是"程序不吃消息"
;   AutoClickBg(...)                  旧名兼容，等价于 backend="bg"
;
; 参数（顺序：跟随、按键、延迟、移动取消、目标、后端）：
;   followCursor  是否跟随鼠标连点，默认 false
;                   false = 固定在启动时的位置；true = 每周期重新取光标位置
;                   【注意】跟随为 true 时 cancelOnMove 没有意义，会被忽略
;   button        连哪个键，默认 "L"
;                   "L" 左键 / "M" 中键 / "R" 右键（只看首字母，不分大小写，
;                   写 "Left" / "Middle" / "Right" 也一样）
;   interval      连点间隔(ms)，默认 50，自动钳到 [1, 60000]
;   cancelOnMove  鼠标移动后是否取消连点，默认 false
;                   false = 移动了也继续点；true = 离开起点超过阈值就自动停
;   target        仅 backend="bg"：0/空 = 光标下的窗口；数字 = 窗口句柄；
;                   字符串 = 窗口标题 / ahk_exe xxx 之类
;   backend       "front"（默认）/ "bg"
;   tipMode       浮窗档位 "persist"（常驻，默认）/ "fade"（2 秒自消）/ "off"（不显示）
;                   不写 = 用设置文件里的档位
;
;   【参数只有"写了"才生效】默认值写在函数签名里，调用处不写就等于用默认。
;   所以要"鼠标一动就停"必须把第 4 个参数写成 true：
;       AutoClick(false, "L", 50, true)
;
; 当前接线（data/config.json）：
;   【Tab 模式】*LCtrl -> AutoClickToggle()     按设置开 / 停（主入口）
;              *LWin  -> AutoClickSettings()   设置界面
;   【CapsLock】*p     -> AutoClickBg(false, "L", 50, false)   后台左键 50ms（旧名写法，仍有效）
;              *LAlt  -> AutoClick(false, "R", 50, false)     前台右键（临时预设）
;              *LWin  -> AutoClick(false, "L", 50, true)      前台左键 + 移动就停（临时预设）
;              *LCtrl -> AutoClick(false, "L", 50, false)     前台左键（临时预设）
;   再按一次同一个键 = 停止。
;
; 更多用法：
;   AutoClick()                                  全默认：前台 / 左键 / 当前点 / 50ms
;   AutoClick(false, "M", 50, true)              前台中键，鼠标一动就停
;   AutoClick(false, "L", 50, false, 0, "bg")    后台左键，点光标下的窗口
;   AutoClick(false, "L", 50, false, 123456)     后台左键，点句柄 0x1E240
;   AutoClickProbe("L")                          后台试针（先验目标吃不吃消息）
;
; 提示：贴在点击位置旁边（不是屏幕角），显示时长由「浮窗」档位决定：
;   persist 常驻（默认）  启动提示一直挂到按停止；停止后换成 连点器[停止]，2 秒自清
;   fade    短暂          2 秒自消（旧行为）
;   off     关闭          不弹启动/停止提示 —— 但"没找到窗口"这类**错误提示照弹**
;   前台  连点器[前台]（启动） / 连点器[停止]          —— ToolTip 通道 1
;   后台  连点器[后台]（启动） / 连点器[停止]          —— ToolTip 通道 AC_BgTipNo(6)
;   两条流水线各用各的通道，同时跑也不会互相清掉提示。
;
; 设置文件：<本模块目录>\scripts\autoclick.cfg（UTF-8 无 BOM，一行一条 key=value）
;   backend=front|bg   button=L|M|R   interval=1..60000
;   follow=0|1         cancelMove=0|1  tipMode=persist|fade|off
;   文件不存在 / 某项认不出 = 用内置默认；手改也行，AutoClickToggle 每次都重读（不用重载脚本）。
;   ⚠ 不用 IniWrite：它新建文件的编码不受控，会破坏本仓"UTF-8 无 BOM"的规矩。
;
; 说明：
;   1. 用 SetTimer 驱动，不阻塞脚本主线程，不影响 MyKeymap 其他热键
;   2. 间隔是"至少 N 毫秒"：AHK 定时器精度约 10~16ms，填小于 10 也不会更快
;   3. MyKeymap 重载 / 退出会重置状态，连点自动中断，不会遗留定时器
;   4. 命名：对外一律 PascalCase 不带前缀（AutoClick / AutoClickStop / AutoClickProbe）；
;      内部函数走 Ac 前缀（AcTip、AcFrontTick…），模块级变量 AC_ 打头；
;      后台专用的再叠一层 Bg：AC_BgHwnd / AcBgClickAt —— 一眼分清哪条流水线。
;
; 【坑 1】MouseClick 的 Speed 参数不能填 0（只影响前台后端）
;   0 的本意是"瞬移 + 最快"。但在 MyKeymap 的运行环境里
;   （SendMode Event + SetMouseDelay 0 + #UseHook true），Speed=0 会让这次调用
;   彻底空转：光标不动、点击事件一个都不发。本机 AHK v2.0.19 实测（同点循环 10 次）：
;       MouseClick("Left", x, y, 0)   -> 命中 0/10     ← "连点没反应"的根因之一
;       MouseClick("Left", x, y, 1)   -> 命中 10/10（50ms / 500ms 都是 10/10）
;   所以速度写死 AC_ClickSpeed = 1，别为了"再快一点"改回 0。
;
; 【坑 2】函数里要赋值的状态变量，一个都不能漏进 global
;   AHK v2 里函数读全局变量不用声明，但赋值会新建一个"同名局部变量"。漏声明的后果
;   完全静默：本文件曾经因为 AutoClick 的 global 列表漏了 AC_X / AC_Y，
;   AC_X := mx 建出局部变量、全局 AC_X 恒为 0，于是前台连点一直往屏幕左上角
;   (0,0) 点 —— 表现同样是"连点完全没反应"。加变量时请顺手加进 global，
;   加 AC_Bg* 状态时同样要确认在 global 里。
;
; 【坑 3】SetTimer 传 .Bind() 出来的绑定函数，必须自己存下来
;   AcTip 的自动清除用 AcTipClear.Bind(tipNo)。.Bind() 每次都会造一个**新对象**，
;   同一个 tipNo 再 Bind 一次拿到的不是同一个定时器 —— 不把绑定对象存进
;   AC_TipTimers 就取消不掉，提示会永远黏在屏幕上。
;====================================================================

; ========== 前台 / 共享：配置参数 ==========
AC_Interval      := 50     ; 默认连点间隔(ms)
AC_Button        := "L"    ; 默认按钮：L 左键 / M 中键 / R 右键
AC_CancelOnMove  := false  ; 默认：鼠标移动后不取消
AC_FollowCursor  := false  ; 默认：固定在启动位置
AC_ClickSpeed    := 1      ; 点击速度，最小 1，绝不能为 0（见文件头【坑 1】）
AC_IntervalMin   := 1      ; 间隔下限保护
AC_IntervalMax   := 60000  ; 间隔上限保护
AC_MoveThreshold := 5      ; 判定"鼠标动了"的像素阈值
AC_BgTipNo       := 6      ; 后台提示专用的 ToolTip 通道号，避开前台(1)与亮度(5)
AC_TipTimers     := 0      ; 提示自动清除的定时器表(tipNo -> 绑定函数)，首次用时建成 Map
AC_TipMs         := 2000   ; 提示停留时长(ms)
AC_TipGap        := 16     ; 提示相对连点位置的偏移(px)，避开点击点本身
AC_TipEstW       := 190    ; 提示预估宽(px)，只用于贴边时翻方向（前台/后台共用，取宽的那个）
AC_TipEstH       := 46     ; 提示预估高(px)，两行提示，同上

; ========== 设置文件（AutoClickToggle / AutoClickSettings 用） ==========
AC_CfgName       := "autoclick.cfg"  ; 落在 <模块目录>\scripts\ 下（发布仓 .gitignore 已忽略）
AC_CfgPath       := ""     ; 完整路径，懒算一次，见 AcCfgPath()
AC_Home          := ""     ; 本模块目录，懒算一次，见 AcHomeDir()
AC_TipMode       := ""     ; 当前浮窗档位 persist / fade / off，见 AcTipModeGet()
AC_TipModeLoaded := false  ; 是否已从设置文件读过档位

; ========== 前台：内部状态 ==========
AC_Running := false        ; 是否正在连点
AC_X := 0                  ; 固定点击坐标 X(屏幕坐标)
AC_Y := 0                  ; 固定点击坐标 Y(屏幕坐标)

;--------------------------------------------------------------------
; 数值钳位：把 v 限制在 [lo, hi]
;--------------------------------------------------------------------
AcClamp(v, lo, hi) {
    if (v < lo)
        return lo
    if (v > hi)
        return hi
    return v
}

;--------------------------------------------------------------------
; "L" / "M" / "R"（或 Left / Middle / Right）-> AHK 的按钮名
; 认不出来的一律当左键，不让一个手滑的参数把功能搞没
;--------------------------------------------------------------------
AcButton(name) {
    switch StrUpper(SubStr(Trim(String(name)), 1, 1)) {
        case "M": return "Middle"
        case "R": return "Right"
        default:  return "Left"
    }
}

;--------------------------------------------------------------------
; 同上，给提示用的中文短标签
;--------------------------------------------------------------------
AcButtonLabel(name) {
    switch AcButton(name) {
        case "Middle": return "中键"
        case "Right":  return "右键"
        default:       return "左键"
    }
}

;--------------------------------------------------------------------
; 提示文案（单独抽出来，方便改字 / 方便测）
;   启动：  连点器[前台]
;           左键(50ms)          <- 跟随模式会在后面接 " 跟随"
;   停止：  连点器[停止]        <- 前台/后台、正常停/自动停，文案都一样
;--------------------------------------------------------------------
AcStartText() {
    t := "连点器[前台]`n" AcButtonLabel(AC_Button) "(" AC_Interval "ms)"
    if (AC_FollowCursor)
        t .= " 跟随"
    return t
}

; reason 仍由调用方传（将来要记日志可用），但不再拼进提示
AcStopText(reason := "") {
    return "连点器[停止]"
}

;--------------------------------------------------------------------
; 弹提示，贴在 (ax, ay) 这个位置旁边；tipNo 选 ToolTip 通道
;   - 偏移 AC_TipGap，保证提示窗口不压在点击点上（否则可能挡住自己的点击）
;   - 贴到屏幕右 / 下边界外时翻到反方向，再兜底夹进屏幕内
;   - 存 / 还原 CoordMode，不污染 MyKeymap 的全局设置
;   - AC_TipMs 后自动消失；persist=true 则不挂这个定时器（浮窗常驻档用）
;   - 同一通道的新提示会顶掉上一次的自动清除（所以"常驻 -> 停止"能自然收尾）
;--------------------------------------------------------------------
AcTip(text, ax, ay, tipNo := 1, persist := false) {
    global AC_TipMs, AC_TipGap, AC_TipEstW, AC_TipEstH, AC_TipTimers
    oldMode := A_CoordModeToolTip
    CoordMode("ToolTip", "Screen")

    tx := ax + AC_TipGap
    ty := ay + AC_TipGap
    if (tx + AC_TipEstW > A_ScreenWidth)      ; 右边放不下 -> 翻到左边
        tx := ax - AC_TipGap - AC_TipEstW
    if (ty + AC_TipEstH > A_ScreenHeight)     ; 下边放不下 -> 翻到上边
        ty := ay - AC_TipGap - AC_TipEstH
    if (tx < 0)
        tx := 0
    if (ty < 0)
        ty := 0

    ToolTip(text, tx, ty, tipNo)
    CoordMode("ToolTip", oldMode)

    if !IsObject(AC_TipTimers)
        AC_TipTimers := Map()
    if AC_TipTimers.Has(tipNo) {              ; 先清掉同一通道上一轮的自动清除
        SetTimer(AC_TipTimers[tipNo], 0)
        AC_TipTimers.Delete(tipNo)
    }
    if (persist)                              ; 常驻：不挂清除定时器，等下一次提示来顶掉
        return

    cb := AcTipClear.Bind(tipNo)              ; 绑定对象要存下来才取消得掉，见【坑 3】
    AC_TipTimers[tipNo] := cb
    SetTimer(cb, -AC_TipMs)
}

AcTipClear(tipNo) {
    ToolTip("", 0, 0, tipNo)
}

;--------------------------------------------------------------------
; 取屏幕坐标下的光标位置（临时切 CoordMode，用完还原）
;   前台/后台共用，别再各写一份
;--------------------------------------------------------------------
AcMouseScreen(&mx, &my) {
    oldMode := A_CoordModeMouse
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    CoordMode("Mouse", oldMode)
}

;====================================================================
; 设置文件 + 设置界面
;   AutoClickToggle()   读盘 -> 开 / 停
;   AutoClickSettings() 读盘 -> 改 -> 写盘
;   参数落在 <模块目录>\scripts\autoclick.cfg，一行一条 key=value。
;
; 【为什么必须落盘，不能只存内存】
;   data/custom_functions.ahk 在 WM_DISPLAYCHANGE 里挂了
;   SetTimer(MyKeymapReload, -5000) —— 插拔显示器 / 改分辨率后 MyKeymap 会
;   5 秒后自己重载脚本，内存里的设置会被静默清回默认值。
;====================================================================

;--------------------------------------------------------------------
; 本模块所在目录
;   坑：include 文件里**顶层**的 A_LineFile 是宿主 bin/MyKeymap.ahk，
;   只有**函数体内**拿到的才是本文件自己的路径 —— 所以只能懒算，别写顶层。
;--------------------------------------------------------------------
AcHomeDir() {
    global AC_Home
    if (AC_Home != "")
        return AC_Home
    SplitPath(A_LineFile, , &dir)
    AC_Home := (dir != "") ? dir : A_ScriptDir
    return AC_Home
}

AcCfgPath() {
    global AC_CfgPath, AC_CfgName
    if (AC_CfgPath != "")
        return AC_CfgPath
    AC_CfgPath := AcHomeDir() "\scripts\" AC_CfgName
    return AC_CfgPath
}

;--------------------------------------------------------------------
; 内置默认值（配置文件不存在 / 某项认不出时用它）
;--------------------------------------------------------------------
AcCfgDefault() {
    return {backend: "front", button: "L", interval: 50, follow: false, cancelMove: false, tipMode: "persist"}
}

;--------------------------------------------------------------------
; 数值兜底：空 / 非数字 -> def；否则四舍五入并钳到 [lo, hi]
;--------------------------------------------------------------------
AcNum(v, lo, hi, def) {
    s := Trim(String(v))
    if (s = "" || !IsNumber(s))
        return def
    return AcClamp(Round(s + 0), lo, hi)
}

;--------------------------------------------------------------------
; 浮窗档位字符串归一（认几种手写别名，认不出 = 常驻）
;--------------------------------------------------------------------
AcModeValue(v) {
    switch StrLower(Trim(String(v))) {
        case "fade", "2", "2s", "short": return "fade"
        case "off", "0", "none", "hide", "no": return "off"
        default: return "persist"
    }
}

;--------------------------------------------------------------------
; 按钮字符串归一："m"/"middle" -> "M"，认不出 = "L"
;   （AcButton 是拿首字母去换算 AHK 按钮名，这个是给配置文件用的）
;--------------------------------------------------------------------
AcButtonKey(v) {
    b := StrUpper(SubStr(Trim(String(v)), 1, 1))
    return (b = "M" || b = "R") ? b : "L"
}

;--------------------------------------------------------------------
; 读设置文件（每次 AutoClickToggle 都重读，改完不用重载脚本）
;   坏行 / 未知键直接跳过，不抛异常 —— 一个手滑不该让连点器整个用不了
;--------------------------------------------------------------------
AcCfgLoad() {
    global AC_IntervalMin, AC_IntervalMax
    cfg := AcCfgDefault()
    path := AcCfgPath()
    if !FileExist(path)
        return cfg
    try txt := FileRead(path, "UTF-8")
    catch
        return cfg

    for line in StrSplit(txt, "`n", "`r") {
        line := Trim(line)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        p := InStr(line, "=")
        if (!p)
            continue
        k := Trim(SubStr(line, 1, p - 1))
        v := Trim(SubStr(line, p + 1))
        switch k {
            case "backend":
                cfg.backend := (StrLower(v) = "bg") ? "bg" : "front"
            case "button":
                cfg.button := AcButtonKey(v)
            case "interval":
                cfg.interval := AcNum(v, AC_IntervalMin, AC_IntervalMax, 50)
            case "follow":
                cfg.follow := (v = "1" || StrLower(v) = "true")
            case "cancelMove":
                cfg.cancelMove := (v = "1" || StrLower(v) = "true")
            case "tipMode":
                cfg.tipMode := AcModeValue(v)
        }
    }
    if (cfg.follow)                    ; 跟随模式下"移动就停"无从判断，代码里也会忽略
        cfg.cancelMove := false
    return cfg
}

;--------------------------------------------------------------------
; 写设置文件
;   用 FileOpen + "UTF-8-RAW"（不加 BOM），跟本仓其他文件一个规矩；
;   ⛔别换成 IniWrite —— 它新建文件时的编码不受控。
;--------------------------------------------------------------------
AcCfgSave(cfg) {
    path := AcCfgPath()
    SplitPath(path, , &dir)
    if (dir != "" && !DirExist(dir)) {
        try DirCreate(dir)
        catch
            return false
    }
    txt := "; 连点器设置 —— AutoClickSettings() 写入；也可以手改，AutoClickToggle 每次都重读`r`n"
    txt .= "backend=" cfg.backend "`r`n"
    txt .= "button=" cfg.button "`r`n"
    txt .= "interval=" cfg.interval "`r`n"
    txt .= "follow=" (cfg.follow ? 1 : 0) "`r`n"
    txt .= "cancelMove=" (cfg.cancelMove ? 1 : 0) "`r`n"
    txt .= "tipMode=" cfg.tipMode "`r`n"
    try {
        f := FileOpen(path, "w", "UTF-8-RAW")
        f.Write(txt)
        f.Close()
        return true
    } catch {
        return false
    }
}

;--------------------------------------------------------------------
; 当前浮窗档位（懒读设置文件，只读一次）
;--------------------------------------------------------------------
AcTipModeGet() {
    global AC_TipMode, AC_TipModeLoaded
    if (!AC_TipModeLoaded) {
        AC_TipMode := AcCfgLoad().tipMode
        AC_TipModeLoaded := true
    }
    return AC_TipMode
}

AcTipModeSet(mode) {
    global AC_TipMode, AC_TipModeLoaded
    AC_TipMode := AcModeValue(mode)
    AC_TipModeLoaded := true
}

;--------------------------------------------------------------------
; 启动 / 停止提示：受浮窗档位管
;   isStart=true 且档位=persist 才常驻；停止提示一律 2 秒自清（否则常驻会留残影）
;   错误提示（没找到窗口 / 取客户区失败）不走这里，永远弹
;--------------------------------------------------------------------
AcTipState(text, ax, ay, tipNo, isStart) {
    mode := AcTipModeGet()
    if (mode = "off") {
        ; 停止时照样清一次：档位是"常驻"时留下的提示没有清除定时器，
        ; 改档位后按停止就再也没人收它了 —— 会永远挂在屏幕上
        if (!isStart)
            AcTipClear(tipNo)
        return
    }
    AcTip(text, ax, ay, tipNo, (isStart && mode = "persist"))
}

;--------------------------------------------------------------------
; 文案标签
;--------------------------------------------------------------------
AcBackendLabel(be) {
    return (StrLower(Trim(String(be))) = "bg") ? "后台" : "前台"
}

AcTipModeLabel(m) {
    switch AcModeValue(m) {
        case "fade": return "2 秒"
        case "off":  return "关闭"
        default:     return "常驻"
    }
}

AcCfgSummary(cfg) {
    s := AcBackendLabel(cfg.backend) " · " AcButtonLabel(cfg.button) " · " cfg.interval "ms · "
    s .= cfg.follow ? "跟随光标" : "固定点"
    if (cfg.cancelMove)
        s .= " · 移动停"
    s .= " · 浮窗" AcTipModeLabel(cfg.tipMode)
    return s
}

;--------------------------------------------------------------------
; 对外：按设置文件里的参数 开 / 停（Tab+Ctrl 走这个）
;   正在连点 -> 停；没在跑 -> 读盘后按配置启动
;   配置里的 backend=bg 时，目标是**启动那一刻**光标下的窗口
;--------------------------------------------------------------------
AutoClickToggle() {
    global AC_Running, AC_BgRunning
    if (AC_Running || AC_BgRunning) {
        AutoClickStop()
        return true
    }
    cfg := AcCfgLoad()
    AcTipModeSet(cfg.tipMode)
    AutoClick(cfg.follow, cfg.button, cfg.interval, cfg.cancelMove, 0, cfg.backend)
    return true
}

;--------------------------------------------------------------------
; 对外：设置界面（Tab+Win 走这个）
;   开着连点时先停 —— 前台后端会把光标拽走，那会儿根本点不动这个窗口
;   返回值：true = 保存了 / false = 取消或写盘失败
;--------------------------------------------------------------------
AutoClickSettings() {
    global AC_Running, AC_BgRunning
    if (AC_Running || AC_BgRunning)
        AutoClickStop()

    st := {cfg: AcCfgLoad(), ok: false, g: 0}
    AcCfgGui(st)
    if (!st.g)
        return false

    AcShowModal(st.g, "w392 h400 Center", st.edInterval)
    if (!st.ok)
        return false

    AcMouseScreen(&mx, &my)
    if (!AcCfgSave(st.cfg)) {
        AcTip("设置:写入失败`n" AcCfgPath(), mx, my, 1, false)
        return false
    }
    AcTipModeSet(st.cfg.tipMode)
    AcTip("设置已保存`n" AcCfgSummary(st.cfg), mx, my, 1, false)
    return true
}

;--------------------------------------------------------------------
; 弹窗挂起 + 等待关闭
;   Suspend 必须在**建框之后**调 —— 建框抛异常时不会把脚本留在挂起态；
;   原值要还回去（MyKeymap 自己有裸 Suspend 的用法）。
;   不 Suspend 的后果：Tab 层 / CapsLock 层的热键还在，输入框里
;   "有的数字打得进、有的打不进"（见 KeyRecorder 坑 R10 / R20）。
;--------------------------------------------------------------------
AcShowModal(g, opts, focusCtl := 0) {
    wasSuspended := A_IsSuspended
    Suspend(true)
    try {
        g.Show(opts)
        WinActivate("ahk_id " g.Hwnd)
        if (IsObject(focusCtl))
            try focusCtl.Focus()
        WinWaitClose("ahk_id " g.Hwnd)
    } finally {
        Suspend(wasSuspended)
    }
}

;--------------------------------------------------------------------
; 建设置界面（**不 Show**）
;   拆成"建框 / 取值 / 恢复默认"三块，控件选项写错是**建的时候就抛**，
;   拆开才能在不弹窗的前提下把它跑一遍验证掉。
;   坑：Gui 的**窗口构造选项不认 w/h**，尺寸只能写在 Show() 里（控件选项支持）。
;--------------------------------------------------------------------
AcCfgGui(st) {
    global AC_IntervalMin, AC_IntervalMax
    cfg := st.cfg

    ckL      := (cfg.button = "L") ? " Checked" : ""
    ckM      := (cfg.button = "M") ? " Checked" : ""
    ckR      := (cfg.button = "R") ? " Checked" : ""
    ckFixed  := cfg.follow ? "" : " Checked"
    ckFollow := cfg.follow ? " Checked" : ""
    ckCancel := cfg.cancelMove ? " Checked" : ""
    ckFront  := (StrLower(cfg.backend) = "bg") ? "" : " Checked"
    ckBg     := (StrLower(cfg.backend) = "bg") ? " Checked" : ""
    tipIdx   := (cfg.tipMode = "fade") ? 2 : ((cfg.tipMode = "off") ? 3 : 1)

    g := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "连点器设置")
    g.SetFont("s9", "Microsoft YaHei UI")

    g.AddGroupBox("x12 y12 w368 h136", "点击")
    g.AddText("x24 y34 w44", "按键")
    rL := g.AddRadio("x76 y32 w56" ckL, "左键")
    rM := g.AddRadio("x136 y32 w56" ckM, "中键")
    rR := g.AddRadio("x196 y32 w56" ckR, "右键")

    g.AddText("x24 y62 w44", "间隔")
    edInt := g.AddEdit("x76 y59 w70 Number", String(cfg.interval))
    udInt := g.AddUpDown("x149 y59 w18", AC_IntervalMin "-" AC_IntervalMax)   ; 必须紧跟上面的 Edit
    edInt.Value := String(cfg.interval)        ; 坑：UpDown 挂上来会把 Edit 改成范围下限，得再写一次
    g.AddText("x172 y62 w160 cGray", "ms（" AC_IntervalMin "–" AC_IntervalMax "）")

    g.AddText("x24 y90 w44", "位置")
    rFixed := g.AddRadio("x76 y88 w72" ckFixed, "固定点")
    rFollow := g.AddRadio("x160 y88 w84" ckFollow, "跟随光标")
    cbCancel := g.AddCheckBox("x76 y112 w290" ckCancel, "鼠标一动就停（仅固定点有效）")

    g.AddGroupBox("x12 y152 w368 h94", "后端")
    rFront := g.AddRadio("x24 y174 w330" ckFront, "前台：真挪光标，什么程序都能点")
    rBg := g.AddRadio("x24 y196 w330" ckBg, "后台：投窗口消息，不挪光标")
    g.AddText("x24 y220 w340 cGray", "后台目标＝启动时光标下的窗口；Unity / UWP 可能收不到")

    g.AddGroupBox("x12 y254 w368 h64", "浮窗")
    g.AddText("x24 y278 w44", "显示")
    cbTip := g.AddComboBox("x76 y275 w132 ReadOnly", ["常驻（不消失）", "2 秒后消失", "不显示"])
    cbTip.Value := tipIdx
    g.AddText("x214 y278 w160 cGray", "常驻 = 一直挂到按停止")

    txtSum := g.AddText("x16 y328 w368 cGray", "当前：" AcCfgSummary(cfg))
    btnOK := g.AddButton("x16 y354 w116 h30 Default", "保存")
    btnReset := g.AddButton("x146 y354 w116 h30", "恢复默认")
    btnNo := g.AddButton("x276 y354 w100 h30", "取消")

    btnOK.OnEvent("Click", (*) => AcCfgTake(st))
    btnReset.OnEvent("Click", (*) => AcCfgResetUI(st))
    btnNo.OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Close", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())

    syncH := (*) => AcCfgSync(st)              ; 一个闭包给所有控件用，别在 for 里建（会全部指向最后一个）
    for ctl in [rL, rM, rR, rFixed, rFollow, cbCancel, rFront, rBg]
        ctl.OnEvent("Click", syncH)
    cbTip.OnEvent("Change", syncH)
    edInt.OnEvent("Change", syncH)

    st.g := g
    st.edInterval := edInt
    st.udInterval := udInt
    st.rL := rL
    st.rM := rM
    st.rR := rR
    st.rFixed := rFixed
    st.rFollow := rFollow
    st.cbCancel := cbCancel
    st.rFront := rFront
    st.rBg := rBg
    st.cbTip := cbTip
    st.txtSum := txtSum
    AcCfgSync(st)                              ; 初始就把"跟随 -> 移动停置灰"摆对
}

;--------------------------------------------------------------------
; 界面 -> 配置对象（不写盘）
;--------------------------------------------------------------------
AcCfgReadUI(st) {
    global AC_IntervalMin, AC_IntervalMax
    btn := "L"
    if (st.rM.Value)
        btn := "M"
    else if (st.rR.Value)
        btn := "R"

    follow := st.rFollow.Value ? true : false
    cancel := (!follow && st.cbCancel.Value) ? true : false

    modes := ["persist", "fade", "off"]
    mi := st.cbTip.Value
    if (mi < 1 || mi > 3)
        mi := 1

    return {
        backend: st.rBg.Value ? "bg" : "front",
        button: btn,
        interval: AcNum(st.edInterval.Value, AC_IntervalMin, AC_IntervalMax, 50),
        follow: follow,
        cancelMove: cancel,
        tipMode: modes[mi]
    }
}

;--------------------------------------------------------------------
; 界面联动：跟随光标 -> "移动就停"置灰并清掉勾；顺便刷新底部摘要
;--------------------------------------------------------------------
AcCfgSync(st) {
    follow := st.rFollow.Value ? true : false
    st.cbCancel.Enabled := !follow
    if (follow && st.cbCancel.Value)
        st.cbCancel.Value := false
    st.txtSum.Text := "当前：" AcCfgSummary(AcCfgReadUI(st))
}

;--------------------------------------------------------------------
; 保存按钮的处理体（独立出来，能在不弹窗的情况下直接验证）
;--------------------------------------------------------------------
AcCfgTake(st) {
    st.cfg := AcCfgReadUI(st)
    st.ok := true
    st.g.Destroy()
}

;--------------------------------------------------------------------
; 恢复默认：只改界面，不写盘 —— 还得自己按保存
;   顺序有讲究：先把要取消的那几个设 false，最后再设 true，否则会把刚选上的顶掉
;--------------------------------------------------------------------
AcCfgResetUI(st) {
    d := AcCfgDefault()
    st.rM.Value := (d.button = "M")
    st.rR.Value := (d.button = "R")
    st.rL.Value := (d.button = "L")
    st.rFixed.Value := !d.follow
    st.rFollow.Value := d.follow
    st.cbCancel.Value := d.cancelMove
    st.rBg.Value := (d.backend = "bg")
    st.rFront.Value := (d.backend = "front")
    st.cbTip.Value := 1
    st.edInterval.Value := String(d.interval)
    AcCfgSync(st)
}

;--------------------------------------------------------------------
; 统一入口：开 / 关连点
;   followCursor  是否跟随光标连点（默认 false = 固定在启动时的点）
;   button        "L" / "M" / "R"（或 Left / Middle / Right）
;   interval      连点间隔(ms)，钳到 [AC_IntervalMin, AC_IntervalMax]
;   cancelOnMove  鼠标移动后是否取消（跟随模式下无意义，会被忽略）
;   target        仅 backend="bg"：0/空 = 光标下窗口、数字 = hwnd、字符串 = 标题
;   backend       "front"（默认）真挪光标，什么程序都能点，代价是占着鼠标
;                 "bg"           往目标窗口投消息，不占光标、不抢焦点，
;                                只对「自己处理鼠标消息」的程序有效（见后半段）
;   tipMode       浮窗档位 "persist" / "fade" / "off"，不写 = 用设置文件里的档位
;
;   再调一次同一个入口 = 停（哪个后端在跑就停哪个）
;--------------------------------------------------------------------
AutoClick(followCursor := false, button := "L", interval := 50, cancelOnMove := false, target := 0, backend := "front", tipMode := "") {
    global AC_Running, AC_BgRunning

    if (AC_Running || AC_BgRunning) {         ; 任一后端在跑 -> 本次当"关闭"
        AutoClickStop()
        return
    }

    if (tipMode != "")                        ; 显式传了就用传的
        AcTipModeSet(tipMode)
    else
        AcTipModeGet()                        ; 没传就沿用设置文件里的浮窗档位

    if (StrLower(Trim(String(backend))) = "bg")
        return AcBgStart(followCursor, button, interval, cancelOnMove, target)

    return AcFrontStart(followCursor, button, interval, cancelOnMove)
}

;--------------------------------------------------------------------
; 显式停止：两个后端都停，没在跑的那个是空操作
;   reason 不再拼进提示（停止一律显示 连点器[停止]），保留形参给将来记日志用
;--------------------------------------------------------------------
AutoClickStop(reason := "停止") {
    AcBgStop(reason)
    AcFrontStop(reason)
}

;--------------------------------------------------------------------
; 旧名兼容：config.json 的 *p 现在绑的还是 AutoClickBg(false, "L", 50, false)。
; 新写法：AutoClick(false, "L", 50, false, 0, "bg")。
;--------------------------------------------------------------------
AutoClickBg(followCursor := false, button := "L", interval := 50, cancelOnMove := false, target := 0, fakeActivate := "", tipMode := "") {
    global AC_Running, AC_BgRunning
    if (AC_Running || AC_BgRunning) {
        AutoClickStop()
        return
    }
    if (tipMode != "")
        AcTipModeSet(tipMode)
    else
        AcTipModeGet()
    return AcBgStart(followCursor, button, interval, cancelOnMove, target, fakeActivate)
}

;--------------------------------------------------------------------
; 前台后端（front）：真挪光标去点
;   所有程序都能点；代价是连点期间光标被它拽着，会打断你手上的事。
;   （对外请用 AutoClick(...)，本函数只是它的 front 分支）
;--------------------------------------------------------------------
AcFrontStart(followCursor := false, button := "L", interval := 50, cancelOnMove := false) {
    global AC_Running, AC_Interval, AC_IntervalMin, AC_IntervalMax
    global AC_Button, AC_CancelOnMove, AC_FollowCursor
    global AC_X, AC_Y            ; ← 别删，见文件头【坑 2】

    ; 正在跑 -> 本次调用当"关闭"处理
    if (AC_Running) {
        AcFrontStop()
        return
    }

    ; 参数保护：非数字回落到默认值，再钳位
    if (!IsNumber(interval))
        interval := 50
    AC_Interval     := AcClamp(Round(interval), AC_IntervalMin, AC_IntervalMax)
    AC_Button       := button
    AC_CancelOnMove := cancelOnMove ? true : false
    AC_FollowCursor := followCursor ? true : false
    ; 跟随模式下位置一直在变，"移动就取消"无从判断，直接忽略
    if (AC_FollowCursor)
        AC_CancelOnMove := false

    ; 采样当前位置当起点（AcMouseScreen 内部临时切 Screen 坐标并还原）
    AcMouseScreen(&mx, &my)
    AC_X := mx
    AC_Y := my

    AC_Running := true
    SetTimer(AcFrontTick, -1)         ; 负值 = 只触发一次，之后由 AcFrontTick 自己续期

    AcTipState(AcStartText(), AC_X, AC_Y, 1, true)
}

;--------------------------------------------------------------------
; 停前台连点（对外请用 AutoClickStop，它会两个后端一起停）
;   reason 不再拼进提示（停止一律显示 连点器[停止]），保留形参给将来记日志用
;--------------------------------------------------------------------
AcFrontStop(reason := "停止") {
    global AC_Running, AC_X, AC_Y
    if (!AC_Running)
        return
    AC_Running := false
    SetTimer(AcFrontTick, 0)
    AcTipState(AcStopText(reason), AC_X, AC_Y, 1, false)
}

;--------------------------------------------------------------------
; 定时器回调：点一次，然后把定时器续到下一个间隔
; 用"负延时 + 自己续期"而不是固定周期，避免目标程序慢时点击堆积
;--------------------------------------------------------------------
AcFrontTick() {
    global AC_Running, AC_X, AC_Y, AC_Interval, AC_ClickSpeed, AC_Button
    global AC_CancelOnMove, AC_FollowCursor, AC_MoveThreshold

    if (!AC_Running)
        return

    oldMode := A_CoordModeMouse
    CoordMode("Mouse", "Screen")

    if (AC_FollowCursor) {
        ; 跟随：每个周期重新取一次当前光标位置
        MouseGetPos(&cx, &cy)
    } else {
        cx := AC_X
        cy := AC_Y
        if (AC_CancelOnMove) {
            ; "手一动就停"：拿当前光标和起点比，超过阈值说明用户不想点了
            MouseGetPos(&px, &py)
            if (Abs(px - AC_X) > AC_MoveThreshold || Abs(py - AC_Y) > AC_MoveThreshold) {
                CoordMode("Mouse", oldMode)
                AcFrontStop("移动停")
                return
            }
        }
    }

    MouseClick(AcButton(AC_Button), cx, cy, AC_ClickSpeed)   ; Speed 必须 >= 1，见【坑 1】
    CoordMode("Mouse", oldMode)

    SetTimer(AcFrontTick, -AC_Interval)
}

;--------------------------------------------------------------------
; ========== 后台后端（bg）：往目标窗口投鼠标消息 ==========
;--------------------------------------------------------------------
;
; 与前台后端的区别只有一点：点击怎么发出去。
;   front  用 MouseClick -> SendInput，是**真实输入**：光标必须挪到点上、靠前台焦点
;          送达。所以它一定打断你手上的事。
;   bg     用 PostMessage 把 WM_LBUTTONDOWN/UP 直接投给目标窗口，光标一动不动、
;          焦点不变 —— 你可以同时干别的。
;
; 代价（这是本方案的全部限制，先看清楚再接线）：
;   1. 目标程序必须**自己处理这些鼠标消息**。它要是从 RawInput / 硬件队列读输入
;      （多数 UWP、开始菜单这类合成层界面），投进去的消息根本没人看 —— 无效。
;   2. **定位靠系统真实光标的程序，点位无解**（典型：Unity，见【坑 B2】）。
;   3. 目标程序如果检查"我是不是前台窗口"，后台点击一样会被丢掉
;      —— 设计如此，绕不过（可用补激活缓解，见【坑 B6】）。
;   4. 投消息**不产生真实鼠标状态**。用 GetAsyncKeyState / GetCursorPos 判断的软件
;      会认为你没按。
;   5. 目标窗口**最小化**时通常无效（消息还进队列，但程序不处理）。
;
; 入口（对外统一走 AutoClick(..., "bg")；旧名 AutoClickBg 仍可用）：
;   AcBgStart(followCursor, button, interval, cancelOnMove, target, fakeActivate)
;       followCursor 是否跟随光标（默认 false，固定在一个点）
;       button       "L" / "M" / "R"，默认 "L"
;       interval     间隔 ms，默认 50
;       cancelOnMove 光标移动超过 AC_MoveThreshold 就自动停（默认 false）
;       target       0 / 空        -> 光标下的窗口（WindowFromPoint）
;                    正整数        -> 直接当窗口句柄 hwnd
;                    字符串        -> 当窗口标题 / ahk_exe xxx 之类去匹配
;       fakeActivate 目标不在前台时是否补发 WM_ACTIVATE+WM_SETFOCUS
;                    （默认不写 = 用 AC_BgFakeActivate；按需 + 节流，见【坑 B6】）
;   AcBgStop(reason)             显式停止
;   AutoClickProbe(button, target)  **单发试针**
;       只发一次点击，并把"打到了哪个窗口、客户区坐标多少"提示出来，
;       完整诊断（hwnd / 类名 / 父窗口 / 顶层窗口 / 进程 / 是否无响应）
;       追加到 %TEMP%\mykeymap_autoclickbg.log。
;       用法：光标放到目标程序的要点位置上 -> 按这个键 -> 看目标有没有反应。
;       没反应就把日志那一行发我，能直接判断是"窗口选错了"还是"程序不吃消息"。
;
; 【语义与前台版最大的差异】坐标系
;   前台版存的是**屏幕坐标**，窗口挪走了它照样点屏幕上那个位置。
;   后台版必须存**客户区坐标**（lParam 就是客户区坐标），于是：
;     - 目标窗口被拖动 / 改大小，点击仍然落在窗口内同一个相对位置上（跟着窗口走）；
;     - 点跑到客户区之外时自动停（提示"出窗口"），不会瞎点到别处去。
;
; 【坑 B1】用 PostMessage，不要用 SendMessage
;   Post 是"投进队列就走"，目标卡住也不会拖住 MyKeymap；Send 会等对方处理完，
;   碰上目标弹出模态框就是一次超时挂起。本文件只用 PostMessageW。
;
; 【坑 B2】每次发 DOWN 之前补一条 WM_MOUSEMOVE（默认每轮都补）—— 但要知道它救不了谁
;   能救：靠 WM_MOUSEMOVE 更新内部 hover / 命中状态的程序。只补第一发的话，
;         之后真实鼠标一动就把位置盖掉，表现为"点击跟着鼠标跑"。
;         所以 AC_BgSendMoveEachTick 默认 true：每轮先喂一条 MOVE，紧接着发 DOWN/UP。
;         配套要求：连点期间**别把光标移进目标窗口**（真实 MOUSEMOVE 会盖掉喂的坐标）。
;   救不了：**按系统真实光标定位**的程序。Windows 上最典型的就是 Unity ——
;         uGUI 的事件命中用 Input.mousePosition，而它每帧取自 GetCursorPos()，
;         DOWN 消息里的 lParam 它根本不看。
;         实测（Unity / UnityWndClass）：单发试针"有反应"，
;         做成连点后点击随鼠标走；**改成每轮都补 MOVE 之后**依然随鼠标走
;         ⇒ 判定它属于这一类。
;         结论：**每轮补了 MOVE 仍随鼠标走 = 后台固定点无解**，别再往这个方向调参；
;         只能真挪光标（用前台后端），或退回前台点击。
;
; 【坑 B3】间隔别调太小
;   Post 不阻塞，投太快会在目标的消息队列里堆积、甚至被丢。建议 >= 30ms。
;
; 【坑 B4】WindowFromPoint 拿到的窗口不一定是该收消息的那个
;   它跳过隐藏/禁用窗口；点在静态文本上时返回的是父窗口。Electron / 浏览器类
;   程序更是有好几层子窗口。所以试针会把**类名**报出来 —— 不对就换 target 参数
;   显式指定（例如 target 传 "ahk_exe chrome.exe" 直接打到顶层窗口）。
;
; 【坑 B5】提示用独立的 ToolTip 编号
;   前台用默认通道(1)、亮度用 5，后台用 AC_BgTipNo = 6，互不清掉。
;
; 【坑 B6】目标可能「失去焦点就不处理鼠标输入」
;   实测（09-19）：Unity 游戏在**有别的窗口压在它上面**时，投进去的 DOWN/UP 依然送达
;   （日志里 0 条投递失败），但它就是不理 —— 它的输入处理挂在"自己是不是激活窗口"上。
;   对策：在投鼠标消息**之前**给目标补发 WM_ACTIVATE(WA_ACTIVE) + WM_SETFOCUS，
;   让它**自认为**是激活的。这只是消息层面的自欺：系统真正的前台窗口没变，
;   别的程序也看不出差别；目标若用 GetForegroundWindow / IsWindowVisible 之类的
;   **系统状态**判断，骗不过去。
;   两条限制（别小看）：
;   a) **只在目标不是前台窗口时才补** —— 它已经是前台就没必要，补了反而打扰它；
;   b) **节流到 AC_BgFakeActivateMs（默认 1000ms）补一次**。不能每轮都补：50ms 一轮
;      = 每秒 20 次伪造 WM_ACTIVATE，对方的 OnApplicationFocus / OnApplicationPause
;      会跟着反复触发（Unity 常见），轻则闪烁、重则卡顿。目标一旦被「告知」激活，
;      那个状态会一直留着，所以每秒确认一次就够。
;   **已验证（实测）：这一招能让被压住的 Unity 窗口重新收点击。**
;   关掉的开关：AC_BgFakeActivate := false，或给第 6 个参数写 false。
;--------------------------------------------------------------------

; ========== 后台：配置参数 ==========
AC_BgInterval      := 50     ; 默认连点间隔(ms)
AC_BgButton        := "L"    ; 默认按钮：L 左键 / M 中键 / R 右键
AC_BgCancelOnMove  := false  ; 默认：光标移动后不取消
AC_BgFollowCursor  := false  ; 默认：固定在启动时的点（客户区坐标）
AC_BgSendMoveEachTick := true  ; 每轮点击前都补一条 WM_MOUSEMOVE（见【坑 B2】；对 Unity 这类读系统光标的程序无效）
AC_BgFakeActivate  := true     ; 目标非前台时补发 WM_ACTIVATE+WM_SETFOCUS，骗它「我是激活的」（见【坑 B6】）
AC_BgFakeActivateMs := 1000    ; 补激活的节流间隔(ms)：非前台时最多这么久补一次（别每轮补，见【坑 B6】b）
AC_BgClientSlack   := 2      ; 客户区边界容差(px)，点贴边时不算"出窗口"
AC_BgTipNo         := 6      ; 专用 ToolTip 编号，避开 AutoClick(默认) 与亮度(5)
AC_BgLog           := A_Temp "\mykeymap_autoclickbg.log"   ; 试针诊断日志（可随时删）

; ========== 后台：内部状态 ==========
AC_BgRunning    := false     ; 是否正在后台连点
AC_BgHwnd       := 0         ; 目标窗口句柄
AC_BgClientX    := 0         ; 客户区坐标（不是屏幕坐标！见文件头）
AC_BgClientY    := 0
AC_BgScreenX    := 0         ; 启动时的屏幕坐标，只用于提示定位 + 移动判定
AC_BgScreenY    := 0
AC_BgNeedMove   := true      ; 本轮是否要先补一条 WM_MOUSEMOVE（默认每轮都补，见【坑 B2】）
AC_BgFakeLast   := 0         ; 上次补激活的时间戳(A_TickCount)，用于节流（见【坑 B6】b）

;--------------------------------------------------------------------
; 提示文案（单独抽出来，方便改字 / 方便测）
;--------------------------------------------------------------------
AcBgStartText() {
    t := "连点器[后台]`n" AcButtonLabel(AC_BgButton) "(" AC_BgInterval "ms)"
    if (AC_BgFollowCursor)
        t .= " 跟随"
    return t
}

;--------------------------------------------------------------------
; 后台提示走独立 ToolTip 编号（AC_BgTipNo=6），
; 免得和前台提示(通道 1)、亮度提示(通道 5)互相清掉
;--------------------------------------------------------------------
AcBgTip(text, ax, ay) {
    global AC_BgTipNo
    AcTip(text, ax, ay, AC_BgTipNo)
}

; 启动 / 停止提示（受浮窗档位管）；错误提示仍走 AcBgTip，永远弹
AcBgTipState(text, ax, ay, isStart) {
    global AC_BgTipNo
    AcTipState(text, ax, ay, AC_BgTipNo, isStart)
}

;--------------------------------------------------------------------
; 解析目标窗口
;   target  0/空 = 光标底下窗口；正整数 = hwnd；字符串 = 标题匹配
;   返回 hwnd，取不到返回 0
;--------------------------------------------------------------------
AcBgTarget(target) {
    if IsNumber(target) {
        if (target > 0)
            return WinExist("ahk_id " target) ? target : 0
        ; 0 / 负数 -> 落到下面"光标底下窗口"
    } else if (Trim(String(target)) != "") {
        h := WinExist(String(target))
        return h ? h : 0
    }

    AcMouseScreen(&mx, &my)
    ; WindowFromPoint 的 POINT 是按值传的（两个 LONG 打包成一个 64 位）
    pt := (my << 32) | (mx & 0xFFFFFFFF)
    return DllCall("user32\WindowFromPoint", "Int64", pt, "Ptr")
}

;--------------------------------------------------------------------
; 屏幕坐标 -> 目标窗口的客户区坐标
;   坑：WinGetClientPos 给的是客户区左上角在**屏幕**上的位置，要减掉
;--------------------------------------------------------------------
AcBgClientPoint(hwnd, sx, sy, &cx, &cy) {
    try WinGetClientPos(&ox, &oy, &w, &h, "ahk_id " hwnd)
    catch
        return false
    if (w <= 0 || h <= 0)
        return false
    cx := sx - ox
    cy := sy - oy
    return true
}

;--------------------------------------------------------------------
; 往 hwnd 投一组鼠标消息：可选 MOUSEMOVE -> DOWN -> UP
;   (cx, cy) 必须是**客户区**坐标；lParam = y 在高 16 位、x 在低 16 位
;   返回 true = 三条消息都投出去了（注意：投出去 != 对方处理了）
;--------------------------------------------------------------------
AcBgClickAt(hwnd, cx, cy, button, sendMove, fakeAct := false) {
    lp := (cy << 16) | (cx & 0xFFFF)

    ; 先自欺一条：让目标以为自己是激活/有焦点的（见【坑 B6】）。
    ; 注意这只是**消息层面**的自欺，系统真正的前台窗口不会变。
    if fakeAct {
        DllCall("user32\PostMessageW", "Ptr", hwnd, "UInt", 0x0006, "UPtr", 1, "Ptr", 0)   ; WM_ACTIVATE, wParam=WA_ACTIVE
        DllCall("user32\PostMessageW", "Ptr", hwnd, "UInt", 0x0007, "UPtr", 0, "Ptr", 0)   ; WM_SETFOCUS
    }

    if sendMove
        DllCall("user32\PostMessageW", "Ptr", hwnd, "UInt", 0x0200, "UPtr", 0, "Ptr", lp)   ; WM_MOUSEMOVE

    switch AcButton(button) {
        case "Right":
            downMsg := 0x0204          ; WM_RBUTTONDOWN
            upMsg   := 0x0205          ; WM_RBUTTONUP
            downWp  := 0x0002          ; MK_RBUTTON
        case "Middle":
            downMsg := 0x0207          ; WM_MBUTTONDOWN
            upMsg   := 0x0208          ; WM_MBUTTONUP
            downWp  := 0x0010          ; MK_MBUTTON
        default:
            downMsg := 0x0201          ; WM_LBUTTONDOWN
            upMsg   := 0x0202          ; WM_LBUTTONUP
            downWp  := 0x0001          ; MK_LBUTTON
    }

    ok := DllCall("user32\PostMessageW", "Ptr", hwnd, "UInt", downMsg, "UPtr", downWp, "Ptr", lp)
    ok := ok && DllCall("user32\PostMessageW", "Ptr", hwnd, "UInt", upMsg, "UPtr", 0, "Ptr", lp)
    return ok ? true : false
}

;--------------------------------------------------------------------
; 诊断信息（试针用）：类名 / 父窗口 / 顶层窗口 / 进程 / 是否无响应
;   一行写进 AC_BgLog，方便把"到底打到哪个窗口"这件事带回来
;--------------------------------------------------------------------
AcBgLogProbe(hwnd, label, button, sx, sy, cx, cy, posted) {
    global AC_BgLog
    cls    := ""
    rootCls := ""
    pid    := 0
    exe    := ""
    try cls := WinGetClass("ahk_id " hwnd)
    try pid := WinGetPID("ahk_id " hwnd)
    try exe := WinGetProcessName("ahk_id " hwnd)
    try {
        root := DllCall("user32\GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")   ; GA_ROOT
        if root
            rootCls := WinGetClass("ahk_id " root)
    }
    parent := DllCall("user32\GetParent", "Ptr", hwnd, "Ptr")
    hung   := DllCall("user32\IsHungAppWindow", "Ptr", hwnd) ? 1 : 0
    vis    := DllCall("user32\IsWindowVisible", "Ptr", hwnd) ? 1 : 0
    En     := DllCall("user32\IsWindowEnabled", "Ptr", hwnd) ? 1 : 0

    line := A_Now " " label " button=" AcButton(button) " hwnd=0x" Format("{:X}", hwnd)
    line .= " class=" cls " parent=0x" Format("{:X}", parent) " root=" rootCls
    line .= " pid=" pid " exe=" exe
    line .= " screen=" sx "," sy " client=" cx "," cy
    line .= " posted=" posted " visible=" vis " enabled=" En " hung=" hung "`n"
    try FileAppend(line, AC_BgLog, "UTF-8")
}

;--------------------------------------------------------------------
; 对外：单发试针 —— 只点一次，并把"打到哪儿"报出来
;   button  默认 "L"
;   target  默认 0（光标底下窗口），同 AutoClickBg
;   返回 true = 消息投出去了（不代表目标处理了）
;--------------------------------------------------------------------
AutoClickProbe(button := "L", target := 0) {
    global AC_BgFakeActivate
    AcMouseScreen(&mx, &my)

    hwnd := AcBgTarget(target)
    if !hwnd {
        AcBgTip("试针:没找到窗口", mx, my)
        return false
    }
    if !AcBgClientPoint(hwnd, mx, my, &cx, &cy) {
        AcBgTip("试针:取客户区失败", mx, my)
        return false
    }

    posted := AcBgClickAt(hwnd, cx, cy, button, true, AC_BgFakeActivate)   ; 补 MOUSEMOVE + 补激活，成功率明显更高
    AcBgLogProbe(hwnd, "PROBE", button, mx, my, cx, cy, posted ? 1 : 0)

    cls := ""
    try cls := WinGetClass("ahk_id " hwnd)
    suffix := posted ? "" : "(失败)"          ; 单独拎出来，避免三元表达式夹在隐式拼接里产生歧义
    AcBgTip("试针:发-" AcButtonLabel(button) suffix "`n" cls " " cx "," cy, mx, my)
    return posted
}

;--------------------------------------------------------------------
; 对外：后台连点 开 / 关（语义与 AutoClick 一致：再调一次就是停）
;--------------------------------------------------------------------
AcBgStart(followCursor := false, button := "L", interval := 50, cancelOnMove := false, target := 0, fakeActivate := "") {
    global AC_BgRunning, AC_BgInterval, AC_IntervalMin, AC_IntervalMax
    global AC_BgButton, AC_BgCancelOnMove, AC_BgFollowCursor, AC_BgFakeActivate
    global AC_BgHwnd, AC_BgClientX, AC_BgClientY, AC_BgScreenX, AC_BgScreenY, AC_BgNeedMove, AC_BgFakeLast

    ; 正在跑 -> 本次调用当"关闭"处理
    if (AC_BgRunning) {
        AcBgStop()
        return
    }

    if (!IsNumber(interval))
        interval := 50
    AC_BgInterval     := AcClamp(Round(interval), AC_IntervalMin, AC_IntervalMax)
    AC_BgButton       := button
    AC_BgCancelOnMove := cancelOnMove ? true : false
    AC_BgFollowCursor := followCursor ? true : false
    ; 跟随模式下位置一直在变，"移动就取消"无从判断，直接忽略（同 AutoClick）
    if (AC_BgFollowCursor)
        AC_BgCancelOnMove := false
    ; 第 6 个参数只在**写了**的时候才覆盖配置默认值（同 AutoClick 的"写了才生效"）
    if (fakeActivate != "")
        AC_BgFakeActivate := fakeActivate ? true : false

    AcMouseScreen(&mx, &my)
    hwnd := AcBgTarget(target)
    if !hwnd {
        AcBgTip("连点器[后台] 没找到窗口", mx, my)
        return
    }
    if !AcBgClientPoint(hwnd, mx, my, &cx, &cy) {
        AcBgTip("连点器[后台] 取客户区失败", mx, my)
        return
    }

    AC_BgHwnd     := hwnd
    AC_BgClientX  := cx
    AC_BgClientY  := cy
    AC_BgScreenX  := mx
    AC_BgScreenY  := my
    AC_BgNeedMove := true          ; 第一发先补 MOUSEMOVE（见【坑 B2】）
    AC_BgFakeLast := 0             ; 重置节流，好让第一发立刻带上补激活（见【坑 B6】b）
    AC_BgRunning  := true

    SetTimer(AcBgTick, -1)         ; 负值 = 只触发一次，之后由 AcBgTick 自己续期
    AcBgTipState(AcBgStartText(), mx, my, true)
}

;--------------------------------------------------------------------
; 对外：显式停止
;   reason 不再拼进提示（停止一律显示 连点器[停止]）
;--------------------------------------------------------------------
AcBgStop(reason := "停止") {
    global AC_BgRunning, AC_BgScreenX, AC_BgScreenY
    if (!AC_BgRunning)
        return
    AC_BgRunning := false
    SetTimer(AcBgTick, 0)
    AcBgTipState("连点器[停止]", AC_BgScreenX, AC_BgScreenY, false)
}

;--------------------------------------------------------------------
; 定时器回调：投一次点击，然后把定时器续到下一个间隔
; 用"负延时 + 自己续期"而不是固定周期，避免目标处理慢时消息堆积
;--------------------------------------------------------------------
AcBgTick() {
    global AC_BgRunning, AC_BgHwnd, AC_BgClientX, AC_BgClientY, AC_BgInterval, AC_BgButton
    global AC_BgCancelOnMove, AC_BgFollowCursor, AC_MoveThreshold, AC_BgSendMoveEachTick
    global AC_BgNeedMove, AC_BgScreenX, AC_BgScreenY, AC_BgClientSlack, AC_BgLog, AC_BgFakeActivate
    global AC_BgFakeActivateMs, AC_BgFakeLast

    if (!AC_BgRunning)
        return

    ; 目标窗口还在吗（可能已经被用户关掉了）
    if !WinExist("ahk_id " AC_BgHwnd) {
        AcBgStop("窗口没了")
        return
    }

    AcMouseScreen(&mx, &my)

    ; "手一动就停"
    if (AC_BgCancelOnMove) {
        if (Abs(mx - AC_BgScreenX) > AC_MoveThreshold || Abs(my - AC_BgScreenY) > AC_MoveThreshold) {
            AcBgStop("移动停")
            return
        }
    }

    cx := AC_BgClientX
    cy := AC_BgClientY
    if (AC_BgFollowCursor) {
        if !AcBgClientPoint(AC_BgHwnd, mx, my, &cx, &cy) {
            AcBgStop("出窗口")
            return
        }
    }

    ; 客户区范围检查：点跑到窗口外就别点了，免得落到别的界面元素上
    try WinGetClientPos(&ox, &oy, &w, &h, "ahk_id " AC_BgHwnd)
    catch {
        AcBgStop("窗口没了")
        return
    }
    if (cx < -AC_BgClientSlack || cy < -AC_BgClientSlack || cx > w + AC_BgClientSlack || cy > h + AC_BgClientSlack) {
        AcBgStop("出窗口")
        return
    }

    ; 要不要补激活（见【坑 B6】）：目标本来就在前台就不用补；否则节流到 AC_BgFakeActivateMs 补一次。
    needFake := false
    if (AC_BgFakeActivate) {
        if (DllCall("user32\GetForegroundWindow", "Ptr") != AC_BgHwnd) {
            tickNow := A_TickCount
            if ((tickNow - AC_BgFakeLast) >= AC_BgFakeActivateMs) {
                needFake    := true
                AC_BgFakeLast := tickNow
            }
        }
    }

    if !AcBgClickAt(AC_BgHwnd, cx, cy, AC_BgButton, AC_BgNeedMove, needFake) {
        try FileAppend(A_Now " TICK post-failed hwnd=0x" Format("{:X}", AC_BgHwnd) " client=" cx "," cy "`n", AC_BgLog, "UTF-8")
        AcBgStop("发消息失败")
        return
    }
    AC_BgNeedMove := AC_BgSendMoveEachTick

    SetTimer(AcBgTick, -AC_BgInterval)
}
