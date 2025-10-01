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
        git remote prune origin 
        
        # Get all local branches except the current one
        $localBranches = git branch --format="%(refname:short)" | Where-Object { $_ -notmatch '^\*' -and $_ -ne 'main' -and $_ -ne 'master' -and $_ -ne 'develop' }
        
        foreach ($branch in $localBranches) {
            $branch = $branch.Trim()
            if ($branch) {
                # Check if the branch has a remote tracking branch
                $remoteBranch = git config --get "branch.$branch.remote" 
                if ($remoteBranch) {
                    $remoteRef = git config --get "branch.$branch.merge" 
                    if ($remoteRef) {
                        # Extract the remote branch name from refs/heads/branch-name
                        $remoteBranchName = $remoteRef -replace '^refs/heads/', ''
                        
                        # Check if the remote branch still exists
                        $remoteExists = git ls-remote --heads origin $remoteBranchName 
                        if (-not $remoteExists) {
                            Write-Host "  Deleting local branch '$branch' (remote branch no longer exists)" -ForegroundColor Red
                            
                            # Remove the local branch
                            git branch -D $branch 
                            
                            # Clean up the git config entries for this branch
                            Write-Host "  Cleaning up config for branch '$branch'" -ForegroundColor Yellow
                            git config --unset "branch.$branch.remote" 
                            git config --unset "branch.$branch.merge" 
                        }
                    }
                }
            }
        }
        
        # Additional cleanup: Find orphaned branch configs for branches that no longer exist locally
        Write-Host "Checking for orphaned branch configurations..." -ForegroundColor Magenta
        $allConfigBranches = git config --get-regexp "^branch\." | ForEach-Object { 
            if ($_ -match "^branch\.([^.]+)\.") { 
                $matches[1] 
            }
        } | Sort-Object -Unique
        
        $currentLocalBranches = git branch --format="%(refname:short)"
        
        foreach ($configBranch in $allConfigBranches) {
            if ($configBranch -and $currentLocalBranches -notcontains $configBranch) {
                Write-Host "  Cleaning up orphaned config for deleted branch '$configBranch'" -ForegroundColor DarkYellow
                git config --remove-section "branch.$configBranch" 
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
