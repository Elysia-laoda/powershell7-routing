<#
Installs the powershell -> pwsh routing shim for the guest's Git Bash, then verifies it by
running that bash and asking what `powershell` resolves to.

Runs in the guest. The three shim scripts are staged as plain files (C:\Windows\Temp\psshim)
and land in $HOME\bin, which the Git profile already puts first on PATH
(D:\Git\etc\profile.d\env.sh does `export PATH="$HOME/bin:$PATH"` on the host -- same
installer, same file, so the shim needs no PATH edit of its own).

Scope, deliberately: Git Bash only. cmd.exe, Task Scheduler and Windows' own components
keep resolving C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe, because shadowing
that machine-wide needs a real launcher .exe ahead of System32 on the machine PATH and
redirects Windows' own scripts too. See the repository README.
#>
[CmdletBinding()]
param(
  [string]$Stage = 'C:\Windows\Temp\psshim',
  [string]$Bash  = 'C:\Program Files\Git\bin\bash.exe'
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

$names = 'powershell', 'powershell.exe', 'powershell5'
$bin   = Join-Path $env:USERPROFILE 'bin'
New-Item -ItemType Directory -Force -Path $bin | Out-Null

foreach ($n in $names) {
  $src = Join-Path $Stage $n
  if (-not (Test-Path $src)) { throw "staged shim missing: $src" }
  Copy-Item -Path $src -Destination (Join-Path $bin $n) -Force
}
"installed into $bin :"
(Get-ChildItem $bin -Name | Where-Object { $_ -like 'powershell*' }) -join ', '

if (-not (Test-Path $Bash)) { "no Git Bash at $Bash -- shim installed but unverified"; return }

# MSYS decides executability for extension-less files from the ACL, not from the source
# file's mode, so a copied file can land non-executable. chmod once, then prove it by running.
$chmod = 'chmod +x $HOME/bin/powershell $HOME/bin/powershell.exe $HOME/bin/powershell5; echo chmod_exit=$?'

# Keep double quotes out of this string. Under 5.1 an argument carrying an embedded " reaches a
# native exe truncated at the first one, which silently ate the tail of this probe and printed
# `via` where the whole prefix belonged. Single quotes survive. Full verification, with a bash
# -x trace of which branch the shim takes, is Test-GuestPsshim.ps1.
$probe = 'command -v powershell; command -v powershell.exe; command -v powershell5; ' +
         'powershell -NoProfile -Command ''$PSVersionTable.PSVersion.ToString()''; ' +
         'powershell5 -NoProfile -Command ''$PSVersionTable.PSVersion.ToString()'''

"chmod: " + ((& $Bash -lc $chmod 2>&1 | Out-String).Trim())
"probe:"
((& $Bash -lc $probe 2>&1 | Out-String).Trim())
