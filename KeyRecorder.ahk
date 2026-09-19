;====================================================================
; 键鼠录制 / 回放 AHK v2   —— MyKeymap2 自定义函数
;
; 对外 7 个入口：
;   RecToggle(ignoreKey, recordMove, alphaPct)   录制 开 / 关（再调一次 = 停）
;                                      recordMove 不写 = 先弹框问（默认勾"录制鼠标移动"）；
;                                      写 true/false = 不弹框、直接照办
;   RecPlay(speed, loops, count, mode, alphaPct) 回放；不写参数 = 先弹询问框
;                                      loops=true 一直循环（count 作废）/ false 放 count 遍
;                                      手里没内容时会问一句"要加载脚本吗"（见下）
;   alphaPct 是**状态提示的透明度(%)**：不写 = 用模块默认 RC_HoldAlphaPct(20)；
;            0 = 完全不透明（同"脚本[停止]"），100 = 全透。config.json 里传的就是它。
;   RecSave(path)                      把当前内容存成脚本文件（JSON）；path 不写 = 弹系统另存为框；成功 = 左上角不透明的"脚本[保存]"条（2 秒或一动就收）
;   RecLoad(path)                      从脚本文件载入（andPlay=true 时载完直接弹「键鼠回放」窗）；path 不写 = 弹系统打开框
;                                      载入**只装进内存**，跟"自己刚录完"是同一种状态，
;                                      想放就按回放键（倍速/次数照样弹框问）
;   RecStop()                          强制停止（录制 / 回放都停）—— 安全键用这个
;   RecClear()                         清空已录内容
;   RecInfo()                          返回"条数 / 时长"一行说明
;
; 现接线（data/config.json 的 **Tab 模式**层，键名就是实际按的键）：
;   [  -> RecToggle("", "", 15)   开录时弹框问"要不要录鼠标移动"，再按一次结束；提示 15% 透
;   ]  -> RecPlay("", false, 1, "Event", 15)  弹窗问：循环 / 次数 / 倍速，确认后回放；15% 透
;   \  -> RecStop()               【安全键】中途反悔按这个，立刻停
;   ;  -> RecSave()               存成脚本文件（系统另存为框，默认落在 <本模块目录>\scripts\）
;   '  -> RecLoad()               从脚本文件载入（打开框）；载完直接弹回放框
;
; 脚本文件（JSON）长这样 —— 自己手写一份也能加载：
;   {"tag":"MyKeymap KeyRecorder","version":1,"savedAt":"…","count":2,
;    "events":[{"type":"k","t":120,"key":"s","mods":"^"},
;              {"type":"c","t":340,"btn":"LButton","x":123,"y":192}]}
;   t 是**相对开录时刻的毫秒偏移**；mods 用 AHK 的修饰键前缀（^ ! + #）。
;   加载时认 tag 不认别人家的 JSON；认不出的 type 会跳过（老版本也能读个大概）。
;
; 录制内容（都是"操作意图"级别，不是原始钩子流）：
;   k  键盘按下 —— 键名 + 当时的修饰键（Ctrl/Alt/Shift/Win）
;   c  鼠标点击 —— 左/中/右 + 屏幕坐标（按下抬起中间没动）
;   d  鼠标按下 —— 拖拽的起点（按下后动过才生成）
;   u  鼠标抬起 —— 拖拽的终点
;   w  滚轮     —— 上下左右 + 屏幕坐标
;   m  鼠标移动 —— 开录时在弹框里选（默认录）；**拖拽过程中的移动总是记**
;  键盘来自 InputHook.OnKeyDown，鼠标来自 WH_MOUSE_LL 低级钩子 —— 都是屏幕坐标。
;  拖拽为什么会拆成 d/m/u：按下时还不知道是"点一下"还是"拖"，所以要等抬起才定性 ——
;  没动过 = 记一条 c；动过 = 补一条 d（回填按下时刻）+ 中间 m + 最后 u。
;
; 已知不还原的东西（不是 bug，是这套方案的边界）：
;   1. 长按不放（键盘）。只记按下，回放是"按下+松开"的短击；按住 Ctrl 再点这类是记修饰键状态，没问题。
;   2. 输入法。录的是物理按键，不是上屏文字 —— 回放会重打一遍拼音，
;      输入法状态一样时结果一样；状态不一样结果就不一样。
;   3. 拖拽轨迹是**采样点**（4px 一次），长距离框选中间点不够密时，结果基本对但未必像素级一致。
;   4. Ctrl+Alt+Del / UAC 这类安全桌面收不到合成的键鼠，回放无效。
;   5. 录到一半按了别的 MyKeymap 热键（连点器等），回放时会连着一起触发。
;
; 【与连点器的关系】录制期间那个连点器启停键本身**不会**被录进去
;   （见【坑 R1】的忽略键机制），但你在录制时按下它 -> 连点器会被真的开起来。
;   要干净录制，先把它关掉再按 [。
;
; 提示：分两种，都用系统的 ToolTip 窗口（通道岔开，互不打扰）。
;   ① 状态提示（录制 / 回放期间一直挂着）—— ToolTip 通道 RC_HoldNo(8)，
;      **贴屏幕左上角**（x = y = RC_HoldMargin = 14），不跟光标跑；按停止键才收起。
;      最多四行（空的整行不显示）：
;        第 1 行 标题 —— 统一叫 脚本[录制] / 脚本[回放]（不带"中"）
;        第 2 行 模式 —— 只在回放时有：倍速 + [当前轮/总轮]，如 0.8x [1/99]、0.8x [1/∞]
;        第 3 行 按键 + 时长 —— (左键) 3.1s / (上滚) 91.1s / (Ctrl+S) 3.1s
;                              "时长"是该事件在录制里的时间偏移，不随倍速变
;        第 4 行 坐标 —— [123,192]（键盘事件没有坐标，整行不显示）
;      半透明 —— 透明度由 RecToggle / RecPlay 的末位参数给（不传就用模块默认 RC_HoldAlphaPct=20 ⇒ alpha 204）。
;   ② 短提示（脚本[停止] / 没内容 / 已清空）—— 复用 AutoClick.ahk 的 AcTip，
;      ToolTip 通道 7，**贴光标**、2 秒自消（依赖它已被 include）。
;   ③ 一闪而过的状态条（脚本[保存] / 脚本[加载]）—— 还是通道 8 / 屏幕左上角，但**不透明**；
;      2 秒兜底 + 一动（鼠标 / 按键）就收。
;   【为什么回到 ToolTip】自建 Gui 折腾过两版都不行：透明键那版要叠两个 AlwaysOnTop
;   窗口，z 序来回跳 ⇒ 字一会儿黑一会儿白（实测）；纯透明键单窗口也不如系统
;   ToolTip 来得稳。而 ToolTip 其实**本来就能半透明**（见【坑 R15】），所以直接用回它。
;
; 命名：对外 PascalCase 不带前缀（RecToggle / RecPlay / …）；
;   内部函数 Rc 打头，模块级变量 RC_ 打头。
;
; 【坑 R1】启停热键会把自己录进去
;   InputHook 是"按了就回调"，用它启停时，**停止那一下**会先被钩子收到。
;   对策：RecToggle 把触发它的那个键丢进 RC_Ignore，录制期间该键一律不入库。
;   启动那一下天然安全（这时钩子还没 Start）。
;
; 【坑 R2】InputHook 的 OnKeyDown 给的是 VK/SC，不是键名
;   用 GetKeyName("vkXXscYYY") 换成键名；换不出来（多媒体键之类）就直接
;   存 vk 形式，回放时 Send("{vkXXscYYY}") 一样能发出去。
;
; 【坑 R3】纯修饰键的按下不记
;   Ctrl+C 会先回调一次 Ctrl、再回调一次 c。Ctrl 单独记下来的话，回放会
;   变成"按住 Ctrl 不放"，后面的键全被污染。所以修饰键只作为**状态**附加到
;   下一个普通键上（Send 的 ^!+# 前缀），本身不入库。
;
; 【坑 R4】回放的时间轴要拿 QPC 算，别拿 A_TickCount
;   本机实测 A_TickCount 走 Sleep(50) 只有 46ms 分辨率、误差 ±15ms；
;   QPC 频率 10000000，够用。事件时间一律用 RcNow()（QPC 毫秒）。
;   等待用"绝对目标时间 + 分片 Sleep"，不做逐事件累加，避免误差累积。
;
; 【坑 R5】回放循环里必须让出线程，否则安全键按不动
;   回放是普通函数里的循环，Sleep 会把控制权交回消息队列，热键线程才插得进来。
;   所以循环里只允许 Sleep/有限自旋，绝不能 Critical —— 一旦 Critical，
;   RecStop 就永远等不到执行，回放停不下来。
;
; 【坑 R6】回放发键走 RcSend() 分函数，不用 Send()
;   v2 的 Send() **只收 1 个参数**，传第二个直接报"Too many parameters"（加载期就挂）。
;   模式得分函数调用：SendEvent / SendInput / SendPlay / SendText，
;   这样不用改全局 SendMode（MyKeymap 是 Event，别的功能在用），不带副作用。
;   鼠标点则走 MouseClick(RcClickName(btn), x, y, 1)：Speed **必须 >= 1**，
;   本环境填 0 会一次点击都发不出去（同 AutoClick.ahk 的【坑 1】）。
;   鼠标移动用 SetCursorPos，绕开 MouseMove 的 Speed 参数。
;
; 【坑 R7】InputHook 默认会把**文本按键吃掉**，必须显式放行
;   官方文档：默认只放行非文本键，产生文本的键会被屏蔽、不进前台窗口。
;   照默认用 => 录制期间你打字打不进去。所以两个可见性属性都要置 true。
;   另外默认输入缓冲只有 1023 字符上限（到顶就不再收），选项 "L0" 关掉它 ——
;   我们只要 OnKeyDown 回调，根本不需要缓冲文本。
;   注意 InputHook 的 "I" 选项是 MinSendLevel（过滤低于该 send level 的输入），
;   **不是**"忽略 AHK 生成的输入"；别拿它当去重手段，它会把物理按键一起滤掉。
;
; 【坑 R8】别用 "~*LButton" 这类动态热键来录鼠标
;   Hotkey() 会把 config.json 里**同一个键**的热键顶掉 —— *WheelUp / *WheelDown / *MButton
;   现在接着亮度（BrightAuto），录完再 Hotkey(..., "Off") 就永久失效，得重载脚本才恢复。
;   改用 WH_MOUSE_LL 低级鼠标钩子：不碰热键表、零副作用，还顺带拿到滚轮方向和 XButton。
;   回调签名 LowLevelMouseProc(nCode, wParam, lParam)，lParam 是 MSLLHOOKSTRUCT*：
;   x64 下 pt.x=0 pt.y=4 mouseData=8 flags=12；flags & 0x1 = 注入事件（Send/MouseClick 发的），
;   要跳过，免得把自己回放/连点器发出去的鼠标事件又录一遍。
;   wParam 只来 DOWN 侧消息（LL 钩子不收 WM_NC*），所以不会左右键各记两遍。
;
; 【坑 R9】「鼠标键名」和「MouseClick 按钮名」是两套，别直接丢过去
;   录制存的是**键名**：LButton / RButton / MButton / XButton1 / XButton2
;   而 MouseClick 的 WhichButton 只认：Left / Right / Middle（或首字母 L/R/M）
;   + X1（第 4 键）/ X2（第 5 键）。直接传 "RButton" 会
;   `Error: Parameter #1 of MouseClick is invalid. Specifically: RButton` —— 回放当场挂。
;   滚轮那四个（WheelUp/WheelDown/WheelLeft/WheelRight）两边同名，不用转。
;   统一由 RcClickName() 在**回放时**映射：录制格式保持"键名"，不跟回放 API 绑定。
;
; 【坑 R10】询问框里打字会被 MyKeymap 的层热键吃掉 —— 必须临时 Suspend
;   MyKeymap 的层里 `*0`~`*9` 都占着（CapsLock 层=窗口尺寸、CapsLock+F 层=F1~F10、
;   逗号/句号/分号层=分屏与窗口位置）。触发回放往往正是「按住 CapsLock + F + 9」，
;   这时 CapsLock 还按着、层是启用的 -> 往 Edit 里打的数字全被层热键拦走（还顺手发 F1~F10）。
;   注意这是**值层面的**吞键，`/validate` 与「控件选项对不对」都看不出来。
;   对策：RcAsk 弹框前 `Suspend(true)`，关框后还原 `A_IsSuspended` 原值。
;   MyKeymap 自己的输入功能（lib/Functions.ahk 的 StartInputHook）就是这么干的，
;   而且它把真正的输入框放在独立进程 MyKeymap-CommandInput.exe 里 —— 同一套道理。
;   另外必须**先存 A_IsSuspended 再还原**：MyKeymap 的 SendMouseButton 用的是裸 `Suspend`
;   （切换），脚本有可能本来就处于挂起态，直接 Suspend(false) 会把它的状态搅乱。
;
; 【坑 R11】低级钩子回调里别干"重活" —— 会被 Windows 摘钩子
;   WH_MOUSE_LL 的回调必须**快返**（超过 LowLevelHooksTimeout 系统会静默把钩子卸掉，
;   之后录制就"突然不记东西了"，还不报错）。所以回调里只做取值 + 入库；
;   像画 ToolTip / 拆钩子这种要碰窗口的操作，一律 `SetTimer(fn, -1)` 挂到回调外面做。
;   RcHoldInfoSet（刷状态提示的事件行，外加 60ms 节流）与 RcFull（录满上限）都是这么干的。
;
; 【坑 R12】「一直循环」必须自己让出一拍，否则连停止键都进不来
;   记录很短 / 倍速高的时候，一整轮可能耗时 ≈0ms。这时 while 会**空转**，AHK 的消息
;   循环拿不到执行机会 -> 热键（含安全键 Pause）根本派发不出去 -> 表现就是"循环起来
;   停不掉，只能重启脚本"。对策：每轮开头（取 base **之前**）`Sleep(1)`，轮间恒定让一拍。
;   只做"每轮一次"，别在事件之间加延迟 —— 那会破坏回放的时间对齐。
;
; 【坑 R13】"按下/抬起"必须成对，两头都得兜底
;   拖拽拆成 d…u 之后就出现了"中间态"。两处会把它撕开：
;     ① 录制侧：录到一半按停（按下还没抬起）-> 列表里只有 d 没有 u；
;        对策 RcFlushDown()：停了就补一条 u（拖拽必须补，普通点击补成 c）。
;     ② 回放侧：放到 d 和 u 之间被停止键打断 -> 系统层面那个键一直按着（鼠标像粘住）；
;        对策 RcRun 里记 held，循环结束后无条件 RcReleaseHeld()。
;   松开**不能用 MouseClick(...,"U")** —— 它会先把光标挪到指定坐标再松，位置就错了；
;   用 mouse_event(0x0004/0x0010/0x0020/0x0100+dxButton) 纯松键。
;
; 【坑 R14】ToolTip 的 x/y **不是同一套量纲** —— x 是屏幕物理像素，y 相对工作区
;   实测：同一个 y=14，落在屏幕上是 46+14=60（本机任务栏在顶）。
;   ⇒ 贴 y 方向直接传 RC_HoldMargin(14) 就对，**别**再去减任务栏高度；
;     x 方向贴左边缘直接给 14 就行（屏幕物理像素从 0 起算）。
;   （自建 Gui 那套"x/y 物理像素 vs w/h 被 DPI 放大"的坑随方案废弃，细节留在
;    skill ahk-static-verify 里，这里不重复。）
;
; 【坑 R15】ToolTip 其实**可以半透明**（这条以前写错过），但每次重画会被重置
;   ① ToolTip 窗口本身就是 **layered**（WS_EX_LAYERED），`WinSetTransparent(204, hwnd)`
;      实测真的吃：`GetLayeredWindowAttributes` 回 `alpha=204 flags=2 (LWA_ALPHA)`。
;      **默认是 255**；但每次 `ToolTip(...)` 重画都会**被打回 255** ⇒ 重画后必须重设一遍。
;   ② 要给 ToolTip 设透明度得先拿到**本进程**的那个 tooltips_class32 窗口：
;      `WinSetTransparent(..., "ahk_class tooltips_class32")` 可能选到别的进程的；
;      按 `WinGetList` + `GetWindowThreadProcessId == GetCurrentProcessId` 过滤。
;      窗口是**复用**的（反复 ToolTip 不换 Hwnd），所以找到就缓存。
;   ③ 透明度是**整窗**的 —— 字体也一起淡（20% 透明 ≈ alpha 204）。要"只淡背景、
;      字保持实心"只能自绘，但**别**叠两个 AlwaysOnTop 窗口：z 序互跳 ⇒
;      "字一会儿黑一会儿白"（实测）。
;====================================================================

; ========== 配置参数 ==========
RC_TipNo        := 7        ; 专用 ToolTip 通道，避开 1/5/6
RC_MaxEvents    := 50000    ; 事件条数上限，超了自动停（防手滑录一整晚）
RC_SpeedMin     := 0.1      ; 倍速下限
RC_SpeedMax     := 10       ; 倍速上限
RC_CountMax     := 9999     ; 循环次数上限
RC_MoveMinPx    := 4        ; 光标挪动超过几像素才算"一次移动"（也是拖拽的起判阈值）
RC_StartDelayMs := 800      ; 弹窗确认到真正开跑之间的缓冲(ms)，给手离开鼠标的时间
RC_HoldNo       := 8        ; 状态提示的 ToolTip 通道（岔开短提示的 7）
RC_HoldAlphaPct := 20       ; 状态提示的**默认透明度**(%)：20 = 20% 透 ⇒ alpha 204。
                            ;   RecToggle / RecPlay 的末位参数可覆盖它；0 = 完全不透明（同"脚本[停止]"）。
RC_HoldMargin   := 14       ; 贴**屏幕左上角**的留白(像素)：x / y 都用它
RC_InfoMinMs    := 60       ; 第 3/4 行(当前事件)的最小重绘间隔(ms)，密集事件别把钩子拖慢
RC_AskSaveOnStop := false   ; 录完（**用户主动停**）要不要问"保存成脚本文件" —— 默认不问；
                            ;   开了的话，框上的默认按钮是"不保存"
RC_AskLoadOnEmpty := true   ; 按回放但手里没内容时，问不问"去加载一个脚本" —— 默认问；
                            ;   框上的默认按钮是"加载"
RC_SaveTag      := "MyKeymap KeyRecorder"   ; 写进脚本文件当"身份证"，加载时对不上就拒收
RC_SaveVer      := 1        ; 脚本文件格式版本（将来改结构时好做兼容判断）
RC_ModKeys      := ["Shift", "LShift", "RShift", "Control", "LControl", "RControl", "Alt", "LAlt", "RAlt", "LWin", "RWin"]
RC_FlashMs    := 2000       ; "闪一下"状态条的**兜底**停留时长(ms)（保存/加载成功后那条）
RC_FlashWait  := 400        ; 先等"触发它的那次输入"老去，之后才进入"一动就收"
RC_FlashIdle  := 200        ; 判定"用户动过了"的阈值(ms)，别调小 —— A_TimeIdle 本身粒度就粗
RC_FlashPoll  := 100        ; 上面这个判定的轮询间隔(ms)
RC_FlashArmed := false      ; 两段式判定的第 2 段是否已武装
RC_FlashT     := 0          ; 这条状态条出现的时刻(A_TickCount)，算兜底用

; ========== 内部状态 ==========
RC_Rec       := false      ; 正在录制
RC_Play      := false      ; 正在回放
RC_Abort     := false      ; 回放中断标志（RecStop 置位）
RC_Hook      := ""         ; InputHook 实例
RC_Ignore    := 0          ; 忽略键集合(Map)，首次用时建成
RC_Ev        := []         ; 事件数组
RC_Freq      := 0          ; QPC 频率，首次用时初始化
RC_T0        := 0          ; 录制起点(QPC 计数)
RC_RecMove   := false      ; 本次录制是否连鼠标轨迹一起录（每次开录时由询问框定）
RC_MvX       := -1         ; 去重/拖拽起判用：上次记录的光标位置
RC_MvY       := -1
RC_Down      := 0          ; 已按下还没抬起的按钮 {btn,x,y,t,drag}；0 = 没按住
                           ;   按下不立刻入库 —— 抬起时才知道这次是"点一下"还是"拖拽"
RC_MouseHook := 0          ; WH_MOUSE_LL 钩子句柄
RC_MouseCb   := 0          ; CallbackCreate 出来的回调指针（建一次，长期复用）
RC_HoldAlphaNow := 204     ; 本次实际用的 alpha(0-255)：RcHoldOn 时按百分比算好，RcHoldPaint 直接用
RC_HoldHwnd  := 0          ; 状态提示用的 ToolTip 窗口句柄（实测窗口是复用的，找到就缓存）
RC_HoldPainted := ""       ; 上次真正画上去的整块文案，一样就不重画（防闪）
RC_HoldTitle := ""         ; 第 1 行（脚本[录制] / 脚本[回放]），空 = 不该显示
RC_HoldSpeed := ""         ; 第 2 行的倍速（"0.8x"），空 = 第 2 行整行不显示（录制时）
RC_HoldRound := 1          ; 第 2 行方括号里的当前轮
RC_HoldTotal := ""         ; 第 2 行方括号里的总轮（次数 或 ∞）
RC_HoldInfo  := ""         ; 第 3/4 行（当前事件：按键+时长一行 + 坐标一行）
RC_InfoT     := 0          ; 上次重绘事件的时刻(QPC ms)，节流用
RC_LastDir   := ""         ; 上次存/取脚本用的目录（只在本次会话里记；没记就退回模块目录\scripts）
RC_Home      := ""         ; 本模块所在目录，载入时定一次（见 RcHomeDir）

;--------------------------------------------------------------------
; 当前时间(ms，QPC)。RC_Freq 只取一次
;--------------------------------------------------------------------
RcNow() {
    global RC_Freq
    if (!RC_Freq) {
        f := 0
        DllCall("kernel32\QueryPerformanceFrequency", "Int64*", &f)
        RC_Freq := f ? f : 1000        ; 取不到就当毫秒用，不让它变成除零
    }
    c := 0
    DllCall("kernel32\QueryPerformanceCounter", "Int64*", &c)
    return c / (RC_Freq / 1000)
}

;--------------------------------------------------------------------
; 短提示：贴在光标旁边、2 秒自消，复用 AutoClick.ahk 的 AcTip（通道 7）
;   只用于"一瞬间的状态"（脚本[停止] / 没内容 / 已清空）
;--------------------------------------------------------------------
RcTip(text) {
    global RC_TipNo
    AcMouseScreen(&mx, &my)
    AcTip(text, mx, my, RC_TipNo)
}

;--------------------------------------------------------------------
; 状态提示：录制 / 回放期间挂在**屏幕左上角**的多行状态条，按停止键才收起
;   标题 / 模式（倍速 + [当前轮/总轮]，只有回放有）/ 按键+时长 / 坐标
;
; 【用系统的 ToolTip 窗口】省事、稳定、不会闪（自建 Gui 的两版都翻过车，见【坑 R15】）。
;   两个原来以为做不到的点，实测都能：
;     ① 半透明 —— ToolTip 窗口本身就是 **layered** 的，`WinSetTransparent(204)` 真的吃
;        （实测 flags=2 LWA_ALPHA、alpha=204）。只是**每次重画会被重置回 255**，
;        所以每次 `ToolTip(...)` 之后都要重设一遍。
;     ② 不跟光标 —— 显式给 x/y 就固定在那儿（不给才跟光标）。
;   位置：贴**屏幕左上角**，x / y 都给 RC_HoldMargin（坐标语义见【坑 R14】）。
;--------------------------------------------------------------------
; 透明度(%) -> WinSetTransparent 的 alpha(0-255)
;   pct 不写 / 传空 -> 用模块默认 RC_HoldAlphaPct
;   0 = 完全不透明(alpha 255)；100 = 全透(alpha 0)。超范围自动钳住。
;--------------------------------------------------------------------
RcAlphaPct(pct := "") {
    global RC_HoldAlphaPct
    p := IsNumber(pct) ? pct + 0 : RC_HoldAlphaPct
    return Round(255 * (100 - RcClamp(p, 0, 100)) / 100)
}

RcHoldOn(title, pct := "") {
    global RC_HoldTitle, RC_HoldSpeed, RC_HoldRound, RC_HoldTotal, RC_HoldInfo, RC_HoldPainted, RC_InfoT, RC_HoldAlphaNow
    RC_HoldAlphaNow := RcAlphaPct(pct)
    RC_HoldTitle := title
    RC_HoldSpeed := ""
    RC_HoldRound := 1
    RC_HoldTotal := ""
    RC_HoldInfo := ""
    RC_HoldPainted := ""
    RC_InfoT := 0
    RcHoldPaint()
}

RcHoldOff() {
    global RC_HoldTitle, RC_HoldSpeed, RC_HoldTotal, RC_HoldInfo, RC_HoldPainted, RC_HoldNo
    RC_HoldTitle := ""
    RC_HoldSpeed := ""
    RC_HoldTotal := ""
    RC_HoldInfo := ""
    RC_HoldPainted := ""
    ToolTip("", , , RC_HoldNo)          ; 清空这个通道 = 收起状态提示
}

;--------------------------------------------------------------------
; "闪一下"的状态条：保存 / 加载成功后用
;   同一个通道(8)、同一个位置（屏幕左上角），但**完全不透明** —— 跟"脚本[停止]"一样清楚
;   （录制/回放那条是半透明的，这里故意不用）。
;   什么时候收：**2 秒兜底 + 一动（鼠标或按键）就收**，谁先到算谁。
;
; 【为什么用 A_TimeIdle 而不是 A_TimeIdlePhysical】(2026-09-19 查官方文档定论)
;   官方原文：只装一个钩子时，只有该类型钩子的**物理**输入影响 A_TimeIdlePhysical，
;   另一种输入"both physical and artificial, has no effect"。
;   MyKeymap 有 #UseHook ⇒ 键盘钩子常驻；而鼠标钩子**只在录制期间**才装
;   ⇒ 用 Physical 版的话鼠标移动压根不生效，"一动就收"只能靠按键。
;   A_TimeIdle 与钩子无关，键盘/鼠标/其他输入都算（代价：连点器那种**注入**输入也算 ——
;   那会走不到第 2 段，退化成 2 秒兜底，正是我们想要的）。
;   两段式：先等"触发它的那一下"老去（否则刚弹出来就被自己的按键收掉），再等下一次输入。
;--------------------------------------------------------------------
RcHoldFlash(title, info := "") {
    global RC_HoldInfo, RC_HoldPainted, RC_FlashArmed, RC_FlashT, RC_FlashMs, RC_FlashPoll
    RcHoldOn(title, 0)                 ; 0 = 完全不透明（同"脚本[停止]"）
    if (info != "") {                  ; 第 2 行：条数 / 时长
        RC_HoldInfo := info
        RC_HoldPainted := ""
        RcHoldPaint()
    }
    RC_FlashArmed := false
    RC_FlashT := A_TickCount
    SetTimer(RcHoldFlashTick, RC_FlashPoll)
}

RcHoldFlashTick() {
    global RC_FlashArmed, RC_FlashT, RC_FlashMs, RC_FlashWait, RC_FlashIdle
    global RC_Rec, RC_Play
    if (RC_Rec || RC_Play) {           ; 已经在录/在放：停表，别误收真正的状态条
        SetTimer(RcHoldFlashTick, 0)
        return
    }
    if (A_TickCount - RC_FlashT > RC_FlashMs) {    ; 兜底先判 —— 跟"有没有人动"无关
        SetTimer(RcHoldFlashTick, 0)
        RcHoldOff()
        return
    }
    if (!RC_FlashArmed) {              ; 第 1 段：等触发它的那次输入"老去"
        if (A_TimeIdle > RC_FlashWait)
            RC_FlashArmed := true
        return
    }
    if (A_TimeIdle < RC_FlashIdle) {   ; 第 2 段：动过了就收
        SetTimer(RcHoldFlashTick, 0)
        RcHoldOff()
    }
}

; 第 2 行整块：倍速 + 轮次（回放开跑时定一次总轮，之后每轮只改当前轮）
RcHoldSetMode(speedStr, total) {
    global RC_HoldSpeed, RC_HoldTotal, RC_HoldRound, RC_HoldPainted
    RC_HoldSpeed := speedStr
    RC_HoldTotal := total
    RC_HoldRound := 1
    RC_HoldPainted := ""
    RcHoldPaint()
}

; 每轮开头：当前轮次
RcHoldSetRound(n) {
    global RC_HoldRound
    RC_HoldRound := n
    RcHoldPaint()
}

; 第 3/4 行：当前事件（按键+时长一行 + 坐标一行，由 RcEventInfo 给）。**不直接重绘** ——
;   录制时这个函数是在 LL 钩子回调里被调的，
;   钩子里干重活会被 Windows 摘钩子（见【坑 R11】）；这里只记状态 + 挂 -1 定时器，
;   出了回调再画。定时器按 RC_InfoMinMs 节流。
RcHoldInfoSet(text) {
    global RC_HoldInfo, RC_InfoT, RC_InfoMinMs
    RC_HoldInfo := text
    now := RcNow()
    if (now - RC_InfoT < RC_InfoMinMs)
        return
    RC_InfoT := now
    SetTimer(RcHoldPaint, -1)
}

;--------------------------------------------------------------------
; 状态提示那个 ToolTip 窗口的句柄
;   为什么要自己找：`WinSetTransparent(..., "ahk_class tooltips_class32")` 可能选到
;   **别的进程**的 tooltip 窗口，得按 PID 过滤出本脚本自己的那个。
;   实测窗口是**复用**的（反复 ToolTip 不换 Hwnd），所以找到就缓存。
;--------------------------------------------------------------------
RcTipWin() {
    global RC_HoldHwnd
    if (RC_HoldHwnd && DllCall("user32\IsWindow", "Ptr", RC_HoldHwnd))
        return RC_HoldHwnd
    pid := DllCall("GetCurrentProcessId", "UInt")
    for h in WinGetList("ahk_class tooltips_class32") {
        p := 0
        DllCall("user32\GetWindowThreadProcessId", "Ptr", h, "UInt*", &p)
        if (p = pid) {
            RC_HoldHwnd := h
            return h
        }
    }
    return 0
}

;--------------------------------------------------------------------
; 画（内容没变就什么都不做，省得闪）
;   ToolTip 的 `n 就是换行；行数变了窗口自己会重排。
;   位置：**贴屏幕左上角** —— x / y 都给 RC_HoldMargin，不给才会跟光标跑。
;     x 是屏幕物理像素、y 相对工作区（见【坑 R14】）。
;   透明度是**整窗**的，而且每次 ToolTip 重画都会被打回 255 ⇒ 画完必须重设一遍。
;--------------------------------------------------------------------
RcHoldPaint() {
    global RC_HoldTitle, RC_HoldPainted, RC_HoldNo, RC_HoldAlphaNow, RC_HoldMargin

    if (RC_HoldTitle = "") {
        ToolTip("", , , RC_HoldNo)
        return
    }
    text := RcHoldCompose()
    if (text = RC_HoldPainted)
        return
    RC_HoldPainted := text

    ToolTip(text, RC_HoldMargin, RC_HoldMargin, RC_HoldNo)

    h := RcTipWin()
    if (!h)
        return
    try WinSetTransparent(RC_HoldAlphaNow, "ahk_id " h)   ; 每次重画都会被打回 255，必须重设
}

;--------------------------------------------------------------------
; 拼装状态提示（空的整行不显示）—— 单独成函数只为能直接被探针调
;   标题 / 倍速+轮次(回放才有) / 按键+时长 / 坐标   —— **最多 4 行**
;   第 2 行形如：  0.8x [1/99]   或   0.8x [1/∞]
;   第 3、4 行由 RcEventInfo 一次给出（内部带 `n）
;   模式文字（"循环/次数"）不写了 —— 方括号里的分母是不是 ∞ 一看就知道。
;--------------------------------------------------------------------
RcHoldCompose() {
    global RC_HoldTitle, RC_HoldSpeed, RC_HoldRound, RC_HoldTotal, RC_HoldInfo
    text := RC_HoldTitle
    if (RC_HoldSpeed != "")
        text .= "`n" RC_HoldSpeed " [" RC_HoldRound "/" RC_HoldTotal "]"
    if (RC_HoldInfo != "")
        text .= "`n" RC_HoldInfo
    return text
}

;--------------------------------------------------------------------
; 事件 -> 提示的第 3 / 4 行（两行，中间用 `n 接）
;   第 3 行 按键(或按钮) + 时长： (左键) 3.1s / (上滚) 91.1s / (Ctrl+S) 3.1s
;   第 4 行 坐标：  [123,192]   （键盘事件没有坐标 ⇒ 这行整行不出，提示只剩 3 行）
;   时长 = 该事件在录制里的时间偏移，不随倍速变（跟"第几秒发生的"一致）
;--------------------------------------------------------------------
RcEventInfo(e) {
    switch e.type {
        case "k":
            k := "(" RcKeyLabel(e) ")"
            pos := ""
        case "c":
            k := "(" RcBtnLabel(e.btn) ")"
            pos := "[" e.x "," e.y "]"
        case "d":
            k := "(" RcBtnLabel(e.btn) "按下)"                       ; 拖拽的起点
            pos := "[" e.x "," e.y "]"
        case "u":
            k := "(" RcBtnLabel(e.btn) "抬起)"                       ; 拖拽的终点
            pos := "[" e.x "," e.y "]"
        case "w":
            k := "(" RcWheelLabel(e.dir) ")"
            pos := "[" e.x "," e.y "]"
        case "m":
            k := "(移动)"
            pos := "[" e.x "," e.y "]"
        default:
            return ""
    }
    ; 第 3 行 = 按键 + 时长（时间跟在按键右边），第 4 行 = 坐标（键盘事件没有坐标就不出这行）
    head := k . " " . RcSecs(e.t) . "s"
    return (pos = "") ? head : head . "`n" . pos
}

