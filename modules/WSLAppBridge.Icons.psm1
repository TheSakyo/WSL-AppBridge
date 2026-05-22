<#
.SYNOPSIS
    Resolves Linux icon references and produces Windows-friendly .ico files.
.DESCRIPTION
    Search order is a pragmatic subset of freedesktop.org icon-theme spec:
        1. Absolute paths from the .desktop Icon= field
        2. hicolor theme at preferred sizes
        3. /usr/share/pixmaps
        4. Any other theme under /usr/share/icons, preferring our size list
    PNG → ICO conversion *wraps* the PNG inside a Vista-format ICO
    container -- no Bitmap.GetHicon() resampling loss, full alpha preserved.
    SVG/XPM sources fall back to the default wsl.exe icon (no in-box converter).
#>

# (inter-module dependency loaded by the orchestrating script via dot-sourcing)
# (inter-module dependency loaded by the orchestrating script via dot-sourcing)
# (inter-module dependency loaded by the orchestrating script via dot-sourcing)
# 256 first so we get crisp Start-Menu/taskbar icons on high-DPI displays.
$script:PreferredSizes = @('256x256','128x128','96x96','64x64','48x48','scalable')

function Resolve-WABIconPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Distro,
        [Parameter(Mandatory)][string] $IconRef
    )

    if (-not $IconRef) { return $null }

    # 1. Absolute Linux path → use directly through the UNC bridge.
    if ($IconRef.StartsWith('/')) {
        $unc = Convert-WABWslPathToUnc -Distro $Distro -LinuxPath $IconRef
        if (Test-Path -LiteralPath $unc) { return $unc }
        return $null
    }

    # Strip any extension the .desktop file happened to include.
    $base = [System.IO.Path]::GetFileNameWithoutExtension($IconRef)
    if (-not $base) { return $null }

    $hicolorRoot = Convert-WABWslPathToUnc -Distro $Distro -LinuxPath '/usr/share/icons/hicolor'
    $pixmapsRoot = Convert-WABWslPathToUnc -Distro $Distro -LinuxPath '/usr/share/pixmaps'
    $iconsRoot   = Convert-WABWslPathToUnc -Distro $Distro -LinuxPath '/usr/share/icons'

    # 2. hicolor at our preferred sizes.
    if (Test-Path -LiteralPath $hicolorRoot) {
        foreach ($size in $script:PreferredSizes) {
            foreach ($ext in 'png','svg') {
                $p = Join-Path $hicolorRoot "$size\apps\$base.$ext"
                if (Test-Path -LiteralPath $p) { return $p }
            }
        }
    }

    # 3. /usr/share/pixmaps (legacy flat layout).
    if (Test-Path -LiteralPath $pixmapsRoot) {
        foreach ($ext in 'png','xpm','svg') {
            $p = Join-Path $pixmapsRoot "$base.$ext"
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }

    # 4. Any other theme under /usr/share/icons (size-preferring then any).
    if (Test-Path -LiteralPath $iconsRoot) {
        foreach ($size in $script:PreferredSizes) {
            $hit = Get-ChildItem -LiteralPath $iconsRoot -Recurse `
                       -Filter "$base.png" -ErrorAction SilentlyContinue |
                   Where-Object { $_.FullName -match "\\$size\\" } |
                   Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
        $any = Get-ChildItem -LiteralPath $iconsRoot -Recurse `
                   -Filter "$base.png" -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($any) { return $any.FullName }
    }

    return $null
}

function Convert-WABPngToIco {
<#
.SYNOPSIS
    Wraps a PNG inside a single-image, Vista-format ICO container.
.NOTES
    Vista+ ICO supports raw PNG payload (no BMP DIB needed). Width/height
    are read from the PNG IHDR chunk (big-endian uint32 at offsets 16..23).
    Values ≥256 are encoded as 0 in the ICO directory (per spec).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $PngPath,
        [Parameter(Mandatory)][string] $IcoPath
    )
    $png = [System.IO.File]::ReadAllBytes($PngPath)
    if ($png.Length -lt 24) { throw "PNG too small: $PngPath" }
    # Signature: 89 50 4E 47
    if ($png[0] -ne 0x89 -or $png[1] -ne 0x50 -or
        $png[2] -ne 0x4E -or $png[3] -ne 0x47) {
        throw "Not a PNG: $PngPath"
    }
    $w32 = ([uint32]$png[16] -shl 24) -bor ([uint32]$png[17] -shl 16) -bor `
           ([uint32]$png[18] -shl  8) -bor  [uint32]$png[19]
    $h32 = ([uint32]$png[20] -shl 24) -bor ([uint32]$png[21] -shl 16) -bor `
           ([uint32]$png[22] -shl  8) -bor  [uint32]$png[23]
    $w = if ($w32 -ge 256) { [byte]0 } else { [byte]$w32 }
    $h = if ($h32 -ge 256) { [byte]0 } else { [byte]$h32 }

    $fs = [System.IO.File]::Create($IcoPath)
    try {
        $bw = New-Object System.IO.BinaryWriter($fs)
        # ICONDIR (6 bytes)
        $bw.Write([uint16]0)            # reserved
        $bw.Write([uint16]1)            # type = 1 (icon)
        $bw.Write([uint16]1)            # one image
        # ICONDIRENTRY (16 bytes)
        $bw.Write([byte]$w)
        $bw.Write([byte]$h)
        $bw.Write([byte]0)              # palette colors (0 = >256)
        $bw.Write([byte]0)              # reserved
        $bw.Write([uint16]1)            # planes
        $bw.Write([uint16]32)           # bpp
        $bw.Write([uint32]$png.Length)  # image data size
        $bw.Write([uint32]22)           # offset to image data (6+16)
        # Image data -- raw PNG.
        $bw.Write($png)
        $bw.Flush()
    } finally {
        $fs.Dispose()
    }
}

