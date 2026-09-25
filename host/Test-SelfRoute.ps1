<#
自路由的验收探针：报告自己跑在哪个引擎、收到了什么参数、并按需返回指定退出码。
它自己也会被加上自路由片段（本工具跑一遍 tools 就会带上），所以它的输出就是"路由是否生效"的证据。

证明的是三件名字垫片做不到的事：
  * 写死 System32 全路径启动它 → 仍然跑在 Core
  * 干净 PATH 下的 cmd 启动它（解析到 5.1）→ 仍然跑在 Core
  * 参数与退出码在 5.1 → pwsh 那一次重启里没有丢

  powershell -File Test-SelfRoute.ps1 -Tag hello -ExitCode 7      # 5.1 入口，期望 engine=Core、tag=hello、exit=7
#>
[CmdletBinding()]
param(
  [string]$Tag = '(none)',
  [int]$ExitCode = 0
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




"engine=" + $PSVersionTable.PSEdition + " " + $PSVersionTable.PSVersion.ToString()
"tag=" + $Tag
"argcount=" + $args.Count
"script=" + $PSCommandPath
exit $ExitCode
