# --- ps7-router begin (managed block) ------------------------------------------------------
# Environment-side routing for Windows PowerShell 5.1.
#
# Install: append this whole block to your Windows PowerShell 5.1 profile
#   $PROFILE   ->  %USERPROFILE%\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1
# then set $__r7Roots below to the directories whose scripts should run on PowerShell 7.
#
# What it does: on every 5.1 start that loads a profile -- cmd, Task Scheduler, another program,
# a double-click -- look at the "-File <path>" argument. If that path normalises to somewhere
# under one of the roots below, run the job under PowerShell 7 and terminate this process with
# that exit code. Everything else (no -File, path outside the roots, pwsh missing) falls through
# untouched, so 5.1 stays the default. Callers that pass -NoProfile skip this block entirely.
#
# Structure rules, all three learned the hard way:
#   * the DECISION lives inside try/catch; the job launch and the process exit sit OUTSIDE it.
#   * "exit" from inside a profile does NOT cancel the command the caller asked for -- the 5.1
#     session happily ran the script a second time after the redirect. [Environment]::Exit is
#     what actually stops it. Note it terminates immediately: no finally blocks, no cleanup.
#   * the file is pure ASCII: the 5.1 tokenizer reads it, and a no-BOM UTF-8 profile carrying
#     non-ASCII text can fail to parse before anything here runs.
$__r7Go = $null
$__r7A = @()
$__r7Code = 0
try {
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        # EDIT ME: the roots whose scripts should be handed to PowerShell 7
        $__r7Roots = @('D:\your-workspace')
        $__r7Pwsh = 'C:\Program Files\PowerShell\7\pwsh.exe'
        if (-not (Test-Path -LiteralPath $__r7Pwsh)) { $__r7Pwsh = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe' }
        if (Test-Path -LiteralPath $__r7Pwsh) {
            $__r7C = [Environment]::GetCommandLineArgs()
            $__r7N = $__r7C.Count
            $__r7File = $null
            $__r7At = -1
            for ($__r7I = 1; $__r7I -lt $__r7N; $__r7I++) {
                if ($__r7C[$__r7I] -ieq '-File') { if ($__r7I + 1 -lt $__r7N) { $__r7File = $__r7C[$__r7I + 1]; $__r7At = $__r7I + 1 }; break }
                if ($__r7C[$__r7I] -like '-File:*') { $__r7File = $__r7C[$__r7I].Substring(6); $__r7At = $__r7I; break }
            }
            if ($__r7File) {
                $__r7Full = $null
                try { $__r7Full = [IO.Path]::GetFullPath($__r7File.Replace('/', '\')) } catch { }
                if ($__r7Full) {
                    foreach ($__r7Root in $__r7Roots) {
                        $__r7R = $__r7Root.TrimEnd('\')
                        if (($__r7Full -ieq $__r7R) -or ($__r7Full.StartsWith($__r7R + '\', [StringComparison]::OrdinalIgnoreCase))) {
                            $__r7Go = $__r7Full
                            if ($__r7At + 1 -lt $__r7N) { $__r7A = $__r7C[($__r7At + 1)..($__r7N - 1)] }
                            try {
                                Add-Content -LiteralPath (Join-Path $env:TEMP 'ps7-router.log') -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' routed-to-pwsh  ' + $__r7Full) -Encoding utf8
                            } catch { }
                            break
                        }
                    }
                }
            }
        }
    }
} catch { }
if ($__r7Go) {
    # Outside try/catch on purpose. A failure to start pwsh must still not fall through to a
    # second run of the same script on 5.1, so the exit below is unconditional.
    try { & $__r7Pwsh -NoProfile -ExecutionPolicy Bypass -File $__r7Go @__r7A; $__r7Code = $LASTEXITCODE } catch { $__r7Code = 66 }
    [Environment]::Exit($__r7Code)
}
# --- ps7-router end -------------------------------------------------------------------------
