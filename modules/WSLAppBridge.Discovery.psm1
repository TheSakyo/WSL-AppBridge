<#
.SYNOPSIS
    Discovers and parses Linux .desktop files from a WSL distribution.
.DESCRIPTION
    Direct IO via the \\wsl.localhost\<distro>\ UNC bridge (falls back to
    \\wsl$\<distro>\ for older Windows builds). wsl.exe is only invoked
    once, to resolve $HOME -- everything else is plain file IO, which is
    orders of magnitude faster than shelling out per-file.
#>

# (inter-module dependency loaded by the orchestrating script via dot-sourcing)
# ----------------------------- internals -----------------------------------
# freedesktop field codes that must be stripped from Exec.
$script:FieldCodeRegex = '(?<!%)%[fFuUdDnNickvm]'
$script:UncPrefix      = $null   # cached after first call

function Get-WABUncPrefix {
    param([Parameter(Mandatory)][string]$Distro)
    if ($script:UncPrefix) { return $script:UncPrefix }
    foreach ($p in '\\wsl.localhost\','\\wsl$\') {
        if (Test-Path -LiteralPath "$p$Distro\") {
            $script:UncPrefix = $p
            return $p
        }
    }
    # Default to modern form; later Test-Path failures will surface clearly.
    return '\\wsl.localhost\'
}

function Convert-WABWslPathToUnc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$LinuxPath
    )
    $prefix = Get-WABUncPrefix -Distro $Distro
    $rel    = $LinuxPath -replace '/', '\'
    return "$prefix$Distro$rel"
}

function Get-WABWslHome {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Distro)
    # Single wsl.exe invocation, no shell quoting traps.
    $h = (& wsl.exe -d $Distro -- sh -c 'printf "%s" "$HOME"' 2>$null) -join ''
    if (-not $h) { return $null }
    return $h.Trim()
}

function ConvertFrom-WABDesktopFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $lines = Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-WABDebug "Read failure on $Path : $($_.Exception.Message)"
        return $null
    }

    $inEntry = $false
    $kv      = @{}
    foreach ($raw in $lines) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        if ($line.StartsWith('[')) {
            # Only the [Desktop Entry] group is consumed (skip [Desktop Action ...]).
            $inEntry = ($line -eq '[Desktop Entry]')
            continue
        }
        if (-not $inEntry) { continue }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { continue }
        $key = $line.Substring(0, $eq).Trim()
        $val = $line.Substring($eq + 1).Trim()
        # Drop locale variants (Name[fr], Comment[de_DE], etc.) -- use defaults.
        if ($key -match '\[.+\]$') { continue }
        $kv[$key] = $val
    }
    return $kv
}

function Format-WABExec {
    param([string]$Exec)
    if (-not $Exec) { return $null }
    $clean = [regex]::Replace($Exec, $script:FieldCodeRegex, '')
    $clean = ($clean -replace '\s+', ' ').Trim()
    if (-not $clean) { return $null }
    return $clean
}

