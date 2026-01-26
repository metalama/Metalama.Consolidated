# Get the absolute path of the root directory
$rootPath = "$PSScriptRoot/../.."

# Get all directories in the root path
$directories = Get-ChildItem -Path $rootPath -Directory

foreach ($dir in $directories) {

    Write-Host "===== $dir ====" -ForegroundColor Cyan

    # Change to the directory
    Set-Location $dir.FullName
    
    ./Build.ps1 prepare

    Write-Host ""
    Write-Host ""
}

# Return to the original directory
Set-Location $rootPath
