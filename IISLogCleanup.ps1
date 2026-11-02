#Requires -Version 5.1
<#
.SYNOPSIS
    Deletes old IIS log files based on age (using system local time zone), with logging to file and Windows Event Log.

.DESCRIPTION
    PowerShell equivalent of Microsoft's official VBScript for IIS log cleanup.
    Scans the IIS LogFiles directory (and subfolders such as W3SVC*), deletes *.log files
    older than the specified number of days.
    
    Age determination prefers the date embedded in the IIS filename (u_exYYMMDD.log / exYYMMDD.log)
    and treats it as a date in the **system local time zone**. Falls back to file CreationTime
    (also local) when the filename does not contain a parseable date.
    
    Records detailed actions to a log file and writes a summary (including all deleted filenames)
    to the Windows Application Event Log.

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

    IIS filename dates are interpreted in the system local time zone.
    Ensure "Use local time for file naming and rollover" in IIS matches your expectation,
    or rely on the fallback CreationTime logic.
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
        # Event Log message limit is roughly 32 KB; truncate if necessary
        if ($Message.Length -gt 30000) {
            $Message = $Message.Substring(0, 29900) + "`n`n... (message truncated due to Event Log size limit)"
        }
        Write-EventLog -LogName $eventLogName -Source $eventSource -EventId $EventId -EntryType $EntryType -Message $Message -ErrorAction Stop
    }
    catch {
        Write-Log "Failed to write to Event Log: $_" "WARN"
    }
}

function Get-IISLogDateFromName {
    param([string]$FileName)
    # Matches u_exYYMMDD.log or exYYMMDD.log (IIS W3C default naming)
    if ($FileName -match '(?:u_)?ex(\d{6})\.log$') {
        $yy = $Matches[1].Substring(0, 2)
        $mm = $Matches[1].Substring(2, 2)
        $dd = $Matches[1].Substring(4, 2)
        try {
            $year = 2000 + [int]$yy
            # Return as local date (midnight) in system time zone
            return [datetime]::new($year, [int]$mm, [int]$dd, 0, 0, 0, [DateTimeKind]::Local)
        }
        catch {
            return $null
        }
    }
    return $null
}

# Start
$tz = [System.TimeZoneInfo]::Local
Write-Log "=== IIS Log Cleanup started ===" "INFO"
Write-Log "System time zone: $($tz.DisplayName) (Id: $($tz.Id))" "INFO"
Write-Log "Parameters: DaysToKeep=$DaysToKeep, LogPath=$LogPath, LogFile=$LogFile, WhatIf=$($PSBoundParameters.ContainsKey('WhatIf'))" "INFO"

Ensure-EventSource

if (-not (Test-Path -Path $LogPath)) {
    $msg = "Log path does not exist: $LogPath"
    Write-Log $msg "ERROR"
    Write-EventLogEntry -Message $msg -EventId 1001 -EntryType "Error"
    exit 1
}

$cutoffDate = (Get-Date).AddDays(-$DaysToKeep).Date   # local midnight cutoff
Write-Log "Cutoff date (local): $cutoffDate (files with date older than this will be deleted)" "INFO"

$deletedCount = 0
$deletedSize = 0
$errorCount = 0
$scannedFolders = 0
$deletedFiles = New-Object System.Collections.Generic.List[string]
$filenameDateUsed = 0
$creationTimeUsed = 0

# Get all subfolders (W3SVC*, etc.) and the root if needed
$foldersToScan = @()
try {
    $foldersToScan = Get-ChildItem -Path $LogPath -Directory -ErrorAction Stop
    if ($foldersToScan.Count -eq 0) {
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
        $logFiles = Get-ChildItem -Path $folderPath -Filter "*.log" -File -ErrorAction SilentlyContinue

        foreach ($file in $logFiles) {
            $fileDate = Get-IISLogDateFromName -FileName $file.Name
            $ageMethod = "CreationTime"
            $effectiveDate = $file.CreationTime.Date

            if ($null -ne $fileDate) {
                $effectiveDate = $fileDate
                $ageMethod = "FilenameDate (local)"
                $filenameDateUsed++
            }
            else {
                $creationTimeUsed++
            }

            if ($effectiveDate -lt $cutoffDate) {
                $fileSize = $file.Length
                $actionMsg = "Deleting: $($file.FullName) | Date=$effectiveDate | Method=$ageMethod | Size=$([math]::Round($fileSize/1MB, 2)) MB"

                if ($PSCmdlet.ShouldProcess($file.FullName, "Delete")) {
                    try {
                        Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                        $deletedCount++
                        $deletedSize += $fileSize
                        $deletedFiles.Add($file.Name)
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
                    $deletedFiles.Add($file.Name)
                }
            }
        }
    }
    catch {
        $errorCount++
        Write-Log "Error scanning $folderPath : $_" "ERROR"
    }
}

# Build deleted files list for Event Log (limit to avoid huge messages)
$maxFilesInEvent = 200
$deletedListText = if ($deletedFiles.Count -eq 0) {
    "(none)"
}
elseif ($deletedFiles.Count -le $maxFilesInEvent) {
    ($deletedFiles -join ", ")
}
else {
    ($deletedFiles[0..($maxFilesInEvent-1)] -join ", ") + ", ... and $($deletedFiles.Count - $maxFilesInEvent) more"
}

# Summary
$summary = @"
IIS Log Cleanup completed.
System time zone: $($tz.DisplayName)
Folders scanned: $scannedFolders
Files deleted: $deletedCount
Space freed: $([math]::Round($deletedSize/1MB, 2)) MB
Errors: $errorCount
DaysToKeep: $DaysToKeep
LogPath: $LogPath
Age method: Filename date (local) used=$filenameDateUsed, CreationTime fallback used=$creationTimeUsed

Deleted files:
$deletedListText
"@

Write-Log $summary "INFO"
Write-Log "=== IIS Log Cleanup finished ===" "INFO"

$eventId = if ($errorCount -gt 0) { 1002 } else { 1000 }
$entryType = if ($errorCount -gt 0) { "Warning" } else { "Information" }
Write-EventLogEntry -Message $summary -EventId $eventId -EntryType $entryType

exit $(if ($errorCount -gt 0) { 1 } else { 0 })
