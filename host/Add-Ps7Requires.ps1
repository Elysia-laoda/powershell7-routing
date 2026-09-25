<#
给主机侧脚本加一行 `#requires -PSEdition Core`：引擎不是 PowerShell 7 就**大声失败**，
而不是静默按 5.1 跑出 GBK 乱码 / UTF-16 落盘那类结果。
插在文件头注释块之后、`param` 之前；行尾与 BOM 保持原样；已含 #requires -PSEdition 的跳过。

默认是**干跑**（只列会改哪些文件），确认后再加 -Apply。

   .\Add-Ps7Requires.ps1 -Path D:\ZCodeprojecttt\tools\vm -Exclude Dsh-Server.ps1,Guest.ps1
   .\Add-Ps7Requires.ps1 -Path D:\ZCodeprojecttt\tools\vm -Exclude ... -Apply

别给这些加：guest 侧脚本（装 PS7 之前就得能跑）、以及启动器还写死 powershell 的脚本
（例如 Dsh-Server.ps1 由 GoWebUI.bat 用 powershell.exe 启动 —— 加了它会让服务器起不来）。
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string[]]$Path,
  [string[]]$Exclude = @(),
  [switch]$Apply,
  [switch]$Remove            # 反向：把标记行删掉（用于纠正误加）
)
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




$ErrorActionPreference = 'Stop'
$marker = '#requires -PSEdition Core'

# 归一化排除项：用 -File 调用脚本时 PowerShell **不做逗号拆分**，`-Exclude a,b,c` 会作为
# 一个整串进来（逗号拆分只发生在 -Command 的命令行解析里）。所以这里自己拆。
$flat = @()
foreach ($e in $Exclude) {
  foreach ($piece in ($e -split ',')) {
    $t = $piece.Trim()
    if ($t.Length -gt 0) { $flat += $t }
  }
}
$Exclude = $flat

$files = @()
foreach ($p in $Path) {
  if (Test-Path -Path $p -PathType Container) {
    $files += Get-ChildItem -Path $p -Filter *.ps1 -File | Where-Object { $_.FullName -notmatch '\\_trash\\' }
  } else {
    $files += Get-Item -Path $p
  }
}

$added = 0; $skipped = 0
foreach ($f in $files) {
  if ($Exclude -contains $f.Name) { "  skip(排除)  $($f.Name)"; continue }

  $bytes = [IO.File]::ReadAllBytes($f.FullName)
  $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $text = [IO.File]::ReadAllText($f.FullName)
  $enc = New-Object System.Text.UTF8Encoding($hasBom)

  if ($Remove) {
    if ($text -notmatch '(?m)^[ \t]*#requires\s+-PSEdition') { "  skip(无标记) $($f.Name)"; $skipped++; continue }
    # 连同插入时多出来的那个空行一起删
    $new = [regex]::Replace($text, '(?m)^[ \t]*#requires -PSEdition Core[ \t]*\r?\n(\r?\n)?', '')
    if ($Apply) { [IO.File]::WriteAllText($f.FullName, $new, $enc); "  REMOVED     $($f.Name)" }
    else        { "  would drop  $($f.Name)" }
    $added++
    continue
  }

  if ($text -match '(?m)^\s*#requires\s+-PSEdition') { "  skip(已有)  $($f.Name)"; $skipped++; continue }

  $eol = "`n"
  if ($text.Contains("`r`n")) { $eol = "`r`n" }

  $at = 0
  if ($text.StartsWith('<#')) {
    $close = $text.IndexOf('#>')
    if ($close -ge 0) { $at = $close + 2 }
  }
  $new = $text.Substring(0, $at) + $eol + $marker + $eol + $text.Substring($at)

  if ($Apply) {
    [IO.File]::WriteAllText($f.FullName, $new, $enc)
    "  ADDED       $($f.Name)"
  } else {
    "  would add   $($f.Name)"
  }
  $added++
}

if ($Remove) { $verb = '会撤' } else { $verb = '会加' }
if ($Apply) { "改了 $added 个，跳过 $skipped 个" } else { "干跑：$verb $added 个，跳过 $skipped 个（加 -Apply 才落盘）" }
