$repo = $PSScriptRoot

$products = @(
    @{ Path = "$repo/source-dependencies/Metalama";           Dependencies = @() },
    @{ Path = "$repo/source-dependencies/Metalama.Community"; Dependencies = @("Metalama") },
    @{ Path = "$repo/source-dependencies/Metalama.Premium";   Dependencies = @("Metalama") },
    @{ Path = "$repo/source-dependencies/Metalama.Samples";   Dependencies = @("Metalama.Premium") }
)

foreach ($product in $products) {
    $buildScript = Join-Path $product.Path "Build.ps1"
    $fullPath = Resolve-Path $buildScript -ErrorAction SilentlyContinue

    if (-not $fullPath) {
        Write-Error "Build script not found at: $buildScript"
        exit 1
    }

    $productName = Split-Path -Leaf (Resolve-Path $product.Path)
    Write-Host "`n===== $productName =====" -ForegroundColor Cyan

    foreach ($dep in $product.Dependencies) {
        Write-Host "  Setting dependency $dep to local" -ForegroundColor Yellow
        & $fullPath dependencies set local $dep
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to set dependency '$dep' to local for $productName."
            exit 1
        }
    }

    Write-Host "  Building $productName" -ForegroundColor Green
    & $fullPath build
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build failed for $productName."
        exit 1
    }
}

Write-Host "`nAll builds succeeded." -ForegroundColor Green
