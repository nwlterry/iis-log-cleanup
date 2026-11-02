# IIS Log Cleanup

PowerShell scripts to automatically delete old IIS rotated log files, with logging to both a text file and the Windows Event Log.

This is a modern PowerShell equivalent of the official Microsoft VBScript published in the documentation:

[Managing IIS Log File Storage](https://learn.microsoft.com/en-us/iis/manage/provisioning-and-managing-iis/managing-iis-log-file-storage)

## Features

- Deletes `*.log` files older than a configurable number of days (based on CreationTime)
- Scans all subfolders under the IIS LogFiles directory (W3SVC*, etc.)
- Detailed logging to a text file
- Summary written to Windows Application Event Log (source: `IISLogCleanup`)
- Supports `-WhatIf` for safe preview
- Interactive setup script that:
  - Scans and displays detected IIS log locations and sizes
  - Prompts for retention days
  - Waits for user confirmation
  - Creates a daily scheduled task running as SYSTEM

## Files

| File | Description |
|------|-------------|
| `IISLogCleanup.ps1` | Main cleanup script (run by the scheduled task) |
| `Setup-IISLogCleanup.ps1` | Interactive setup script (run once as Administrator) |

## Quick Start

1. Copy both scripts to a folder on the IIS server.
2. Open PowerShell **as Administrator**.
3. Run the setup script:

   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force
   .\Setup-IISLogCleanup.ps1
   ```

4. Follow the prompts (it will show log locations, ask for days to keep, and confirm).

The setup script will:
- Copy `IISLogCleanup.ps1` to `C:\Scripts\IISLogCleanup\`
- Create the Event Log source
- Register a scheduled task named **IIS Log Cleanup** that runs daily at 02:00

## Manual Usage

```powershell
# Preview what would be deleted
.\IISLogCleanup.ps1 -DaysToKeep 30 -WhatIf

# Actually delete
.\IISLogCleanup.ps1 -DaysToKeep 14

# Custom path
.\IISLogCleanup.ps1 -LogPath "D:\IISLogs" -DaysToKeep 7
```

## Scheduled Task

The task runs as `NT AUTHORITY\SYSTEM` with highest privileges. You can manage it with:

```powershell
Get-ScheduledTask -TaskName "IIS Log Cleanup"
Start-ScheduledTask -TaskName "IIS Log Cleanup"
Unregister-ScheduledTask -TaskName "IIS Log Cleanup" -Confirm:$false
```

## Logs

- **File log**: `C:\Scripts\IISLogCleanup\IISLogCleanup.log`
- **Event Log**: Application log, source `IISLogCleanup` (Event ID 1000 = success, 1001/1002 = errors/warnings)

## Notes

- There is **no official GPO Administrative Template** for IIS log retention. The recommended Microsoft approach is a script + scheduled task (which can itself be deployed via GPO Preferences if desired).
- Always test with `-WhatIf` first on production servers.
- Consider shipping logs to a central system (ELK, etc.) before deleting local copies if you need longer retention.

## License

MIT
