' WindowsClaudeNotify - Silent VBS wrapper for focus.ps1
' Launches PowerShell hidden (no console window flash) to handle claude-focus: protocol
Set shell = CreateObject("WScript.Shell")
uri = ""
If WScript.Arguments.Count > 0 Then uri = WScript.Arguments(0)
localAppData = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%")
script = localAppData & "\ClaudeNotify\focus.ps1"
shell.Run "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & script & """ -Uri """ & uri & """", 0, False
