# WSL Screenshot Tool

Paste screenshots directly into Claude Code (or other terminals) running on WSL.

## Why?

Claude Code on WSL cannot access images from the Windows clipboard directly. When you take a screenshot and try to paste with `Ctrl+V`, nothing happens.

This tool fixes it:
1. Monitors the Windows clipboard
2. When it detects an image, saves it to `~/.screenshots/` in WSL
3. Copies the file path to the clipboard
4. Now when you paste, Claude Code can read the image

## Installation

### Prerequisites
- Windows 10/11 with WSL2
- PowerShell 5.1+

### Steps

1. Clone the repo somewhere in Windows (not in WSL):
```powershell
cd C:\Users\YourUsername
git clone https://github.com/CairoAC/wsl-screenshot-tool.git
```

2. Create the screenshots directory in WSL:
```bash
mkdir -p ~/.screenshots
```

3. Set up autostart (run in PowerShell as your normal user):
```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\YourUsername\wsl-screenshot-tool\setup-autostart.ps1"
```

## Usage

1. Take a screenshot with `PrintScreen`
2. Paste in Claude Code with `Ctrl+V`

The monitor starts automatically on Windows login.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\YourUsername\wsl-screenshot-tool\remove-autostart.ps1"
```

## Files

- `screenshot-monitor.ps1` - Background clipboard monitor
- `setup-autostart.ps1` - Configures Task Scheduler for autostart
- `remove-autostart.ps1` - Removes autostart

## How it works

The PowerShell script:
1. Auto-detects the WSL distribution
2. Monitors the clipboard every 500ms
3. When it detects a new image, saves to `\\wsl.localhost\<distro>\home\<user>\.screenshots\`
4. Copies the WSL path (`/home/<user>/.screenshots/screenshot_<timestamp>.png`) to clipboard
5. Claude Code can now read the image from that path
