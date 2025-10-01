# Get the absolute path of the root directory
$rootPath = "$PSScriptRoot/../.."

# Get all directories in the root path
$directories = Get-ChildItem -Path $rootPath -Directory

foreach ($dir in $directories) {

    Write-Host "===== $dir ====" -ForegroundColor Cyan

    # Change to the directory
    Set-Location $dir.FullName
    
    git pull --no-edit
    & ./Build.ps1 dependencies set local PostSharp.Engineering --path c:\src\PostSharp.Engineering

    Write-Host ""
    Write-Host ""
}

# Return to the original directory
Set-Location $rootPath
