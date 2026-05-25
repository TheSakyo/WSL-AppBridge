<#
.SYNOPSIS
    One-shot synchronisation of WSL GUI apps into Windows .lnk shortcuts.
.DESCRIPTION
    1. Loads settings (defaults override-able by config\settings.json).
    2. Computes a fingerprint of all .desktop files; short-circuits if
       nothing changed (override with -Force).
    3. Discovers apps, builds icons, writes shortcuts, removes orphans.
    4. Persists fingerprint + counters to state.json for the watcher.
.PARAMETER ConfigPath
    Path to a settings.json overriding the defaults.
.PARAMETER Force
    Rebuild every shortcut regardless of the fingerprint short-circuit.
.EXAMPLE
    pwsh .\Sync-WSLApps.ps1
.EXAMPLE
    pwsh .\Sync-WSLApps.ps1 -Force
#>
[CmdletBinding()]
param(
    [string] $ConfigPath,
    [switch] $Force
)

# ----------------------------- bootstrap -----------------------------------
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Modules = Join-Path $Root 'modules'

# Load modules sequentially using Import-Module.
# This respects Export-ModuleMember statements and exposes functions globally
# across scripts while handling .psm1 strict encapsulation correctly.
foreach ($m in 'Logger', 'Categories', 'Discovery', 'WslSetup', 'Icons', 'Shortcuts') {
    $path = Join-Path $Modules "WSLAppBridge.$m.psm1"
    if (-not (Test-Path $path)) { throw "Module file missing: $path" }
    try { Unblock-File -Path $path -ErrorAction SilentlyContinue } catch {}
    Import-Module -Name $path -Force -Scope Global
}

if (-not (Get-Command Initialize-WABLogger -ErrorAction SilentlyContinue)) {
    throw "Logger functions still not in scope -- WSLAppBridge.Logger.psm1 may be corrupted."
}

# ----------------------------- configuration -------------------------------
$defaultCfg = [pscustomobject]@{
    Distro       = 'Debian'
    Display      = ':0'
    ShortcutRoot = $null  # Built dynamically below to include the targeted Distro name
    IconCache    = Join-Path $env:LOCALAPPDATA 'WSL-AppBridge\icons'
    StateFile    = Join-Path $env:LOCALAPPDATA 'WSL-AppBridge\state.json'
    LogFile      = Join-Path $env:LOCALAPPDATA 'WSL-AppBridge\sync.log'
    LogLevel     = 'Info'
}
$cfgFile = if ($ConfigPath) { $ConfigPath } else { Join-Path $Root 'config\settings.json' }
$cfg = $defaultCfg.PSObject.Copy()
if (Test-Path $cfgFile) {
    try {
        $user = Get-Content $cfgFile -Raw | ConvertFrom-Json
        foreach ($prop in $user.PSObject.Properties) {
            $cfg.$($prop.Name) = $prop.Value
        }
    }
    catch {
        Write-Warning "Cannot read '$cfgFile': $($_.Exception.Message). Using defaults."
    }
}

# FIX: Dynamically assign the shortcut directory to the Windows Start Menu, isolation by Distro
if ([string]::IsNullOrEmpty($cfg.ShortcutRoot)) {
    $cfg.ShortcutRoot = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\WSL Apps\$($cfg.Distro)"
}

Initialize-WABLogger -Path $cfg.LogFile -Level $cfg.LogLevel
Write-WABInfo "WSL-AppBridge sync starting (distro=$($cfg.Distro))."

$vbs = Join-Path $Root 'Run-WSL.vbs'
if (-not (Test-Path $vbs)) {
    Write-WABError "VBS launcher missing at $vbs. Re-run Install.ps1."
    exit 2
}

