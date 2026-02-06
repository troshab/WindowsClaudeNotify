# WindowsClaudeNotify

> Windows toast notifications for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with **smart tab switching** in Windows Terminal.

When Claude Code needs your attention, you get a toast notification. Click **"Open Terminal"** to jump straight to the correct window and tab - even with multiple terminals and sessions open.

![Toast notification](assets/screenshot.png)

## Why this one?

Other notification tools ([claude-code-notify-powershell](https://github.com/nicholasgasior/claude-code-notify-powershell), [cctoast-wsl](https://github.com/aaddrick/cctoast-wsl), [code-notify](https://github.com/nicholasgasior/code-notify)) show a toast and that's it. None of them solve the real problem:

**Which tab do I switch to when I have 5 terminals open?**

This project finds the exact window and tab using:
- `EnumWindows` + UI Automation to locate the tab by project name across all WT windows
- `NtQueryInformationProcess` to walk the process tree as a fallback
- A custom `claude-focus:` URI protocol that encodes the window handle (HWND) + tab index

## Features

- **Correct window & tab** - finds the right WT window even when multiple windows are open (WT runs as a single process, so PID alone won't work)
- **Non-intrusive** - shows a toast without stealing focus; you switch when ready
- **Real messages** - displays the actual notification text (permission prompts, task status, etc.)
- **No window resize** - restores minimized windows with `SW_RESTORE` (doesn't un-maximize)
- **No console flash** - VBS wrapper launches PowerShell hidden

## Requirements

- Windows 10/11
- Windows Terminal
- PowerShell 5.1+ (ships with Windows)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

## Install

```powershell
git clone https://github.com/troshab/WindowsClaudeNotify.git
cd WindowsClaudeNotify
powershell -ExecutionPolicy Bypass -File install.ps1
```

The installer copies files to `%LOCALAPPDATA%\ClaudeNotify\`, registers the `claude-focus:` protocol, and adds the hook to `~/.claude/settings.json`.

<details>
<summary><b>Manual install</b></summary>

1. Create `%LOCALAPPDATA%\ClaudeNotify\`
2. Copy files:
   ```
   src/notify.ps1  ->  %LOCALAPPDATA%\ClaudeNotify\notify.ps1
   src/focus.ps1   ->  %LOCALAPPDATA%\ClaudeNotify\focus.ps1
   src/focus.vbs   ->  %LOCALAPPDATA%\ClaudeNotify\focus.vbs
   assets/claude.png -> %LOCALAPPDATA%\ClaudeNotify\claude.png
   ```
3. Register the protocol:
   ```powershell
   $key = "HKCU:\Software\Classes\claude-focus"
   New-Item -Path "$key\shell\open\command" -Force | Out-Null
   Set-ItemProperty -Path $key -Name "(Default)" -Value "Claude Focus Protocol"
   Set-ItemProperty -Path $key -Name "URL Protocol" -Value ""
   $vbs = "$env:LOCALAPPDATA\ClaudeNotify\focus.vbs"
   Set-ItemProperty -Path "$key\shell\open\command" -Name "(Default)" -Value "wscript.exe `"$vbs`" `"%1`""
   ```
4. Add the hook to `~/.claude/settings.json`:
   ```json
   {
     "hooks": {
       "Notification": [
         {
           "matcher": "",
           "hooks": [
             {
               "type": "command",
               "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%LOCALAPPDATA%\\ClaudeNotify\\notify.ps1\""
             }
           ]
         }
       ]
     }
   }
   ```
</details>

## How it works

```
Claude Code fires Notification hook
         |
         v
    notify.ps1
         |
         |  1. Reads hook JSON from stdin (cwd, message)
         |  2. Walks process tree up to find WindowsTerminal PID
         |  3. EnumWindows -> finds all WT windows (CASCADIA_HOSTING_WINDOW_CLASS)
         |  4. UI Automation -> searches tab names for project folder match
         |  5. Shows toast with HWND + tab index encoded in button URL
         |
         v
    Toast: "Open Terminal"  -->  claude-focus:{hwnd}:{tabIndex}
         |
         v
    focus.vbs  (silent launcher, no console window)
         |
         v
    focus.ps1
         |  1. Parses HWND + tab index from URI
         |  2. ShowWindow(SW_RESTORE) if minimized
         |  3. SetForegroundWindow(hwnd)
         |  4. UI Automation: SelectionItemPattern.Select() on TabItem
```

### The multi-window problem

Windows Terminal uses a **single-process model** - all windows share one `WindowsTerminal.exe`. So `Get-Process -Name WindowsTerminal` returns the same PID regardless of which window you need. You can't just focus by PID.

**How we solve it:**

| Step | What | How |
|------|-------|-----|
| Find WT PID | Walk up parent chain from hook process | `NtQueryInformationProcess` |
| Find correct window | Enumerate all WT windows, search tabs by name | `EnumWindows` + UI Automation |
| Encode target | Pack window handle + tab index into URI | `claude-focus:{hwnd}:{tabIndex}` |
| Focus on click | Restore & focus the exact window, select tab | `SetForegroundWindow` + `SelectionItemPattern.Select()` |

**Fallback:** if no tab name matches the project, falls back to `MainWindowHandle` + process tree tab index.

## Configuration

The `matcher` field in the hook filters which notifications trigger a toast. Empty string = all notifications.

```json
{ "matcher": "" }
{ "matcher": "permission" }
{ "matcher": "permission|input|error" }
```

To use a custom icon, replace `%LOCALAPPDATA%\ClaudeNotify\claude.png`.

## Uninstall

```powershell
# Remove hook from settings.json (edit manually)
# Delete files
Remove-Item -Path "$env:LOCALAPPDATA\ClaudeNotify" -Recurse -Force
# Remove protocol
Remove-Item -Path "HKCU:\Software\Classes\claude-focus" -Recurse -Force
```

## License

[MIT](LICENSE)
