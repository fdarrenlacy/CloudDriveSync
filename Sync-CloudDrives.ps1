#Requires -Version 7.0
<#
.SYNOPSIS
    Bidirectional sync between two cloud drive folders (e.g., OneDrive and iCloud Drive).
    
.DESCRIPTION
    Synchronizes files between two local cloud-synced folders.
    - Syncs bidirectionally (newest timestamp wins on conflicts)
    - Deletions propagate from Side A to Side B only (not reverse)
    - Only syncs specified file types (configurable)
    - Logs all activity to a JSON file
    - Designed to run on a schedule (Task Scheduler on Windows, cron on Linux, launchd on macOS)
    
.EXAMPLE
    # Run a sync
    .\Sync-CloudDrives.ps1
    
    # Schedule it (run once from elevated PowerShell — see README for details)
#>

# ============================================================
# CONFIGURATION — Update these to match your setup
# ============================================================

# Side A is the "primary" — deletions here propagate to Side B
$SideA = "<SIDE_A_PATH>"   # e.g., "C:\Users\YourName\OneDrive\Documents\MyFolder" (Windows)
                           #       "/Users/YourName/Library/CloudStorage/OneDrive-Personal/MyFolder" (macOS)
                           #       "/home/YourName/OneDrive/MyFolder" (Linux)

# Side B is the "secondary" — deletions here do NOT propagate to Side A
$SideB = "<SIDE_B_PATH>"   # e.g., "C:\Users\YourName\iCloudDrive\MyFolder" (Windows)
                           #       "/Users/YourName/Library/Mobile Documents/com~apple~CloudDocs/MyFolder" (macOS)

# Log and state files — update the path prefix to your user folder
$LogFile = "<USER_HOME>\.sync-cloud-drives.json"       # e.g., "C:\Users\YourName\.sync-cloud-drives.json" (Windows)
                                                       #       "/Users/YourName/.sync-cloud-drives.json" (macOS/Linux)
$StateFile = "<USER_HOME>\.sync-cloud-drives-state.json" # e.g., "C:\Users\YourName\.sync-cloud-drives-state.json" (Windows)
                                                         #       "/Users/YourName/.sync-cloud-drives-state.json" (macOS/Linux)

# Only sync these file types (add or remove as needed)
$IncludeExtensions = @(".docx", ".doc", ".pdf", ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".heic")

# ============================================================
# STATE MANAGEMENT
# Tracks files that have been synced so we can distinguish
# "deleted from Side A" vs. "new on Side B, not yet synced"
# ============================================================
function Get-SyncState {
    if (Test-Path $StateFile) {
        $content = Get-Content $StateFile -Raw
        if ($content) {
            return $content | ConvertFrom-Json -AsHashtable
        }
    }
    return @{ "knownFiles" = @() }
}

function Save-SyncState {
    param([hashtable]$State)
    $State | ConvertTo-Json -Depth 5 | Set-Content $StateFile -Encoding UTF8
}

