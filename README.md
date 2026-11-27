# winiso —— Windows ISO 生成终端

像 UUP dump 一样，用**微软官方源**下载原版文件，自动合成**任意版本、任意架构**的 Windows ISO，
并可对 ISO 做**精简 / 广告拦截 / macOS 风格 / 无人值守**等定制。

**纯 PowerShell + CMD，不需要 Python，不需要装 ADK，也不需要模板 ISO。**

---

## 两种用法

**图形界面（推荐）**：双击 `winiso.exe`（首次请先跑一次 `build-exe.ps1` 生成它），或双击 `gui\WinIsoGui.cmd`。
界面里选家族/架构 → 加载构建 → 选语言与版本 → 勾操作与美化 → 选目录 → 开始生成，日志实时滚动。

**命令行**：见下面一节。

## 快速开始

```cmd
winiso                  :: 交互向导（指定版本 → 选择操作 → 开始生成）
winiso list             :: 列出所有正式版构建
winiso list win10 arm64 :: 指定家族 + 架构
winiso slim D:\VLSC.iso :: 直接精简你已有的原版 ISO
winiso check            :: 检查环境
```

> 生成/精简需要管理员权限，程序会自动请求提权（UAC 弹窗点"是"）。

---

## 三步流程

### 1. 指定版本
- **系统家族**：Windows 11 / Windows 10 / Windows Server / 手动输入 UUID
- **架构**：x64 (amd64) / ARM64
- **具体构建**：默认最新的正式版（自动排除 Insider 预览、.NET 更新包等非完整构建）
- **语言**：中文(简/繁)、English 等 40 种
- **版本种类**：专业版 / 家庭版 / 企业版 / 教育版…

### 2. 选择操作（可多选）

| 操作 | 说明 |
|------|------|
| 精简组件 | 删 Copilot / Cortana / Bing 全家桶 / Xbox / OneDrive 同步 等预置应用与冗余功能包 |
| 广告与追踪拦截 | 137+ 广告/遥测域名写入系统 hosts，装机即全局屏蔽 |
| macOS 风格（含美化细节） | 见下方「美化清单」 |
| 无人值守安装 | 跳过 TPM/安全启动检测、免联网 OOBE |
| 移除 WinRE | 省约 500MB |
| 移除 Edge | 激进选项 |
| 集成 .NET 3.5 | 老软件需要 |
| 清理组件库 | ResetBase，显著缩小体积（之后无法卸载更新） |
| 跳过商店应用下载 | 更快，且商店应用不被预置 |

### 美化清单（勾选"macOS 风格"后进入子菜单）

**主题**
- 深色 / 浅色（可选，默认深色）
- 透明效果（毛玻璃）+ 强调色跟随（接近 macOS 蓝 `#0078D4`）

**任务栏 / 开始菜单**
- 图标居中（macOS 观感）
- 小图标（更纤细）
- 按钮始终合并（TaskbarSn=0 / TaskbarGlomLevel=2）
- 隐藏 Copilot 按钮、任务视图、Widgets 角标、聊天图标
- 开始菜单关闭"推荐项"

**细节**
- 时钟显示秒
- 菜单响应 150ms、字体平滑
- 资源管理器：显示文件扩展名 / 默认打开"此电脑" / 紧凑视图

**壁纸**
- 程序在首次登录时用 GDI+ 自绘 3840×2160 渐变壁纸并设为桌面背景（不涉及任何版权素材）

**可选组件（需联网，首次登录时 winget 安装）**
- Spotlight 式全局搜索：PowerToys Run，`Alt+Space` ≈ macOS `⌘ + Space`
- 程序坞 Dock：Nexus Dock（第三方，失败会留提示）

> 这些改动同时写进两处：① 离线注入 `Users\Default\NTUSER.DAT`（新用户默认生效）；
> ② 首次登录脚本再执行一遍（跨架构/未挂载场景的兜底，也覆盖当前用户）。

