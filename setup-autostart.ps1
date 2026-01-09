$scriptPath = $PSScriptRoot
$vbsScript = Join-Path $scriptPath "run-hidden.vbs"

if (-not (Test-Path $vbsScript)) {
    Write-Error "run-hidden.vbs not found in $scriptPath"
    exit 1
}

$taskName = "WSL-Screenshot-Monitor"
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($existingTask) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Removed existing task"
}

$action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$vbsScript`""
$triggerLogon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$triggerLogon.Delay = "PT30S"
$triggerStartup = New-ScheduledTaskTrigger -AtStartup
$triggerStartup.Delay = "PT30S"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -DontStopOnIdleEnd -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($triggerLogon, $triggerStartup) -Settings $settings -Principal $principal -Description "Monitors clipboard for screenshots and saves to WSL" | Out-Null

Start-ScheduledTask -TaskName $taskName

Write-Host ""
Write-Host "Setup complete!"
Write-Host ""
Write-Host "The monitor will now:"
Write-Host "  - Start automatically when you log in"
Write-Host "  - Run silently in background"
Write-Host "  - Save screenshots to ~/.screenshots"
Write-Host "  - Copy the path to clipboard automatically"
Write-Host ""
Write-Host "Just take a screenshot (Win+Shift+S) and paste the path!"
