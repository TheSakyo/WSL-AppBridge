<#
.SYNOPSIS
    Creates and prunes Windows .lnk shortcuts for WSL GUI apps.
.DESCRIPTION
    Shortcuts target wscript.exe + a shared VBS launcher so the underlying
    wsl.exe runs with no console window (no flash on click). Layout is
    category-folder based. Each shortcut embeds a [sig:…] hash of its
    target/args/icon in its Description, so re-runs only rewrite when
    something actually changed.
#>

# (inter-module dependency loaded by the orchestrating script via dot-sourcing)
# (inter-module dependency loaded by the orchestrating script via dot-sourcing)
# ----------------------------- internals -----------------------------------
# WScript.Shell COM is expensive to spin up; reuse one instance per session.
$script:ShellCom = $null
function Get-WABShellCom {
    if (-not $script:ShellCom) {
        $script:ShellCom = New-Object -ComObject WScript.Shell
    }
    return $script:ShellCom
}

function ConvertTo-WABSafeFileName {
    param([Parameter(Mandatory)][string]$Name)
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $sb = [System.Text.StringBuilder]::new()
    foreach ($c in $Name.ToCharArray()) {
        if ($invalid -contains $c) { [void]$sb.Append('_') }
        else                       { [void]$sb.Append($c) }
    }
    return $sb.ToString().Trim()
}

function Get-WABShortcutSignature {
    param([string]$Target, [string]$Arguments, [string]$Icon)
    $payload = "$Target|$Arguments|$Icon"
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $h   = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($payload))
    return (([BitConverter]::ToString($h) -replace '-','').Substring(0,12)).ToLower()
}

# ----------------------------- public API ----------------------------------
function New-WABShortcut {
<#
.SYNOPSIS
    Creates or updates a .lnk for one WSL app. Skip-rewrite when unchanged.
.OUTPUTS
    PSCustomObject @{ Path = <lnk>; Changed = $true|$false }
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]         $RootDir,
        [Parameter(Mandatory)][pscustomobject] $App,
        [Parameter(Mandatory)][string]         $Distro,
        [Parameter(Mandatory)][string]         $VbsLauncher,
        [string] $IconPath,
        [string] $Display = ':0'
    )

    $folder     = Get-WABCategoryFolder -Categories $App.Categories
    $folderPath = Join-Path $RootDir $folder
    if (-not (Test-Path $folderPath)) {
        New-Item -ItemType Directory -Force -Path $folderPath | Out-Null
    }
    $safeName = ConvertTo-WABSafeFileName -Name $App.Name
    $lnkPath  = Join-Path $folderPath "$safeName.lnk"

    # Switched target to PowerShell to bypass enterprise wscript restrictions
    $target = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

# Escape any literal " inside Exec for the outer Windows-quoted string.
    # Most .desktop Exec values are simple -- this just survives the rare
    # `vlc "my file.mp4"` case.
    $execEscaped = ($App.Exec) -replace '"', '""'

    # Constructed command -- pass through ~/.wsl-appbridge/launch.sh which sets
    # DISPLAY, PULSE_SERVER, forces X11 backends, and starts a DBus session.
    # Fixed: Switched to native call operator '&' with an array of arguments to
    # completely bypass deep quote nesting and parser token breakdown issues.
    $shortcutArgs = "-WindowStyle Hidden -Command ""& wsl.exe -d $Distro --cd ~ bash -c 'DISPLAY=$Display `$HOME/.wsl-appbridge/launch.sh $execEscaped < /dev/null'"""
    $iconArg      = if ($IconPath) { "$IconPath,0" }
                    else { (Join-Path $env:WINDIR 'System32\wsl.exe') + ',0' }

    $signature = Get-WABShortcutSignature -Target $target -Arguments $shortcutArgs -Icon $iconArg

    # Idempotency: if existing .lnk already encodes this signature → skip.
    if (Test-Path -LiteralPath $lnkPath) {
        try {
            $existing = (Get-WABShellCom).CreateShortcut($lnkPath)
            if ($existing.Description -like "*[sig:$signature]*") {
                Write-WABDebug "Up to date: $($App.Name)"
                return [pscustomobject]@{ Path = $lnkPath; Changed = $false }
            }
        } catch {}
    }

    $desc = if ($App.Comment) { "$($App.Comment) [sig:$signature]" }
            else              { "WSL app: $($App.Name) [sig:$signature]" }

    $sc = (Get-WABShellCom).CreateShortcut($lnkPath)
    $sc.TargetPath       = $target
    $sc.Arguments        = $shortcutArgs
    $sc.WorkingDirectory = $env:USERPROFILE
    $sc.IconLocation     = $iconArg
    $sc.Description      = $desc
    $sc.WindowStyle      = 7   # minimised (defence in depth; VBS already hides)
    $sc.Save()

    Write-WABInfo "Updated shortcut: $folder\$safeName.lnk"
    return [pscustomobject]@{ Path = $lnkPath; Changed = $true }
}

function Remove-WABOrphanShortcuts {
<#
.SYNOPSIS
    Deletes .lnk files under RootDir that aren't in KeepPaths.
.DESCRIPTION
    Also collapses category folders that end up empty after pruning.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]   $RootDir,
        [Parameter(Mandatory)][string[]] $KeepPaths
    )
    if (-not (Test-Path $RootDir)) { return }
    $keep = New-Object System.Collections.Generic.HashSet[string]
    foreach ($p in $KeepPaths) { [void]$keep.Add($p.ToLower()) }

    Get-ChildItem -Path $RootDir -Recurse -Filter *.lnk -File `
            -ErrorAction SilentlyContinue |
        ForEach-Object {
            if (-not $keep.Contains($_.FullName.ToLower())) {
                Write-WABInfo "Removing orphan: $($_.FullName)"
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }

    # Drop now-empty category folders.
    Get-ChildItem -Path $RootDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { -not (Get-ChildItem $_.FullName -File -ErrorAction SilentlyContinue) } |
        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
}

# Wrapped so dot-sourcing (outside a module context) doesn't error.
try {
    Export-ModuleMember -Function New-WABShortcut, Remove-WABOrphanShortcuts
} catch { }