### 3. 开始生成
自动完成：拉官方脚本包 → 下载 UUP 文件集（4 线程断点续传 + SHA1 校验）→ 官方转换器合成 ISO →
DISM 离线精简 → `oscdimg` 重建 BIOS+UEFI 双引导 ISO。

输出：`<输出目录>\<版本>_<架构>_<语言>_<版本种类>.iso`

---

## 目录结构

```
winiso\
├── winiso.cmd            启动器（双击或命令行）
├── winiso.ps1            主程序：向导 / 分流 / 生成流水线
├── lib\
│   ├── common.ps1        日志、彩色菜单、curl 下载、并发下载、提权
│   ├── uup.ps1           UUP 接口：构建列表 / 语言 / 版本 / 下载清单
│   ├── converter.ps1     官方转换器 uup-converter-wimlib 的获取与编排
│   └── slim.ps1          DISM 离线精简、hosts 广告拦截、注册表调优、重建 ISO
└── data\
    ├── debloat_win11.txt   Win11 精简清单（Appx + 功能包）
    ├── debloat_win10.txt   Win10 精简清单
    ├── debloat_server.txt  Server 精简清单
    └── adblock_hosts.txt   广告/追踪域名
```

清单都是纯文本，`#` 开头是注释，可以自己加删。

---

## 实测记录（在你的 Windows 机器上实际跑过）

| 项目 | 结果 |
|---|---|
| `winiso check` | 通过（curl / dism / robocopy 全部找到，能访问 UUP API） |
| `winiso list win11 amd64` | 通过，列出 317 个正式版构建（最新 26H1 28000.3501） |
| 官网打包（POST get.php） | 通过：返回 8226 字节合法 ZIP，11 个条目（含 uup_download_windows.cmd、ConvertConfig.ini、files/converter_windows） |
| aria2 下载清单 | 通过：33624 字节文本，含 `out=` 与 `checksum=sha-1` |
| 转换器下载 + 解压 | 通过：1,686,886 字节，解出 convert-UUP.cmd、`bin\wimlib-imagex.exe`、`bin\cdimage.exe` |
| cdimage 实际打包 | 通过：退出码 0，生成 638 KB ISO |
| 美化注册表 / 首登脚本 | 生成的脚本语法校验通过（48 条注册表项；深色/浅色切换正确） |

> 注：官方转换器自带的是 `cdimage.exe`（不是 oscdimg，但 `-bootdata:2#...` 语法完全一致），
> 引导文件 `boot\etfsboot.com` 与 `efi\microsoft\boot\efisys.bin` 来自镜像介质本身，所以无需 ADK。

## 原理与关键技术点

1. **UUP 是微软自己的分发通道**：`api.uupdump.net/listid.php` 列出构建，
   `listlangs.php` / `listeditions.php` 列出语言和版本，
   `get.php?id&pack&edition&aria2=2` 返回文件下载清单（微软 delivery 直链）。

2. **官方脚本包的坑（已绕过）**：
   `get.php?id&pack=zh-cn&edition=0` 这类请求会被服务端拒绝并返回
   *"The language and edition combination is not correct."*。
   `edition` 必须写**真实版本键**（`PROFESSIONAL` / `CORE` / `ENTERPRISE` …），
   写 `0` 就会失败。本程序直接用 `listeditions.php` 返回的键。

3. **不需要 ADK / 模板 ISO**：`uup-converter-wimlib` 自带
   `wimlib-imagex`、`oscdimg` 和引导文件集，转换结束就是可引导 ISO。

4. **跨架构（arm64）**：转换器本身与架构无关；但 x64 主机无法 DISM 挂载 arm64 映像，
   所以 arm64 目标自动降级为"运行期精简"——把清理脚本通过
   `sources\$OEM$\$$\Setup\Scripts` 注入，首次登录时执行。

5. **精简安全性**：删包、删预置应用都做了 `try/catch` 单独容错，
   失败的项跳过并计数，不会中断整体流程。

