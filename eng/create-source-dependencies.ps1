$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $repoRoot) { $repoRoot = Split-Path -Parent (Get-Location) }
$parentDir = Split-Path -Parent $repoRoot
$targetDir = Join-Path $repoRoot "source-dependencies"

if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir | Out-Null
}

Get-ChildItem $parentDir -Directory | Where-Object {
    $_.Name -ne (Split-Path -Leaf $repoRoot) -and
    $_.Name -ne ".claude" -and
    $_.Name -ne ".vs"
} | ForEach-Object {
    $linkPath = Join-Path $targetDir $_.Name
    if (-not (Test-Path $linkPath)) {
        cmd /c mklink /J $linkPath $_.FullName
    }
}