# ----------------------------- public API ----------------------------------
function Get-WABDesktopApps {
<#
.SYNOPSIS
    Returns the curated list of GUI apps from a WSL distribution.
.OUTPUTS
    PSCustomObject with: Id, Name, Exec, IconRef, Categories,
    StartupWMClass, Comment, DesktopFile, LinuxPath.
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Distro)

    $wslHome = Get-WABWslHome -Distro $Distro
    if (-not $wslHome) {
        Write-WABError "Cannot resolve WSL home for distro '$Distro'. Is the VM running?"
        return @()
    }
    
    # FIX: Sanitize the home path string by stripping embedded null characters
    $wslHome = $wslHome.Replace([char]0, "").Trim()

    # First-match-wins precedence: system → vendor → user.
    $linuxDirs = @(
        '/usr/share/applications',
        '/usr/local/share/applications',
        "$wslHome/.local/share/applications"
    )

    $apps    = New-Object System.Collections.Generic.List[object]
    $seenIds = New-Object System.Collections.Generic.HashSet[string]

    foreach ($lDir in $linuxDirs) {
        $uncDir = Convert-WABWslPathToUnc -Distro $Distro -LinuxPath $lDir
        if (-not (Test-Path -LiteralPath $uncDir)) {
            Write-WABDebug "Skipping (not present): $lDir"
            continue
        }
        Write-WABDebug "Scanning $lDir"
        $files = Get-ChildItem -LiteralPath $uncDir -Filter *.desktop -File `
                    -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            $kv = ConvertFrom-WABDesktopFile -Path $f.FullName
            if (-not $kv) { continue }

            # Per freedesktop spec -- silently skip non-apps and hidden entries.
            if ($kv['Type'] -and $kv['Type'] -ne 'Application') { continue }
            if ($kv['NoDisplay'] -eq 'true') { continue }
            if ($kv['Hidden']    -eq 'true') { continue }
            if ($kv['Terminal']  -eq 'true') { continue }   # explicit requirement

            $name = $kv['Name']; if (-not $name) { continue }
            $exec = Format-WABExec $kv['Exec']
            if (-not $exec) { continue }

            $id = $f.BaseName
            if (-not $seenIds.Add($id)) { continue }   # earlier dir already won

            $cats = @()
            if ($kv['Categories']) {
                $cats = $kv['Categories'].Split(
                    ';', [StringSplitOptions]::RemoveEmptyEntries)
            }

            $apps.Add([pscustomobject]@{
                Id             = $id
                Name           = $name
                Exec           = $exec
                IconRef        = $kv['Icon']
                Categories     = $cats
                StartupWMClass = $kv['StartupWMClass']
                Comment        = $kv['Comment']
                DesktopFile    = $f.FullName
                LinuxPath      = "$lDir/$($f.Name)"
            })
        }
    }
    Write-WABInfo "Discovered $($apps.Count) desktop application(s)."
    return $apps
}

function Get-WABDesktopFilesHash {
<#
.SYNOPSIS
    Cheap MD5 fingerprint of all relevant .desktop files (name+size+mtime).
.DESCRIPTION
    Used to short-circuit a full sync when nothing has changed.
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Distro)

    $wslHome = Get-WABWslHome -Distro $Distro
    if (-not $wslHome) { return $null }
    
    # FIX: Sanitize the home path string by stripping embedded null characters
    $wslHome = $wslHome.Replace([char]0, "").Trim()

    $dirs = @(
        Convert-WABWslPathToUnc -Distro $Distro -LinuxPath '/usr/share/applications'
        Convert-WABWslPathToUnc -Distro $Distro -LinuxPath '/usr/local/share/applications'
        Convert-WABWslPathToUnc -Distro $Distro -LinuxPath "$wslHome/.local/share/applications"
    )
    $sb = [System.Text.StringBuilder]::new()
    foreach ($d in $dirs) {
        # FIX: Ensure paths are purged from trailing C-style null characters before Test-Path
        $dClean = $d.Replace([char]0, "").Trim()
        if (-not (Test-Path -LiteralPath $dClean)) { continue }
        Get-ChildItem -LiteralPath $dClean -Filter *.desktop -File -ErrorAction SilentlyContinue |
            Sort-Object Name | ForEach-Object {
                [void]$sb.Append($_.Name);                  [void]$sb.Append('|')
                [void]$sb.Append($_.Length);                [void]$sb.Append('|')
                [void]$sb.Append($_.LastWriteTimeUtc.Ticks); [void]$sb.Append(';')
            }
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
    $md5   = [System.Security.Cryptography.MD5]::Create()
    return ([BitConverter]::ToString($md5.ComputeHash($bytes)) -replace '-','').ToLower()
}

# Wrapped so dot-sourcing (outside a module context) doesn't error.
try {
    Export-ModuleMember -Function Get-WABDesktopApps, Get-WABDesktopFilesHash,
        Convert-WABWslPathToUnc, Get-WABWslHome, Get-WABUncPrefix
} catch { }