# ----------------------------- wrapper self-heal --------------------------
# If ~/.wsl-appbridge/launch.sh is missing inside the distro (fresh WSL,
# distro recreated, user wiped $HOME, etc.) -- redeploy it transparently so
# the user never sees a half-broken state.
try {
    $wrapperLinux = Get-WABWrapperLinuxPath -Distro $cfg.Distro
    if ($wrapperLinux) {
        $wrapperUnc = Convert-WABWslPathToUnc -Distro $cfg.Distro -LinuxPath $wrapperLinux
        
        # FIX: Sanitize the UNC path string by stripping embedded null characters ([char]0)
        # that occur when WSL outputs raw C-style byte strings during execution.
        if ($null -ne $wrapperUnc) {
            $wrapperUnc = $wrapperUnc.Replace("`0", "").Trim()
        }

        # Safely evaluate path existence only if the string is valid and populated
        if (-not [string]::IsNullOrEmpty($wrapperUnc) -and -not (Test-Path -LiteralPath $wrapperUnc)) {
            $assetSrc = Join-Path $Root 'assets\launch.sh'
            if (Test-Path $assetSrc) {
                Write-WABWarn "Wrapper missing in distro -- redeploying."
                Install-WABWslWrapper -Distro $cfg.Distro -LocalWrapperSource $assetSrc
            }
        }
    }
}
catch {
    Write-WABWarn "Wrapper self-heal skipped: $($_.Exception.Message)"
}

# ----------------------------- first-run dep probe ------------------------
# On the very first sync (no state.json yet), tell the user which optional
# Linux packages are missing. Quiet on every subsequent run.
if (-not (Test-Path $cfg.StateFile)) {
    try { Test-WABWslDependencies -Distro $cfg.Distro | Out-Null }
    catch { Write-WABWarn "Dependency probe failed: $($_.Exception.Message)" }
}

# ----------------------------- fingerprint short-circuit -------------------
$fingerprint = Get-WABDesktopFilesHash -Distro $cfg.Distro
if (-not $fingerprint) {
    Write-WABError "Cannot reach WSL distro '$($cfg.Distro)'. Aborting."
    exit 3
}
$state = $null
if (Test-Path $cfg.StateFile) {
    try { $state = Get-Content $cfg.StateFile -Raw | ConvertFrom-Json } catch {}
}
if (-not $Force -and $state -and $state.Fingerprint -eq $fingerprint) {
    Write-WABInfo "No .desktop changes (fingerprint $fingerprint). Skipping."
    exit 0
}

# ----------------------------- discovery -----------------------------------
$apps = Get-WABDesktopApps -Distro $cfg.Distro
if (-not $apps -or $apps.Count -eq 0) {
    Write-WABWarn 'No applications discovered. Nothing to sync.'
    exit 0
}

# ----------------------------- write shortcuts -----------------------------
if (-not (Test-Path $cfg.ShortcutRoot)) {
    New-Item -ItemType Directory -Force -Path $cfg.ShortcutRoot | Out-Null
}
$kept = New-Object System.Collections.Generic.List[string]
$changed = 0
foreach ($app in $apps) {
    try {
        $icon = Get-WABIconForApp -Distro $cfg.Distro -AppId $app.Id `
            -IconRef $app.IconRef -CacheDir $cfg.IconCache
        $res = New-WABShortcut -RootDir $cfg.ShortcutRoot -App $app `
            -Distro $cfg.Distro -VbsLauncher $vbs `
            -IconPath $icon -Display $cfg.Display
        $kept.Add($res.Path)
        if ($res.Changed) { $changed++ }
    }
    catch {
        Write-WABError "Failed for '$($app.Name)': $($_.Exception.Message)"
    }
}

Remove-WABOrphanShortcuts -RootDir $cfg.ShortcutRoot -KeepPaths $kept

# ----------------------------- persist state -------------------------------
$stateDir = Split-Path $cfg.StateFile -Parent
if (-not (Test-Path $stateDir)) {
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
}
[pscustomobject]@{
    Fingerprint = $fingerprint
    SyncedAt    = (Get-Date).ToString('o')
    AppCount    = $apps.Count
    Changed     = $changed
} | ConvertTo-Json | Set-Content -Path $cfg.StateFile -Encoding UTF8

Write-WABInfo "Sync complete: $($apps.Count) apps, $changed shortcut(s) updated."