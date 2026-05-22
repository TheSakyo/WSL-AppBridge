<#
.SYNOPSIS
    Polling watcher: triggers Sync-WSLApps.ps1 when .desktop files change.
.DESCRIPTION
    A deliberately simple loop (default 60s). Cheaper than a Linux daemon,
    survives WSL restarts, and a stale poll just means the next interval
    catches up. Launched at logon via Scheduled Task by Install.ps1.
.PARAMETER IntervalSeconds
    Polling interval in seconds (default 60).
.PARAMETER ConfigPath
    Path to a settings.json overriding the defaults.
#>
[CmdletBinding()]
param(
    [int]    $IntervalSeconds = 60,
    [string] $ConfigPath
)

$ErrorActionPreference = 'Continue'
$Root    = $PSScriptRoot
$Modules = Join-Path $Root 'modules'

foreach ($m in 'Logger','Discovery') {
    $path = Join-Path $Modules "WSLAppBridge.$m.psm1"
    if (-not (Test-Path $path)) { throw "Module file missing: $path" }
    try { Unblock-File -Path $path -ErrorAction SilentlyContinue } catch {}
    . ([scriptblock]::Create((Get-Content -Raw -LiteralPath $path)))
}
if (-not (Get-Command Initialize-WABLogger -ErrorAction SilentlyContinue)) {
    throw "Logger functions still not in scope."
}

# Reuse the same config the sync script uses.
$cfgFile = if ($ConfigPath) { $ConfigPath } else { Join-Path $Root 'config\settings.json' }
$logPath = Join-Path $env:LOCALAPPDATA 'WSL-AppBridge\watcher.log'
$distro  = 'Debian'
if (Test-Path $cfgFile) {
    try {
        $user = Get-Content $cfgFile -Raw | ConvertFrom-Json
        if ($user.Distro)  { $distro  = $user.Distro }
        if ($user.LogFile) { $logPath = Join-Path (Split-Path $user.LogFile -Parent) 'watcher.log' }
    } catch {}
}
Initialize-WABLogger -Path $logPath -Level 'Info'

$syncScript = Join-Path $Root 'Sync-WSLApps.ps1'

# Pick the same PowerShell host that's currently running.
function Get-WABPwshExe {
    $p = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($p) { return $p.Source }
    return "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
}
$psExe = Get-WABPwshExe

$last = $null
Write-WABInfo "Watcher started (distro=$distro, interval=${IntervalSeconds}s)."
while ($true) {
    try {
        $fp = Get-WABDesktopFilesHash -Distro $distro
        if ($fp -and $fp -ne $last) {
            Write-WABInfo "Change detected (fingerprint $fp). Triggering sync."
            & $psExe -NoProfile -ExecutionPolicy Bypass -File $syncScript -ConfigPath $cfgFile
            $last = $fp
        }
    } catch {
        Write-WABError "Watcher error: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $IntervalSeconds
}
