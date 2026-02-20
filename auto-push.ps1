# ============================================
# AUTO COMMIT & PUSH - File Watcher
# ============================================
# Jalankan: .\auto-push.ps1
# Stop:     Ctrl+C
#
# Script ini memantau perubahan file di folder project.
# Setiap ada perubahan, otomatis commit + push ke GitHub.
# Delay 10 detik setelah perubahan terakhir agar batch edit terkumpul.
# ============================================

param(
    [int]$DelaySeconds = 10,
    [string]$Branch = "main"
)

$projectPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectPath

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  AUTO COMMIT & PUSH - File Watcher" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Folder  : $projectPath" -ForegroundColor Gray
Write-Host "  Branch  : $Branch" -ForegroundColor Gray
Write-Host "  Delay   : ${DelaySeconds}s setelah perubahan terakhir" -ForegroundColor Gray
Write-Host "  Stop    : Ctrl+C" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Filter: hanya file yang relevan
$filter = "*.*"
$includeExtensions = @(".html", ".css", ".js", ".json", ".png", ".jpg", ".svg", ".ico", ".txt", ".md")
$excludePatterns = @(".git", "node_modules", "auto-push.ps1", ".tmp", ".swp")

function Get-Timestamp {
    return (Get-Date).ToString("HH:mm:ss")
}

function Should-Ignore($path) {
    foreach ($pattern in $excludePatterns) {
        if ($path -like "*$pattern*") { return $true }
    }
    $ext = [System.IO.Path]::GetExtension($path)
    if ($ext -and $ext -notin $includeExtensions) { return $true }
    return $false
}

function Do-CommitAndPush {
    $status = git status --porcelain 2>&1
    if ([string]::IsNullOrWhiteSpace($status)) {
        Write-Host "  [$(Get-Timestamp)] Tidak ada perubahan untuk di-commit." -ForegroundColor DarkGray
        return
    }

    # Buat commit message otomatis berdasarkan file yang berubah
    $changedFiles = git diff --name-only HEAD 2>&1
    $stagedNew = git ls-files --others --exclude-standard 2>&1
    
    $allChanged = @()
    if ($changedFiles) { $allChanged += $changedFiles -split "`n" | Where-Object { $_ } }
    if ($stagedNew) { $allChanged += $stagedNew -split "`n" | Where-Object { $_ } }
    
    $fileList = ($allChanged | Select-Object -First 5) -join ", "
    if ($allChanged.Count -gt 5) { $fileList += " +$($allChanged.Count - 5) more" }
    
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm")
    $commitMsg = "auto: update $fileList [$timestamp]"

    Write-Host ""
    Write-Host "  [$(Get-Timestamp)] Perubahan terdeteksi!" -ForegroundColor Green
    
    # Stage all
    git add -A 2>&1 | Out-Null
    Write-Host "  [$(Get-Timestamp)] Staged all changes" -ForegroundColor DarkCyan
    
    # Commit
    $commitResult = git commit -m $commitMsg 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [$(Get-Timestamp)] Committed: $commitMsg" -ForegroundColor Green
    } else {
        Write-Host "  [$(Get-Timestamp)] Commit skipped (no changes)" -ForegroundColor DarkGray
        return
    }
    
    # Push
    Write-Host "  [$(Get-Timestamp)] Pushing ke origin/$Branch..." -ForegroundColor Yellow
    $pushResult = git push origin $Branch 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [$(Get-Timestamp)] Push berhasil!" -ForegroundColor Green
    } else {
        Write-Host "  [$(Get-Timestamp)] Push gagal: $pushResult" -ForegroundColor Red
    }
    Write-Host ""
}

# --- File System Watcher ---
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $projectPath
$watcher.Filter = $filter
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $false
$watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor 
                         [System.IO.NotifyFilters]::LastWrite -bor 
                         [System.IO.NotifyFilters]::DirectoryName

$script:lastChangeTime = [DateTime]::MinValue
$script:pendingPush = $false

Write-Host "  [$(Get-Timestamp)] Menunggu perubahan file..." -ForegroundColor DarkGray
Write-Host ""

$watcher.EnableRaisingEvents = $true

try {
    while ($true) {
        # Poll for changes
        $result = $watcher.WaitForChanged(
            [System.IO.WatcherChangeTypes]::Changed -bor 
            [System.IO.WatcherChangeTypes]::Created -bor 
            [System.IO.WatcherChangeTypes]::Deleted -bor 
            [System.IO.WatcherChangeTypes]::Renamed, 
            1000  # 1 second timeout
        )
        
        if (-not $result.TimedOut) {
            $changedPath = $result.Name
            if (-not (Should-Ignore $changedPath)) {
                $script:lastChangeTime = Get-Date
                $script:pendingPush = $true
                Write-Host "  [$(Get-Timestamp)] Berubah: $changedPath" -ForegroundColor DarkYellow
            }
        }
        
        # Check if we should commit (delay passed since last change)
        if ($script:pendingPush) {
            $elapsed = ((Get-Date) - $script:lastChangeTime).TotalSeconds
            if ($elapsed -ge $DelaySeconds) {
                $script:pendingPush = $false
                Do-CommitAndPush
                Write-Host "  [$(Get-Timestamp)] Menunggu perubahan file..." -ForegroundColor DarkGray
            }
        }
    }
} finally {
    $watcher.EnableRaisingEvents = $false
    $watcher.Dispose()
    Write-Host ""
    Write-Host "  File watcher dihentikan." -ForegroundColor Yellow
}
