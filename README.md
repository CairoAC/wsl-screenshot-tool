# WSL Screenshot Tool

Paste screenshots directly into CLI tools (like Claude Code) running on WSL2.

## The Problem

When using CLI tools on WSL that accept image paths (like Claude Code), you can't paste images directly from the Windows clipboard. The clipboard contains image data, but WSL applications expect a file path.

This tool bridges that gap by:
1. Monitoring the Windows clipboard for images
2. Automatically saving them to a WSL-accessible directory
3. Copying the WSL file path to the clipboard
4. Now you can paste the path directly into your terminal

## Requirements

- Windows 10/11 with WSL2
- PowerShell 5.1+
- A WSL distribution (Ubuntu, Debian, etc.)

## Installation

### 1. Clone the repository (on Windows, not inside WSL)

```powershell
cd C:\Users\YourUsername
git clone https://github.com/CairoAC/wsl-screenshot-tool.git
```

### 2. Create the screenshots directory in WSL

```bash
mkdir -p ~/.screenshots
```

### 3. Set up autostart

Run PowerShell **as Administrator** and execute:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\YourUsername\wsl-screenshot-tool\setup-autostart.ps1"
```

## Usage

1. Take a screenshot with `Win+Shift+S` (or `PrintScreen`)
2. The tool automatically detects the image in your clipboard
3. Saves it to `~/.screenshots/` in your WSL home directory
4. Copies the WSL path to your clipboard
5. Paste the path (`Ctrl+V`) in your terminal

**Example flow:**
```
[Take screenshot] → [Tool saves to ~/.screenshots/screenshot_2024-01-15_14-30-45.png]
                  → [Clipboard now contains: /home/user/.screenshots/screenshot_2024-01-15_14-30-45.png]
                  → [Paste in terminal]
```

## How It Works

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         WINDOWS                                 │
│  ┌──────────────┐    ┌─────────────────┐    ┌───────────────┐  │
│  │ Task         │───>│ run-hidden.vbs  │───>│ PowerShell    │  │
│  │ Scheduler    │    │ (hides window)  │    │ (main script) │  │
│  └──────────────┘    └─────────────────┘    └───────┬───────┘  │
│                                                      │          │
│                              ┌───────────────────────┘          │
│                              │ Polls clipboard every 500ms      │
│                              ▼                                  │
│                      ┌───────────────┐                          │
│                      │   Clipboard   │                          │
│                      │ (image data)  │                          │
│                      └───────┬───────┘                          │
│                              │                                  │
└──────────────────────────────┼──────────────────────────────────┘
                               │ Save via \\wsl.localhost\...
┌──────────────────────────────┼──────────────────────────────────┐
│                         WSL2 │                                  │
│                              ▼                                  │
│                      ┌───────────────┐                          │
│                      │ ~/.screenshots│                          │
│                      │  (PNG files)  │                          │
│                      └───────────────┘                          │
└─────────────────────────────────────────────────────────────────┘
```

### File Descriptions

#### `screenshot-monitor.ps1` - Main monitoring script

The core PowerShell script that:

1. **Waits for WSL to be ready** (`Wait-ForWslReady`)
   - Polls `wsl.exe --status` every 2 seconds
   - If WSL isn't running after 3 attempts, starts it automatically
   - Times out after 5 minutes (configurable)

2. **Auto-detects WSL configuration** (`Get-SafeWslDistro`, `Get-SafeWslUsername`)
   - Finds the first non-Docker WSL distribution
   - Gets the username via `wsl.exe -e whoami`
   - Validates inputs to prevent path injection

3. **Monitors the clipboard** (main loop)
   - Checks for images every 500ms (configurable)
   - Uses SHA256 hash to detect duplicate images (won't save the same image twice)
   - Saves images as PNG with timestamp: `screenshot_YYYY-MM-DD_HH-mm-ss.png`

4. **Auto-recovers from WSL shutdown**
   - If WSL shuts down due to inactivity, the script detects this
   - Automatically restarts WSL and resumes monitoring
   - Never exits unless manually stopped

**Parameters:**
| Parameter | Default | Description |
|-----------|---------|-------------|
| `SaveDirectory` | Auto | Custom save path (default: `~/.screenshots`) |
| `WslDistro` | `auto` | WSL distribution name (auto-detected) |
| `PollingIntervalMs` | `500` | How often to check clipboard (ms) |
| `MaxErrorCount` | `10` | Errors before attempting WSL restart |
| `WslStartupTimeoutSeconds` | `300` | Max wait time for WSL startup |

#### `setup-autostart.ps1` - Task Scheduler configuration

Creates a Windows Scheduled Task with:

- **Triggers:**
  - At user logon (30 second delay)
  - At system startup (30 second delay)

- **Settings:**
  - Runs on battery power
  - Doesn't stop when going on batteries
  - No execution time limit (runs indefinitely)
  - Auto-restart on failure (3 retries, 1 minute interval)
  - Doesn't stop on idle
  - Ignores new instances if already running

- **Principal:**
  - Runs as current user
  - Interactive logon (required for clipboard access)
  - Limited privileges (no admin required)

#### `run-hidden.vbs` - Window hider

A VBScript wrapper that launches PowerShell completely hidden. This is necessary because:

- PowerShell's `-WindowStyle Hidden` flag still shows a brief window flash
- Task Scheduler cannot truly hide console windows
- VBScript's `WScript.Shell.Run` with windowstyle `0` provides true invisibility

#### `remove-autostart.ps1` - Uninstaller

Removes the scheduled task cleanly:
- Stops the running task
- Unregisters from Task Scheduler

## Troubleshooting

### Script not running after restart

Check if the task exists and its state:
```powershell
Get-ScheduledTask -TaskName "WSL-Screenshot-Monitor" | Select-Object TaskName, State
```

Manually start it:
```powershell
Start-ScheduledTask -TaskName "WSL-Screenshot-Monitor"
```

### Screenshots not being saved

1. Check if the process is running:
```powershell
Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -like '*screenshot-monitor*' }
```

2. Run manually to see errors:
```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\YourUsername\wsl-screenshot-tool\screenshot-monitor.ps1"
```

3. Verify WSL is accessible:
```powershell
wsl.exe --status
```

### Clipboard not being detected

The script requires an **interactive session**. If running via Task Scheduler with "Run whether user is logged on or not", clipboard access will fail. The setup script configures this correctly, but if you modified the task, ensure:
- LogonType is set to `Interactive`
- Task runs as your user account

### WSL keeps shutting down

Windows automatically shuts down WSL after a period of inactivity. The script handles this by:
1. Detecting when the save directory becomes inaccessible
2. Automatically restarting WSL
3. Resuming monitoring

If this happens frequently, you can prevent WSL auto-shutdown by keeping a background process running in WSL, or by modifying `.wslconfig`:

```ini
# %UserProfile%\.wslconfig
[wsl2]
vmIdleTimeout=-1
```

## Uninstallation

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\YourUsername\wsl-screenshot-tool\remove-autostart.ps1"
```

Then delete the cloned repository and optionally `~/.screenshots` in WSL.

## Security Considerations

- The script validates all WSL usernames and distribution names against strict regex patterns to prevent path injection
- No network access required - everything runs locally
- Runs with limited (non-admin) privileges
- Screenshots are saved with user-only permissions

## License

MIT