;--------------------------------------------------------------------
; ms -> "3.1" 这种一位小数（不用 Format：本机 Format 的格式串语义没验过，Round 稳）
;--------------------------------------------------------------------
RcSecs(ms) {
    s := String(Round(ms / 1000, 1))
    return InStr(s, ".") ? s : s ".0"
}

RcKeyLabel(e) {
    mods := e.HasProp("mods") ? e.mods : ""
    s := ""
    if InStr(mods, "^")
        s .= "Ctrl+"
    if InStr(mods, "!")
        s .= "Alt+"
    if InStr(mods, "+")
        s .= "Shift+"
    if InStr(mods, "#")
        s .= "Win+"
    k := e.key
    if (s != "" && StrLen(k) = 1)
        k := StrUpper(k)            ; 带修饰键时单个字母显示成大写，好认
    return s . k
}

RcBtnLabel(btn) {
    switch btn {
        case "LButton":  return "左键"
        case "RButton":  return "右键"
        case "MButton":  return "中键"
        case "XButton1": return "X1"
        case "XButton2": return "X2"
        default:         return btn
    }
}

RcWheelLabel(dir) {
    switch dir {
        case "WheelUp":    return "上滚"
        case "WheelDown":  return "下滚"
        case "WheelLeft":  return "左滚"
        case "WheelRight": return "右滚"
        default:           return dir
    }
}

