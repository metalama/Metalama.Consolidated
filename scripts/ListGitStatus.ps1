$root = Resolve-Path "$PSScriptRoot/../.."

# Get all direct directories under root
$directories = Get-ChildItem -Path $root -Directory

foreach ($dir in $directories) {
    $gitDir = Join-Path $dir.FullName ".git"
    
    # Check if this directory is a git repository
    if (Test-Path $gitDir) {
        Push-Location $dir.FullName
        
        try {
            # Get current branch name
            $branch = git rev-parse --abbrev-ref HEAD 2>$null
            
            # Check if repository is clean or dirty
            $status = git status --porcelain 2>$null
            $statusText = if ($status) { "dirty" } else { "clean" }
            
            # Get upstream tracking info
            $upstream = git rev-parse --abbrev-ref "@{upstream}" 2>$null
            $trackingStatus = ""
            
            if ($upstream) {
                # Fetch latest changes from origin (suppress output)
                git fetch origin 2>$null | Out-Null
                
                # Get commit counts
                $ahead = git rev-list --count "$upstream..HEAD" 2>$null
                $behind = git rev-list --count "HEAD..$upstream" 2>$null
                
                if ($ahead -eq "0" -and $behind -eq "0") {
                    $trackingStatus = "up-to-date"
                } elseif ($ahead -gt 0 -and $behind -eq "0") {
                    $trackingStatus = "ahead $ahead"
                } elseif ($ahead -eq "0" -and $behind -gt 0) {
                    $trackingStatus = "behind $behind"
                } elseif ($ahead -gt 0 -and $behind -gt 0) {
                    $trackingStatus = "diverged (ahead $ahead, behind $behind)"
                }
            } else {
                $trackingStatus = "no upstream"
            }
            
            # Display the result with color coding
            $message = "$($dir.Name): $branch ($statusText, $trackingStatus)"
            
            # Use yellow color if dirty or not up-to-date
            if ($statusText -eq "dirty" -or $trackingStatus -ne "up-to-date") {
                Write-Host $message -ForegroundColor Yellow
            } else {
                Write-Host $message
            }
        }
        catch {
            Write-Host "$($dir.Name): Error reading git status"
        }
        finally {
            Pop-Location
        }
    }
}