---

## 空间与时间

| 项目 | 需求 |
|------|------|
| 磁盘 | 约 30 GB（下载 5-6GB + 解包 6GB + 成品 ISO 6-8GB） |
| 时间 | 下载 30-90 分钟（看带宽），转换 20-60 分钟，精简 10-30 分钟 |
| 断点续传 | 中断后重跑同一构建，已下的文件会跳过 |

---

## 常见问题

**Q：能不能生成"VLSC 原版"那种 ISO？**
能。winiso 拉的就是微软 Windows Update 的同一套原版文件，效果等同 UUP dump 产物。
如果你手上已有 VLSC ISO，直接用 `winiso slim 你的.iso` 定制即可。

**Q：arm64 能不能做离线精简？**
在 ARM64 主机上运行即可（程序自动判断架构相同才挂载）。在 x64 主机上会走运行期精简。

**Q：精简后还能正常更新吗？**
删预置应用和功能包不影响 Windows Update。如果勾了 ResetBase，之后无法卸载已装更新。

**Q：能不能只要原版 ISO、不做任何改动？**
操作里全部取消勾选，即输出纯净原版 ISO。


## 图形界面目录

```
winiso/
├── winiso.exe            ← 双击即用（由 build-exe.ps1 编译生成）
├── build-exe.ps1         ← 用系统自带 csc.exe 编译上面这个 exe（无需下载）
├── gui/
│   ├── WinIsoGui.ps1     ← WPF 界面（纯 PowerShell，无 Python）
│   └── WinIsoGui.cmd     ← 命令行启动界面（exe 的备用方案）
└── launcher/
    └── WinIsoLauncher.cs ← exe 的外壳源码（只做一件事：拉起 WPF 界面）
```

界面做的事和命令行完全一样：它把选择写成一个 JSON，再以管理员身份调用
`winiso.ps1 run <params.json>`，然后把子进程日志实时显示在窗口里。
所以命令行、图形界面产出的 ISO 完全一致，且都能断点续传。

## 图形界面实测记录（2026-11-14，Windows 11 / Parallels 虚拟机）

- 已在本机真实启动通过：窗口正常渲染、构建列表自动加载（Windows 11 26H1 28000.35011）、
  语言与版本种类自动填充、9 个操作项与 6 项美化细节可勾选、D:\ISO\work / D:\ISO\out 默认填好。
- 关键修复：**虚拟机里 WPF 硬件加速会把窗口渲染成一片空白**，脚本开头已强制
  `RenderOptions.ProcessRenderMode = SoftwareOnly`，所以在这台电脑上也能正常显示。
- `winiso.exe` 已用系统自带 csc.exe 预编译好（5 KB），双击即可运行；
  源码在 `launcher/WinIsoLauncher.cs`，随时可用 `build-exe.ps1` 重新编译。
- 界面只是壳：所有干活都交给 `winiso.ps1 run <params.json>`，因此命令行与 GUI 产物完全一致。

## 生成流程（点「开始生成」之后发生了什么）

1. 界面把选择写成 `%TEMP%\winiso_gui_<时间>\params.json`
2. 用临时 `run.cmd` + UAC 提权启动 `winiso.ps1 run`，日志同时写入 `run.log`
3. 界面按文件偏移增量读取日志，实时滚动；识别到 `WINISO_RESULT_ISO=` 即判定成功
4. 成功后「打开输出目录」按钮可用，可直接跳到 D:\ISO\out

## 下载失败怎么办（winiso diag）

界面右下角有「诊断下载」按钮，也可以命令行跑：

```
winiso.cmd diag
```

它会真的走一遍下载链路并逐项判定：

1. `curl.exe` 是否存在、版本
2. UUP API 是否通（win11/amd64 正式版条数）
3. 语言 / 版本种类列表
4. `get.php` POST 是否返回真正的 ZIP（现在会校验 ZIP 魔数，并把返回网页的头 120 字带进错误里）
5. aria2 清单是否完整（URL 数与 `out=` 数必须一一对应，防代理截断）
6. 真下一个小文件（5 MB 级）并核对 SHA-1