function Convert-WABViaWsl {
<#
.SYNOPSIS
    Rasterizes an SVG or XPM source into a PNG via in-distro converters.
.DESCRIPTION
    SVG  → rsvg-convert  (librsvg2-bin, lightweight, alpha-preserving)
    XPM  → convert       (ImageMagick, fallback)
    Both write directly to a Windows path resolved through wslpath -u, so
    no temp files leak inside the distro.
.OUTPUTS
    $true on success and a readable PNG at $WinPngDest, $false otherwise.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Distro,
        [Parameter(Mandatory)][string] $LinuxSrcPath,
        [Parameter(Mandatory)][string] $WinPngDest,
        [int] $Size = 256
    )
    $ext = [System.IO.Path]::GetExtension($LinuxSrcPath).ToLower()

    # Translate the Windows destination into a path the WSL converter can write.
    $linuxDest = (& wsl.exe -d $Distro -- wslpath -u "$WinPngDest" 2>$null) -join ''
    if ($LASTEXITCODE -ne 0 -or -not $linuxDest) {
        Write-WABDebug "wslpath -u failed for '$WinPngDest'."
        return $false
    }
    $linuxDest = $linuxDest.Trim()

    # Single shell invocation per format, with a graceful "missing tool" guard.
    switch ($ext) {
        '.svg' {
            $cmd = "command -v rsvg-convert >/dev/null && " +
                   "rsvg-convert -w $Size -h $Size -f png " +
                   "-o '$linuxDest' '$LinuxSrcPath'"
        }
        '.xpm' {
            $cmd = "command -v convert >/dev/null && " +
                   "convert '$LinuxSrcPath' -resize ${Size}x${Size} '$linuxDest'"
        }
        default { return $false }
    }
    & wsl.exe -d $Distro -- sh -c $cmd 2>$null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $WinPngDest)) {
        Write-WABDebug "Conversion failed for $ext (tool missing or runtime error)."
        return $false
    }
    return $true
}

function Get-WABIconForApp {
<#
.SYNOPSIS
    Returns a path to a cached .ico for the given app, building one if needed.
.NOTES
    Idempotent: a previously cached .ico is returned untouched.
    Returns $null when no usable raster icon could be located.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Distro,
        [Parameter(Mandatory)][string] $AppId,
        [string] $IconRef,
        [Parameter(Mandatory)][string] $CacheDir
    )

    if (-not (Test-Path $CacheDir)) {
        New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
    }
    $icoPath = Join-Path $CacheDir "$AppId.ico"
    $pngPath = Join-Path $CacheDir "$AppId.png"

    if (Test-Path -LiteralPath $icoPath) { return $icoPath }

    $src = Resolve-WABIconPath -Distro $Distro -IconRef $IconRef
    if (-not $src) {
        Write-WABDebug "No icon located for '$AppId' (ref='$IconRef')."
        return $null
    }

    $ext = [System.IO.Path]::GetExtension($src).ToLower()
    try {
        switch ($ext) {
            '.png' {
                Copy-Item -LiteralPath $src -Destination $pngPath -Force
                Convert-WABPngToIco -PngPath $pngPath -IcoPath $icoPath
                return $icoPath
            }
            '.ico' {
                Copy-Item -LiteralPath $src -Destination $icoPath -Force
                return $icoPath
            }
            { $_ -in '.svg','.xpm' } {
                # Derive the Linux path from the UNC we resolved and let the
                # in-distro rasterizer produce a PNG we can wrap into ICO.
                $linuxSrc = Convert-WABUncToWslPath -UncPath $src
                if (-not $linuxSrc) {
                    Write-WABDebug "Cannot derive Linux path from '$src'."
                    return $null
                }
                $ok = Convert-WABViaWsl -Distro $Distro `
                          -LinuxSrcPath $linuxSrc -WinPngDest $pngPath
                if (-not $ok) {
                    Write-WABDebug "Skipped $ext icon for '$AppId' -- converter unavailable."
                    return $null
                }
                Convert-WABPngToIco -PngPath $pngPath -IcoPath $icoPath
                return $icoPath
            }
            default {
                Write-WABDebug "Unsupported icon format for '$AppId' ($ext)."
                return $null
            }
        }
    } catch {
        Write-WABWarn "Icon conversion failed for '$AppId': $($_.Exception.Message)"
        return $null
    }
}

# Wrapped so dot-sourcing (outside a module context) doesn't error.
try {
    Export-ModuleMember -Function Resolve-WABIconPath, Convert-WABPngToIco,
        Convert-WABViaWsl, Get-WABIconForApp
} catch { }
