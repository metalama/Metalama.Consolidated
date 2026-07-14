# Stop script on any error
$ErrorActionPreference = "Stop"

# Get the absolute path of the root directory
$rootPath = "$PSScriptRoot/../.."

# Order of processing is important.
$products = @( "Metalama.Compiler",
    "Metalama",
    "Metalama.Community",
    "Metalama.Premium",
    "Metalama.Samples",
    "Metalama.Documentation",
    "Metalama.Tests.NopCommerce",
    ".")


foreach ($dir in $products) {

    Write-Host "===== $dir ====" -ForegroundColor Cyan
    
    try {
        # Change to the directory
        Set-Location "$rootPath/${dir}"
        
        # Execute git pull and check for errors
        git pull --no-edit
        if ($LASTEXITCODE -ne 0) {
            throw "Git pull failed for $dir with exit code $LASTEXITCODE"
        }
        
        # Execute build script and check for errors
        & ./Build.ps1 bump --override
        if ($LASTEXITCODE -ne 0) {
            throw "Build script failed for $dir with exit code $LASTEXITCODE"
        }
    }
    catch {
        Write-Error "Failed processing $dir`: $_"
        exit 1
    }

    Write-Host ""
    Write-Host ""
}

# Return to the original directory
Set-Location $rootPath