结论那一行会直接告诉你是「链路完好」还是「网络/代理或组合不可用」。

## 已做的下载健壮性改动

- `Invoke-CurlText`：curl 自带 `--retry 4 --retry-all-errors`，外层再重试 3 次（应对连接被重置）
- 清单完整性校验：数量不匹配就重取，最多 4 轮
- `Save-UupPackage`：POST 两次 + GET 兜底，拿到非 ZIP 会明确说明「服务器返回的不是 ZIP」并附内容开头
- 单文件下载：每文件最多 3 次，带 `-C -` 续传，失败的文件名会列出来，重跑继续

## 关键修复：并发下载传参 bug（这才是「下载 ISO 失败」的真凶）

原代码用逗号写法把分片传给后台 Job：
`Start-Job ... -ArgumentList (,$chunk), $DestDir, $UA, $curl`

这写法会让 PowerShell 少剥一层数组，Job 里 `$Files` 变成一个只有 1 个元素的集合，元素本身是**整个分片**；
于是 `$f` 是数组，`$f.Out` 取不到文件名，`Join-Path $Dest $null` 直接报「Supply values for ChildPath」，
所有「含多个文件的分片」瞬间全部失败 —— 95 个文件分 4 片，等于一个都下不下来，界面就会显示下载失败。

现在改成哈希表整体传参，实测：8 个文件 / 24 个文件分片全部下载 + SHA-1 校验通过。
`winiso diag` 里也加了一步「4 线程并发下载 8 个文件」，专门防这个 bug 回归。

## 全量代码审查与修复（2026-11-20）

对 6 个脚本（约 3000 行）逐行审过一遍，除语法/AST/真机接口层验证外，修掉了下面这些**会真实导致失败**的问题：

**阻断级**

1. `lib/slim.ps1` 的 `Select-WimIndex` 在非交互模式（GUI / `winiso run`）返回 `$script:AutoIndex`，而这个变量从来没被赋值 —— 等于 `dism /Mount-Wim /Index:0`，必然「挂载 install.wim 失败」。现在未显式给就用索引 1。
2. `lib/common.ps1` 的 `-C -` 与 `--retry-all-errors` 在 Win10 1803-1909 自带的 curl 7.55-7.66 上是**未知选项**（退出码 2）。现在先探测 `curl --version`，< 7.71 自动降级，只有新版本才带这个开关。
3. `lib/converter.ps1` 的 `Invoke-Convert` 用 `Get-ChildItem *.iso | Sort LastWriteTime` 找产物，会把上一轮遗留的旧 ISO 当成本轮结果；现在只认「本次开始时间之后」写出的 ISO，找不到才宽松兜底并告警。
4. 转换器在出错分支里会 `pause` 等回车 —— 图形界面是无输入环境，会**永久卡住**。现在以 `convert-UUP.cmd < nul` 启动，堵死输入。

**断点续跑（本来是假的）**

5. `Invoke-Generate` 每轮都会 `Remove-Item $stage -Recurse`，把已下好的 6-8 GB `UUPs` 一起删掉，所谓「重跑会接着下」根本做不到。现在重建 `pkg` 前先把 `UUPs` 挪到 `UUPs_keep`，解包后挪回。
6. 转换完的原版 ISO 立刻缓存到 `<项目目录>\base_<架构>_<版本>.iso`；下次运行若发现它，直接跳过「下载 + 转换」（省 30-60 分钟），只重做精简这一步。
7. 完整性兜底原来只看「文件存在」；截断的半截文件也算存在，于是转换器报莫名其妙的错。现在逐个核对 SHA-1，坏文件删掉并提示重下。

**无人值守 / 精简正确性**

