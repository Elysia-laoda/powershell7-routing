<#
Verifies the guest's powershell -> pwsh routing shim. Runs in the guest.

Every case runs in a FRESH login bash (bash -lc), so a hard exit in one case -- which is
what a failed `exec` in a non-interactive shell does -- cannot hide the next one, and each
case echoes its own exit code. A `bash -x` trace of the shim is included so the branch it
takes (Program Files / WindowsApps alias / 5.1 fallback) is visible rather than inferred.
#>
[CmdletBinding()]
param([string]$Bash = 'C:\Program Files\Git\bin\bash.exe')
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





$cases = @(
  'command -v powershell; command -v powershell.exe; command -v powershell5',
  'head -1 $HOME/bin/powershell',
  'test -x $HOME/AppData/Local/Microsoft/WindowsApps/pwsh.exe; echo alias_exec_bit=$?',
  'bash -x $HOME/bin/powershell --version 2>&1 | tail -20',
  '$HOME/bin/powershell --version; echo rc=$?',
  'powershell --version; echo rc=$?',
  'powershell -NoProfile -Command ''$PSVersionTable.PSVersion.ToString()''; echo rc=$?',
  'powershell5 -NoProfile -Command ''$PSVersionTable.PSVersion.ToString()''; echo rc=$?',
  'POWERSHELL_LEGACY=1 powershell -NoProfile -Command ''$PSVersionTable.PSVersion.ToString()''; echo rc=$?',

  # The setup script's inline probe reproduced this exactly twice: it printed `via` where
  # `echo -n "via powershell:  "` should have printed the whole prefix, then stopped. These
  # isolate whether an unwrapped echo -n before the shim is what cuts the capture short.
  'echo -n "via powershell:  "; powershell --version; echo END1',
  'echo -n "via powershell:  "; echo MARK; powershell --version; echo END2',
  'echo "via powershell:  "; powershell --version; echo END3',
  'printf "via powershell:  "; powershell --version; echo END4',
  'echo -n "plain "; echo END5'
)

foreach ($c in $cases) {
  "== " + $c
  (& $Bash -lc $c 2>&1 | Out-String).Trim()
  "--"
}
