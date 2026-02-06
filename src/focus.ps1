# WindowsClaudeNotify - Focus helper script
# Called via claude-focus: protocol when clicking the toast "Open Terminal" button
# Focuses the correct Windows Terminal window and switches to the correct tab
# URI format: claude-focus:{wtPid}:{tabIndex}

param(
    [string]$Uri = "",
    [int]$TabIndex = -1,
    [int]$WtPid = 0
)

# Parse WT PID and tab index from protocol URI (claude-focus:PID:TAB)
if ($Uri -match 'claude-focus:(\d+):(\d+)') {
    $WtPid = [int]$Matches[1]
    $TabIndex = [int]$Matches[2]
} elseif ($Uri -match 'claude-focus:(\d+)') {
    # Fallback: old format with tab index only
    $TabIndex = [int]$Matches[1]
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinFocus {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
}
"@

# Find the correct WT window: by PID if available, otherwise first one
$wt = $null
if ($WtPid -gt 0) {
    $wt = Get-Process -Id $WtPid -ErrorAction SilentlyContinue
}
if (-not $wt) {
    $wt = Get-Process -Name WindowsTerminal -ErrorAction SilentlyContinue | Select-Object -First 1
}
if (-not $wt) { exit }

$h = $wt.MainWindowHandle

if ([WinFocus]::IsIconic($h)) {
    # SW_RESTORE (9): restores minimized window without un-maximizing
    [WinFocus]::ShowWindow($h, 9)
}
[WinFocus]::SetForegroundWindow($h)

if ($TabIndex -ge 0) {
    try {
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes

        $root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
        $tabCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::TabItem
        )
        $tabs = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCond)

        if ($TabIndex -lt $tabs.Count) {
            $pattern = $tabs[$TabIndex].GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
            $pattern.Select()
        }
    } catch {}
}
