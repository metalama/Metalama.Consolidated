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

    # Check if this is a git repository
    if (Test-Path ".git") {
        
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
        $allConfigBranches = git config --get-regexp "^branch\..*remote" | ForEach-Object { 
            if ($_ -match "^branch\.(.+)\.remote") { 
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
        
        # Clean up bad and duplicate fetch refspecs in [remote "origin"]
        $fetchRefspecs = git config --get-all remote.origin.fetch 2>$null
        if ($fetchRefspecs) {
            $validRefspecs = @()
            $seenRefspecs = @{}
            $duplicatesFound = 0
            
            foreach ($refspec in $fetchRefspecs) {
                # Check for duplicates first
                if ($seenRefspecs.ContainsKey($refspec)) {
                    Write-Host "  Removing duplicate refspec: $refspec" -ForegroundColor DarkRed
                    $duplicatesFound++
                    continue
                }
                $seenRefspecs[$refspec] = $true
                
                if ($refspec -match '\+refs/heads/([^:]+):refs/remotes/origin/(.+)') {
                    $remoteBranchName = $matches[1]
                    
                    # Check if this remote branch still exists
                    $remoteExists = git ls-remote --heads origin $remoteBranchName 2>$null
                    if ($remoteExists) {
                        $validRefspecs += $refspec
                    } else {
                        Write-Host "  Removing invalid refspec: $refspec (remote branch no longer exists)" -ForegroundColor Red
                    }
                } else {
                    # Keep non-standard refspecs (like wildcards) as they might be intentional
                    $validRefspecs += $refspec
                    Write-Host "  Keeping non-standard refspec: $refspec" -ForegroundColor Cyan
                }
            }
            
            # Check if we need to update the config (invalid refspecs or duplicates found)
            $needsUpdate = ($validRefspecs.Count -lt $fetchRefspecs.Count) -or ($duplicatesFound -gt 0)
            
            if ($needsUpdate) {
                Write-Host "  Updating remote.origin.fetch configuration..." -ForegroundColor Yellow
                
                # Remove all current fetch refspecs
                git config --unset-all remote.origin.fetch 2>$null
                
                # Add back only the valid, unique ones
                foreach ($validRefspec in $validRefspecs) {
                    git config --add remote.origin.fetch $validRefspec
                }
                
                $removedCount = $fetchRefspecs.Count - $validRefspecs.Count
                Write-Host "  Updated fetch refspecs: $($fetchRefspecs.Count) -> $($validRefspecs.Count) (removed $removedCount total)" -ForegroundColor Green
                if ($duplicatesFound -gt 0) {
                    Write-Host "  Removed $duplicatesFound duplicate(s)" -ForegroundColor Green
                }
            } else {
                Write-Host "  All fetch refspecs are valid and unique" -ForegroundColor Green
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
