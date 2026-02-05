# WindowsClaudeNotify - Main notification hook script
# Called by Claude Code via the Notification hook
# Reads hook JSON from stdin, focuses the correct WT tab, and shows a toast

param(
    [string]$Title = "Claude Code",
    [string]$Body = ""
)

# Read hook JSON from stdin
$stdinText = ""
try {
    if ([Console]::In.Peek() -ge 0) {
        $stdinText = [Console]::In.ReadToEnd()
    }
} catch {}

$project = ""
if ($stdinText) {
    try {
        $hookData = $stdinText | ConvertFrom-Json
        if ($hookData.cwd) {
            $project = Split-Path $hookData.cwd -Leaf
            $Title = $hookData.cwd
        }
        if ($hookData.message -and -not $Body) {
            $msg = $hookData.message
            if ($msg.Length -gt 200) { $msg = $msg.Substring(0, 197) + "..." }
            $Body = $msg
        }
    } catch {}
}

if (-not $Body) { $Body = "Waiting for your input" }

# --- Focus terminal + switch tab ---
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("ntdll.dll")]
    private static extern int NtQueryInformationProcess(IntPtr hProcess, int pic, ref PBI pbi, int cb, ref int sz);
    [StructLayout(LayoutKind.Sequential)]
    private struct PBI { public IntPtr r1; public IntPtr peb; public IntPtr r2a; public IntPtr r2b; public IntPtr pid; public IntPtr ppid; }
    public static int GetParentPid(int pid) {
        var pbi = new PBI(); int sz = 0;
        var h = System.Diagnostics.Process.GetProcessById(pid).Handle;
        NtQueryInformationProcess(h, 0, ref pbi, Marshal.SizeOf(pbi), ref sz);
        return pbi.ppid.ToInt32();
    }
}
"@

$wt = Get-Process -Name WindowsTerminal -ErrorAction SilentlyContinue | Select-Object -First 1
if ($wt) {
    $h = $wt.MainWindowHandle
    if ([WinAPI]::IsIconic($h)) {
        # SW_RESTORE (9): restores minimized window without un-maximizing
        [WinAPI]::ShowWindow($h, 9)
    }
    [WinAPI]::SetForegroundWindow($h)

    # Switch to correct tab via process tree analysis
    try {
        $wtPid = $wt.Id

        # Find shell processes that are direct children of WT (exclude OpenConsole)
        $shells = Get-Process | Where-Object {
            try {
                [WinAPI]::GetParentPid($_.Id) -eq $wtPid -and $_.ProcessName -ne 'OpenConsole'
            } catch { $false }
        } | Sort-Object StartTime

        # Walk up our parent chain to find which shell is our ancestor
        $ancestors = @()
        $p = $PID
        for ($i = 0; $i -lt 15; $i++) {
            try {
                $ancestors += $p
                $p = [WinAPI]::GetParentPid($p)
                if ($p -eq $wtPid) { break }
            } catch { break }
        }

        $ourShell = $shells | Where-Object { $ancestors -contains $_.Id } | Select-Object -First 1
        $tabIndex = -1
        if ($ourShell) {
            $tabIndex = 0
            foreach ($s in $shells) {
                if ($s.Id -eq $ourShell.Id) { break }
                $tabIndex++
            }
        }

        # Select tab by index via UI Automation
        if ($tabIndex -ge 0) {
            Add-Type -AssemblyName UIAutomationClient
            Add-Type -AssemblyName UIAutomationTypes

            $root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
            $tabCond = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::TabItem
            )
            $uiTabs = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCond)

            if ($tabIndex -lt $uiTabs.Count) {
                $pattern = $uiTabs[$tabIndex].GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
                $pattern.Select()
            }
        }
    } catch {}
}

# --- Show toast notification ---
$Body = $Body -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' -replace "'","&apos;"
$Title = $Title -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' -replace "'","&apos;"

[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null

$iconPath = "$env:LOCALAPPDATA\ClaudeNotify\claude.png"
$xml = [Windows.Data.Xml.Dom.XmlDocument]::new()
$xml.LoadXml("<toast>
  <visual>
    <binding template='ToastGeneric'>
      <image placement='appLogoOverride' src='$iconPath'/>
      <text>$Title</text>
      <text>$Body</text>
    </binding>
  </visual>
  <actions>
    <action content='Open Terminal' activationType='protocol' arguments='claude-focus:$tabIndex'/>
  </actions>
  <audio silent='true'/>
</toast>")

[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe').Show(
    [Windows.UI.Notifications.ToastNotification]::new($xml)
)
