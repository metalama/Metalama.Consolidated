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
            
            # Display the result
            Write-Host "$($dir.Name): $branch ($statusText)"
        }
        catch {
            Write-Host "$($dir.Name): Error reading git status"
        }
        finally {
            Pop-Location
        }
    }
}