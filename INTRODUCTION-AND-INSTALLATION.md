# IIS Log Cleanup

## Introduction

**IIS Log Cleanup** is a PowerShell-based solution for automatically managing Internet Information Services (IIS) log files on Windows Server.

IIS only controls **log file rollover** (how often a new file is created). It does **not** delete or archive old rolled-over files. Over time these files can consume significant disk space. Microsoft’s official guidance is to use a script plus a scheduled task.

This solution provides a modern PowerShell equivalent of the approach described in the official Microsoft documentation.

**Official Microsoft references (for reference only):**
- [Managing IIS Log File Storage](https://learn.microsoft.com/en-us/iis/manage/provisioning-and-managing-iis/managing-iis-log-file-storage)
- [Configure Logging in IIS](https://learn.microsoft.com/en-us/iis/manage/provisioning-and-managing-iis/configure-logging-in-iis)

**Note:** Microsoft’s official guidance, example script, and recommendations are provided **for reference only**. The PowerShell scripts in this repository are an independent implementation.

Features:

- A cleanup script that deletes old IIS `*.log` files based on age
- Age evaluation using the **system local time zone** (prefers the date embedded in the IIS filename)
- Detailed logging to a text file **and** the Windows Application Event Log (including the list of deleted filenames)
- Log rotation and lifecycle management for the cleanup job’s own log file
- An interactive setup script that scans IIS log locations, prompts for settings, and registers a scheduled task

There is **no official GPO Administrative Template** for IIS log retention. The recommended approach is a script + scheduled task (which can itself be deployed via GPO Preferences if desired).

## Microsoft Official Guidance (Reference Only)

Microsoft’s official documentation recommends using a script together with a scheduled task to control disk usage of IIS logs. Their example is a short VBScript that deletes files older than a specified age based on DateCreated.

**Official links (for reference only):**
- [Managing IIS Log File Storage](https://learn.microsoft.com/en-us/iis/manage/provisioning-and-managing-iis/managing-iis-log-file-storage)
- [Configure Logging in IIS](https://learn.microsoft.com/en-us/iis/manage/provisioning-and-managing-iis/configure-logging-in-iis)

That guidance is provided **for reference only**. The PowerShell scripts in this repository are an independent implementation that follows the same general pattern (script + scheduled task) while adding logging, Event Log integration, local-time-zone awareness, and an interactive setup experience.

## Configuring IIS Log File Rollover

IIS controls how often a new log file is created through the **Logging** feature. Proper rollover settings help keep individual log files manageable and make age-based cleanup reliable.

### Steps to configure rollover in IIS Manager

1. Open **Internet Information Services (IIS) Manager**.
2. In the **Connections** pane, select the server name (for server-level defaults) or a specific site.
3. Double-click **Logging** in the Features View.
4. Under **Log File**, confirm the format (typically **W3C**) and the directory (default: `%SystemDrive%\inetpub\logs\LogFiles`).
5. In the **Log File Rollover** section, choose one of the following:
   - **Schedule** — create a new file on a fixed interval:
     - **Hourly**
     - **Daily** (most common)
     - **Weekly**
     - **Monthly**
   - **Maximum file size (in bytes)** — create a new file when the current one reaches the specified size (minimum 1,048,576 bytes).
   - **Do not create a new log file** — a single continuously growing file (not recommended for long-term retention).
6. Select the checkbox **Use local time for file naming and rollover** if you want the date embedded in the filename (`u_exYYMMDD.log` / `exYYMMDD.log`) and the rollover boundary to use the server’s local time instead of UTC.
   - When unchecked, filename dates and rollover use UTC.
   - Note: timestamps *inside* W3C/NCSA log records remain UTC regardless of this setting.
7. Click **Apply** in the Actions pane.

This PowerShell solution prefers the date embedded in the IIS filename and treats it as a date in the **system local time zone** (with a CreationTime fallback). Aligning the “Use local time for file naming and rollover” setting with your preference makes age-based cleanup more predictable.

![Full IIS Manager Logging feature page](iis-logging-rollover.png)

*Full IIS Manager Logging feature page. Shows Log File settings (Format, Directory, Encoding) and the complete Log File Rollover section, including Schedule (Daily), Maximum file size, Do not create a new log file, and the “Use local time for file naming and rollover” checkbox.*

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
