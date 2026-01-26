param(
    [string]$Branch = "release/2026.0"
)

$parentDir = Get-Location
$repos = Get-ChildItem -Path $parentDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName ".git") }

Write-Host "Found $($repos.Count) repositories in $parentDir" -ForegroundColor Cyan

foreach ($repo in $repos) {
    Write-Host "`nProcessing: $($repo.Name)" -ForegroundColor Yellow

    Push-Location $repo.FullName
    try {
        # Set the default branch using gh
        $output = gh repo edit --default-branch $Branch 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ Successfully set default branch to '$Branch'" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Failed to set default branch: $output" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  ✗ Error: $_" -ForegroundColor Red
    }
    finally {
        Pop-Location
    }
}

Write-Host "`nDone!" -ForegroundColor Cyan