;--------------------------------------------------------------------
; 数值钳位
;--------------------------------------------------------------------
RcClamp(v, lo, hi) {
    if (v < lo)
        return lo
    if (v > hi)
        return hi
    return v
}

;--------------------------------------------------------------------
; 热键字符串 -> 裸键名
;   "*F8" -> "F8"、"~*LButton" -> "LButton"、"*CapsLock & p" -> "p"
;   解析不出来返回 ""
;--------------------------------------------------------------------
RcParseHotkey(s) {
    s := Trim(String(s))
    loop {
        if (s = "")
            break
        c := SubStr(s, 1, 1)
        if (c = "~" || c = "*" || c = "$" || c = "#" || c = "!" || c = "^" || c = "+" || c = "<" || c = ">")
            s := Trim(SubStr(s, 2))
        else
            break
    }
    p := InStr(s, " & ")
    if (p)
        s := Trim(SubStr(s, p + 3))
    return s
}

;--------------------------------------------------------------------
; 是不是"纯修饰键"（本身不记，只当状态用，见【坑 R3】）
;--------------------------------------------------------------------
RcIsModKey(key) {
    global RC_ModKeys
    for m in RC_ModKeys {
        if (key = m)
            return true
    }
    return false
}

;--------------------------------------------------------------------
; VK/SC -> 可发送的键名
;   拿不到键名（多媒体键等）就退化成 vk 形式，Send 一样吃（见【坑 R2】）
;--------------------------------------------------------------------
RcVkName(vk, sc) {
    v := Format("vk{:X}sc{:X}", vk, sc)
    try {
        n := GetKeyName(v)
        if (n != "")
            return n
    }
    return v
}

