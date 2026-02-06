# WindowsClaudeNotify - Main notification hook script
# Called by Claude Code via the Notification hook
# Reads hook JSON from stdin, determines tab index, and shows a toast
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

# --- Determine tab index via process tree ---
$tabIndex = -1
Add-Type @"
using System;
using System.Runtime.InteropServices;
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
}
"@

$wt = Get-Process -Name WindowsTerminal -ErrorAction SilentlyContinue | Select-Object -First 1
if ($wt) {
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
        if ($ourShell) {
            $tabIndex = 0
            foreach ($s in $shells) {
                if ($s.Id -eq $ourShell.Id) { break }
                $tabIndex++
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
