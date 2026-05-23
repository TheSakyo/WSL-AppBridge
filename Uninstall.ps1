<#
.SYNOPSIS
    Removes one WSL-AppBridge instance (a single distro) or every installed
    instance plus the shared payload.
.DESCRIPTION
    The new install layout puts per-distro state under
    %LOCALAPPDATA%\WSL-AppBridge\instances\<Distro>\. Removing an instance
    means: unregister its Scheduled Tasks (suffixed with -<Distro>), delete
    its shortcut tree, delete its instance folder. The shared payload
    (modules, scripts) is only removed when -All is passed and no instances
    are left.
.PARAMETER Distro
    Name of the distro to uninstall (default: Debian).
.PARAMETER All
    Remove every instance and the shared payload -- wipes %LOCALAPPDATA%\WSL-AppBridge.
.PARAMETER KeepShortcuts
    Keep the generated .lnk tree(s) on disk.
.EXAMPLE
    .\Uninstall.ps1 -Distro Debian
.EXAMPLE
    .\Uninstall.ps1 -All
#>
[CmdletBinding(DefaultParameterSetName='Single')]
param(
    [Parameter(ParameterSetName='Single')]
    [string] $Distro = 'Debian',

    [Parameter(ParameterSetName='All')]
    [switch] $All,

    [switch] $KeepShortcuts
)

$ErrorActionPreference = 'Continue'
$dst = Join-Path $env:LOCALAPPDATA 'WSL-AppBridge'

# Resolve which distros are about to be removed.
$instancesRoot = Join-Path $dst 'instances'
$targets = if ($All) {
    if (Test-Path $instancesRoot) {
        (Get-ChildItem -Path $instancesRoot -Directory -ErrorAction SilentlyContinue).Name
    } else { @() }
} else { @($Distro) }

foreach ($d in $targets) {
    Write-Host "Removing instance: $d" -ForegroundColor Cyan

    # 1. Scheduled tasks (suffixed by distro).
    foreach ($t in "WSL-AppBridge-Sync-$d","WSL-AppBridge-Watcher-$d") {
        if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $t -Confirm:$false
            Write-Host "  [ok] Removed task: $t"
        }
    }

    # 2. Shortcut tree (path comes from the instance's settings.json).
    if (-not $KeepShortcuts) {
        $cfgFile = Join-Path $dst "instances\$d\settings.json"
        if (Test-Path $cfgFile) {
            try {
                $root = (Get-Content $cfgFile -Raw | ConvertFrom-Json).ShortcutRoot
                if ($root -and (Test-Path $root)) {
                    # Delete children first, sleep slightly to let explorer release handles, then drop the root folder
                    Get-ChildItem -Path $root -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 100
                    Remove-Item -Path $root -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Host "  [ok] Removed shortcuts: $root"
                }
            } catch {}
        }
    }

    # 3. Instance directory.
    $instanceDir = Join-Path $dst "instances\$d"
    if (Test-Path $instanceDir) {
        Remove-Item -Path $instanceDir -Recurse -Force
        Write-Host "  [ok] Removed instance dir: $instanceDir"
    }
}

# Legacy cleanup: old single-distro layout used WSL-AppBridge-Sync / -Watcher
# (no suffix) and a top-level config\settings.json. Drop them on -All too.
if ($All) {
    foreach ($t in 'WSL-AppBridge-Sync','WSL-AppBridge-Watcher') {
        if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $t -Confirm:$false
            Write-Host "  [ok] Removed legacy task: $t"
        }
    }
    if (Test-Path $dst) {
        # Remove everything except the running script itself to prevent sharing violations
        Get-ChildItem -Path $dst -Recurse -ErrorAction SilentlyContinue | 
            Where-Object { $_.FullName -ne $PSCommandPath } | 
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    
        # Schedule the removal of the remaining directory and script after this process exits
        Start-Process cmd.exe -ArgumentList "/c timeout /t 1 /nobreak >nul & rmdir /s /q `"$dst`"" -WindowStyle Hidden
        Write-Host "  [ok] Removed shared payload: $dst"
    }
} elseif ((Test-Path $instancesRoot) -and
         (-not (Get-ChildItem -Path $instancesRoot -Directory -ErrorAction SilentlyContinue))) {
    # No instances left -- clean up the empty shared payload too without self-locking
    Get-ChildItem -Path $dst -Recurse -ErrorAction SilentlyContinue | 
        Where-Object { $_.FullName -ne $PSCommandPath } | 
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    
    Start-Process cmd.exe -ArgumentList "/c timeout /t 1 /nobreak >nul & rmdir /s /q `"$dst`"" -WindowStyle Hidden
    Write-Host "No instances remaining. Removed shared payload: $dst"
}

Write-Host 'Uninstall complete.' -ForegroundColor Green
