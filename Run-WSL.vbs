' ============================================================================
'  Run-WSL.vbs — Hidden-window launcher for WSL commands.
'  Usage: wscript.exe Run-WSL.vbs "<full wsl command line>"
'
'  Spawns the supplied command with no console window (Run style = 0)
'  and returns immediately (bWaitOnReturn = False). The .lnk files
'  produced by WSLAppBridge.Shortcuts.psm1 target this script so that
'  GUI apps launched from Windows shortcuts never flash a console.
' ============================================================================

If WScript.Arguments.Count < 1 Then
    WScript.Quit 1
End If

CreateObject("WScript.Shell").Run WScript.Arguments(0), 0, False
