' DeepSeek Harness — Desktop Launcher Wrapper
' Launches launcher.ps1 (in the same directory as this VBS) with hidden PowerShell.
' Fully portable: derives all paths relative to its own location.

Dim fso, scriptDir, ps1Path, cmd

Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1Path   = scriptDir & "\launcher.ps1"

' Build PowerShell command with properly escaped quotes
cmd = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & ps1Path & """"

' 0 = hidden window, False = don't wait for completion
CreateObject("WScript.Shell").Run cmd, 0, False