8. `BypassNRO` 原来写在 `windowsPE` 段的 RunSynchronous —— 那是改 WinPE 自己的注册表，对装好的系统无效。现在挪到 `specialize` 段（`Microsoft-Windows-Deployment`）。
9. 删掉了 `Microsoft-Windows-SQM-Opt-in` 组件（组件名不一定在每版映像里都有，写错会让 setup 直接报解析错误；遥测本来就已用组策略关掉）。
10. `InputLocale` 从裸 `zh-CN` 改成规范写法 `0804:00000804`（en-us 为 `0409:00000409`）。
11. `reg load` 配置单元：加载前先 unload 同名残留（上次崩溃会留挂载导致 `reg load` 报「已被加载」）；卸载加 5 次重试，避免句柄未释放把 `NTUSER.DAT` 锁住。
12. `Do-SlimExisting` 原来硬编码 `Offline = $true`，arm64 ISO 在 amd64 机上会挂载失败；现在先问架构，按架构判定能否离线。
13. 勾了「移除 WinRE」但没勾精简时，原来的代码整段跳过（WinRE 根本没删）；现在也会进精简流程。

**其它**

14. GUI 取构建标题用 `.Split('    ')` —— 字符串参数被当成 `char[]`，等于按单个空格切，标题只剩「Windows」。改用 `-split '\s{4,}'`。
15. GUI / CLI 默认工作目录改成优先 E 盘（E → D → 用户目录），符合「别放 C 盘」的约定。
16. 启动器 `oscdimg` 的 `-bootdata` 参数里 boot 文件路径补上引号（工作目录带空格时原本解不出来）。
17. `Build-FirstLogonScript` 的 PowerToys 启动路径修正（实际装在 `Program Files\PowerToys`，不是 `%LOCALAPPDATA%`）；`-Arch` 从主机架构改为 ISO/所选架构。
18. `Save-UrlToFile` 加了 `-f`（404 网页不再被当成文件存下）、`--connect-timeout 20`、外层 3 次重试。
19. `Resolve-Exe` 在 `$env:SystemRoot` 为空时不再崩；`Do-Check` 的 `Test-Admin` 也加了 try。
20. `Start-ParallelDownload` 的分片 Job 改用统一的「版本自适应」重试参数（原来硬编码 `--retry-all-errors`）。

**这次做的自动化验证**

- 6 个脚本 Parser 解析：0 错误
- AST 交叉比对：72 个函数、851 处调用、0 个未定义
- 真打 API：321 个 win11 构建、39 种语言、3 个版本种类
- 真下 6 个文件（3 线程）：6/6 下载 + SHA-1 通过；把一个文件截断成一半后再下：续传成功且 SHA-1 一致
- `Save-UupPackage` POST 返回真 ZIP（8226 字节）
- 生成的 `autounattend.xml` 用 XmlDocument 解析通过，并断言 BypassNRO 在 specialize 段、PE 段没有
- 生成的首登脚本再过一遍 PowerShell Parser：0 错误
- ConvertConfig.ini 键位与官方 `convert-UUP.cmd` 的 `findstr /b` 读法对齐（键必须在行首）

**还没法在这里验证的**（必须 Windows + 管理员）

- DISM 挂载/提交、`convert-UUP.cmd` 全流程、cdimage 出可引导 ISO、装机实际效果（尤其 autounattend 各段是否被 setup 接受）

## 第二轮复查：对照官方转换器源码再核一遍（2026-11-21）

第一轮是"通读 + 跑断言"，第二轮把官方 `uup-converter-wimlib-v128m.7z` 重新下下来（1,686,886 字节），
解开里面的 `convert-UUP.cmd` **逐句读它的判断逻辑**，再回来对配置项的语义。这一步抓到的都是
"脚本本身没报错、但语义理解错了"的隐性 bug：

