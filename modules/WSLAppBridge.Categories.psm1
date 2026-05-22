<#
.SYNOPSIS
    Maps freedesktop.org `Categories` tokens to top-level shortcut folders.
.NOTES
    First matching token wins (so put more specific tokens up top). Anything
    not matched falls through to "Other".
#>

# Ordered for deterministic resolution.
$script:CategoryMap = [ordered]@{
    # ---- Development ----
    'Development'      = 'Development'
    'IDE'              = 'Development'
    'Building'         = 'Development'
    'Debugger'         = 'Development'
    'RevisionControl'  = 'Development'

    # ---- Graphics ----
    'Graphics'         = 'Graphics'
    'Photography'      = 'Graphics'
    '2DGraphics'       = 'Graphics'
    '3DGraphics'       = 'Graphics'
    'RasterGraphics'   = 'Graphics'
    'VectorGraphics'   = 'Graphics'

    # ---- Multimedia ----
    'AudioVideo'       = 'Multimedia'
    'Audio'            = 'Multimedia'
    'Video'            = 'Multimedia'
    'Player'           = 'Multimedia'
    'Recorder'         = 'Multimedia'

    # ---- Internet ----
    'Network'          = 'Internet'
    'WebBrowser'       = 'Internet'
    'Email'            = 'Internet'
    'InstantMessaging' = 'Internet'
    'P2P'              = 'Internet'

    # ---- Office ----
    'Office'           = 'Office'
    'WordProcessor'    = 'Office'
    'Spreadsheet'      = 'Office'
    'Presentation'     = 'Office'

    # ---- Games ----
    'Game'             = 'Games'

    # ---- Education ----
    'Education'        = 'Education'
    'Science'          = 'Education'

    # ---- System ----
    'System'           = 'System'
    'Settings'         = 'System'
    'Administration'   = 'System'
    'Monitor'          = 'System'
    'TerminalEmulator' = 'System'

    # ---- Utilities (catch-all useful stuff) ----
    'Utility'          = 'Utilities'
    'Accessibility'    = 'Utilities'
    'Core'             = 'Utilities'
    'FileManager'      = 'Utilities'
    'TextEditor'       = 'Utilities'
}

function Get-WABCategoryFolder {
    [CmdletBinding()]
    param([string[]] $Categories)
    if (-not $Categories -or $Categories.Count -eq 0) { return 'Other' }
    foreach ($cat in $Categories) {
        if ($script:CategoryMap.Contains($cat)) { return $script:CategoryMap[$cat] }
    }
    return 'Other'
}

# Wrapped so dot-sourcing (outside a module context) doesn't error.
try {
    Export-ModuleMember -Function Get-WABCategoryFolder
} catch { }
