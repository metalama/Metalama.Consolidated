# Get the absolute path of the root directory
$rootPath = "$PSScriptRoot/../.."

# Get all directories in the root path
$directories = Get-ChildItem -Path $rootPath -Directory

foreach ($dir in $directories) {

    # Change to the directory
    Set-Location $dir.FullName
    
    git pull --no-edit
    & ./Build.ps1  tools git merge-downstream
}

# Return to the original directory
Set-Location $rootPath
