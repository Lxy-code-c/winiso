# winiso 代码审查报告（五轮，累计 33 处修复）

审查对象：7 个脚本 + 4 个数据文件，共 3,155 行

| 文件 | 行数 | 作用 |
|---|---|---|
| winiso.ps1 | 896 | 入口 / check / diag / list / pack / run / 交互向导 / 精简已有 ISO |
| lib/common.ps1 | 435 | 日志、菜单、提权、curl 下载、多线程分片、磁盘 |
| lib/uup.ps1 | 242 | UUPdump 接口：构建/语言/版本/aria2 清单/脚本包 |
| lib/converter.ps1 | 206 | 官方转换器：下载、解压、写 ConvertConfig、跑 convert-UUP、找 oscdimg |
| lib/slim.ps1 | 540 | DISM 挂载精简、hosts、注册表、autounattend、首登脚本、重建 ISO |
| gui/WinIsoGui.ps1 | 837 | WPF 界面（XAML 内嵌） |
| build-exe.ps1 | 26 | 用系统 csc.exe 编 exe |
| data/*.txt | 173+69+36+25 | hosts 黑名单 + 三套精简清单 |

## 五轮各自查什么、抓到什么

| 轮次 | 方法 | 抓到 |
|---|---|---|
| 第 1 轮 | 通读 + 语法解析 + AST 未定义扫描 + 真打 API + 真下载/续传 | 20 处（阻断级 2 处：索引默认 0、旧 curl 不支持 `--retry-all-errors`；假断点续传；BypassNRO 写错 pass…） |
| 第 2 轮 | 下载官方 `convert-UUP.cmd` 源码，逐句核对配置项语义 | 5 处（SkipEdge 档位给错、StubAppsFull、vAutoStart、无效 TaskbarSn、文案） |
| 第 3 轮 | 扫 PowerShell 7 专属语法、`$script:` 变量赋值闭环、路径带空格 | 2 处（缓存名缺语言会复用错语言 ISO、`/out` 无引号） |
| 第 4 轮 | 逐行通读 7 个脚本，专找"换台机器就炸" | 5 处（缓存命中时 oscdimg 找不到、ESD 导出不看退出码、索引返回空、`-bootdata` 内嵌引号被 PS 5.1 拆坏、文案 6GB） |
| 第 5 轮 | **真跑**：造一棵假 ISO 树 + 假 dism/robocopy/reg/oscdimg/cmdlet，执行 `Invoke-SlimIso` 两条路径 | 1 处（etc 目录不存在时 hosts 写入直接抛错） |

## 第 5 轮：可执行验证（不是读代码）

在 Linux 的 pwsh 7 上，把 Windows 专属命令全部换成"假可执行文件"，
真正调用 `Invoke-SlimIso`，覆盖两条主路径：

**场景 A —— 跨架构（不挂载，走 `$OEM$` 注入）**
- 复制 ISO 内容（假 robocopy）→ 写 autounattend.xml → 注入 `sources\$OEM$\$\$\Setup\Scripts\winiso-firstlogon.ps1` → 重建 ISO
- 断言 cmd 收到的是 `/s /c "<oscdimg>" … -bootdata:2#p0,e,b"…"#pEF,e,b"…"`（引号正确）

**场景 B —— 同架构（DISM 挂载 → 改映像 → 提交）**
- 假 dism 负责 `/Mount-Wim`（铺出假 Windows 树）、`/Unmount-Wim /Commit`
- 写 hosts（2 条域名）、写注册表（2 条，一条 SOFTWARE 一条 DEFAULT）、删 WinRE、写回 install.wim
- 断言调用序列里确实出现 `reg add` 和 `Unmount-Wim … Commit`

结果：**12 项断言全部 PASS**。过程中发现：挂载映像里 `Windows\System32\drivers\etc` 不存在时
`Add-Content` 直接抛错、整套流程中断 —— 已改为先建目录再写，且用 `-LiteralPath`。

## 当前状态（静态层面已无已知缺陷）

- 7 个脚本 Parser 语法：0 错误
- AST：72 个函数定义，120 个不同调用，0 个未定义
- PS 5.1 兼容性：`??`/`?.`/`-Parallel`/`AsHashtable`/`AsByteStream`/`Test-Json`/`Join-String`/`Get-Error`/`-LeafBase` 全部 0 处；`::new()` 8 处（5.0+ 支持）
- 生成 `ConvertConfig.ini`：`AutoStart=1 / SkipEdge=2 / StubAppsFull=1 / vAutoStart=0 / SkipWinRE=0/1 / SkipApps=0/1`
- `autounattend.xml`（amd64/arm64 × zh-CN/en-us）：XmlDocument 解析通过，BypassNRO 在 specialize、PE 段无、InputLocale 规范
- 首登脚本：Parser 0 错误，不含 Spotlight 时不会去装 PowerToys
- 数据：win11 33/10、win10 21/9、server 17/5；hosts 152 域名；mac 注册表 47 条

## 仍然只能在 Windows 实机验证的（不吹）

1. DISM 真挂载/提交（假 dism 只验证了我们的调用与判断逻辑）
2. `convert-UUP.cmd` 全流程（下载 7.8 GB → wimlib 合成 → cdimage 打包）
3. `autounattend.xml` 是否被 setup 真正接受（语法对 ≠ 微软认）
4. 离线 `reg load` 是否成功（假 reg 恒返回 0）
5. `/s /c` 交给真 cmd 后 cdimage 是否正常打包并**可引导**
6. `Get-AppxProvisionedPackage / Get-WindowsPackage -Path` 在真实挂载目录上的行为
