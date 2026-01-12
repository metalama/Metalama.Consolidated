# This script executes Build.ps1 for each defined product in the list, and passes all arguments it received.

$repo = $PSScriptRoot

$products = @( "$repo/source-dependencies/Metalama.Compiler",
    "$repo/source-dependencies/Metalama",
    "$repo/source-dependencies/Metalama.Community",
    "$repo/source-dependencies/Metalama.Premium",
    "$repo/source-dependencies/Metalama.Samples",
    "$repo/source-dependencies/Metalama.Documentation",
    "$repo/source-dependencies/Metalama.Tests.NopCommerce",
    ".")

$errors = 0
$successes = 0
foreach ( $product in $products ) {
    $buildScriptPath = Join-Path $product "Build.ps1"
    $fullPath = Resolve-Path $buildScriptPath -ErrorAction SilentlyContinue
    
    if ($fullPath) {
        Write-Host "Executing: $fullPath $args" -ForegroundColor Green
        & $fullPath @args
    }
    else {
        Write-Error "Build script not found at: $buildScriptPath"
        $errors = $errors + 1 
        continue
    }

    if ( $LASTEXITCODE -ne 0 ) {
        Write-Error "$fullPath' failed with exit code $LASTEXITCODE."
        $errors = $errors + 1 
    } else {
        $successes = $successes + 1 
    }


    Write-Host "`n------------------------------`n"
}

if ( $errors -gt 0 ) {
    Write-Error "$errors scripts were in error, $successes were successful."
    exit 1
}
else {
    Write-Host "All $successes scripts were successful."
    & $fullPath @args
    exit 0
}