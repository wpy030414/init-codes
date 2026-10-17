# init-codes

一键初始化代码目录：创建 `~/Codes`、设置语义化图标、加入 Finder「个人收藏」，并在文件管理器中打开。

| 平台 | 脚本 |
|------|------|
| macOS | [`init.sh`](init.sh) |
| Windows | [`init.ps1`](init.ps1) |

## macOS

### 用法

```bash
chmod +x init.sh
./init.sh
```

### 可选参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--dir <路径>` | `~/Codes` | 目标目录 |
| `--icon <文件>` | 自动生成 | 自定义图标（`.icns` / `.png` / `.tiff` 等） |
| `--reset` | — | 移除自定义图标，恢复系统默认 |
| `--no-pin` | — | 不加入 Finder「个人收藏」 |
| `--no-open` | — | 完成后不打开 Finder |
| `-h, --help` | — | 显示帮助 |

### 示例

```bash
# 使用默认设置
./init.sh

# 换一个目录
./init.sh --dir ~/Projects

# 使用自己的图标
./init.sh --icon ~/Pictures/code.icns

# 恢复默认图标
./init.sh --reset

# 不加入 Finder「个人收藏」
./init.sh --no-pin
```

### 图标

默认图标由「当前系统版本的通用文件夹」叠加 SF Symbol `chevron.left.forwardslash.chevron.right`（也就是 `</>` 代码符号）生成。这是 macOS 系统图形库中与「代码」语义最直接对应的符号：比 `DeveloperFolderIcon`（锤子，偏「开发工具」）和 Terminal 图标（偏「命令行」）都更贴题。

符号颜色不是纯白，而是取系统文件夹图形同款的深蓝色（比文件夹底色深一档），所以在 Finder 里和「图片 / 下载 / 音乐」这些系统文件夹放在一起不会显得突兀。

系统没有 SF Symbols（macOS 11 以下）时，自动退回使用内置的 `DeveloperFolderIcon.icns`。

### 做了什么

1. 确保 `~/Codes` 目录存在
2. 生成图标，并通过 `NSWorkspace.setIcon:forFile:options:` 写入——等价于在 Finder「显示简介」里粘贴图标：目录内会出现隐藏的 `Icon\r`（图标数据存在资源分支），目录被打上 `com.apple.FinderInfo` 的自定义图标标记
3. 把目录加入 Finder「个人收藏」（侧边栏），已存在则跳过
4. 触发 Finder 刷新图标，并打开目录

### 限制

- 仅支持 macOS 11+；更低版本仍可运行，但图标会退回系统内置的「开发者文件夹」图标
- macOS 没有为普通文件夹单独指定显示名的机制（没有 `desktop.ini` 的等价物），文件夹名即显示名
- Finder 侧边栏没有官方命令行接口：脚本使用的是已废弃但仍可工作的 `LSSharedFileList`（`mysides` 等第三方工具走的也是这条路），并且需要 Xcode 命令行工具提供的 `clang` 现场编译一个小辅助程序；没有 `clang` 时会跳过「个人收藏」这一步，不影响目录和图标

### 系统要求

- macOS 11+，使用系统自带的 `bash` 与 `osascript`
- 加入「个人收藏」额外需要 Xcode 命令行工具（`clang`）；缺失时自动跳过

## Windows

一键初始化 Windows `~/Codes` 目录，设置中文显示名、自定义图标，并固定到快速访问。

### 用法

```powershell
.\init.ps1
```

### 可选参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `-IconResource` | string | `%SystemRoot%\System32\imageres.dll,-198` | 文件夹图标资源路径 |
| `-DisplayName` | string | `代码` | 文件夹在资源管理器中的显示名称 |
| `-PinToQuickAccess` | bool | `$true` | 是否固定到快速访问 |

### 示例

```powershell
# 使用默认设置
.\init.ps1

# 自定义显示名和图标
.\init.ps1 -DisplayName "项目" -IconResource "C:\icons\folder.ico,0"

# 不固定到快速访问
.\init.ps1 -PinToQuickAccess $false
```

### 做了什么

1. 确保 `~/Codes` 目录存在
2. 通过 `desktop.ini` 设置文件夹的本地化显示名称和图标（GBK 编码写入，兼容中文系统）
3. 设置文件夹和 `desktop.ini` 的只读/系统/隐藏属性
4. 通过 Shell.Application COM 接口将文件夹固定到快速访问（幂等：已固定则跳过）
5. 打开文件夹

### 系统要求

- Windows 10 / Windows 11
- PowerShell 5.1+
