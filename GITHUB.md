# 传到 GitHub（3 种方式，选一个）

这个目录已经是**可以直接 push 的仓库结构**：源码 + `LICENSE` + `.gitignore` + GitHub Actions 自动编译 exe。

```
winiso/
├─ winiso.ps1  winiso.cmd          主脚本 / 命令行入口
├─ gui/WinIsoGui.ps1  WinIsoGui.cmd  图形界面（WPF，内嵌 XAML）
├─ launcher/WinIsoLauncher.cs       exe 外壳（负责拉起 WPF）
├─ build-exe.ps1                   用系统自带 csc.exe 编译 winiso.exe
├─ lib/*.ps1                       common / uup / converter / slim
├─ data/*.txt                      精简清单 + hosts 黑名单
├─ .github/workflows/build.yml     push 后自动：语法检查 → 编译 → 上传 exe
├─ LICENSE (MIT)  .gitignore  README.md
```

## 方式一：网页上传（最省事）

1. GitHub 右上角 **+ → New repository**，名字随便（如 `winiso`），**不要**勾"Add a README"。
2. 进仓库页 → **Add file → Upload files** → 把这个目录里的**所有文件/文件夹**拖进去（`.github`、`.gitignore` 属于隐藏项，Windows 资源管理器里要打开"显示隐藏文件"才看得到）。
3. 底下 Commit changes。
4. 进 **Actions** 标签页，`build` 会自动跑，跑完在 Artifacts 里拿到 `winiso.zip` 和编译好的 `winiso.exe`。

## 方式二：命令行（已经装 Git）

```bash
cd winiso
git init -b main
git add .
git commit -m "winiso: 官方源生成 Windows ISO（GUI + 精简 + 美化）"
git remote add origin https://github.com/<你的用户名>/winiso.git
git push -u origin main
```

## 方式三：打 tag 发 Release（自带 exe 下载）

```bash
git tag v1.0
git push origin v1.0
```
然后到仓库 **Releases → Draft a new release**，选 `v1.0`，把 `winiso.zip` 传上去。

> 注意：仓库里**不要**提交 `.iso` / `.esd` / `_work` 这类大文件，`.gitignore` 已经挡掉了；
> 单个文件超过 100 MB 会被 GitHub 拒收（真要传大文件请用 Release 附件）。