;--------------------------------------------------------------------
; 当时按住的修饰键 -> Send 前缀
;--------------------------------------------------------------------
RcModPrefix() {
    m := ""
    if (GetKeyState("Ctrl"))
        m .= "^"
    if (GetKeyState("Alt"))
        m .= "!"
    if (GetKeyState("Shift"))
        m .= "+"
    if (GetKeyState("LWin") || GetKeyState("RWin"))
        m .= "#"
    return m
}

;--------------------------------------------------------------------
; 记一条事件（内部统一入口，顺便管上限）
;   t 不传 = 用"现在"；传了 = 用给定偏移(ms)。
;   需要"补记一条过去发生的事"时用得上：拖拽是按下那一刻开始算的，
;   直到动起来才知道是拖拽，这时补的 d 事件必须回填按下的时间戳。
;--------------------------------------------------------------------
RcPush(ev, t := "") {
    global RC_Ev, RC_T0, RC_MaxEvents
    if (RC_Ev.Length >= RC_MaxEvents) {
        SetTimer(RcFull, -1)         ; 满了：拆钩子推到下一拍，别在钩子回调里拆自己
        return
    }
    ev.t := (t = "") ? (RcNow() - RC_T0) : t
    RC_Ev.Push(ev)
    RcHoldInfoSet(RcEventInfo(ev))    ; 状态提示事件行：实时刷按键/坐标/时长
}

;--------------------------------------------------------------------
; 条数到顶后的收尾（定时器拍里跑）
;--------------------------------------------------------------------
RcFull() {
    global RC_MaxEvents
    RecStop(true)                     ; 先安静地收掉（撤状态提示、别弹短提示）
    RcTip("脚本[停止]`n已满 " RC_MaxEvents " 条")
}

;--------------------------------------------------------------------
; 键盘回调：InputHook 的 OnKeyDown（签名为 (ih, vk, sc)）
;--------------------------------------------------------------------
RcKeyDown(ih, vk, sc) {
    global RC_Rec, RC_Ignore
    if (!RC_Rec)
        return
    key := RcVkName(vk, sc)
    if (RcIsModKey(key))
        return                                   ; 纯修饰键只当状态，见【坑 R3】
    if (IsObject(RC_Ignore) && RC_Ignore.Has(StrLower(key)))
        return                                   ; 启停键自己，见【坑 R1】
    RcPush({type: "k", key: key, mods: RcModPrefix()})
}

;--------------------------------------------------------------------
; 鼠标低级钩子回调（WH_MOUSE_LL，见【坑 R8】）
;   必须原样把返回值透给 CallNextHookEx；里面一律 try 住，回调里抛异常会弹框
;--------------------------------------------------------------------
RcMouseHookCb(nCode, wParam, lParam) {
    if (nCode >= 0) {
        try RcMouseEvent(wParam, lParam)
    }
    return DllCall("user32\CallNextHookEx", "Ptr", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam, "Ptr")
}

;--------------------------------------------------------------------
; 鼠标事件 -> 入库
;   msg:  WM_MOUSEMOVE / WM_*BUTTONDOWN / WM_*BUTTONUP / WM_MOUSEWHEEL / WM_MOUSEHWHEEL
;   lp:   MSLLHOOKSTRUCT*
;
; 【要点】按下不当场入库，先记进 RC_Down 待定：
;   - 抬起时**中间没动过** -> 记一条 c（点一下），坐标取按下点、时间取按下时刻；
;   - 中间动过           -> 记 d（按下）+ 若干 m（轨迹）+ u（抬起），回放才还原得出拖拽。
;   这样"选文字 / 拖框"才能录出来；老写法把按下直接记成 c，回放就只剩一个点击。
;--------------------------------------------------------------------
RcMouseEvent(msg, lp) {
    global RC_Rec, RC_RecMove, RC_MvX, RC_MvY, RC_MoveMinPx, RC_Down, RC_T0
    if (!RC_Rec)
        return
    if (NumGet(lp, 12, "UInt") & 0x3)                ; 注入事件 -> 跳过，见【坑 R8】
        return

    x := NumGet(lp, 0, "Int")
    y := NumGet(lp, 4, "Int")
    isMove := (msg = 0x0200)

    ; 没开"录轨迹"、也没按住任何键 -> 移动不记（按住时的移动是拖拽，必须记）
    if (isMove && !RC_RecMove && !RC_Down)
        return

    if (isMove) {                                    ; WM_MOUSEMOVE
        if (Abs(x - RC_MvX) < RC_MoveMinPx && Abs(y - RC_MvY) < RC_MoveMinPx)
            return                                   ; 抖动，不算一次移动
        if (RC_Down && !RC_Down.drag) {              ; 动了 -> 这其实是一次拖拽
            RC_Down.drag := true
            RcPush({type: "d", btn: RC_Down.btn, x: RC_Down.x, y: RC_Down.y}, RC_Down.t)
        }
        RC_MvX := x
        RC_MvY := y
        RcPush({type: "m", x: x, y: y})
        return
    }

    md := NumGet(lp, 8, "UInt")
    if (msg = 0x0201 || msg = 0x0204 || msg = 0x0207 || msg = 0x020B) {   ; *BUTTONDOWN
        if (msg = 0x0201)
            btn := "LButton"
        else if (msg = 0x0204)
            btn := "RButton"
        else if (msg = 0x0207)
            btn := "MButton"
        else
            btn := (((md >> 16) & 0xFFFF) = 1) ? "XButton1" : "XButton2"
        RC_Down := {btn: btn, x: x, y: y, t: RcNow() - RC_T0, drag: false}
        RC_MvX := x                                  ; 起判基准 = 按下点，之前的小抖动不算拖拽
        RC_MvY := y
        return
    }

    if (msg = 0x0202 || msg = 0x0205 || msg = 0x0208 || msg = 0x020C) {   ; *BUTTONUP
        if (RC_Down) {
            if (RC_Down.drag)
                RcPush({type: "u", btn: RC_Down.btn, x: x, y: y})
            else
                RcPush({type: "c", btn: RC_Down.btn, x: RC_Down.x, y: RC_Down.y}, RC_Down.t)
            RC_Down := 0
        }
        return
    }

    if (msg = 0x020A || msg = 0x020E) {                                   ; 滚轮
        d := (md >> 16) & 0xFFFF
        if (d >= 0x8000)
            d -= 0x10000                             ; 转有符号：正 = 上 / 右
        dir := (msg = 0x020A) ? (d > 0 ? "WheelUp" : "WheelDown")
                              : (d > 0 ? "WheelRight" : "WheelLeft")
        RcPush({type: "w", dir: dir, x: x, y: y})
    }
}

