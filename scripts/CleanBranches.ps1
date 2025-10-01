# Get the absolute path of the root directory
$rootPath = "$PSScriptRoot/../.."

# Get all directories in the root path
$directories = Get-ChildItem -Path $rootPath -Directory

foreach ($dir in $directories) {

    Write-Host "===== $dir ====" -ForegroundColor Cyan

    # Change to the directory
    Set-Location $dir.FullName
    
    # Check if this is a git repository
    if (Test-Path ".git") {
        Write-Host "Cleaning branches in git repository: $($dir.Name)" -ForegroundColor Yellow
        
        # First, prune remote references to clean up stale remote-tracking branches
        git remote prune origin 2>$null
        
        # Get all local branches except the current one
        $localBranches = git branch --format="%(refname:short)" | Where-Object { $_ -notmatch '^\*' -and $_ -ne 'main' -and $_ -ne 'master' -and $_ -ne 'develop' }
        
        foreach ($branch in $localBranches) {
            $branch = $branch.Trim()
            if ($branch) {
                # Check if the branch has a remote tracking branch
                $remoteBranch = git config --get "branch.$branch.remote" 2>$null
                if ($remoteBranch) {
                    $remoteRef = git config --get "branch.$branch.merge" 2>$null
                    if ($remoteRef) {
                        # Extract the remote branch name from refs/heads/branch-name
                        $remoteBranchName = $remoteRef -replace '^refs/heads/', ''
                        
                        # Check if the remote branch still exists
                        $remoteExists = git ls-remote --heads origin $remoteBranchName 2>$null
                        if (-not $remoteExists) {
                            Write-Host "  Deleting local branch '$branch' (remote branch no longer exists)" -ForegroundColor Red
                            git branch -D $branch 2>$null
                        }
                    }
                }
            }
        }
    } else {
        Write-Host "Skipping non-git directory: $($dir.Name)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host ""
}

# Return to the original directory
Set-Location $rootPath