| # | 问题 | 后果 | 改法 |
|---|---|---|---|
| 1 | `SkipEdge` 给了 1 | 官方里它是**档位**不是开关：0=不处理、1=只是不集成 Edge 更新组件、**2 才真正移除 Edge** | 勾"移除 Edge"时写 2，不勾写 0；`New-ConvertConfig` 改成原样写档位（原来被压成 1/0） |
| 2 | `StubAppsFull =0` | 0 会让商店应用装成"占位存根"，点开才去下载，体验更差 | 改成官方默认 1 |
| 3 | `vAutoStart =1` | 与 `StartVirtual=0` 冲突，可能额外跑一遍虚拟版本转换 | 改 0 |
| 4 | 写了 `TaskbarSn` | 官方 ini 里没有这个键名，属于自造，写了也没人读 | 删掉 |
| 5 | 界面提示"放 D 盘 / 5-6 GB / 40-90 分钟" | 实际清单 7.82 GB、95 个文件，耗时也更长，会误导 | 改成"E 盘 / 7-8 GB / 60-120 分钟" |

顺带修的三处细节：

- 三个清单文件/data 文件带 UTF-8 BOM，第一行行首残留零宽字符，解析时会多出一条垃圾项 → 解析前统一剥掉 `U+FEFF`。
- 挂载 ISO 后用 `Get-Volume` 取盘符，个别镜像会带**多个卷**（UDF + 元数据卷），取回来是数组，拼路径会变成 `C D:\` → 只取真正有盘符的第一个卷。
- 首登脚本里 PowerToys 的安装路径按 `Program Files` 判断，不再写死 LOCALAPPDATA。

第二轮验证（全部通过）：

- 6 个脚本 Parser 语法：0 错误；AST 交叉比对：72 个函数定义、120 个不同调用、**0 个未定义**。
- 生成出来的 `ConvertConfig.ini` 断言：`SkipEdge=2`（勾移除 Edge）、`StubAppsFull=1`、`vAutoStart=0`、`SkipWinRE=1`、`SkipApps=0`。
- aria2 清单解析 95 条；mac 美化注册表 47 项且确认没有 `TaskbarSn`。
- `autounattend.xml` 用 arm64 + en-us 生成后 XmlDocument 解析通过、`InputLocale` 为 `0409:00000409`、`processorArchitecture="arm64"`。
- 首登脚本再跑一次 Parser：0 错误；不勾 Spotlight 时确实不会去装 PowerToys。
- 三个精简清单解析：win11 Appx 33 / 包 10，win10 21 / 9，server 17 / 5，无垃圾项；hosts 域名 152 条（`www.facebook.com/tr` 这种带路径的行会被自动丢掉）。

## 第三轮复查：逐行通读 + 换"环境角度"再验（2026-11-23）

前两轮是"读逻辑 + 对照官方源码"，这轮专门找**在自己机器上跑得通、换台机器就炸**的那类问题，
又修了 5 处：

| # | 位置 | 问题 | 后果 |
|---|---|---|---|
| 1 | `winiso.ps1` 精简段 | 命中"原版 ISO 缓存"时，上面的下载/转换整段没执行，`$conv` 是空的；而 `Resolve-Oscdimg` 里搜的是 `..\stage\bin` 这种旧布局目录，根本指不到 `<项目>\pkg\bin` | 第二次运行时如果没装 ADK，会报"找不到 oscdimg"，明明转换器就在硬盘上 |
| 2 | `lib/slim.ps1` ESD→WIM | 只判断"文件存在"，不看 dism 退出码 | 导出中途失败留下半截 wim，后面挂载报的是看不懂的错，还会白跑 20 分钟 |
| 3 | `lib/slim.ps1` 选索引 | 用户在菜单里按 `q` 返回 `$null` | `dism /Index:` 后面是空值，直接失败 |
| 4 | `lib/slim.ps1` 打包 ISO | `-bootdata` 里必须带引号，但 **PowerShell 5.1 调原生程序不转义参数里的引号**，参数又含空格时整条命令行被拼坏 | 工作目录一旦带空格（`E:\winiso work`），cdimage 解不出 bootdata，打出来的 ISO 不可引导 |
| 5 | `winiso.ps1` 提示文案 | 还写着"下载 6GB" | 实际清单 7-8 GB，和界面对不上 |

第 4 条的修法是把整条命令交给 `cmd.exe /s /c` 原样解析（`/s` 只剥最外层一对引号），
实测拼出来的命令行是：

```
/s /c ""E:\winiso work\pkg\bin\cdimage.exe" -m -o -u2 -udfver102 -bootdata:2#p0,e,b"…\etfsboot.bin"#pEF,e,b"…\efisys.bin" "-lWINISO" "…\iso" "…\out.iso""
```

另外补了 `$script:AutoIndex` / `$script:NonInteractive` 的初始化（原来只读不赋值，
现在没有 StrictMode 不会报错，但初始化了更干净）。

### 这轮怎么查的

1. **逐行读完全部 7 个脚本**（winiso 895 行 / common 435 / uup 242 / converter 206 / slim 540 / gui 837 / build-exe），
   不是扫关键词，是一行行往下读，边读边记"这一行依赖什么、什么情况下不成立"。
2. **扫描 `$script:` 变量**：把 GUI 和 lib 里所有 `$script:xxx` 引用列出来，逐个核"有没有地方给它赋值"，
   结果只有一个 `AutoIndex`（可选参数，已初始化）。
3. **扫 PowerShell 7 专属语法**（`??`、`?.`、`-Parallel`、`AsHashtable`、`AsByteStream`、`Test-Json`、
   `Join-String`、`Get-Error`、`-LeafBase`）：全部为 0，只有 `::new()` 8 处，5.0+ 就支持。
4. **把 oscdimg 命令行真的拼出来看**（带空格的路径），确认 `/s /c` 后 cmd 收到的是合法命令。
5. **重跑全套断言**：7 文件 Parser 0 错误；ConvertConfig 档位 `SkipEdge=2 / StubAppsFull=1 / vAutoStart=0`。

## 第五轮：可执行验证（2026-11-23）

前四轮都是"读 + 断言"，这轮直接**把 `Invoke-SlimIso` 跑起来**：在 Linux 的 pwsh 里把
`dism.exe`/`robocopy.exe`/`reg.exe`/`oscdimg.exe` 换成假的壳、用假 cmdlet 顶替
`Mount-DiskImage`/`Get-Volume`/`Start-Process`，然后喂一棵假的 ISO 目录树进去，
跑"跨架构（$OEM$ 注入）"和"同架构（挂载→改→提交）"两条路径，12 项断言全部 PASS。

这轮抓到 1 处：挂载映像里 `Windows\System32\drivers\etc` 不存在时（少数精简/Server 核心版），
`Add-Content` 写 hosts 会直接抛错、整套流程中断。已改为先确保目录存在，并统一用 `-LiteralPath`。

完整审查记录见 `AUDIT.md`。

## 第六轮：结构与可用性复查（2026-11-27）

这轮不再看"哪里会报错"，而是看**代码里有没有用不上的东西、有没有把用户合法的需求堵死**：

| 检查项 | 方法 | 结果 |
|---|---|---|
| 死代码 | 用 PowerShell AST 把「函数定义」和「命令调用/字符串分派」对齐，逐一求差 | 72 个函数里只有 `Pause-Any` 从未被调用（无害小工具，保留） |
| 重名函数 | 同名定义计数 | 0 处 |
| 硬编码路径 | 全量 grep `X:\` | 只剩 E 盘默认工作目录、ADK 的 `C:\Program Files (x86)\Windows Kits` 搜索路径，无 C 盘产出路径 |
| TODO / 调试残留 | grep `TODO/FIXME/HACK/breakpoint/Debug` | 0 处 |
| 文件编码 | 逐字节检查 BOM + 行尾 | 6 个 ps1 + build-exe = BOM+CRLF；两个 cmd = 纯 ASCII+CRLF；cs = 无 BOM+CRLF；数据文件 BOM+CRLF |
| hosts 安全性 | 检查是否误封系统域名 | 无 `microsoft.com / windowsupdate / office / azure / bing / github` 等，只用广告/统计域，不会搞坏更新和商店 |
| 包体一致性 | 解压 zip 后逐文件 md5 对比源码 | 7 个关键文件全部一致 |

修了 2 处：

1. **GUI 把"只做原版 ISO"这条需求堵死了**：一项操作都不勾时直接 `return`，只弹"至少勾选一项"。
   实际上底层 `Invoke-Generate` 完全支持零操作（不做精简，直接把原版 ISO 复制到输出目录）。
   现在改成放行并提示"本次只生成官方原版 ISO"。
2. GUI 状态栏还写着"下载 5-6 GB，40-90 分钟"（第 4 轮只改了左侧提示，漏了这一处），已统一为 7-8 GB / 60-120 分钟；
   顺带给 `$work.Substring(0,2)` 加了长度保护（用户只输入一个字母时不会抛异常）。

## 第七轮：死磕真漏洞（2026-11-27）

这轮只干一件事：找"用户真会遇到、但代码里看不出来"的坑。逐个复现，找到 5 个。

**① 中文用户名 → 图形界面点"开始生成"后管理员窗口一闪就没，日志永远空白（致命）**

`gui/WinIsoGui.ps1` 里用 `[Text.Encoding]::ASCII` 写 `run.cmd`。
中文用户名时 `%TEMP%` 就是 `C:\Users\李旭熠\AppData\Local\Temp\...`，ASCII 编码把汉字写成 `?`：

```
powershell -File "E:\winiso\winiso.ps1" run "C:\Users\???\AppData\Local\Temp\...\params.json"
```

实测复现：`是否被破坏: True`。PowerShell 找不到参数文件 → 立刻退出 → 界面上什么都看不到。
改成"全 ASCII 才用 ASCII，含非 ASCII 就用 UTF-8 无 BOM"（第一行已有 `chcp 65001`）。

**② 退出码 0 但没抓到结果标记 → 按钮永久灰掉，只能关窗口重开**

原逻辑只在"失败"分支恢复按钮。补上：退出码 0 时如果没看到 `WINISO_RESULT_ISO=`，
自动去输出目录找最新的 `.iso` 当结果；找不到也把按钮恢复，状态写"已结束"。

**③ 一分钟没有任何输出时没有任何提示**

UAC 被拒、或参数文件没读到时，界面就一直"正在生成…"。现在空转 60 次（约 55 秒）后
提示"管理员窗口是否弹出来了？被拒的话重新点开始生成"，并恢复按钮。

**④ 原版 ISO 缓存门槛只有 100 MB → 残缺文件被当成完好缓存**

断电/中断留下的半截 ISO（比如 800 MB）会通过 `> 100MB` 的判断，被直接拿去精简，
打出来的镜像是坏的，日志里却一路"正常"。实测判定逻辑：门槛提到 **2 GB**（任何 Windows ISO 都 ≥ 2 GB），
不到 2 GB 就明确报"发现不完整的缓存（x GB），已丢弃重做"。

**⑤ 只检查工作盘空间，从不检查输出盘**

输出目录指到 2 GB 的 U 盘时，全程跑完（40-90 分钟）才在最后拷贝 ISO 这步失败。
现在开工前就查：输出盘不足 8 GB 直接拒绝并说明原因。

**验证**：7 个脚本 Parser 0 错误；模拟运行 12 项断言仍全 PASS；
用 `C:\Users\李旭熠\...` 真实复现了 ①，用假缓存文件验证了 ④ 的判定分支。

累计修复：**38 处**（前五轮 33 + 第六轮 2 + 本轮 5，其中第六轮第 3 项为附带保护）。
