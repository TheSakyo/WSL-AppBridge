<#
.SYNOPSIS
    Installs WSL-AppBridge for a given WSL distribution.
.DESCRIPTION
    Layout:
        %LOCALAPPDATA%\WSL-AppBridge\
            modules\                        -- shared payload (one copy total)
            assets\launch.sh                -- shared payload
            Sync-WSLApps.ps1                -- shared payload
            Watch-WSLApps.ps1               -- shared payload
            Run-WSL.vbs                     -- shared payload
            Uninstall.ps1                   -- shared payload
            instances\<Distro>\
                settings.json               -- per-distro config
                state.json                  -- per-distro fingerprint
                sync.log / watcher.log      -- per-distro logs
                icons\                      -- per-distro icon cache

    Scheduled Tasks are suffixed with the distro name so multiple distros can
    coexist without trampling each other:
        WSL-AppBridge-Sync-<Distro>         -- at logon + daily noon
        WSL-AppBridge-Watcher-<Distro>      -- at logon, polls indefinitely

    A Linux-side wrapper (~/.wsl-appbridge/launch.sh) is deployed inside the
    distro to handle X11, PulseAudio, DBus and Wayland-only bypass.
.PARAMETER Distro
    WSL distribution name (default: Debian). Run Install.ps1 again with a
    different value to install a second instance side by side.
.PARAMETER Display
    X11 DISPLAY value passed to the wrapper (default: :0).
.PARAMETER ShortcutRoot
    Where to write the shortcut tree.
    Default: %USERPROFILE%\Desktop\WSL Apps\<Distro>.
.PARAMETER SkipWatcher
    Don't register the watcher task -- sync-only mode.
.PARAMETER SkipScheduledTasks
    Don't register any tasks -- manual operation only.
.EXAMPLE
    .\Install.ps1
.EXAMPLE
    .\Install.ps1 -Distro Ubuntu
.EXAMPLE
    # Two instances side by side
    .\Install.ps1 -Distro Debian
    .\Install.ps1 -Distro Ubuntu
#>
[CmdletBinding()]
param(
    [string] $Distro = 'Debian',
    [string] $Display = ':0',
    [string] $ShortcutRoot,
    [switch] $SkipWatcher,
    [switch] $SkipScheduledTasks
)

$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$dst = Join-Path $env:LOCALAPPDATA 'WSL-AppBridge'

# Per-distro paths.
$instanceDir = Join-Path $dst        "instances\$Distro"
$settingsPath = Join-Path $instanceDir 'settings.json'

if (-not $ShortcutRoot) {
    $ShortcutRoot = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\WSL Apps\$Distro"
}

Write-Host "Installing WSL-AppBridge ($Distro) -> $dst" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 1. Copy shared payload (idempotent -- overwrites in place).
# ---------------------------------------------------------------------------
if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Force -Path $dst         | Out-Null }
if (-not (Test-Path $instanceDir)) { New-Item -ItemType Directory -Force -Path $instanceDir | Out-Null }

foreach ($item in 'Sync-WSLApps.ps1', 'Watch-WSLApps.ps1', 'Run-WSL.vbs', 'Uninstall.ps1', 'README.md') {
    $p = Join-Path $src $item
    if (Test-Path $p) { Copy-Item $p (Join-Path $dst $item) -Force }
}

# Recreate modules + assets cleanly to avoid stale files between upgrades.
foreach ($folder in 'modules', 'assets') {
    $dstFolder = Join-Path $dst $folder
    if (Test-Path $dstFolder) { Remove-Item $dstFolder -Recurse -Force }
    if (Test-Path (Join-Path $src $folder)) {
        Copy-Item (Join-Path $src $folder) $dst -Recurse -Force
    }
}

