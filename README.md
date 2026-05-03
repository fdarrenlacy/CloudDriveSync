# CloudDriveSync

A lightweight PowerShell script that bidirectionally syncs files between two cloud drive folders (e.g., OneDrive and iCloud Drive) on Windows. Designed to run silently via Task Scheduler.

## What It Does

- **Bidirectional sync** — new and updated files sync both directions (newest timestamp wins on conflicts)
- **One-way deletes** — deletions only propagate from Side A (primary) to Side B (secondary), not the reverse. If you delete from Side B, the file stays on Side A and gets re-synced back
- **File type filtering** — only syncs specified file types (`.docx`, `.pdf`, `.jpg`, etc.) and logs any skipped files
- **Smart state tracking** — uses a JSON state file to distinguish "deleted from primary" vs. "new file not yet synced"
- **Cloud offload protection** — if a cloud provider offloads all files to placeholders (0 files visible), deletions are automatically skipped to prevent data loss
- **JSON logging** — every action (NEW, UPDATED, DELETED, SKIPPED, ERROR) is logged with timestamps

## Prerequisites

- **Windows 10/11**
- **PowerShell 7+** — [Download here](https://github.com/PowerShell/PowerShell/releases/latest). Install the MSI version (not the Store version) for Task Scheduler compatibility.
- **Both cloud drives syncing locally** — e.g., OneDrive and [iCloud for Windows](https://apps.microsoft.com/detail/9PKTQ5699M62) installed with local sync enabled

## Setup

### 1. Configure the script

Open `Sync-CloudDrives.ps1` and update the configuration section at the top:

```powershell
# Side A is the "primary" — deletions here propagate to Side B
$SideA = "C:\Users\YourName\OneDrive\Documents\MyFolder"

# Side B is the "secondary" — deletions here do NOT propagate to Side A  
$SideB = "C:\Users\YourName\iCloudDrive\MyFolder"

# Log and state files
$LogFile = "C:\Users\YourName\.sync-cloud-drives.json"
$StateFile = "C:\Users\YourName\.sync-cloud-drives-state.json"
```

Optionally update the allowed file types:

```powershell
$IncludeExtensions = @(".docx", ".doc", ".pdf", ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".heic")
```

### 2. Configure the VBS launcher (optional, prevents window flash)

Open `RunSync.vbs` and replace the placeholders:

```
<PWSH_PATH>   → C:\Program Files\PowerShell\7\pwsh.exe
<SCRIPT_PATH> → C:\path\to\Sync-CloudDrives.ps1
```

### 3. Test it

Run the script manually first to verify it works:

```powershell
& "C:\Program Files\PowerShell\7\pwsh.exe" -ExecutionPolicy Bypass -File "C:\path\to\Sync-CloudDrives.ps1"
```

### 4. Schedule it

Open **Task Scheduler** → **Create Task** (not "Create Basic Task"):

| Tab | Setting |
|-----|---------|
| **General** | Name: `CloudDriveSync` — Check "Run only when user is logged on" — Check "Hidden" |
| **Triggers** | Daily, recur every 1 day — Repeat every **15 minutes** for **Indefinitely** |
| **Actions** | Program: `wscript.exe` — Arguments: `"C:\path\to\RunSync.vbs"` |

> **Note:** "Run only when user is logged on" includes locked screen sessions — the task will fire as long as your Windows session is active.

> **Why the VBS wrapper?** Task Scheduler + PowerShell always flashes a console window briefly. The VBS wrapper launches PowerShell completely hidden.

## Files

| File | Purpose |
|------|---------|
| `Sync-CloudDrives.ps1` | Main sync script |
| `RunSync.vbs` | Silent launcher wrapper for Task Scheduler (prevents window flash) |

## Generated Files (created at runtime)

| File | Purpose |
|------|---------|
| `~\.sync-cloud-drives.json` | JSON log — one entry per action (NEW, UPDATED, DELETED, SKIPPED, ERROR) |
| `~\.sync-cloud-drives-state.json` | State file — tracks known synced files for deletion logic |

## Sync Behavior

| Scenario | What Happens |
|----------|-------------|
| New file on Side A | Copied to Side B |
| New file on Side B | Copied to Side A |
| File edited on Side A | Updated on Side B (if newer) |
| File edited on Side B | Updated on Side A (if newer) |
| File edited on both sides | Newest timestamp wins |
| File deleted from Side A | Deleted from Side B |
| File deleted from Side B | Stays on Side A, re-synced back to Side B |
| File deleted from both sides | No action — silently ignored |
| Unsupported file type added | Logged as SKIPPED, not synced |
| Cloud provider offloads all files | Deletions skipped with warning (prevents data loss) |

## Known Limitations

- **Microsoft DLP** — files tagged with Microsoft business sensitivity labels may be blocked from copying to non-Microsoft cloud storage (e.g., iCloud). The file will fail to sync and iCloud may create a `.txt` stub file instead. Remove the sensitivity label from the file to resolve.
- **File type filter** — only files matching `$IncludeExtensions` are synced. All others are logged as SKIPPED.
- **Subfolder sync** — syncs the configured folders recursively, including subfolders. The `test\` subfolder pattern from development is not excluded by default.
- **Task Scheduler + "Run whether logged on or not"** — this option requires additional configuration with PowerShell 7 from the Windows Store. Use the MSI-installed version of PowerShell 7 or set to "Run only when user is logged on" for simplicity.

## License

MIT — use it however you want.
