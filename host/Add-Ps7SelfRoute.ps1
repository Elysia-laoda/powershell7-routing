<#
给脚本插入"自路由"片段：脚本被 5.1 启动时，带原参数把自己重启进 pwsh。

这补的是名字垫片补不了的那一块 —— 写死 System32 全路径启动、别人的计划任务、别的程序、
guest 里双击 .ps1：这些调用方根本不经过 PATH 上的 powershell，只有脚本自己能救自己。

片段必须是纯 ASCII：片段的第一现场就是在 5.1 里被解析，而 5.1 会把无 BOM 的 UTF-8 脚本按 GBK
读 —— 中文注释的误码会让 tokenizer 在片段之前就报错，片段永远执行不到。所以本工具顺手做第二件
事：含非 ASCII 内容的脚本补一个 UTF-8 BOM（BOM 让 5.1 按 UTF-8 读，能正常解析；PS7 照读不误）。
缺了这条，含中文的脚本正是最救不回来的那些。

片段特征（用于幂等与撤回）：起始标记行 ... 结束标记行（两个字面量见下面的 $begin / $end）。
插入点在 **脚本头部注释（块注释，或开头连续的 # 行）、param 块、using 语句之后** —— 前两者都不能
被代码挡在前面，注释式帮助被挡住就会失效。已含该片段或已含 #requires -PSEdition 的文件跳过：
两者互斥，因为 #requires 会让 5.1 在片段运行之前就拒绝执行。

pwsh 不存在时片段原样放行（继续按 5.1 跑）：这是给"PS7 还没装的机器"留的退路，不是静默降级。

注意：本文件永远跳过自己（两个模式都跳过）。它的源码里含上面两个标记字面量，幂等检查会把它认成
"已插入"，而移除操作会把保存片段的 here-string 一起剪掉 —— 都踩过。

  .\Add-Ps7SelfRoute.ps1 -Path D:\ZCodeprojecttt\tools              # 干跑
  .\Add-Ps7SelfRoute.ps1 -Path D:\ZCodeprojecttt\tools -Apply       # 落盘
  .\Add-Ps7SelfRoute.ps1 -Path D:\ZCodeprojecttt\tools -Apply -Remove
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string[]]$Path,
  [string[]]$Exclude = @(),
  [switch]$Apply,
  [switch]$Remove
)
$ErrorActionPreference = 'Stop'
$begin = '#psr7-selfroute-' + 'begin'
$end   = '#psr7-selfroute-' + 'end'
$selfName = [IO.Path]::GetFileName($PSCommandPath)

# -File 调用不做逗号拆分（逗号拆分只发生在 -Command 的命令行解析里），所以 -Path 与 -Exclude 都要自己拆
$flatPath = @()
foreach ($p in $Path) { foreach ($piece in ($p -split ',')) { $t = $piece.Trim(); if ($t.Length -gt 0) { $flatPath += $t } } }
$Path = $flatPath
$flat = @()
foreach ($e in $Exclude) { foreach ($piece in ($e -split ',')) { $t = $piece.Trim(); if ($t.Length -gt 0) { $flat += $t } } }
$Exclude = $flat

