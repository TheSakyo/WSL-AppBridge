<#
.SYNOPSIS
    Structured logging for WSL-AppBridge.
.DESCRIPTION
    Levelled, timestamped output to console (coloured) and optionally to a
    UTF-8 log file. Every other module consumes this -- never Write-Host
    directly -- so log routing stays in one place.
#>

# ----------------------------- module state --------------------------------
$script:LogFile  = $null
$script:LogLevel = 'Info'
$script:Levels   = @{ Debug = 0; Info = 1; Warn = 2; Error = 3 }

# ----------------------------- public API ----------------------------------
function Initialize-WABLogger {
    [CmdletBinding()]
    param(
        [string] $Path,
        [ValidateSet('Debug','Info','Warn','Error')]
        [string] $Level = 'Info'
    )
    $script:LogFile  = $Path
    $script:LogLevel = $Level
    if ($Path) {
        $dir = Split-Path $Path -Parent
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
    }
}

function Write-WABLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Debug','Info','Warn','Error')]
        [string] $Level,
        [Parameter(Mandatory)][string] $Message
    )
    if ($script:Levels[$Level] -lt $script:Levels[$script:LogLevel]) { return }
    $ts    = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line  = "[$ts] [$Level] $Message"
    $color = switch ($Level) {
        'Debug' { 'DarkGray' }
        'Info'  { 'Gray' }
        'Warn'  { 'Yellow' }
        'Error' { 'Red' }
    }
    Write-Host $line -ForegroundColor $color
    if ($script:LogFile) {
        try { Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 } catch {}
    }
}

# Thin convenience wrappers -- keep call sites short.
function Write-WABInfo  { param([string]$m) Write-WABLog -Level Info  -Message $m }
function Write-WABWarn  { param([string]$m) Write-WABLog -Level Warn  -Message $m }
function Write-WABError { param([string]$m) Write-WABLog -Level Error -Message $m }
function Write-WABDebug { param([string]$m) Write-WABLog -Level Debug -Message $m }

# Wrapped so dot-sourcing (outside a module context) doesn't error.
try {
    Export-ModuleMember -Function Initialize-WABLogger, Write-WABLog,
        Write-WABInfo, Write-WABWarn, Write-WABError, Write-WABDebug
} catch { }
