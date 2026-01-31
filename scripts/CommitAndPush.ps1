param(
    [Parameter(Mandatory=$true)]
    [string]$CommitMessage
)

# Get the absolute path of the root directory
$rootPath = "$PSScriptRoot/../.."

# Get all directories in the root path
$directories = Get-ChildItem -Path $rootPath -Directory

foreach ($dir in $directories) {

    # Skip directories without Build.ps1
    if (-not (Test-Path (Join-Path $dir.FullName "Build.ps1"))) {
        continue
    }

    Write-Host "===== $dir ====" -ForegroundColor Cyan

    # Change to the directory
    Set-Location $dir.FullName

    # Check if there are any changes to commit
    $status = git status --porcelain
    if ($status) {
        Write-Host "Changes detected, committing..." -ForegroundColor Yellow
        
        # Add all changes
        git add -A
        
        # Commit with the provided message
        git commit -m $CommitMessage
        
        # Push to the current branch
        git push
        
        Write-Host "Committed and pushed successfully" -ForegroundColor Green
    } else {
        Write-Host "No changes to commit" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host ""
}

# Return to the original directory
Set-Location $rootPath
