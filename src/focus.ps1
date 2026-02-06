# WindowsClaudeNotify - Focus helper script
# Called via claude-focus: protocol when clicking the toast "Open Terminal" button
# Focuses the correct Windows Terminal window and switches to the correct tab
# URI format: claude-focus:{hwnd}:{tabIndex}

param(
    [string]$Uri = "",
    [int]$TabIndex = -1,
    [long]$Hwnd = 0
)

# Parse window handle and tab index from protocol URI
if ($Uri -match 'claude-focus:(\d+):(\d+)') {
    $Hwnd = [long]$Matches[1]
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
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
}
"@

$h = [IntPtr]$Hwnd

# If HWND is invalid or missing, fall back to first WT window
if ($Hwnd -eq 0 -or -not [WinFocus]::IsWindow($h)) {
    $wt = Get-Process -Name WindowsTerminal -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $wt) { exit }
    $h = $wt.MainWindowHandle
}

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