# Strip Zone.Identifier (Mark-of-the-Web) from every file we just copied.
# Required so pwsh actually exposes module function exports even though
# -ExecutionPolicy Bypass is set on the parent process.
Get-ChildItem -Path $dst -Recurse -File -ErrorAction SilentlyContinue |
Unblock-File -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# 2. Write per-instance config.
# ---------------------------------------------------------------------------
$cfg = [pscustomobject]@{
    Distro       = $Distro
    Display      = $Display
    ShortcutRoot = $ShortcutRoot
    IconCache    = Join-Path $instanceDir 'icons'
    StateFile    = Join-Path $instanceDir 'state.json'
    LogFile      = Join-Path $instanceDir 'sync.log'
    LogLevel     = 'Info'
}
$cfg | ConvertTo-Json | Set-Content -Path $settingsPath -Encoding UTF8
Write-Host "  [ok] Config: $settingsPath"

# ---------------------------------------------------------------------------
# 3. Resolve a PowerShell host (prefer pwsh, fall back to Windows PowerShell).
# ---------------------------------------------------------------------------
$pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
$rawHost = if ($pwshCmd) { $pwshCmd.Source }
else { "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" }

# WRAPPER CONHOST : Forces Windows to use the legacy invisible console subsystem instead 
# of spawning new tabs/windows in modern Windows Terminal at startup.
$conhost = "$env:WINDIR\System32\conhost.exe"

# ---------------------------------------------------------------------------
# 4. Linux-side setup (wrapper + deps) is handled by Sync's first-run path.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 5. Scheduled tasks (suffixed by distro so multiple installs coexist).
# ---------------------------------------------------------------------------
if (-not $SkipScheduledTasks) {
    $syncScript = Join-Path $dst 'Sync-WSLApps.ps1'
    $watchScript = Join-Path $dst 'Watch-WSLApps.ps1'

    # The action now starts conhost.exe, which instantly swallows the window, 
    # and passes the real PowerShell host as the first parameter.
    $commonArgs = "`"$rawHost`" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File"

    $syncTaskName = "WSL-AppBridge-Sync-$Distro"
    $watchTaskName = "WSL-AppBridge-Watcher-$Distro"

    # FIX: Use Interactive LogonType instead of S4U. 
    # This associates the running context completely with your active desktop session,
    # allows proper interaction with WSL, and guarantees window suppression when combined
    # with the hidden execution settings.
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
    
    # Sync task: at logon AND daily 12:00 (cheap safety net).
    $syncAction = New-ScheduledTaskAction  -Execute $conhost `
        -Argument "$commonArgs `"$syncScript`" -ConfigPath `"$settingsPath`""
    $syncTrigger1 = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $syncTrigger2 = New-ScheduledTaskTrigger -Daily   -At 12:00pm
    $syncSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $syncTaskName -Action $syncAction `
        -Trigger @($syncTrigger1, $syncTrigger2) -Settings $syncSettings -Principal $principal -Force | Out-Null
    Write-Host "  [ok] Scheduled task: $syncTaskName"

    if (-not $SkipWatcher) {
        $watchAction = New-ScheduledTaskAction  -Execute $conhost `
            -Argument "$commonArgs `"$watchScript`" -ConfigPath `"$settingsPath`""
        $watchTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $watchSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -MultipleInstances IgnoreNew `
            -ExecutionTimeLimit ([TimeSpan]::Zero)
        Register-ScheduledTask -TaskName $watchTaskName -Action $watchAction `
            -Trigger $watchTrigger -Settings $watchSettings -Principal $principal -Force | Out-Null
        Write-Host "  [ok] Scheduled task: $watchTaskName"
    }
}

# ---------------------------------------------------------------------------
# 6. Initial sync.
# ---------------------------------------------------------------------------
Write-Host 'Running initial sync...' -ForegroundColor Cyan
& $rawHost -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $dst 'Sync-WSLApps.ps1') -ConfigPath $settingsPath

Write-Host "`nInstalled ($Distro). Shortcuts: $ShortcutRoot" -ForegroundColor Green