# 纯 ASCII —— 见文件头：这段代码要在 5.1 里被解析
$snippet = @'
#psr7-selfroute-begin
# This script has to run under PowerShell 7. Launched by Windows PowerShell 5.1, it restarts
# itself in pwsh with the same arguments. That covers the callers a PATH shim cannot reach: a
# hardcoded System32 path, someone else's scheduled task, another program, a double-click in a
# guest. If pwsh is not installed the script simply continues on 5.1.
if ($PSVersionTable.PSEdition -ne 'Core') {
    $__psr7 = 'C:\Program Files\PowerShell\7\pwsh.exe'
    if (-not (Test-Path -LiteralPath $__psr7)) { $__psr7 = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe' }
    if (Test-Path -LiteralPath $__psr7) {
        $__psrArg = @()
        $__psrCmd = [Environment]::GetCommandLineArgs()
        for ($__psrI = 1; $__psrI -lt $__psrCmd.Count; $__psrI++) {
            $__psrHit = $false
            try { $__psrHit = ([IO.Path]::GetFullPath($__psrCmd[$__psrI].Replace('/', '\')) -ieq [IO.Path]::GetFullPath($PSCommandPath)) } catch { }
            if ($__psrHit) {
                if ($__psrI + 1 -lt $__psrCmd.Count) { $__psrArg = $__psrCmd[($__psrI + 1)..($__psrCmd.Count - 1)] }
                break
            }
        }
        & $__psr7 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @__psrArg
        exit $LASTEXITCODE
    }
}
#psr7-selfroute-end
'@

$files = @()
foreach ($p in $Path) {
  if (Test-Path -Path $p -PathType Container) {
    $files += Get-ChildItem -Path $p -Filter *.ps1 -Recurse -File | Where-Object { $_.FullName -notmatch '\\_trash\\' }
  } else { $files += Get-Item -Path $p }
}

$n = 0; $skipped = 0; $bom = 0
foreach ($f in $files) {
  if ($Exclude -contains $f.Name) { "  skip(排除)  $($f.Name)"; continue }
  if ($f.Name -eq $selfName) { "  skip(工具自身) $($f.Name)"; $skipped++; continue }

  $bytes = [IO.File]::ReadAllBytes($f.FullName)
  $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $text = [IO.File]::ReadAllText($f.FullName)
  $eol = "`n"; if ($text.Contains("`r`n")) { $eol = "`r`n" }

  # 非 ASCII + 无 BOM => 5.1 按 GBK 读它，片段不可达。补 BOM（与是否插片段无关）。
  # 必须对"解码后的文本"判断：对字节数组做 -match 会先把每字节转成十进制字符串，永远匹配不到。
  $wantBom = (($text -match '[^\x00-\x7F]') -and -not $hasBom)
  $enc = New-Object System.Text.UTF8Encoding(($hasBom -or $wantBom))
  if ($wantBom) { $bom++ }
  $suffix = ''; if ($wantBom) { $suffix = '+BOM' }

  if ($Remove) {
    if ($text -notmatch [regex]::Escape($begin)) { "  skip(无片段) $($f.Name)"; $skipped++; continue }
    $new = [regex]::Replace($text, "(?s)\r?\n[ \t]*$([regex]::Escape($begin)).*?$([regex]::Escape($end))[ \t]*", '')
    if ($Apply) { [IO.File]::WriteAllText($f.FullName, $new, $enc); "  REMOVED$suffix  $($f.Name)" } else { "  would drop  $($f.Name)" }
    $n++; continue
  }

  if ($text -match [regex]::Escape($begin)) { "  skip(已有)  $($f.Name)"; $skipped++; continue }
  if ($text -match '(?m)^\s*#requires\s+-PSEdition') { "  skip(#requires) $($f.Name)"; $skipped++; continue }

  # 插入点必须在三样东西之后：脚本头部注释、param 块、using 语句
  $at = 0
  if ($text.StartsWith('<#')) {
    $close = $text.IndexOf('#>')
    if ($close -ge 0) { $at = $close + 2 }
  } else {
    $m = [regex]::Match($text, "(?s)\A(?:[ \t]*(?:#[^\r\n]*)?\r?\n)*")
    if ($m.Success) { $at = $m.Length }
  }
  $tok = $null; $err = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tok, [ref]$err)
  if ($err -and $err.Count -gt 0) { "  skip(解析失败) $($f.Name): $($err[0].Message)"; $skipped++; continue }
  if ($ast.ParamBlock) { if ($ast.ParamBlock.Extent.EndOffset -gt $at) { $at = $ast.ParamBlock.Extent.EndOffset } }
  foreach ($u in @($ast.UsingStatements)) { if ($u.Extent.EndOffset -gt $at) { $at = $u.Extent.EndOffset } }

  $new = $text.Substring(0, $at) + $eol + ($snippet -replace "`r?`n", $eol) + $eol + $text.Substring($at)
  if ($Apply) { [IO.File]::WriteAllText($f.FullName, $new, $enc); "  ADDED$suffix  $($f.Name)" } else { "  would add   $($f.Name)" }
  $n++
}

$verb = '会改'; if ($Remove) { $verb = '会撤' }
if ($Apply) { "done: $n 个，跳过 $skipped 个，补 BOM $bom 个" } else { "干跑：$verb $n 个，跳过 $skipped 个，会补 BOM $bom 个（加 -Apply 才落盘）" }