;--------------------------------------------------------------------
; 收尾时把"还按着的那个键"补完
;   录到一半停了（按下但没抬起）：是拖拽就补一条 u（**必须补**，否则回放时
;   那个键会一直按着、系统层面真的粘住），是普通点击就补一条 c。
;--------------------------------------------------------------------
RcFlushDown() {
    global RC_Down, RC_MvX, RC_MvY
    if (!RC_Down)
        return
    if (RC_Down.drag) {
        ux := (RC_MvX >= 0) ? RC_MvX : RC_Down.x
        uy := (RC_MvY >= 0) ? RC_MvY : RC_Down.y
        RcPush({type: "u", btn: RC_Down.btn, x: ux, y: uy})
    } else
        RcPush({type: "c", btn: RC_Down.btn, x: RC_Down.x, y: RC_Down.y}, RC_Down.t)
    RC_Down := 0
}

;--------------------------------------------------------------------
; 装上 / 卸下 录制钩子（键盘 InputHook + 鼠标 WH_MOUSE_LL）
;   键鼠都**不拦截**：InputHook 靠 VisibleText/VisibleNonText 放行（见【坑 R7】）；
;   LL 钩子本来就只是旁观，回调里不改任何东西。
;--------------------------------------------------------------------
RcHookOn() {
    global RC_Hook, RC_RecMove, RC_MvX, RC_MvY, RC_MouseHook, RC_MouseCb, RC_Down

    RC_Hook := InputHook("L0")          ; L0：不缓冲文本、也没有 1023 长度上限
    RC_Hook.VisibleText := true         ; 不设这两行，打字会被钩子吃掉
    RC_Hook.VisibleNonText := true
    RC_Hook.OnKeyDown := RcKeyDown
    RC_Hook.Start()

    RC_MvX := -1                        ; 重置轨迹去重点，第一条移动一定记下
    RC_MvY := -1
    RC_Down := 0                        ; 清掉上一次残留的"待定按下"

    if (!RC_MouseCb)
        RC_MouseCb := CallbackCreate(RcMouseHookCb, "C", 3)
    if (!RC_MouseHook)
        RC_MouseHook := DllCall("user32\SetWindowsHookEx", "Int", 14, "Ptr", RC_MouseCb, "Ptr", 0, "UInt", 0, "Ptr")
}

RcHookOff() {
    global RC_Hook, RC_MouseHook
    if IsObject(RC_Hook) {
        try RC_Hook.Stop()
        RC_Hook := ""
    }
    if (RC_MouseHook) {
        try DllCall("user32\UnhookWindowsHookEx", "Ptr", RC_MouseHook)
        RC_MouseHook := 0
    }
}

;--------------------------------------------------------------------
; 对外：录制 开 / 关
;   ignoreKey   额外的忽略键名（不写 = 只忽略触发本次调用的那个键）
;   recordMove  是否连鼠标轨迹一起录。**不写 = 先弹框问**（默认勾"录鼠标移动"）；
;               传 true/false 就直接照它走、不弹框（想固定行为时用这个写法）。
;   注意：拖拽（按下-移动-抬起）的轨迹**总是**记，跟 recordMove 无关 ——
;   否则"选文字/拖框"回放出来会走样。
;   每次"开"都是**重新录**（清掉上一次的内容）；想叠加请用 RecClear 之外的
;   两次录制然后自己拼 —— 不做隐式累积，语义才好猜。
;   alphaPct   状态提示的透明度(%)。**不写 = 用模块默认 RC_HoldAlphaPct(20)**；
;              0 = 完全不透明，100 = 全透。config.json 里传的就是这个。
;--------------------------------------------------------------------
RecToggle(ignoreKey := "", recordMove := "", alphaPct := "") {
    global RC_Rec, RC_Play, RC_Ev, RC_Ignore, RC_T0, RC_RecMove

    if (RC_Rec || RC_Play) {          ; 录制中 / 回放中 -> 本次调用当"停"
        RecStop()
        return
    }

    if (recordMove == "") {           ; 没指定 -> 弹框问（取消 = 这次不录）
        mv := RcAskMoveAsk()
        if (mv == "")
            return
        recordMove := mv
    }

    ; 忽略集合：触发本函数的那个热键 + 调用方显式指定的
    RC_Ignore := Map()
    k := RcParseHotkey(A_ThisHotkey)
    if (k != "")
        RC_Ignore[StrLower(k)] := 1
    k2 := Trim(String(ignoreKey))
    if (k2 != "")
        RC_Ignore[StrLower(k2)] := 1

    RC_Ev := []                       ; 开录 = 从头录
    RC_RecMove := recordMove ? true : false
    RC_T0 := RcNow()
    RC_Rec := true
    RcHookOn()

    RcHoldOn("脚本[录制]", alphaPct)
}

;--------------------------------------------------------------------
; 对外：强制停止 —— 录制停录、回放停跑，都没在跑就是空操作
;   安全键接这个；回放中途按下去会立刻停（靠 RC_Abort，见【坑 R5】）
;   quiet=true 供内部调用（回放前先收掉录制）—— 别闪一下"脚本[停止]"
;--------------------------------------------------------------------
RecStop(quiet := false) {
    global RC_Rec, RC_Play, RC_Abort, RC_Ev, RC_RecMove, RC_AskSaveOnStop
    wasRec := RC_Rec
    wasPlay := RC_Play
    RC_Rec := false                   ; 先落标志：钩子拆掉过程中漏进来的事件一律不入库
    RC_Abort := true
    if (wasRec) {
        RcFlushDown()                 ; 按下还没抬起 -> 补完（拖拽必须补，见 RcFlushDown）
        RcHookOff()
        RC_RecMove := false
    }
    if (!wasRec && !wasPlay)
        return                        ; 都没在跑：纯空操作，别弹提示
    RcHoldOff()
    if (!quiet)
        RcTip("脚本[停止]")
    ; quiet=true 是内部收尾（回放前先收录制 / 录满自动停）—— 那两种都别弹保存询问，
    ;   免得机器自己把框推到你脸上。只有"录完之后你自己按的停"才问。
    if (wasRec && !quiet && RC_AskSaveOnStop && RC_Ev.Length)
        RcAskSaveAfterRec()
}

;--------------------------------------------------------------------
; 录完问一句"要不要存成脚本"（由 RC_AskSaveOnStop 控制，默认关）
;   默认按钮是"不保存"——随手回车也不会多出个文件来；
;   选了"保存"就接着弹系统另存为框（取消那个框 = 只是没存，不影响内存里这段内容）。
;--------------------------------------------------------------------
RcAskSaveAfterRec() {
    global RC_Ev
    if (!RcConfirm("录制结束", "要保存这段录制吗？（" RC_Ev.Length " 条 / " RcFmtDur(RcTotalMs()) "）",
                   "保存...", "不保存", false))
        return
    RecSave()
}

;--------------------------------------------------------------------
; 对外：清空已录内容
;--------------------------------------------------------------------
RecClear() {
    global RC_Ev
    RC_Ev := []
    RcTip("已清空")
}

;--------------------------------------------------------------------
; 对外：一行说明
;--------------------------------------------------------------------
RecInfo() {
    global RC_Ev
    if (!RC_Ev.Length)
        return "没内容"
    return RC_Ev.Length " 条 / " RcFmtDur(RcTotalMs())
}

;--------------------------------------------------------------------
; 录制总时长(ms)：最后一条事件的时间戳
;--------------------------------------------------------------------
RcTotalMs() {
    global RC_Ev
    if (!RC_Ev.Length)
        return 0
    return RC_Ev[RC_Ev.Length].t
}

;--------------------------------------------------------------------
; 时长格式化：3421 -> "3.4 秒"；72500 -> "1分12秒"
;--------------------------------------------------------------------
RcFmtDur(ms) {
    if (ms < 1000)
        return Round(ms) " 毫秒"
    s := ms / 1000
    if (s < 60)
        return Round(s, 1) " 秒"
    return Floor(s / 60) "分" Floor(Mod(s, 60)) "秒"   ; 截断，别 Round：72500 应该是 1分12秒
}

;--------------------------------------------------------------------
; 挂起 + 弹框 + 等关（两个询问框共用）
;   Suspend 必须在**建框之后**调 —— 建框抛异常时就不会把脚本留在挂起态；
;   原值要还回去（MyKeymap 的 SendMouseButton 用裸 Suspend 切换）。
;--------------------------------------------------------------------
RcShowModal(g, opts, focusCtl := 0) {
    wasSuspended := A_IsSuspended
    Suspend(true)                        ; 见【坑 R10】
    try {
        g.Show(opts)
        WinActivate("ahk_id " g.Hwnd)    ; 防"窗口没拿到焦点、键盘打在别的窗口上"
        if (IsObject(focusCtl))
            try focusCtl.Focus()         ; 设焦点（如次数框），开框就能直接打数字
        WinWaitClose("ahk_id " g.Hwnd)
    } finally {
        Suspend(wasSuspended)
    }
}

;--------------------------------------------------------------------
; 开录前的询问框：这次要不要连鼠标移动一起录
;   返回 true(录移动) / false(不录) / ""(取消，不开录)
;--------------------------------------------------------------------
RcAskMoveAsk() {
    st := {move: true, ok: false, g: 0, cbMove: 0}
    RcAskMoveGui(st)
    if (!st.g)
        return ""
    RcShowModal(st.g, "w344 h112 Center")
    if (!st.ok)
        return ""
    return st.move ? true : false
}

RcAskMoveGui(st) {
    g := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "开始录制")
    g.SetFont("s9", "Microsoft YaHei UI")
    cb := g.AddCheckBox("x16 y18 w312 Checked", "录制鼠标移动")
    g.AddText("x16 y46 w312 cGray", "不勾 = 只记按键/点击/滚轮；拖拽的按下和轨迹始终会记")
    btnOK := g.AddButton("x16 y76 w152 h28 Default", "开始录制")
    btnNo := g.AddButton("x176 y76 w152 h28", "取消")

    btnOK.OnEvent("Click", (*) => RcAskMoveTake(st))
    btnNo.OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Close", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())

    st.g := g
    st.cbMove := cb
}

RcAskMoveTake(st) {
    st.move := st.cbMove.Value
    st.ok := true
    st.g.Destroy()
}

