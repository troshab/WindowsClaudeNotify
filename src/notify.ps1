# WindowsClaudeNotify - Main notification hook script
# Called by Claude Code via the Notification hook
# Reads hook JSON from stdin, determines the correct WT window + tab, and shows a toast
# Tab focusing happens only when the user clicks "Open Terminal" in the toast

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

# --- Determine target window handle and tab index ---
$targetHwnd = 0
$targetTabIndex = -1

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class WinAPI {
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

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int nMaxCount);

    public static List<IntPtr> GetWtWindows(int pid) {
        var list = new List<IntPtr>();
        EnumWindows((hWnd, lParam) => {
            if (!IsWindowVisible(hWnd)) return true;
            uint wpid;
            GetWindowThreadProcessId(hWnd, out wpid);
            if ((int)wpid != pid) return true;
            var sb = new StringBuilder(256);
            GetClassName(hWnd, sb, 256);
            if (sb.ToString() == "CASCADIA_HOSTING_WINDOW_CLASS") {
                list.Add(hWnd);
            }
            return true;
        }, IntPtr.Zero);
        return list;
    }
}
"@

# Walk up parent chain to find the WindowsTerminal ancestor
$wtPid = 0
$wtProcesses = @{}
Get-Process -Name WindowsTerminal -ErrorAction SilentlyContinue | ForEach-Object { $wtProcesses[$_.Id] = $_ }

$p = $PID
for ($i = 0; $i -lt 15; $i++) {
    try {
        $p = [WinAPI]::GetParentPid($p)
        if ($wtProcesses.ContainsKey($p)) {
            $wtPid = $p
            break
        }
    } catch { break }
}

# Find the correct window by searching tab names for project match
if ($wtPid -gt 0 -and $project) {
    try {
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes

        $wtWindows = [WinAPI]::GetWtWindows($wtPid)
        $tabCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::TabItem
        )

        foreach ($hwnd in $wtWindows) {
            $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
            $tabs = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCond)
            for ($i = 0; $i -lt $tabs.Count; $i++) {
                if ($tabs[$i].Current.Name -like "*$project*") {
                    $targetHwnd = $hwnd.ToInt64()
                    $targetTabIndex = $i
                    break
                }
            }
            if ($targetTabIndex -ge 0) { break }
        }
    } catch {}
}

# Fallback: use first window, determine tab by process tree
if ($targetHwnd -eq 0 -and $wtPid -gt 0) {
    try {
        $wt = $wtProcesses[$wtPid]
        if ($wt -and $wt.MainWindowHandle) {
            $targetHwnd = $wt.MainWindowHandle.ToInt64()
        }

        # Process tree fallback for tab index
        $shells = Get-Process | Where-Object {
            try {
                [WinAPI]::GetParentPid($_.Id) -eq $wtPid -and $_.ProcessName -ne 'OpenConsole'
            } catch { $false }
        } | Sort-Object StartTime

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
        if ($ourShell) {
            $targetTabIndex = 0
            foreach ($s in $shells) {
                if ($s.Id -eq $ourShell.Id) { break }
                $targetTabIndex++
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
    <action content='Open Terminal' activationType='protocol' arguments='claude-focus:$targetHwnd`:$targetTabIndex'/>
  </actions>
  <audio silent='true'/>
</toast>")

[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe').Show(
    [Windows.UI.Notifications.ToastNotification]::new($xml)
)
