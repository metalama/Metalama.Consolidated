# Get the absolute path of the root directory
$rootPath = "$PSScriptRoot/../.."

$products = @( "Metalama.Compiler",
    "Metalama",
    "Metalama.Community",
    "Metalama.Premium",
    "Metalama.Samples",
    "Metalama.Documentation",
    "Metalama.Vsx",
    "Metalama.Tests.NopCommerce",
    ".")


foreach ($dir in $products) {

    
    # Change to the directory
    Set-Location "$rootPath/${dir}"
    
    git pull --no-edit
    & ./Build.ps1 bump --override

    Write-Host ""
    Write-Host ""
}

# Return to the original directory
Set-Location $rootPath