;--------------------------------------------------------------------
; 回放前的询问框：循环 / 次数 / 倍速
;   返回 Object{loops, count, speed}；取消返回 0
;   坑：① Gui 的**窗口构造选项不认 w/h**（会直接报 ERR_INVALID_OPTION），
;        尺寸只能写在 Show("w.. h..") 里；控件选项那一套是另一个解析器，支持。
;      ② 弹框期间必须 Suspend —— 见【坑 R10】，否则打进来的数字被层热键吃掉。
;      ③ 次数/倍速除了能键入，也都能**纯鼠标**调（UpDown 微调箭头 / 下拉），
;        这样即便哪天又被什么钩子吃了键，功能也还在。
;      ④ 建框那段单独放 RcAskGui（不 Show）、取值那段单独放 RcAskTake —— 控件选项
;        写错是**建的时候就抛**，拆开才能在不出窗口的前提下把它跑一遍验证掉
;        （不拆就只能投 WM_COMMAND 触发回调，而 PostMessage 要窗口消息循环才派发，
;          测试脚本里根本转不起来）。
;--------------------------------------------------------------------
RcAsk() {
    global RC_Ev, RC_SpeedMin, RC_SpeedMax, RC_CountMax
    if (!RC_Ev.Length) {
        RcTip("没内容")
        return 0
    }

    st := {loops: false, count: "1", speed: "1", ok: false, g: 0, edCount: 0}
    RcAskGui(st)
    if (!st.g)
        return 0

    RcShowModal(st.g, "w366 h150 Center", st.edCount)
    if (!st.ok)
        return 0

    sp := st.speed + 0                       ; 非数字 -> 0
    if (!IsNumber(sp) || sp <= 0)
        sp := 1.0
    sp := RcClamp(sp + 0, RC_SpeedMin, RC_SpeedMax)

    cnt := st.count + 0
    if (!IsNumber(cnt) || cnt < 1)
        cnt := 1
    cnt := RcClamp(Round(cnt), 1, RC_CountMax)

    return {loops: (st.loops ? true : false), count: cnt, speed: sp}
}

;--------------------------------------------------------------------
; 建询问框 + 接线（**不 Show**），状态写进传入的 st
;--------------------------------------------------------------------
RcAskGui(st) {
    global RC_Ev, RC_CountMax
    g := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "键鼠回放")
    g.SetFont("s9", "Microsoft YaHei UI")
    g.AddText("x16 y14 w336", "已录：" RC_Ev.Length " 条，时长约 " RcFmtDur(RcTotalMs()))
    cbLoop := g.AddCheckBox("x16 y46 w90", "循环播放")
    g.AddText("x108 y48 w34", "次数")
    edCount := g.AddEdit("x144 y45 w54 Number", "1")
    udCount := g.AddUpDown("x199 y45 w18", "1-" RC_CountMax)   ; 必须紧跟上面的 Edit，挂载关系靠这个
    g.AddText("x226 y48 w34", "倍速")
    cbSpeed := g.AddComboBox("x262 y44 w88", ["0.3", "0.5", "0.8", "1", "1.5", "2", "3", "5", "10"])
    cbSpeed.Text := "1"
    g.AddText("x16 y74 w336 cGray", "勾上循环=一直放到底（次数框作废）；不勾=放「次数」遍")
    btnOK := g.AddButton("x16 y104 w156 h30 Default", "开始回放")
    btnNo := g.AddButton("x192 y104 w156 h30", "取消")

    btnOK.OnEvent("Click", (*) => RcAskTake(st))
    btnNo.OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Close", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    cbLoop.OnEvent("Click", (*) => RcAskLoopUI(st))

    st.g := g
    st.edCount := edCount
    st.cbLoop := cbLoop
    st.cbSpeed := cbSpeed
    st.udCount := udCount
}

;--------------------------------------------------------------------
; 勾了循环就把"次数"禁掉 —— 免得以为还要填次数（空着还以为是 bug）
;--------------------------------------------------------------------
RcAskLoopUI(st) {
    on := st.cbLoop.Value
    st.edCount.Enabled := !on
    st.udCount.Enabled := !on
}

;--------------------------------------------------------------------
; 取值 + 关框（OK 按钮的真实处理体，独立出来是为了能直接调用验证）
;--------------------------------------------------------------------
RcAskTake(st) {
    st.loops := st.cbLoop.Value
    st.count := st.edCount.Value
    st.speed := st.cbSpeed.Text
    st.ok := true
    st.g.Destroy()
}

;====================================================================
; 脚本的保存 / 加载
;   走**系统文件对话框**自己选路径，文件是 JSON。
;   对外两个：RecSave(path) / RecLoad(path)，path 不写 = 弹框选。
;   载入**只把内容装进内存**，跟"自己录一段"完完全全是同一种状态 ——
;   想放就按回放键（倍速/次数照样弹框问你）。
;   两个入口在"录制中 / 回放中"一律拒绝：录着的时候弹系统框会把录制搅乱。
;====================================================================

;--------------------------------------------------------------------
; 本模块所在目录（RC_Home 缓存一次）
;   实测（2026-09-19 探针）：include 进来的文件里，**函数体内**的 A_LineFile
;   就是该 include 文件自己的完整路径，不是宿主 bin/MyKeymap.ahk。
;   所以这里不用顶层赋值，懒算一次即可。
;--------------------------------------------------------------------
RcHomeDir() {
    global RC_Home
    if (RC_Home != "")
        return RC_Home
    SplitPath(A_LineFile, , &dir)
    RC_Home := (dir != "") ? dir : A_ScriptDir
    return RC_Home
}

;--------------------------------------------------------------------
; 文件对话框的起始目录
;   优先用**本次会话上次用过的**（存完接着取名一个很顺手）；
;   没有就 <模块目录>\scripts，不存在就建出来。
;--------------------------------------------------------------------
RcDialogDir() {
    global RC_LastDir
    if (RC_LastDir != "" && DirExist(RC_LastDir))
        return RC_LastDir
    d := RcHomeDir() . "\scripts"
    try DirCreate(d)
    return d
}

;--------------------------------------------------------------------
; 默认文件名：录制-2026-09-19-193106.json
;   带秒 —— 同一分钟里连着存两次也不会撞同一个默认名。
;   时间戳用 A_Now 直接切，不用 Format（本机 Format 的格式串语义没验过，不赌）
;--------------------------------------------------------------------
RcDefaultName() {
    ts := A_Now                        ; 形如 20260919193106
    if (StrLen(ts) < 14)
        return "录制.json"
    return "录制-" SubStr(ts, 1, 4) "-" SubStr(ts, 5, 2) "-" SubStr(ts, 7, 2)
         . "-" SubStr(ts, 9, 2) SubStr(ts, 11, 2) SubStr(ts, 13, 2) ".json"
}

;--------------------------------------------------------------------
; 通用二选一确认框（保存询问 / 加载询问共用）
;   返回 true = 选了"要"；false = 选了"不要"或关窗/按 Esc
;   defaultYes 决定哪个按钮是 Default（回车键落哪个）
;   ★ Suspend 由 RcShowModal 负责（见【坑 R10】），这里只管建框
;--------------------------------------------------------------------
RcConfirm(title, text, yesLabel, noLabel, defaultYes := true) {
    st := {yes: false, g: 0}
    RcConfirmGui(st, title, text, yesLabel, noLabel, defaultYes)
    if (!st.g)
        return false
    RcShowModal(st.g, "w380 h132 Center")
    return st.yes
}

RcConfirmGui(st, title, text, yesLabel, noLabel, defaultYes) {
    g := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", title)
    g.SetFont("s9", "Microsoft YaHei UI")
    g.AddText("x16 y16 w348", text)
    yOpt := defaultYes ? " Default" : ""
    nOpt := defaultYes ? "" : " Default"
    btnYes := g.AddButton("y64 w162 h28" yOpt, yesLabel)
    btnNo  := g.AddButton("x190 y64 w174 h28" nOpt, noLabel)
    btnYes.OnEvent("Click", (*) => RcConfirmTake(st, true))
    btnNo.OnEvent("Click", (*) => RcConfirmTake(st, false))
    g.OnEvent("Close", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    st.g := g
}

RcConfirmTake(st, yes) {
    st.yes := yes
    st.g.Destroy()
}

;--------------------------------------------------------------------
; 系统文件对话框（另存为 / 打开）—— **必须裹 Suspend**，见【坑 R10】
;   起因（2026-09-19 定位）：`Tab+;` 触发保存时 Tab 还按着 ⇒ "Tab 模式"层是启用的
;   ⇒ 往文件名框里打的字先被层热键拦走。Tab 层绑了 a b c d e g h i j k l m n o q s u v w z，
;   **没绑** f p r t x y ⇒ 现象是"有的字母打不进去、有的正常"；按 c 更直接命中 Tab+c
;   （激活Snipper，发 ^7）。
;   层热键是 KeymapManager 在层激活时用 Hotkey("*c", …) 动态注册的（bin/lib/KeymapManager.ahk
;   的 Enable/Disable），仓库里没有任何 #SuspendExempt ⇒ **Suspend(true) 确实能禁掉它们**。
;   对策同 RcShowModal：存原值 -> Suspend(true) -> 关框后还回去
;   （别用裸 Suspend(false)，MyKeymap 的 SendMouseButton 用的是裸 Suspend 切换）。
;   注意：**只裹 FileSelect 这一段**。别顺手把 RecPlay 也裹进去 —— 回放期间安全键 `\`
;   靠热键派发，Suspend 一上就停不下来了。
;--------------------------------------------------------------------
RcFileDialog(opts, root, title, filter) {
    wasSuspended := A_IsSuspended
    Suspend(true)
    try
        return FileSelect(opts, root, title, filter)
    finally
        Suspend(wasSuspended)
}

;--------------------------------------------------------------------
; 对外：把当前内容存成脚本文件
;   path 不写(空) -> 弹系统"另存为"框；写了就直接存到那个路径（探针/脚本用）
;   返回 true = 存成功了
;--------------------------------------------------------------------
RecSave(path := "") {
    global RC_Ev, RC_Rec, RC_Play, RC_LastDir, RC_SaveTag, RC_SaveVer
    if (RC_Rec || RC_Play) {
        RcTip("录制/回放中，先停")
        return false
    }
    if (!RC_Ev.Length) {
        RcTip("没内容")
        return false
    }

    if (Trim(String(path)) = "") {
        dir := RcDialogDir()
        ; FileSelect 只有 4 个参数，默认文件名要跟起始目录拼在同一个参数里（见官方语法）
        p := RcFileDialog("S", dir . "\" . RcDefaultName(), "保存录制脚本", "脚本文件 (*.json)")
        if (p = "")
            return false                    ; 取消
        path := p
        SplitPath(path, , &pd)
        if (pd != "")
            RC_LastDir := pd
    }
    if (!RegExMatch(path, "i)\.json$"))
        path .= ".json"                     ; 手打了没后缀的名字 -> 补上

    try {
        f := FileOpen(path, "w", "UTF-8-RAW")   ; RAW：不加 BOM，跟本仓库其他文件一个规矩
        if (!f)
            throw OSError("打不开文件")
        f.Write(RcJsonBuild(RC_SaveTag, RC_SaveVer, RC_Ev))
        f.Close()
    } catch as e {
        RcTip("保存失败`n" e.Message)
        return false
    }
    RcHoldFlash("脚本[保存]", RC_Ev.Length " 条 / " RcFmtDur(RcTotalMs()))
    return true
}