function Update-KnownFiles {
    $known = @()
    if (Test-Path $SideA) {
        Get-ChildItem $SideA -Recurse -File -ErrorAction SilentlyContinue | Where-Object { Should-Include $_.Name } | ForEach-Object {
            $known += $_.FullName.Substring($SideA.Length).TrimStart('\')
        }
    }
    if (Test-Path $SideB) {
        Get-ChildItem $SideB -Recurse -File -ErrorAction SilentlyContinue | Where-Object { Should-Include $_.Name } | ForEach-Object {
            $rel = $_.FullName.Substring($SideB.Length).TrimStart('\')
            if ($known -notcontains $rel) { $known += $rel }
        }
    }
    $state = @{ "knownFiles" = $known }
    Save-SyncState $state
    return $state
}

# ============================================================
# LOGGING (JSON format)
# ============================================================
function Write-SyncLog {
    param(
        [string]$Action,    # NEW, UPDATED, DELETED, SKIPPED, INFO, ERROR
        [string]$Direction, # SideA->SideB, SideB->SideA, System
        [string]$File,
        [string]$Detail = ""
    )
    
    $entry = [ordered]@{
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        action    = $Action
        direction = $Direction
        file      = $File
        detail    = $Detail
    }
    
    $json = $entry | ConvertTo-Json -Compress
    Add-Content -Path $LogFile -Value $json
    
    $display = "[$($entry.timestamp)] $Direction $Action`: $File"
    if ($Detail) { $display += " ($Detail)" }
    Write-Host $display
}

function Should-Include {
    param([string]$FileName)
    $ext = [System.IO.Path]::GetExtension($FileName).ToLower()
    return $IncludeExtensions -contains $ext
}

# ============================================================
# SYNC: Copy new and updated files
# ============================================================
function Sync-Files {
    param(
        [string]$SourcePath,
        [string]$DestPath,
        [string]$Direction,
        [string[]]$SkipFiles = @()
    )
    
    if (-not (Test-Path $SourcePath)) { return 0 }
    
    if (-not (Test-Path $DestPath)) {
        New-Item -ItemType Directory -Path $DestPath -Force | Out-Null
    }
    
    $changeCount = 0
    $sourceFiles = Get-ChildItem -Path $SourcePath -Recurse -File -ErrorAction SilentlyContinue
    
    foreach ($file in $sourceFiles) {
        if (-not (Should-Include $file.Name)) {
            $relPath = $file.FullName.Substring($SourcePath.Length).TrimStart('\')
            Write-SyncLog -Action "SKIPPED" -Direction $Direction -File $relPath -Detail "File type not in allowed list"
            continue
        }
        
        $relativePath = $file.FullName.Substring($SourcePath.Length).TrimStart('\')
        
        # Skip files that were just deleted in this run
        if ($SkipFiles -contains $relativePath) { continue }
        
        $destFile = Join-Path $DestPath $relativePath
        $destDir = Split-Path $destFile -Parent
        
        $shouldCopy = $false
        $action = ""
        
        if (-not (Test-Path $destFile)) {
            $shouldCopy = $true
            $action = "NEW"
        }
        else {
            $destItem = Get-Item $destFile
            $sourceHash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
            $destHash = (Get-FileHash -Path $destFile -Algorithm SHA256).Hash
            if ($sourceHash -ne $destHash -and ($file.LastWriteTime - $destItem.LastWriteTime).TotalSeconds -gt 2) {
                $shouldCopy = $true
                $action = "UPDATED"
            }
        }
        
        if ($shouldCopy) {
            try {
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Copy-Item -Path $file.FullName -Destination $destFile -Force
                (Get-Item $destFile).LastWriteTime = $file.LastWriteTime
                Write-SyncLog -Action $action -Direction $Direction -File $relativePath -Detail "$([math]::Round($file.Length/1KB, 1)) KB"
                $changeCount++
            }
            catch {
                Write-SyncLog -Action "ERROR" -Direction $Direction -File $relativePath -Detail $_.Exception.Message
            }
        }
    }
    
    return $changeCount
}

# ============================================================
# DELETIONS: Side A -> Side B only
# Only deletes from Side B if the file was previously synced
# (exists in state file) but no longer exists on Side A
# ============================================================
function Sync-Deletions {
    param(
        [string]$SourcePath,
        [string]$DestPath,
        [string]$Direction,
        [hashtable]$State
    )
    
    if (-not (Test-Path $DestPath)) { return @() }
    
    $knownFiles = $State["knownFiles"]
    if (-not $knownFiles) { return @() }
    
    # Safety check: if source has 0 files but we have known files,
    # the cloud provider may have offloaded everything to placeholders.
    # Skip deletions to avoid mass-deleting from the other side.
    $sourceFileCount = 0
    if (Test-Path $SourcePath) {
        $sourceFileCount = @(Get-ChildItem -Path $SourcePath -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { Should-Include $_.Name }).Count
    }
    if ($sourceFileCount -eq 0 -and $knownFiles.Count -gt 0) {
        Write-SyncLog -Action "INFO" -Direction $Direction -File "" -Detail "Source has 0 files but $($knownFiles.Count) known — skipping deletions (possible cloud offload)"
        return @()
    }
    
    $deletedFiles = @()
    $destFiles = Get-ChildItem -Path $DestPath -Recurse -File -ErrorAction SilentlyContinue
    
    foreach ($file in $destFiles) {
        if (-not (Should-Include $file.Name)) { continue }
        
        $relativePath = $file.FullName.Substring($DestPath.Length).TrimStart('\')
        $sourceFile = Join-Path $SourcePath $relativePath
        
        if (-not (Test-Path $sourceFile) -and ($knownFiles -contains $relativePath)) {
            try {
                Remove-Item -Path $file.FullName -Force
                Write-SyncLog -Action "DELETED" -Direction $Direction -File $relativePath
                $deletedFiles += $relativePath
                
                # Clean up empty directories
                $parentDir = Split-Path $file.FullName -Parent
                while ($parentDir -ne $DestPath -and (Test-Path $parentDir) -and (Get-ChildItem $parentDir -Force -ErrorAction SilentlyContinue).Count -eq 0) {
                    Remove-Item $parentDir -Force
                    $parentDir = Split-Path $parentDir -Parent
                }
            }
            catch {
                Write-SyncLog -Action "ERROR" -Direction $Direction -File $relativePath -Detail $_.Exception.Message
            }
        }
    }
    
    return $deletedFiles
}

# ============================================================
# MAIN
# ============================================================

# Validate paths
if ($SideA -match "^<" -or $SideB -match "^<") {
    Write-Host "ERROR: Please update the configuration paths in the script before running."
    Write-Host "Open Sync-CloudDrives.ps1 and replace <SIDE_A_PATH>, <SIDE_B_PATH>, and <USER_HOME> with your actual paths."
    exit 1
}

if (-not (Test-Path $SideA)) {
    Write-SyncLog -Action "ERROR" -Direction "System" -File "" -Detail "Side A path does not exist: $SideA"
    exit 1
}

if (-not (Test-Path $SideB)) {
    Write-SyncLog -Action "INFO" -Direction "System" -File "" -Detail "Creating Side B directory: $SideB"
    New-Item -ItemType Directory -Path $SideB -Force | Out-Null
}

Write-SyncLog -Action "INFO" -Direction "System" -File "" -Detail "Sync started"

# Load state
$state = Get-SyncState

# Step 1: Deletions — Side A to Side B only
$deletedFiles = Sync-Deletions -SourcePath $SideA -DestPath $SideB -Direction "SideA->SideB" -State $state

# Step 2: Sync new/updated files bidirectionally (newest wins)
$abChanges = Sync-Files -SourcePath $SideA -DestPath $SideB -Direction "SideA->SideB"
$baChanges = Sync-Files -SourcePath $SideB -DestPath $SideA -Direction "SideB->SideA" -SkipFiles $deletedFiles

# Step 3: Update state with current snapshot
$state = Update-KnownFiles

$total = $abChanges + $baChanges + $deletedFiles.Count

if ($total -eq 0) {
    Write-SyncLog -Action "INFO" -Direction "System" -File "" -Detail "No changes. Folders in sync."
}
else {
    Write-SyncLog -Action "INFO" -Direction "System" -File "" -Detail "Sync complete. $total change(s) applied."
}
