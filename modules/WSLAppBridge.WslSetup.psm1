<#
.SYNOPSIS
    Linux-side setup helpers for WSL-AppBridge.
.DESCRIPTION
    Deploys the launch.sh wrapper inside the distro (via the UNC bridge to
    avoid quoting hell) and probes for optional dependencies (rsvg-convert,
    ImageMagick, dbus-run-session). No sudo is attempted -- apt requires
    interactive auth, so we just report what's missing with a copy-pastable
    install line for the user.
#>

# (inter-module dependency loaded by the orchestrating script via dot-sourcing)
# (inter-module dependency loaded by the orchestrating script via dot-sourcing)
# Location inside the distro (relative to $HOME). Kept in one place so other
# modules can derive the same path without duplicating the constant.
$script:WrapperRel = '.wsl-appbridge/launch.sh'

function Get-WABWrapperLinuxPath {
<#
.SYNOPSIS
    Returns the absolute Linux path to the wrapper inside the given distro.
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Distro)
    $h = Get-WABWslHome -Distro $Distro
    if (-not $h) { return $null }
    return "$h/$script:WrapperRel"
}

function Install-WABWslWrapper {
<#
.SYNOPSIS
    Copies launch.sh into the distro and makes it executable.
.NOTES
    Writes via the UNC bridge with LF line endings and no BOM -- bash chokes
    on CRLF in the shebang. Then chmod +x via a single wsl.exe call.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Distro,
        [Parameter(Mandatory)][string] $LocalWrapperSource
    )
    if (-not (Test-Path -LiteralPath $LocalWrapperSource)) {
        throw "Wrapper source missing: $LocalWrapperSource"
    }

    $linuxHome = Get-WABWslHome -Distro $Distro
    if (-not $linuxHome) {
        throw "Cannot resolve `$HOME for distro '$Distro' -- is the distro running?"
    }

    # Translate $HOME (Linux) → \\wsl.localhost\<distro>\home\<user>\ (Windows).
    $uncHome = Convert-WABWslPathToUnc -Distro $Distro -LinuxPath $linuxHome
    $dirUnc  = Join-Path $uncHome   '.wsl-appbridge'
    $fileUnc = Join-Path $dirUnc    'launch.sh'

    if (-not (Test-Path -LiteralPath $dirUnc)) {
        New-Item -ItemType Directory -Path $dirUnc -Force | Out-Null
    }

    # Read source, force LF line endings, write UTF-8 without BOM.
    $content = [System.IO.File]::ReadAllText($LocalWrapperSource) -replace "`r`n", "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($fileUnc, $content, $utf8NoBom)

    # Make executable. The chmod runs inside the distro so the +x bit sticks.
    & wsl.exe -d $Distro -- chmod +x "$linuxHome/$script:WrapperRel" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "chmod +x failed for wrapper in distro '$Distro' (exit $LASTEXITCODE)."
    }
    Write-WABInfo "Wrapper installed: $linuxHome/$script:WrapperRel"
}

function Test-WABWslDependencies {
<#
.SYNOPSIS
    Probes the distro for optional dependencies and logs a single apt one-liner
    covering everything that's missing.
.OUTPUTS
    [string[]] List of missing apt package names (empty when all present).
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Distro)

    # Map: command to probe → apt package providing it.
    $checks = [ordered]@{
        'rsvg-convert'     = 'librsvg2-bin'        # SVG icon rasterizer
        'convert'          = 'imagemagick'         # XPM rasterizer + fallback
        'dbus-run-session' = 'dbus-user-session'   # per-launch DBus session
    }
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($cmd in $checks.Keys) {
        & wsl.exe -d $Distro -- sh -c "command -v $cmd >/dev/null 2>&1"
        if ($LASTEXITCODE -ne 0) { [void]$missing.Add($checks[$cmd]) }
    }

    if ($missing.Count -gt 0) {
        $pkgs = ($missing | Select-Object -Unique) -join ' '
        Write-WABWarn "Optional WSL dependencies missing. For full features run:"
        Write-WABWarn "  wsl -d $Distro -- sudo apt-get update"
        Write-WABWarn "  wsl -d $Distro -- sudo apt-get install -y $pkgs"
    } else {
        Write-WABInfo "All optional WSL dependencies present."
    }
    return $missing.ToArray()
}

function Convert-WABUncToWslPath {
<#
.SYNOPSIS
    Reverse of Convert-WABWslPathToUnc -- extracts the Linux path from a UNC
    path under \\wsl.localhost\<distro>\ or \\wsl$\<distro>\.
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $UncPath)
    if ($UncPath -match '^\\\\(?:wsl\$|wsl\.localhost)\\[^\\]+\\(.*)$') {
        return '/' + ($Matches[1] -replace '\\', '/')
    }
    return $null
}

# Wrapped so dot-sourcing (outside a module context) doesn't error.
try {
    Export-ModuleMember -Function Get-WABWrapperLinuxPath, Install-WABWslWrapper,
        Test-WABWslDependencies, Convert-WABUncToWslPath
} catch { }