;--------------------------------------------------------------------
; 对外：从脚本文件载入
;   path 不写(空) -> 弹系统"打开"框
;   载入成功 = 内容替换掉内存里现有的那一段（跟重新录一遍等价）
;   返回 true = 载成功了
;--------------------------------------------------------------------
RecLoad(path := "", andPlay := false) {
    global RC_Ev, RC_Rec, RC_Play, RC_LastDir
    if (RC_Rec || RC_Play) {
        RcTip("录制/回放中，先停")
        return false
    }

    if (Trim(String(path)) = "") {
        dir := RcDialogDir()
        p := RcFileDialog(3, dir, "加载录制脚本", "脚本文件 (*.json)")   ; 3 = 文件必须存在
        if (p = "")
            return false
        path := p
        SplitPath(path, , &pd)
        if (pd != "")
            RC_LastDir := pd
    }

    txt := ""
    try {
        if (!FileExist(path))
            throw OSError("文件不存在")
        f := FileOpen(path, "r", "UTF-8")
        if (!f)
            throw OSError("打不开文件")
        txt := f.Read()
        f.Close()
    } catch as e {
        RcTip("读不了这个文件`n" e.Message)
        return false
    }

    try
        evs := RcJsonEvents(txt)
    catch as e {
        RcTip("不是本模块的脚本`n" e.Message)
        return false
    }
    if (!IsObject(evs) || !evs.Length) {
        RcTip("文件里没有事件")
        return false
    }

    RC_Ev := evs
    RcHoldFlash("脚本[加载]", evs.Length " 条 / " RcFmtDur(RcTotalMs()))
    if (andPlay)
        RecPlay()                      ; 无参 = 弹「键鼠回放」窗（循环 / 次数 / 倍速）
    return true
}

;--------------------------------------------------------------------
; 对外：回放
;   speed 不写(空) -> 弹询问框；写了数字 -> 直接按该倍速、单次回放
;   loops true = **一直循环到底**（此时 count 作废）；false = 放 count 遍
;   mode  送键模式，默认 "Event"（与 MyKeymap 全局一致，兼容性最好）
;         可选 "Input" / "Play" / "Text"，由 RcSend() 分派
;   alphaPct 状态提示的透明度(%)。**不写 = 用模块默认 RC_HoldAlphaPct(20)**；
;            0 = 完全不透明，100 = 全透。config.json 里传的就是这个。
;--------------------------------------------------------------------
RecPlay(speed := "", loops := false, count := 1, mode := "Event", alphaPct := "") {
    global RC_Ev, RC_Play, RC_Abort, RC_Rec, RC_AskLoadOnEmpty
    global RC_SpeedMin, RC_SpeedMax, RC_CountMax, RC_StartDelayMs

    if (RC_Rec) {                 ; 还在录就先停，别把回放的键录进去
        RecStop(true)             ; 安静收尾：直接进"回放中"，不要闪一下[停止]
        Sleep(200)
    }
    if (RC_Play) {                ; 已经在放 -> 当"停"
        RecStop()
        return
    }
    if (!RC_Ev.Length) {           ; 手里没内容 —— 问一句要不要去加载脚本（见 RC_AskLoadOnEmpty）
        if (!RC_AskLoadOnEmpty) {
            RcTip("没内容")
            return
        }
        if (!RcConfirm("没有脚本", "当前没有录好的内容，要加载一个脚本文件吗？", "加载...", "取消", true))
            return
        if (!RecLoad())            ; 载入失败 / 在框里取消了 -> 这次回放就算了
            return
    }

    if (Trim(String(speed)) = "") {
        o := RcAsk()
        if (!o)
            return
        sp := o.speed
        lp := o.loops
        ct := o.count
    } else {
        sp := RcClamp(IsNumber(speed) ? speed + 0 : 1.0, RC_SpeedMin, RC_SpeedMax)
        lp := loops ? true : false
        ct := RcClamp(Round(IsNumber(count) ? count + 0 : 1), 1, RC_CountMax)
    }

    ; 先清中断标志、再进"回放中"状态，最后才等那 800ms ——
    ; 顺序反了的话，缓冲期间按停止键会被后面的 RC_Abort := false 冲掉，停不下来。
    RC_Abort := false
    RC_Play := true
    RcHoldOn("脚本[回放]", alphaPct)
    ; 第 2 行：倍速 + [当前轮/总轮]（0.8x [1/99] / 0.8x [1/∞]）
    RcHoldSetMode(RcSpeedStr(sp), lp ? "∞" : ct)
    Sleep(RC_StartDelayMs)        ; 给手离开鼠标的时间

    RcRun(RcRounds(lp, ct), sp, mode)   ; 勾循环 -> 0(无限)，不勾 -> 次数
    RC_Play := false

    RcHoldOff()
    RcTip("脚本[停止]")
}

