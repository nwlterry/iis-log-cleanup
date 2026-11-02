#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Interactive setup script for IIS Log Cleanup scheduled task.

.DESCRIPTION
    Scans IIS log locations, displays them, prompts for retention days,
    confirms with the user, then creates a scheduled task that runs IISLogCleanup.ps1 daily.

.NOTES
    Run this script elevated (as Administrator).
    It will place scripts under C:\Scripts\IISLogCleanup\ and register a task named "IIS Log Cleanup".
#>

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$targetDir = "C:\Scripts\IISLogCleanup"
$cleanupScript = Join-Path $targetDir "IISLogCleanup.ps1"
$taskName = "IIS Log Cleanup"

function Write-Header {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  IIS Log Cleanup - Setup" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Get-IISLogLocations {
    $locations = @()

    # Try WebAdministration module (IIS 7+)
    try {
        if (Get-Module -ListAvailable -Name WebAdministration) {
            Import-Module WebAdministration -ErrorAction SilentlyContinue
            $sites = Get-Website -ErrorAction SilentlyContinue
            foreach ($site in $sites) {
                $logDir = $site.logFile.directory
                if ($logDir) {
                    $expanded = [System.Environment]::ExpandEnvironmentVariables($logDir)
                    $siteLogPath = Join-Path $expanded "W3SVC$($site.id)"
                    if (Test-Path $siteLogPath) {
                        $locations += [PSCustomObject]@{
                            SiteName = $site.Name
                            SiteId   = $site.id
                            Path     = $siteLogPath
                            Exists   = $true
                        }
                    }
                }
            }
        }
    }
    catch {
        # Ignore - fall back to default
    }

    # Always include the default path
    $defaultPath = "C:\inetpub\logs\LogFiles"
    if (Test-Path $defaultPath) {
        $subFolders = Get-ChildItem -Path $defaultPath -Directory -ErrorAction SilentlyContinue
        foreach ($sf in $subFolders) {
            if ($locations.Path -notcontains $sf.FullName) {
                $locations += [PSCustomObject]@{
                    SiteName = "(default / unknown)"
                    SiteId   = $sf.Name
                    Path     = $sf.FullName
                    Exists   = $true
                }
            }
        }
        if ($locations.Count -eq 0) {
            $locations += [PSCustomObject]@{
                SiteName = "(default)"
                SiteId   = "LogFiles"
                Path     = $defaultPath
                Exists   = $true
            }
        }
    }

    return $locations
}

Write-Header

Write-Host "Scanning for IIS log locations..." -ForegroundColor Yellow
$logLocations = Get-IISLogLocations

if ($logLocations.Count -eq 0) {
    Write-Host "No IIS log folders found. Default path will be used: C:\inetpub\logs\LogFiles" -ForegroundColor Yellow
    $logLocations = @([PSCustomObject]@{ SiteName = "Default"; SiteId = ""; Path = "C:\inetpub\logs\LogFiles"; Exists = (Test-Path "C:\inetpub\logs\LogFiles") })
}

Write-Host ""
Write-Host "Detected IIS Log Locations:" -ForegroundColor Green
$logLocations | Format-Table -AutoSize SiteName, SiteId, Path, Exists

# Calculate approximate size
Write-Host "Calculating approximate log sizes..." -ForegroundColor Yellow
foreach ($loc in $logLocations) {
    if ($loc.Exists) {
        try {
            $size = (Get-ChildItem -Path $loc.Path -Recurse -Filter "*.log" -File -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum).Sum
            $loc | Add-Member -NotePropertyName "ApproxSizeMB" -NotePropertyValue ([math]::Round($size / 1MB, 2)) -Force
        }
        catch {
            $loc | Add-Member -NotePropertyName "ApproxSizeMB" -NotePropertyValue "N/A" -Force
        }
    }
}

Write-Host ""
$logLocations | Format-Table -AutoSize SiteName, Path, ApproxSizeMB

# Configuration
Write-Host ""
$daysInput = Read-Host "Enter number of days to keep logs (default 30)"
$daysToKeep = if ([string]::IsNullOrWhiteSpace($daysInput)) { 30 } else { [int]$daysInput }

if ($daysToKeep -lt 1 -or $daysToKeep -gt 3650) {
    Write-Host "Invalid value. Using 30 days." -ForegroundColor Yellow
    $daysToKeep = 30
}

Write-Host ""
Write-Host "Configuration Summary:" -ForegroundColor Cyan
Write-Host "  Days to keep : $daysToKeep"
Write-Host "  Script path  : $cleanupScript"
Write-Host "  Task name    : $taskName"
Write-Host "  Schedule     : Daily at 02:00"
Write-Host "  Run as       : NT AUTHORITY\SYSTEM (highest privileges)"
Write-Host ""

$confirm = Read-Host "Proceed with setup? (Y/N)"
if ($confirm -notmatch '^[Yy]') {
    Write-Host "Setup cancelled by user." -ForegroundColor Yellow
    exit 0
}

# Create target directory and copy script
Write-Host ""
Write-Host "Creating directory and copying script..." -ForegroundColor Yellow
if (-not (Test-Path $targetDir)) {
    New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
}

$sourceScript = Join-Path $scriptDir "IISLogCleanup.ps1"
if (Test-Path $sourceScript) {
    Copy-Item -Path $sourceScript -Destination $cleanupScript -Force
    Write-Host "Copied IISLogCleanup.ps1 to $targetDir" -ForegroundColor Green
}
else {
    Write-Host "Warning: IISLogCleanup.ps1 not found next to this setup script. Please place it manually in $targetDir" -ForegroundColor Yellow
}

# Create Event Log source (best effort)
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists("IISLogCleanup")) {
        New-EventLog -LogName Application -Source "IISLogCleanup"
        Write-Host "Created Event Log source: IISLogCleanup" -ForegroundColor Green
    }
}
catch {
    Write-Host "Could not create Event Log source (task will still work): $_" -ForegroundColor Yellow
}

# Create scheduled task
Write-Host "Registering scheduled task..." -ForegroundColor Yellow

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$cleanupScript`" -DaysToKeep $daysToKeep"

$trigger = New-ScheduledTaskTrigger -Daily -At "02:00"

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1)

# Remove existing task if present
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Deletes IIS log files older than $daysToKeep days. Logs to file and Event Log." | Out-Null

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Setup completed successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Task Name : $taskName"
Write-Host "Schedule  : Daily at 02:00"
Write-Host "Days kept : $daysToKeep"
Write-Host "Script    : $cleanupScript"
Write-Host "Log file  : $targetDir\IISLogCleanup.log"
Write-Host ""
Write-Host "You can test it immediately with:" -ForegroundColor Cyan
Write-Host "  Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor White
Write-Host ""
Write-Host "Or run the cleanup script manually with -WhatIf first:" -ForegroundColor Cyan
Write-Host "  powershell.exe -ExecutionPolicy Bypass -File `"$cleanupScript`" -DaysToKeep $daysToKeep -WhatIf" -ForegroundColor White
Write-Host ""
