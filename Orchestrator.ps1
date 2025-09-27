# This script executes Build.ps1 for each defined product in the list, and passes all arguments it received.

$repo = $PSScriptRoot

$products = @( "$repo/source-dependencies/Metalama.Compiler",
    "$repo/source-dependencies/Metalama",
    "$repo/source-dependencies/Metalama.Community",
    "$repo/source-dependencies/Metalama.Premium",
    "$repo/source-dependencies/Metalama.Samples",
    "$repo/source-dependencies/Metalama.Documentation",
    "$repo/source-dependencies/Metalama.Vsx",
    "$repo/source-dependencies/NopCommerce",
    ".")

$hasError = $false
foreach ( $product in $products ) {
    $buildScriptPath = Join-Path $product "Build.ps1"
    $fullPath = Resolve-Path $buildScriptPath -ErrorAction SilentlyContinue
    
    if ($fullPath) {
        Write-Host "Executing: $fullPath $args" -ForegroundColor Green
        & $fullPath @args
    }
    else {
        Write-Error "Build script not found at: $buildScriptPath"
        $hasError = $true
        continue
    }

    if ( $LASTEXITCODE ! = 0 ) {
        Write-Error "Processing of '$product' failed with exit code $LASTEXITCODE."
        $hasError = $true
    }
}

if ( $hasError ) {
    exit 1
}
else {
    exit 0
}