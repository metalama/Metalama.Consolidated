# Get the absolute path of the root directory
$rootPath = "$PSScriptRoot/../.."

# Get all directories in the root path
$directories = Get-ChildItem -Path $rootPath -Directory

foreach ($dir in $directories) {

    Write-Host "===== $dir ====" -ForegroundColor Cyan

    # Change to the directory
    Set-Location $dir.FullName

    git reset --hard
    git clean -xfd

    # Use develop/2025.1 for Metalama.Tests.NopCommerce, develop/2025.1 for others (can be customized as needed)
    if ($dir.Name -eq "Metalama.Tests.NopCommerce") {
        git checkout dev/2026.0
    } else {
        git checkout develop/2026.0
    }
    git pull --no-edit

    Write-Host ""
    Write-Host ""
}

# Return to the original directory
Set-Location $rootPath
