param(
    [string]$SaveDirectory = "",
    [string]$WslDistro = "auto",
    [int]$PollingIntervalMs = 500,
    [int]$MaxErrorCount = 10,
    [int]$WslStartupTimeoutSeconds = 300
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"
$script:lastHash = ""
$script:errorCount = 0

function Wait-ForWslReady {
    param([int]$TimeoutSeconds)

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $attempt = 0
    $startAttempted = $false

    Write-Host "Checking WSL status..."

    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $attempt++
        try {
            $result = wsl.exe --status 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "WSL is ready after $attempt attempts ($([int]$stopwatch.Elapsed.TotalSeconds)s)"
                return $true
            }
        } catch {}

        if (-not $startAttempted -and $attempt -ge 3) {
            Write-Host "WSL not running, starting it..."
            Start-Process -FilePath "wsl.exe" -ArgumentList "-e", "true" -WindowStyle Hidden
            $startAttempted = $true
        }

        if ($attempt % 10 -eq 0) {
            Write-Host "Still waiting for WSL... (attempt $attempt, $([int]$stopwatch.Elapsed.TotalSeconds)s elapsed)"
        }
        Start-Sleep -Seconds 2
    }

    Write-Host "Timeout waiting for WSL after $TimeoutSeconds seconds"
    return $false
}

function Get-SafeWslUsername {
    param([string]$Distro)

    $username = (wsl.exe -d $Distro -e whoami 2>$null)
    if (-not $username) {
        return $null
    }

    $username = $username.Trim() -replace '\x00', ''

    if ($username -notmatch '^[a-z_][a-z0-9_-]{0,31}$') {
        Write-Error "Invalid WSL username format: $username"
        return $null
    }

    return $username
}

function Get-SafeWslDistro {
    if ($WslDistro -ne "auto") {
        if ($WslDistro -notmatch '^[a-zA-Z0-9_.-]+$') {
            Write-Error "Invalid WSL distro name"
            return $null
        }
        return $WslDistro
    }

    $distros = @(wsl.exe -l -q 2>$null | Where-Object {
        $_ -and $_.Trim() -ne "" -and $_ -notlike "*docker*"
    } | ForEach-Object {
        $_.Trim() -replace '\s+', '' -replace '\x00', ''
    })

    if ($distros.Count -eq 0) {
        Write-Error "No WSL distribution found"
        return $null
    }

    return $distros[0]
}

function Get-ImageHash {
    param([System.Drawing.Image]$Image)

    $ms = $null
    try {
        $ms = New-Object System.IO.MemoryStream
        $Image.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $bytes = $ms.ToArray()
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', ''
        return $hash
    } finally {
        if ($ms) { $ms.Dispose() }
    }
}

function Save-ClipboardImage {
    param(
        [string]$Directory,
        [string]$Distro,
        [string]$Username
    )

    $image = $null
    $ms = $null

    try {
        if (-not [System.Windows.Forms.Clipboard]::ContainsImage()) {
            return $null
        }

        $image = [System.Windows.Forms.Clipboard]::GetImage()
        if (-not $image) {
            return $null
        }

        $hash = Get-ImageHash -Image $image
        if ($hash -eq $script:lastHash) {
            return $null
        }
        $script:lastHash = $hash

        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $filename = "screenshot_$timestamp.png"
        $filepath = Join-Path $Directory $filename

        $image.Save($filepath, [System.Drawing.Imaging.ImageFormat]::Png)

        $wslPath = "/home/$Username/.screenshots/$filename"
        $wslPath | Set-Clipboard

        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Saved: $filename"
        Write-Host "  Path copied to clipboard: $wslPath"

        return $filepath

    } finally {
        if ($ms) { $ms.Dispose() }
        if ($image) { $image.Dispose() }
    }
}

if (-not (Wait-ForWslReady -TimeoutSeconds $WslStartupTimeoutSeconds)) {
    Write-Error "WSL did not become ready within $WslStartupTimeoutSeconds seconds"
    exit 1
}

$distro = Get-SafeWslDistro
if (-not $distro) {
    Write-Error "Failed to detect WSL distribution"
    exit 1
}
Write-Host "WSL Distribution: $distro"

$username = Get-SafeWslUsername -Distro $distro
if (-not $username) {
    Write-Error "Failed to get WSL username"
    exit 1
}
Write-Host "WSL Username: $username"

if (-not $SaveDirectory) {
    $SaveDirectory = "\\wsl.localhost\$distro\home\$username\.screenshots"
}

if (-not (Test-Path $SaveDirectory)) {
    New-Item -ItemType Directory -Path $SaveDirectory -Force | Out-Null
}
Write-Host "Save directory: $SaveDirectory"
Write-Host "Monitoring clipboard... (Ctrl+C to stop)"
Write-Host ""

while ($true) {
    try {
        Start-Sleep -Milliseconds $PollingIntervalMs
        Save-ClipboardImage -Directory $SaveDirectory -Distro $distro -Username $username | Out-Null
        $script:errorCount = 0

    } catch {
        $script:errorCount++
        Write-Warning "Error: $_"

        if ($script:errorCount -ge $MaxErrorCount) {
            Write-Warning "Too many errors. Checking if WSL is still running..."

            if (-not (Test-Path $SaveDirectory)) {
                Write-Host "WSL directory not accessible. Restarting WSL..."
                Start-Process -FilePath "wsl.exe" -ArgumentList "-e", "true" -WindowStyle Hidden
                Start-Sleep -Seconds 10

                if (Test-Path $SaveDirectory) {
                    Write-Host "WSL recovered. Resuming monitoring."
                    $script:errorCount = 0
                } else {
                    Write-Host "WSL still not ready. Waiting..."
                    Start-Sleep -Seconds 30
                    $script:errorCount = 0
                }
            } else {
                $script:errorCount = 0
            }
        }

        Start-Sleep -Milliseconds 1000
    }
}
