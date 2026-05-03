Set objShell = CreateObject("WScript.Shell")
objShell.Run """<PWSH_PATH>"" -ExecutionPolicy Bypass -WindowStyle Hidden -File ""<SCRIPT_PATH>""", 0, False

' ============================================================
' CONFIGURATION
' ============================================================
' Replace the placeholders above with your actual paths:
'
' <PWSH_PATH>   — Full path to pwsh.exe
'                  Example: C:\Program Files\PowerShell\7\pwsh.exe
'
' <SCRIPT_PATH> — Full path to Sync-CloudDrives.ps1
'                  Example: C:\Users\YourName\Local Automation Scripts\Sync-CloudDrives.ps1
'
' This VBS wrapper launches PowerShell completely hidden (no window flash).
' Point your Task Scheduler action to: wscript.exe
' With arguments: "C:\path\to\RunSync.vbs"
