# init-codes

一键初始化 Windows `~/Codes` 目录，设置中文显示名、自定义图标，并固定到快速访问。

## 用法

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

## 做了什么

1. 确保 `~/Codes` 目录存在
2. 通过 `desktop.ini` 设置文件夹的本地化显示名称和图标（GBK 编码写入，兼容中文系统）
3. 设置文件夹和 `desktop.ini` 的只读/系统/隐藏属性
4. 通过 Shell.Application COM 接口将文件夹固定到快速访问（幂等：已固定则跳过）
5. 打开文件夹

## 系统要求

- Windows 10 / Windows 11
- PowerShell 5.1+