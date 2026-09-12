Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
ps = dir & "\dsh-tray.ps1"
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & ps & """"
CreateObject("WScript.Shell").Run cmd, 0, False
