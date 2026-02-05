# WindowsClaudeNotify - Installer
# Run: powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = "Stop"

$installDir = "$env:LOCALAPPDATA\ClaudeNotify"
$repoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$settingsFile = "$env:USERPROFILE\.claude\settings.json"

Write-Host "WindowsClaudeNotify Installer" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Host ""

# 1. Create install directory
Write-Host "[1/4] Creating $installDir ..." -ForegroundColor Yellow
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

# 2. Copy files
Write-Host "[2/4] Copying files ..." -ForegroundColor Yellow
Copy-Item "$repoDir\src\notify.ps1" "$installDir\notify.ps1" -Force
Copy-Item "$repoDir\src\focus.ps1" "$installDir\focus.ps1" -Force
Copy-Item "$repoDir\src\focus.vbs" "$installDir\focus.vbs" -Force
Copy-Item "$repoDir\assets\claude.png" "$installDir\claude.png" -Force
Write-Host "  Copied: notify.ps1, focus.ps1, focus.vbs, claude.png"

# 3. Register claude-focus: protocol
Write-Host "[3/4] Registering claude-focus: protocol ..." -ForegroundColor Yellow
$protocolKey = "HKCU:\Software\Classes\claude-focus"
New-Item -Path $protocolKey -Force | Out-Null
Set-ItemProperty -Path $protocolKey -Name "(Default)" -Value "Claude Focus Protocol"
Set-ItemProperty -Path $protocolKey -Name "URL Protocol" -Value ""
$commandKey = "$protocolKey\shell\open\command"
New-Item -Path $commandKey -Force | Out-Null
$vbsPath = "$installDir\focus.vbs"
Set-ItemProperty -Path $commandKey -Name "(Default)" -Value "wscript.exe `"$vbsPath`" `"%1`""
Write-Host "  Registered: claude-focus: -> focus.vbs -> focus.ps1"

# 4. Add hook to Claude Code settings
Write-Host "[4/4] Configuring Claude Code hook ..." -ForegroundColor Yellow
$hookCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%LOCALAPPDATA%\\ClaudeNotify\\notify.ps1`""

$claudeDir = "$env:USERPROFILE\.claude"
if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
}

if (Test-Path $settingsFile) {
    $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
} else {
    $settings = [PSCustomObject]@{}
}

# Ensure hooks.Notification exists and contains our hook
$needsUpdate = $true
if ($settings.PSObject.Properties["hooks"]) {
    if ($settings.hooks.PSObject.Properties["Notification"]) {
        $existing = $settings.hooks.Notification
        foreach ($entry in $existing) {
            foreach ($h in $entry.hooks) {
                if ($h.command -like "*ClaudeNotify*notify.ps1*") {
                    $needsUpdate = $false
                    break
                }
            }
            if (-not $needsUpdate) { break }
        }
    }
}

if ($needsUpdate) {
    if (-not $settings.PSObject.Properties["hooks"]) {
        $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue ([PSCustomObject]@{})
    }
    $notifHook = @(
        [PSCustomObject]@{
            matcher = ""
            hooks = @(
                [PSCustomObject]@{
                    type = "command"
                    command = $hookCommand
                }
            )
        }
    )
    if ($settings.hooks.PSObject.Properties["Notification"]) {
        # Append to existing Notification hooks
        $current = @($settings.hooks.Notification)
        $current += $notifHook[0]
        $settings.hooks.Notification = $current
    } else {
        $settings.hooks | Add-Member -NotePropertyName "Notification" -NotePropertyValue $notifHook
    }
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
    Write-Host "  Added Notification hook to settings.json"
} else {
    Write-Host "  Hook already configured, skipping"
}

Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Test it:" -ForegroundColor Cyan
Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File `"$installDir\notify.ps1`" -Body `"Test notification`""
Write-Host ""
Write-Host "The notification will appear the next time Claude Code needs your attention."
