param(
    [string]$IconResource   = "%SystemRoot%\System32\imageres.dll,-198",
    [string]$DisplayName    = "代码",
    [bool]$PinToQuickAccess = $true
)

$folder = Join-Path $HOME "Codes"

if (-not (Test-Path $folder)) {
    New-Item -ItemType Directory -Path $folder | Out-Null
    Write-Host "已创建文件夹: $folder" -ForegroundColor Green
}

$iniPath = Join-Path $folder "desktop.ini"

# 若文件已存在且带只读/系统/隐藏属性，先清成 Normal，否则 WriteAllText 会「拒绝访问」
if (Test-Path $iniPath) {
    Set-ItemProperty -LiteralPath $iniPath -Name Attributes -Value Normal -Force
}

$iniContent = @"
[.ShellClassInfo]
LocalizedResourceName=$DisplayName
IconResource=$IconResource
"@

# desktop.ini 必须用系统 ANSI 代码页(中文系统=GBK)写入。
# Explorer 按 GBK 解析该文件，若写成 UTF-8，中文名会乱码成「浠ｇ爜」这种。
[System.IO.File]::WriteAllText($iniPath, $iniContent, [System.Text.Encoding]::Default)

attrib +s +h +r $iniPath
attrib +r  $folder

Write-Host "已设置显示名称: $DisplayName" -ForegroundColor Green
Write-Host "已设置图标资源: $IconResource" -ForegroundColor Green
Write-Host "如果没有立即变化，请在资源管理器中按 F5 刷新。" -ForegroundColor Cyan

# ── 固定到「快速访问」（已存在则跳过，幂等）─────────────────────────
# 全部走 Shell.Application 的官方动词 API，不读写任何注册表键。
#
# 下面的 CLSID 是【微软公开文档化的 Shell 命名空间常量】，等同于 ssfDESKTOP=0 这类
# 官方标识符，是"调用 Shell API 的地址参数"，并非危险的注册表值写入。快捷方式 .lnk、
# shell::: URI 内部同样使用这些 CLSID——它们是跨版本稳定的寻址方式，不是魔法字符串。
#
# 为什么保留 CLSID 而不是"零 GUID 动态发现"：实测遍历 Desktop 虚拟项、用内容特征定位
# 快速访问需 ~30671ms（要枚举 Gallery/回收站/网络发现等），而直接用 CLSID 仅 ~3ms；
# 且内容特征法依赖"Downloads 等仍被固定"这一假设，反而更脆弱。故用 CLSID + 逐个探测。
#
# 关键实测结论（Windows 11 build 28000）：
#   1. InvokeVerb('pintohome') 是【开关式(toggle)】：对"已固定"的文件夹再调一次会把它
#      【取消固定】。因此「已固定则跳过」的检测不是可选优化，而是防止误删固定的刚需。
#   2. 「是否已固定」只能靠枚举快速访问项、比对路径来判断：文件夹即便已固定，其右键
#      动词仍显示 "Pin to &Quick access"，动词名不可用于幂等判断。
if ($PinToQuickAccess) {
    # Shell 命名空间 CLSID（公开常量，出处见上）。不同 Windows 版本命名不同，逐个探测：
    $CLSID_QUICKACCESS_HOME   = 'shell:::{F874310E-B6B7-47DC-BC84-B9E6B38F5903}'  # Win11 24H2+「主页/Home」
    $CLSID_QUICKACCESS_LEGACY = 'shell:::{679f85cb-0220-4080-b29b-5547cc36176a}'  # Win10/旧版「快速访问」
    $qaClsids = @($CLSID_QUICKACCESS_HOME, $CLSID_QUICKACCESS_LEGACY)

    try {
        $shell = New-Object -ComObject Shell.Application

        $qaClsid = $null
        $qa      = $null
        foreach ($c in $qaClsids) {
            $n = $shell.Namespace($c)
            if ($n) { $qaClsid = $c; $qa = $n; break }
        }

        # 枚举快速访问，判断目标路径是否已固定（忽略大小写与结尾分隔符）
        function Test-Pinned {
            param($Shell, $Clsid, $Target)
            if (-not $Clsid) { return $false }
            $ns = $Shell.Namespace($Clsid)   # 每次重新取，避免缓存导致误判
            if (-not $ns) { return $false }
            $t = $Target.TrimEnd('\')
            return [bool](@($ns.Items() | Where-Object { $_.Path.TrimEnd('\') -ieq $t }).Count)
        }

        if (-not $qa) {
            Write-Host "未能访问快速访问命名空间，跳过固定。" -ForegroundColor Yellow
        }
        elseif (Test-Pinned $shell $qaClsid $folder) {
            Write-Host "已固定在快速访问，跳过: $folder" -ForegroundColor Green
        }
        else {
            $item = $shell.Namespace((Split-Path $folder)).ParseName((Split-Path $folder -Leaf))

            # 首选：canonical verb（与系统语言无关的官方动词标识）
            $item.InvokeVerb('pintohome')
            Start-Sleep -Milliseconds 1500

            # 回退：若该 build 不认 canonical verb（调用后仍未固定），退回本地化动词名匹配
            if (-not (Test-Pinned $shell $qaClsid $folder)) {
                $pinVerb = $null
                foreach ($v in $item.Verbs()) {
                    $vn = ($v.Name -replace '&', '')
                    if ($vn -match 'unpin|取消固定|从.{0,3}快速') { continue }
                    if ($vn -match 'pin|固定') { $pinVerb = $v; break }
                }
                if ($pinVerb) { $pinVerb.DoIt(); Start-Sleep -Milliseconds 1500 }
            }

            if (Test-Pinned $shell $qaClsid $folder) {
                Write-Host "已固定到快速访问: $folder" -ForegroundColor Green
            } else {
                Write-Host "已触发固定但未能确认，请在资源管理器中查看快速访问。" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "固定到快速访问失败（不影响图标/显示名设置）: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

explorer $folder