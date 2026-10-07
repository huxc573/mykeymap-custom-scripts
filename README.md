# MyKeymap 自定义脚本

> **v1.1**（`VERSION` = `1.1.0` · 2026-10-07 09:22）· 变更见 [CHANGELOG.md](CHANGELOG.md)

给 [MyKeymap](https://mykeymap.com) 写的三个 AutoHotkey v2 模块。全部**本地运行、不联网、不驻留后台服务**。

## 模块

| 文件 | 干什么 | 对外入口 |
| :--- | :--- | :--- |
| `KeyRecorder.ahk` | 键鼠录制 / 回放。可把录到的操作存成 JSON 脚本文件，之后再加载回放 | `RecToggle` / `RecPlay` / `RecSave` / `RecLoad` / `RecStop` / `RecClear` / `RecInfo` |
| `AutoClick.ahk` | 连点器。有「前台」和「后台」两条后端：后台用窗口消息投递，不移动系统光标、不抢焦点 | `AutoClick` / `AutoClickStop` / `AutoClickProbe` |
| `Brightness.ahk` | 屏幕亮度调节。**只动鼠标所在的那块屏**（可用 `BR_PerMonitor` 关掉改成全屏）。两个入口：`BrightAuto` 软件优先（Gamma → 遮罩）、`BrightHw` 硬件优先（背光 → Gamma → 遮罩） | `BrightAuto` / `BrightHw` / `BrightDdc` / `BrightWmi` / `BrightGamma` / `BrightGammaReset` / `BrightRefreshGamma` / `BrightMask` / `BrightCursorRestore` |

每个文件头部都有详细注释：函数签名、参数含义、返回值，以及实现时踩过的坑。

## 安装

1. 把三个 `.ahk` 放进 MyKeymap 的 `data/self/` 目录。
2. 在 `data/custom_functions.ahk` 末尾加三行：

   ```ahk
   #Include ../data/self/AutoClick.ahk
   #Include ../data/self/Brightness.ahk
   #Include ../data/self/KeyRecorder.ahk
   ```

   > **依赖**：`KeyRecorder` 复用了 `AutoClick` 里的两个小工具（`AcTip` 贴光标提示、`AcMouseScreen` 取鼠标所在屏幕），
   > 所以 `AutoClick.ahk` 要排在前面，这两个文件别拆开单独装（只装 KeyRecorder 时提示会报「函数未定义」）。
   > `Brightness.ahk` 无跨模块依赖，可以单独用。

3. 在 MyKeymap 的设置界面里，给热键选「自定义函数 / ahkCode」并填下表里的调用，保存后重载脚本。

## 默认接线

以下是从作者 `data/config.json` 里抽出的真实接线（只抄了函数调用本身）。键位前缀 `*` 表示「其它修饰键按住时也触发」，是 MyKeymap 的配置写法，原样照抄即可。

**KeyRecorder（键鼠录制 / 回放）**

| 键位 | ahkCode |
| :--- | :--- |
| `*` `[` | `RecToggle("", "", 15)` |
| `*` `\` | `RecStop()` |
| `*` `]` | `RecPlay("", false, 1, "Event", 15)` |
| `*` `;` | `RecSave()` |
| `*` `'` | `RecLoad("", true)` |

**AutoClick（连点器）**

| 键位 | ahkCode |
| :--- | :--- |
| `*` `p` | `AutoClickBg(false, "L", 50, false)` |
| `*` `LAlt` | `AutoClick(false, "R", 50, false)` |
| `*` `LCtrl` | `AutoClick(false, "L", 50, false, 0, "front")` |
| `*` `LWin` | `AutoClick(false, "L", 50, true)` |

**Brightness（亮度调节）**

| 键位 | ahkCode |
| :--- | :--- |
| `*` `MButton` | `BrightAuto(0)` |
| `*` `WheelDown` | `BrightAuto(-5)` |
| `*` `WheelUp` | `BrightAuto(5)` |
| `*` `-` | `BrightHw(-2)` |
| `*` `=` | `BrightHw(2)` |

滚轮走软件层（快，不碰显示器硬件），`-` / `=` 走硬件背光。`delta = 0` 是还原，两个入口一样：硬件还回原值、Gamma 清空、遮罩撤掉。

## 说明与边界

- **不联网、不写注册表、不装服务**。三个模块都只在 MyKeymap 进程里跑。
- `KeyRecorder` 录的是**物理按键与鼠标事件**并原样回放，属于本地宏工具。录制文件默认存在脚本所在目录的 `scripts\` 子目录，是纯文本 JSON，可以直接读、手改、版本管理。
- `AutoClick` 的「后台」后端靠给目标窗口投递鼠标消息实现。它对**按系统真实光标定位**的程序（典型是 Unity 引擎做的游戏）无效；也不适用于 UWP / 部分 RawInput 程序。**请只用于你自己的、允许自动化的软件**；在游戏里用可能违反其用户协议。
- `Brightness` 的 Gamma 办法在 WinPE 下无效（`SetDeviceGammaRamp` 是空操作），会自动退回遮罩方案；遮罩只能变暗，且压不住开始菜单与独占全屏程序。
- **硬件背光档有前提**：外接屏要在显示器 OSD 里打开 DDC/CI；笔记本内屏要固件暴露 WMI 亮度接口（多数机型可以）。
  两者都不满足时会自动退到 Gamma —— 此时 `BrightHw` 与 `BrightAuto` 表现一致，不是没生效，是这台机器没有可用的硬件通道。
- 按屏生效靠显示器设备名（`\\.\DISPLAYn`）：插拔显示器或换接口后编号可能变，按当前编号重新调一次即可。

## 版本管理

- 语义化版本：`MAJOR` 不兼容变更 / `MINOR` 新功能 / `PATCH` 修复。**版本号唯一来源是 `VERSION`**，
  标签 `v<X.Y.Z>`；`CHANGELOG.md` 段标题与 README 顶部都要带 **24 小时制到分钟**的时间。
- 兼容性边界是**对外函数**（上表三个模块各自的入口）：删函数、改函数名、改参数顺序或含义 = `MAJOR`；
  新增函数，或在参数表**末尾**加带默认值的参数 = `MINOR`；只改实现、不动签名 = `PATCH`。

```bash
git status --short && git add -A && git commit -m "fix(recorder): 一句话"
git tag -a v1.0.1 -m "1.0.1: 一句话概要"
git push origin main v1.0.1      # 只推这一个标签，不要 git push --tags
```

提交信息 `<type>(<scope>): <描述>`，type 取 `feat` / `fix` / `perf` / `refactor` / `docs` / `chore` / `security`；
scope 用模块名小写：`recorder` / `autoclick` / `brightness`，跨模块的改动写 `repo`。

发版检查：静态自检过（`AutoHotkey64.exe /validate <脚本>` 退出码 0 且无输出）→ 无个人路径 / 凭据 / 本机配置入库 →
`VERSION` / `CHANGELOG` / README 三处同步 → 提交打标签按名推送。

回滚：`git checkout v1.0.0 -- <文件>`（单文件），或 `git checkout -b hotfix/x v1.0.0`；回滚后同步 `VERSION` 与 CHANGELOG。

## 许可

MIT，见 `LICENSE`。
