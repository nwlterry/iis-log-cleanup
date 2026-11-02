#Requires -Version 5.1
<#
.SYNOPSIS
    Deletes old IIS log files based on age, with logging to file and Windows Event Log.

.DESCRIPTION
    PowerShell equivalent of Microsoft's official VBScript for IIS log cleanup.
    Scans the IIS LogFiles directory (and subfolders such as W3SVC*), deletes *.log files
    older than the specified number of days (based on CreationTime to match the original VBScript),
    and records actions to both a log file and the Windows Application Event Log.

.PARAMETER DaysToKeep
    Number of days of logs to retain. Files older than this are deleted. Default: 30

.PARAMETER LogPath
    Root path of IIS logs. Default: C:\inetpub\logs\LogFiles

.PARAMETER LogFile
    Path to the execution log file. Default: C:\Scripts\IISLogCleanup\IISLogCleanup.log

.PARAMETER WhatIf
    Preview mode - show what would be deleted without actually deleting.

.EXAMPLE
    .\IISLogCleanup.ps1 -DaysToKeep 14

.EXAMPLE
    .\IISLogCleanup.ps1 -DaysToKeep 30 -WhatIf

.NOTES
    Based on Microsoft documentation: Managing IIS Log File Storage
    https://learn.microsoft.com/en-us/iis/manage/provisioning-and-managing-iis/managing-iis-log-file-storage
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3650)]
    [int]$DaysToKeep = 30,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\inetpub\logs\LogFiles",

    [Parameter(Mandatory = $false)]
    [string]$LogFile = "C:\Scripts\IISLogCleanup\IISLogCleanup.log"
)

# Ensure log directory exists
$logDir = Split-Path -Path $LogFile -Parent
if (-not (Test-Path -Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

# Event Log source
$eventSource = "IISLogCleanup"
$eventLogName = "Application"

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logEntry -Encoding UTF8
    Write-Host $logEntry
}

function Ensure-EventSource {
    if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
        try {
            New-EventLog -LogName $eventLogName -Source $eventSource -ErrorAction Stop
            Write-Log "Created Event Log source: $eventSource" "INFO"
        }
        catch {
            Write-Log "Failed to create Event Log source (may need elevated rights): $_" "WARN"
        }
    }
}

function Write-EventLogEntry {
    param(
        [string]$Message,
        [int]$EventId = 1000,
        [string]$EntryType = "Information"
    )
    try {
        Write-EventLog -LogName $eventLogName -Source $eventSource -EventId $EventId -EntryType $EntryType -Message $Message -ErrorAction Stop
    }
    catch {
        Write-Log "Failed to write to Event Log: $_" "WARN"
    }
}

# Start
Write-Log "=== IIS Log Cleanup started ===" "INFO"
Write-Log "Parameters: DaysToKeep=$DaysToKeep, LogPath=$LogPath, LogFile=$LogFile, WhatIf=$($PSBoundParameters.ContainsKey('WhatIf'))" "INFO"

Ensure-EventSource

if (-not (Test-Path -Path $LogPath)) {
    $msg = "Log path does not exist: $LogPath"
    Write-Log $msg "ERROR"
    Write-EventLogEntry -Message $msg -EventId 1001 -EntryType "Error"
    exit 1
}

$cutoffDate = (Get-Date).AddDays(-$DaysToKeep)
Write-Log "Cutoff date (files older than this will be deleted): $cutoffDate" "INFO"

$deletedCount = 0
$deletedSize = 0
$errorCount = 0
$scannedFolders = 0

# Get all subfolders (W3SVC*, etc.) and the root if needed
$foldersToScan = @()
try {
    $foldersToScan = Get-ChildItem -Path $LogPath -Directory -ErrorAction Stop
    if ($foldersToScan.Count -eq 0) {
        # Also check root for any direct log files
        $foldersToScan = @(Get-Item -Path $LogPath)
    }
}
catch {
    $msg = "Failed to enumerate log folders: $_"
    Write-Log $msg "ERROR"
    Write-EventLogEntry -Message $msg -EventId 1001 -EntryType "Error"
    exit 1
}

foreach ($folder in $foldersToScan) {
    $scannedFolders++
    $folderPath = $folder.FullName
    Write-Log "Scanning folder: $folderPath" "INFO"

    try {
        $logFiles = Get-ChildItem -Path $folderPath -Filter "*.log" -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.CreationTime -lt $cutoffDate }

        foreach ($file in $logFiles) {
            $fileSize = $file.Length
            $actionMsg = "Deleting: $($file.FullName) (Created: $($file.CreationTime), Size: $([math]::Round($fileSize/1MB, 2)) MB)"

            if ($PSCmdlet.ShouldProcess($file.FullName, "Delete")) {
                try {
                    Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                    $deletedCount++
                    $deletedSize += $fileSize
                    Write-Log $actionMsg "INFO"
                }
                catch {
                    $errorCount++
                    $errMsg = "Failed to delete $($file.FullName): $_"
                    Write-Log $errMsg "ERROR"
                }
            }
            else {
                Write-Log "[WHATIF] $actionMsg" "INFO"
                $deletedCount++
                $deletedSize += $fileSize
            }
        }
    }
    catch {
        $errorCount++
        Write-Log "Error scanning $folderPath : $_" "ERROR"
    }
}

# Summary
$summary = @"
IIS Log Cleanup completed.
Folders scanned: $scannedFolders
Files deleted: $deletedCount
Space freed: $([math]::Round($deletedSize/1MB, 2)) MB
Errors: $errorCount
DaysToKeep: $DaysToKeep
LogPath: $LogPath
"@

Write-Log $summary "INFO"
Write-Log "=== IIS Log Cleanup finished ===" "INFO"

$eventId = if ($errorCount -gt 0) { 1002 } else { 1000 }
$entryType = if ($errorCount -gt 0) { "Warning" } else { "Information" }
Write-EventLogEntry -Message $summary -EventId $eventId -EntryType $entryType

exit $(if ($errorCount -gt 0) { 1 } else { 0 })
