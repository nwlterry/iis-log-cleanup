# IIS Log Cleanup - Event Log Reference

This document describes the Windows Event Log entries written by the IIS Log Cleanup scripts.

## Event Log Source

| Property | Value |
|----------|-------|
| **Log Name** | Application |
| **Source** | `IISLogCleanup` |
| **Created by** | `IISLogCleanup.ps1` (on first run) or `Setup-IISLogCleanup.ps1` |

The Event Log source is created automatically when the cleanup script runs (or during setup). Creating the source requires elevated privileges. If the source cannot be created, the script continues and writes a warning to the file log.

## Event IDs

| Event ID | Level | Description |
|----------|-------|-------------|
| **1000** | Information | Cleanup completed successfully |
| **1001** | Error | Critical failure (log path not found, or failed to enumerate folders) |
| **1002** | Warning | Cleanup completed but one or more errors occurred during deletion |

## Event Message Format

### Success (Event ID 1000) / Warning (Event ID 1002)
```
IIS Log Cleanup completed.
System time zone: <display name>
Folders scanned: <number>
Files deleted: <number>
Space freed: <number> MB
Errors: <number>
DaysToKeep: <number>
LogPath: <path>
Age method: Filename date (local) used=<n>, CreationTime fallback used=<n>

Deleted files:
<file1.log>, <file2.log>, ... (up to 200 names; remainder summarized)
```

### Error (Event ID 1001)
A short error message describing the failure, for example:
- `Log path does not exist: C:\inetpub\logs\LogFiles`
- `Failed to enumerate log folders: ...`

## Age Determination (System Time Zone)

The script evaluates log age using the **system local time zone**:

1. **Filename date (preferred)** – Parses `u_exYYMMDD.log` or `exYYMMDD.log` and treats the date as a local date.
2. **CreationTime (fallback)** – Used when the filename does not contain a recognizable IIS date.

The cutoff is calculated as local midnight of `(today - DaysToKeep)`.

## File Log Location

In addition to the Event Log, every run writes a detailed log to:

```
C:\Scripts\IISLogCleanup\IISLogCleanup.log
```

The file log contains timestamped entries for every scanned folder, deleted file (with method used), and error.

## Viewing the Events

### Event Viewer
1. Open **Event Viewer** (`eventvwr.msc`)
2. Navigate to **Windows Logs → Application**
3. Filter by Source = `IISLogCleanup`

### PowerShell
```powershell
# Last 10 events
Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='IISLogCleanup'} -MaxEvents 10 |
    Format-Table TimeCreated, Id, LevelDisplayName, Message -Wrap

# Only errors and warnings
Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='IISLogCleanup'; Level=2,3} -MaxEvents 20
```

### wevtutil
```cmd
wevtutil qe Application /q:"*[System[Provider[@Name='IISLogCleanup']]]" /c:10 /f:text
```

## Troubleshooting

| Symptom | Possible Cause | Action |
|---------|----------------|--------|
| No events appear | Source not created / insufficient rights | Run the script once as Administrator, or run `Setup-IISLogCleanup.ps1` |
| Event ID 1001 | Log path missing or inaccessible | Verify `C:\inetpub\logs\LogFiles` (or custom path) exists and is readable |
| Event ID 1002 | Some files locked or access denied | Check the file log for specific file errors; ensure the task runs as SYSTEM |
| Source creation fails | Not elevated | The script logs a warning and continues; events will be written once the source exists |
| Unexpected files deleted/kept | IIS using UTC naming while script assumes local | Check "Use local time for file naming and rollover" in IIS Logging settings, or review the Age method counts in the event |

## Notes

- Events are written at the end of each run (summary + deleted file list) and on critical failures.
- Up to 200 deleted filenames are included in the Event Log message; additional files are summarized as "... and N more".
- Individual deletions are also recorded in the file log with the age-determination method used.
- The scheduled task runs as `NT AUTHORITY\SYSTEM`, which has sufficient rights to write to the Application log once the source exists.
- Event Log message size is capped at ~30 KB to stay within Windows limits.