;--------------------------------------------------------------------
; 倍速 -> "0.8x" / "1x" / "1.5x"（别再用 [0.5]倍）
;   **不能直接 String(sp)**：本机 String(0.8) 会吐出 "0.80000000000000004"
;   （浮点原样展开）。这里全走整数运算拼字符串，从根上躲开浮点表示问题。
;--------------------------------------------------------------------
RcSpeedStr(sp) {
    n := Round(sp, 2)                     ; 最多留两位小数
    i := Floor(n)                         ; 整数部分
    f := Round((n - i) * 100)             ; 小数部分，取两位
    if (f = 0)
        return i "x"
    if (Mod(f, 10) = 0)
        return i "." (f // 10) "x"
    return i "." (f < 10 ? "0" : "") f "x"
}

;--------------------------------------------------------------------
; 跑几轮：勾了循环 = 0（无限，交给 RcRun 解释），没勾 = 次数
;   单独成函数是为了能被探针直接断言（RecPlay 里那句没法单独试）
;--------------------------------------------------------------------
RcRounds(loops, count) {
    return loops ? 0 : count
}

;--------------------------------------------------------------------
; 真正跑一遍（RcRun 里只做两件事：等时间、发事件）
;   times  跑几轮；**0 = 一直循环**（勾了"循环播放"，只能靠停止键出来）
;   speed  倍速
;   mode   Send 的模式
;--------------------------------------------------------------------
RcRun(times, speed, mode) {
    global RC_Ev, RC_Abort

    oldMouseMode := A_CoordModeMouse
    CoordMode("Mouse", "Screen")

    n := RC_Ev.Length
    round := 0
    held := ""                                 ; 当前"按下没抬起"的回放按钮名（正常应为空）
    while (!RC_Abort && (times <= 0 || round < times)) {
        if (round > 0)
            Sleep(1)                           ; 轮间让一拍：记录很短 + 倍速高时整轮可能 0ms，
                                               ; 空转会把消息循环饿死、连停止键都进不来
        round += 1
        RcHoldSetRound(round)                  ; 状态提示第 2 行：当前轮
        base := RcNow()                        ; 每轮重新对齐起点，误差不跨轮累积
        i := 0
        while (i < n) {
            if (RC_Abort)
                break
            i += 1
            e := RC_Ev[i]
            RcHoldInfoSet(RcEventInfo(e))     ; 状态提示事件行：正在发的这一条
            RcWaitUntil(base + e.t / speed)
            if (RC_Abort)
                break
            switch e.type {
                case "k":
                    RcSend(e.mods . "{" . e.key . "}", mode)
                case "c":
                    MouseClick(RcClickName(e.btn), e.x, e.y, 1)   ; Speed 必须 >=1，见【坑 R6】
                case "d":                                          ; 拖拽：按下
                    held := RcClickName(e.btn)
                    MouseClick(held, e.x, e.y, 1, 1, "D")
                case "u":                                          ; 拖拽：抬起
                    held := ""
                    MouseClick(RcClickName(e.btn), e.x, e.y, 1, 1, "U")
                case "w":
                    MouseClick(e.dir, e.x, e.y, 1)
                case "m":
                    DllCall("user32\SetCursorPos", "Int", e.x, "Int", e.y)
            }
        }
    }

    ; 半路停下时可能停在"按下"和"抬起"之间 —— 不补这一下，那个键在系统层面
    ; 会一直按着（鼠标像粘住），必须无条件松开。
    if (held != "")
        RcReleaseHeld(held)

    CoordMode("Mouse", oldMouseMode)
}

;--------------------------------------------------------------------
; 只"松开"不挪光标（MouseClick 的 U 会先把光标挪过去，这里不能挪）
;   mouse_event 已过时但仍是唯一能"纯松键"的简单途径
;--------------------------------------------------------------------
RcReleaseHeld(name) {
    switch name {
        case "Left":
            DllCall("user32\mouse_event", "UInt", 0x0004, "UInt", 0, "UInt", 0, "UInt", 0, "UPtr", 0)
        case "Right":
            DllCall("user32\mouse_event", "UInt", 0x0010, "UInt", 0, "UInt", 0, "UInt", 0, "UPtr", 0)
        case "Middle":
            DllCall("user32\mouse_event", "UInt", 0x0020, "UInt", 0, "UInt", 0, "UInt", 0, "UPtr", 0)
        case "X1":
            DllCall("user32\mouse_event", "UInt", 0x0100, "UInt", 0, "UInt", 0, "UInt", 1, "UPtr", 0)
        case "X2":
            DllCall("user32\mouse_event", "UInt", 0x0100, "UInt", 0, "UInt", 0, "UInt", 2, "UPtr", 0)
    }
}

;--------------------------------------------------------------------
; 录制存的键名 -> MouseClick 认的按钮名（见【坑 R9】）
;--------------------------------------------------------------------
RcClickName(btn) {
    switch btn {
        case "LButton":  return "Left"
        case "RButton":  return "Right"
        case "MButton":  return "Middle"
        case "XButton1": return "X1"
        case "XButton2": return "X2"
        default:         return btn      ; WheelUp/Down/Left/Right 两边同名，直接用
    }
}

;--------------------------------------------------------------------
; 发键：v2 的 Send() 只收 1 个参数，模式得分函数调用（不改全局 SendMode）
;   mode: "Event"(默认) / "Input" / "Play" / "Text"
;--------------------------------------------------------------------
RcSend(keys, mode) {
    switch mode {
        case "Input":
            SendInput(keys)
        case "Play":
            SendPlay(keys)
        case "Text":
            SendText(keys)
        default:
            SendEvent(keys)
    }
}

;--------------------------------------------------------------------
; 等到 target(ms，QPC 绝对时间) 这个时刻
;   分片 Sleep + 最后 1ms 自旋；期间不停让出线程，好让安全键插进来（见【坑 R5】）
;--------------------------------------------------------------------
RcWaitUntil(target) {
    global RC_Abort
    loop {
        if (RC_Abort)
            return
        remain := target - RcNow()
        if (remain <= 0.6)
            return
        Sleep(remain > 14 ? Round(remain - 8) : 1)
    }
}

;====================================================================
; 附：JSON 的极小实现（只为存/取脚本用）
;   AHK v2 没有内置 JSON，而脚本文件用 JSON 格式，所以自己写一套。
;   **只覆盖本模块自己写的形状**：对象 / 数组 / 字符串 / 整数 / true/false/null。
;   不支持的东西（都用不上，真遇到了就抛错，不会静默出错数据）：
;     ① 浮点保持原样（本模块的数都是整数：时间戳 ms、坐标 px）；
;     ② 转义只处理 \" \\ \/ \n \r \t \b \f \uXXXX；
;     ③ 不检查重复键、不处理超深嵌套（脚本文件是自己的，不做恶意输入防御）。
;   键的顺序：Map 在 v2 里是**有序**的，所以解析出来顺序跟文件里一致。
;====================================================================

;--------------------------------------------------------------------
; 时间戳："2026-09-19 19:31:06"（A_Now 直接切，不碰 Format）
;--------------------------------------------------------------------
RcStamp() {
    ts := A_Now
    if (StrLen(ts) < 14)
        return ts
    return SubStr(ts, 1, 4) "-" SubStr(ts, 5, 2) "-" SubStr(ts, 7, 2)
         . " " SubStr(ts, 9, 2) ":" SubStr(ts, 11, 2) ":" SubStr(ts, 13, 2)
}

;--------------------------------------------------------------------
; 事件对象 -> 整份脚本文件文本（带缩进，人也能看）
;--------------------------------------------------------------------
RcJsonBuild(tag, ver, evs) {
    parts := []
    for e in evs
        parts.Push("    " RcJsonEventStr(e))
    txt := "{`n"
    txt .= '  "tag": "' RcJsonEsc(tag) '",' "`n"
    txt .= '  "version": ' RcJsonNum(ver) ',' "`n"
    txt .= '  "savedAt": "' RcJsonEsc(RcStamp()) '",' "`n"
    txt .= '  "count": ' evs.Length ',' "`n"
    txt .= '  "events": [' "`n"
    txt .= RcJsonJoin(parts, ",`n")
    if (parts.Length)
        txt .= "`n"
    txt .= "  ]`n}`n"
    return txt
}

;--------------------------------------------------------------------
; 一条事件 -> 一行 JSON
;   字段按类型给，不写多余的键（m 没有 btn，k 没有坐标）
;--------------------------------------------------------------------
RcJsonEventStr(e) {
    s := '{"type":"' RcJsonEsc(e.type) '","t":' RcJsonNum(e.t)
    if (e.HasProp("key"))
        s .= ',"key":"' RcJsonEsc(e.key) '"'
    if (e.HasProp("mods"))
        s .= ',"mods":"' RcJsonEsc(e.mods) '"'
    if (e.HasProp("btn"))
        s .= ',"btn":"' RcJsonEsc(e.btn) '"'
    if (e.HasProp("dir"))
        s .= ',"dir":"' RcJsonEsc(e.dir) '"'
    if (e.HasProp("x"))
        s .= ',"x":' RcJsonNum(e.x)
    if (e.HasProp("y"))
        s .= ',"y":' RcJsonNum(e.y)
    return s "}"
}

;--------------------------------------------------------------------
; 字符串转义：只转 " 和 \
;   0x20 以下的控制字符**直接丢掉** —— 事件里只可能是键名/按钮名/方向名，
;   不可能出现控制字符；与其写 \uXXXX（还得赌 Format/Chr 的行为），不如丢掉。
;--------------------------------------------------------------------
RcJsonEsc(s) {
    out := ""
    Loop Parse, String(s) {
        c := A_LoopField
        if (c = '"')
            out .= '\"'
        else if (c = "\")
            out .= "\\"
        else if (Ord(c) >= 0x20)
            out .= c
    }
    return out
}

;--------------------------------------------------------------------
; 数字 -> JSON 数字。一律取整：本模块的数全是整数，而且**不能直接 String(浮点)**
;   （本机 String(0.8) 会吐 0.80000000000000004）
;--------------------------------------------------------------------
RcJsonNum(v) {
    return String(Round(IsNumber(v) ? v + 0 : 0))
}

;--------------------------------------------------------------------
; 拼数组/多行文本（AHK v2 里字符串拼接必须显式用 . 或 .=，没有隐式拼接的坑，但循环里更清楚）
;--------------------------------------------------------------------
RcJsonJoin(arr, sep) {
    out := ""
    for i, v in arr
        out .= (i = 1) ? v : (sep . v)
    return out
}

;--------------------------------------------------------------------
; 文本 -> 事件数组（不合法就抛，让调用方给"不是本模块的脚本"这种短提示）
;   收口在这一层做三件事：① 认 tag（别人的 JSON 直接拒）② 逐条转成事件对象
;   ③ 认不出的 type 跳过（将来加了新事件类型，老版本也能读个大概，不至于整份打不开）
;--------------------------------------------------------------------
RcJsonEvents(txt) {
    global RC_SaveTag
    d := RcJsonParse(txt)
    if (Type(d) != "Map")
        throw ValueError("顶层不是 JSON 对象")
    tag := d.Has("tag") ? String(d["tag"]) : ""
    if (tag != RC_SaveTag)
        throw ValueError("不是本模块保存的脚本")
    if (!d.Has("events") || Type(d["events"]) != "Array")
        throw ValueError("没有 events 列表")
    out := []
    for m in d["events"] {
        if (Type(m) != "Map")
            continue
        ev := RcMapToEv(m)
        if (ev)
            out.Push(ev)
    }
    return out
}

;--------------------------------------------------------------------
; 解析出来的 Map -> 事件对象
;   认不出的 type 返回 0（调用方跳过）。t 负数归零，免得回放时算出一个过去时刻。
;--------------------------------------------------------------------
RcMapToEv(m) {
    tp := m.Has("type") ? String(m["type"]) : ""
    t := m.Has("t") ? m["t"] + 0 : 0
    if (t < 0)
        t := 0
    if (tp = "k")
        return {type: "k"
              , key: (m.Has("key") ? String(m["key"]) : "")
              , mods: (m.Has("mods") ? String(m["mods"]) : ""), t: t}
    if (tp = "c" || tp = "d" || tp = "u")
        return {type: tp
              , btn: (m.Has("btn") ? String(m["btn"]) : "")
              , x: (m.Has("x") ? Round(m["x"] + 0) : 0)
              , y: (m.Has("y") ? Round(m["y"] + 0) : 0), t: t}
    if (tp = "w")
        return {type: "w"
              , dir: (m.Has("dir") ? String(m["dir"]) : "")
              , x: (m.Has("x") ? Round(m["x"] + 0) : 0)
              , y: (m.Has("y") ? Round(m["y"] + 0) : 0), t: t}
    if (tp = "m")
        return {type: "m"
              , x: (m.Has("x") ? Round(m["x"] + 0) : 0)
              , y: (m.Has("y") ? Round(m["y"] + 0) : 0), t: t}
    return 0
}

;--------------------------------------------------------------------
; 递归下降解析：入口
;--------------------------------------------------------------------
RcJsonParse(txt) {
    p := {s: String(txt), i: 1, n: StrLen(String(txt))}
    RcJsonWs(p)
    v := RcJsonVal(p)
    return v
}

; 跳过空白
RcJsonWs(p) {
    while (p.i <= p.n) {
        c := SubStr(p.s, p.i, 1)
        if (c = " " || c = "`t" || c = "`r" || c = "`n")
            p.i += 1
        else
            break
    }
}

; 任意值
RcJsonVal(p) {
    RcJsonWs(p)
    c := (p.i <= p.n) ? SubStr(p.s, p.i, 1) : ""
    if (c = "{")
        return RcJsonObj(p)
    if (c = "[")
        return RcJsonArr(p)
    if (c = '"')
        return RcJsonStr(p)
    if (c = "")
        throw ValueError("JSON 内容意外结束")
    return RcJsonLit(p)
}

; 对象 -> Map（顺序保留）
RcJsonObj(p) {
    m := Map()
    p.i += 1                                  ; 跳过 {
    RcJsonWs(p)
    if (SubStr(p.s, p.i, 1) = "}") {
        p.i += 1
        return m
    }
    loop {
        RcJsonWs(p)
        if (SubStr(p.s, p.i, 1) != '"')
            throw ValueError("JSON 对象里期待键名")
        k := RcJsonStr(p)
        RcJsonWs(p)
        if (SubStr(p.s, p.i, 1) != ":")
            throw ValueError("键名后面期待冒号")
        p.i += 1
        m[k] := RcJsonVal(p)
        RcJsonWs(p)
        c := (p.i <= p.n) ? SubStr(p.s, p.i, 1) : ""
        if (c = ",") {
            p.i += 1
            continue
        }
        if (c = "}") {
            p.i += 1
            return m
        }
        throw ValueError("JSON 对象里期待逗号或右花括号")
    }
}

; 数组 -> Array
RcJsonArr(p) {
    a := []
    p.i += 1                                  ; 跳过 [
    RcJsonWs(p)
    if (SubStr(p.s, p.i, 1) = "]") {
        p.i += 1
        return a
    }
    loop {
        a.Push(RcJsonVal(p))
        RcJsonWs(p)
        c := (p.i <= p.n) ? SubStr(p.s, p.i, 1) : ""
        if (c = ",") {
            p.i += 1
            continue
        }
        if (c = "]") {
            p.i += 1
            return a
        }
        throw ValueError("JSON 数组里期待逗号或右方括号")
    }
}

; 字符串（含转义）
RcJsonStr(p) {
    p.i += 1                                  ; 跳过开引号
    out := ""
    while (p.i <= p.n) {
        c := SubStr(p.s, p.i, 1)
        if (c = '"') {
            p.i += 1
            return out
        }
        if (c = "\") {
            p.i += 1
            esc := SubStr(p.s, p.i, 1)
            if (esc = "n")
                out .= "`n"
            else if (esc = "t")
                out .= "`t"
            else if (esc = "r")
                out .= "`r"
            else if (esc = "b")
                out .= Chr(8)
            else if (esc = "f")
                out .= Chr(12)
            else if (esc = "u") {
                out .= Chr(Integer("0x" . SubStr(p.s, p.i + 1, 4)))
                p.i += 4
            } else if (esc = "")
                throw ValueError("JSON 字符串在转义符后结束")
            else
                out .= esc                    ; \" \\ \/ 都还原成它自己
            p.i += 1
            continue
        }
        out .= c
        p.i += 1
    }
    throw ValueError("JSON 字符串没有收尾引号")
}

; 数字 / true / false / null
;   ★ 别写 (c >= "a" && c <= "z") —— AHK v2 的 > < >= <= 是**只按数字比**的，
;     拿字符串去比会直接抛 "Expected a Number but got a String"（本机实测，四种字符都抛）。
;     要比字符串得用 StrCompare()。这里用 IsAlnum()，它就是干这个的。
;   ★ c 一定非空（外层保证 p.i <= p.n），因为 **IsAlnum("") 本机返回 1**、
;     **InStr(x, "") 直接抛**，两个都会把循环变成死循环，必须靠外层守住。
RcJsonLit(p) {
    start := p.i
    while (p.i <= p.n) {
        c := SubStr(p.s, p.i, 1)
        if (IsAlnum(c) || InStr("-+.", c))
            p.i += 1
        else
            break
    }
    tok := SubStr(p.s, start, p.i - start)
    if (tok = "true")
        return true
    if (tok = "false")
        return false
    if (tok = "null")
        return ""
    if (tok = "")
        throw ValueError("JSON 里读不出值")
    if (!IsNumber(tok))
        throw ValueError("JSON 里有看不懂的值")
    return tok + 0
}

