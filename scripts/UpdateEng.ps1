# Get the absolute path of the root directory
$rootPath = "$PSScriptRoot/../.."

# Get all directories in the root path
$directories = Get-ChildItem -Path $rootPath -Directory

foreach ($dir in $directories) {

    # Skip directories without Build.ps1
    if (-not (Test-Path (Join-Path $dir.FullName "Build.ps1"))) {
        continue
    }

    # Change to the directory
    Set-Location $dir.FullName

    # Work around a bug in a a previous version of eng.
    $env:ENG_REPO_DIRECTORY = $dir.FullName

    git pull --no-edit
    & ./Build.ps1 dependencies update-eng 
    & ./Build.ps1 dependencies reset PostSharp.Engineering
    & ./Build.ps1 generate-scripts
    git commit --all -m "Update eng."
    git push

    Write-Host ""
    Write-Host ""
}

# Return to the original directory
Set-Location $rootPath
