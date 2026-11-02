# IIS Log Cleanup

## Introduction

**IIS Log Cleanup** is a PowerShell-based solution for automatically managing Internet Information Services (IIS) log files on Windows Server.

IIS only controls **log file rollover** (how often a new file is created). It does **not** delete or archive old rolled-over files. Over time these files can consume significant disk space. Microsoft’s official guidance is to use a script plus a scheduled task.

This solution provides a modern PowerShell equivalent of the approach described in the Microsoft documentation:

[Managing IIS Log File Storage](https://learn.microsoft.com/en-us/iis/manage/provisioning-and-managing-iis/managing-iis-log-file-storage)

**Note:** The official Microsoft VBScript, Task Scheduler steps, and related recommendations below are provided **for reference only**. This repository’s PowerShell scripts are an independent implementation.

Features:

- A cleanup script that deletes old IIS `*.log` files based on age
- Age evaluation using the **system local time zone** (prefers the date embedded in the IIS filename)
- Detailed logging to a text file **and** the Windows Application Event Log (including the list of deleted filenames)
- Log rotation and lifecycle management for the cleanup job’s own log file
- An interactive setup script that scans IIS log locations, prompts for settings, and registers a scheduled task

There is **no official GPO Administrative Template** for IIS log retention. The recommended approach is a script + scheduled task (which can itself be deployed via GPO Preferences if desired).

## Official Microsoft VBScript (Reference Only)

**For reference only.** The following is the official VBScript example from Microsoft documentation for deleting old IIS log files. It is shown for comparison and background; the PowerShell scripts in this repository are an independent implementation.

```vbscript
sLogFolder = "c:\inetpub\logs\LogFiles"
iMaxAge = 30   'in days
Set objFSO = CreateObject("Scripting.FileSystemObject")
set colFolder = objFSO.GetFolder(sLogFolder)
For Each colSubfolder in colFolder.SubFolders
        Set objFolder = objFSO.GetFolder(colSubfolder.Path)
        Set colFiles = objFolder.Files
        For Each objFile in colFiles
                iFileAge = now-objFile.DateCreated
                if iFileAge > (iMaxAge+1)  then
                        objFSO.deletefile objFile, True
                end if
        Next
Next
```

**Notes from Microsoft:**
- The script scans all subfolders under the specified log folder, processing logs for all sites.
- Customize the folder path (line 1) and maximum age in days (line 2).
- Run manually with: `cscript.exe c:\scripts\retentionscript.vbs`
- Schedule it with Task Scheduler for ongoing maintenance.

### Official Microsoft Task Scheduler Steps (Reference Only)

**For reference only.** Microsoft documents the following steps to schedule the VBScript. The PowerShell setup script in this repository creates a scheduled task using a different (PowerShell-based) approach:

1. Open **Server Manager**, click **Tools** > **Task Scheduler**.
2. In the **Actions** pane, click **Create Task**.
3. On the **General** tab, name the task (e.g., “Delete Log Files”) and select a user account with sufficient privileges.
4. On the **Triggers** tab, click **New**, set the schedule (e.g., Daily), and ensure it is enabled.
5. On the **Actions** tab, click **New**:
   - Action: **Start a program**
   - Program/script: `cscript`
   - Add arguments: path to the script (e.g., `C:\iis\Log_File_Deletion.vbs`)
6. Click **OK** to save the task.
7. Verify the task appears in Active Tasks, then right-click and select **Run** to test.

The PowerShell solution in this repository follows a similar pattern (script + scheduled task) while adding logging, Event Log integration, local-time-zone awareness, and an interactive setup experience. The Microsoft guidance above remains for reference only.

## IIS Logging Rollover Settings

In IIS Manager, the **Logging** feature controls how often a new log file is created. The **Log File Rollover** section offers:

- **Schedule**: Hourly, Daily, Weekly, or Monthly
- **Maximum file size**
- **Do not create a new log file**

The checkbox **Use local time for file naming and rollover** determines whether the date embedded in the filename (`u_exYYMMDD.log` / `exYYMMDD.log`) uses the server’s local time or UTC. This PowerShell solution interprets that filename date as local system time (with a CreationTime fallback).

![IIS Logging feature page showing Log File Rollover section](iis-logging-rollover.png)

*Screenshot of the IIS Manager Logging feature page (Log File Rollover section).*

## Features

| Feature | Description |
|---------|-------------|
| IIS log cleanup | Deletes `*.log` files older than a configurable number of days |
| Local time zone awareness | Prefers filename date (`u_exYYMMDD.log` / `exYYMMDD.log`) treated as local; falls back to CreationTime |
| File logging | Timestamped detailed log of every action |
| Event Log | Summary written to Application log (source `IISLogCleanup`) including deleted filenames |
| Log lifecycle | Rotates and deletes the cleanup job’s own log files based on retention |
| Interactive setup | Scans IIS sites, shows sizes, prompts for settings, creates scheduled task |
| WhatIf support | Preview mode so nothing is deleted until you confirm |

## Prerequisites

- Windows Server with IIS installed
- PowerShell 5.1 or later
- Administrator privileges (for setup and Event Log source creation)
- IIS Management Tools / WebAdministration module (optional, improves site detection)

## Files in This Repository

| File | Purpose |
|------|---------|
| `IISLogCleanup.ps1` | Main cleanup script (run by the scheduled task) |
| `Setup-IISLogCleanup.ps1` | Interactive setup script (run once as Administrator) |
| `EVENT-LOG.md` | Event Log source, Event IDs, and troubleshooting |
| `README.md` | Quick reference |
| `INTRODUCTION-AND-INSTALLATION.md` | This document |

## Installation Steps

### 1. Download the scripts

Clone the repository or download the files:

```powershell
git clone https://github.com/nwlterry/iis-log-cleanup.git
cd iis-log-cleanup
```

Or copy `IISLogCleanup.ps1` and `Setup-IISLogCleanup.ps1` to a folder on the target server.

### 2. Run the setup script (elevated)

Open PowerShell **as Administrator** and run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force
.\Setup-IISLogCleanup.ps1
```

### 3. Follow the prompts

The setup script will:

1. Scan for IIS log locations (using the WebAdministration module when available, otherwise the default path)
2. Display detected folders and approximate sizes
3. Prompt for settings (press **Enter** to accept defaults):

| Prompt | Default | Description |
|--------|---------|-------------|
| Days to keep IIS logs | 30 | How many days of IIS site logs to retain |
| Cleanup job log location | `C:\Logs` | Folder where the cleanup script writes its own log |
| Cleanup job log retention | 30 | Days to keep the cleanup job’s own log files |

4. Show a configuration summary and ask for confirmation (`Y` to proceed)
5. Copy `IISLogCleanup.ps1` to `C:\Scripts\IISLogCleanup\`
6. Create the Event Log source `IISLogCleanup`
7. Register a scheduled task named **IIS Log Cleanup**

### 4. Verify the scheduled task

```powershell
Get-ScheduledTask -TaskName "IIS Log Cleanup"
```

The task runs daily at 02:00 as `NT AUTHORITY\SYSTEM` with highest privileges.

### 5. Test the cleanup (recommended)

Preview what would be deleted without making changes:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Scripts\IISLogCleanup\IISLogCleanup.ps1" `
    -DaysToKeep 30 -LogFile "C:\Logs\IISLogCleanup.log" -LogRetentionDays 30 -WhatIf
```

Or run the scheduled task immediately:

```powershell
Start-ScheduledTask -TaskName "IIS Log Cleanup"
```

## Configuration Reference

### Cleanup script parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-DaysToKeep` | 30 | Days of IIS logs to retain |
| `-LogPath` | `C:\inetpub\logs\LogFiles` | Root path of IIS logs |
| `-LogFile` | `C:\Logs\IISLogCleanup.log` | Path of the cleanup job’s log file |
| `-LogRetentionDays` | 30 | Days to keep the cleanup job’s own logs |
| `-WhatIf` | — | Preview mode (no deletions) |

### Scheduled task

| Setting | Value |
|---------|-------|
| Name | IIS Log Cleanup |
| Schedule | Daily at 02:00 |
| Account | NT AUTHORITY\SYSTEM |
| Privileges | Highest |
| Action | `powershell.exe` with the cleanup script and configured parameters |

## Logging

### File log
- Location: configured path (default `C:\Logs\IISLogCleanup.log`)
- Contains timestamped entries for every scanned folder, deleted file, and error
- Rotated automatically when older than `LogRetentionDays`; old rotated files are deleted

### Event Log
- Log: Application
- Source: `IISLogCleanup`
- Event IDs:
  - **1000** – Success
  - **1001** – Critical error
  - **1002** – Completed with warnings/errors
- The event message includes the list of deleted filenames (up to 200; remainder summarized)

See `EVENT-LOG.md` for full details and viewing commands.

## Uninstall / Remove the Task

```powershell
Unregister-ScheduledTask -TaskName "IIS Log Cleanup" -Confirm:$false
```

Optionally remove the script folder and log directory:

```powershell
Remove-Item -Path "C:\Scripts\IISLogCleanup" -Recurse -Force
Remove-Item -Path "C:\Logs\IISLogCleanup.log" -Force -ErrorAction SilentlyContinue
```

## Troubleshooting

| Symptom | Possible Cause | Action |
|---------|----------------|--------|
| No Event Log entries | Source not created / not elevated | Run setup again as Administrator |
| Event ID 1001 | IIS log path missing | Verify `C:\inetpub\logs\LogFiles` exists |
| Unexpected files deleted/kept | UTC vs local filename naming | Check “Use local time for file naming and rollover” in IIS Logging settings |
| Task does not run | Execution policy or path | Confirm the task action points to the correct script path |

## Notes

- Always test with `-WhatIf` on production servers before the first real run.
- Consider shipping IIS logs to a central system (ELK, SIEM, etc.) before deleting local copies if longer retention is required.
- The scheduled task can be deployed via GPO Preferences (Computer Configuration → Preferences → Control Panel Settings → Scheduled Tasks) if you prefer centralized deployment.

## License

MIT
