param([Parameter(Mandatory=$true)][ValidateSet("none", "preview", "rc")][string]$Suffix)

$root = Resolve-Path "$PSScriptRoot/../.."
$suffixValue = if ($Suffix -eq "none") { "" } else { $Suffix }

Get-ChildItem -Path $root -Directory -Name "eng*" | ForEach-Object {
    $engDir = Join-Path $root $_
    Get-ChildItem -Path $engDir -File -Name "MainVersion.props"
} | ForEach-Object {
    $file = Join-Path $root $_
    $dir = Split-Path $file -Parent

    Push-Location $dir

    git pull --no-edit
    
    Write-Host "Writing $_"
    [xml]$xml = Get-Content $file
    $xml.Project.PropertyGroup.PackageVersionSuffix = $suffixValue
    $xml.Save($file)
    
  
    git add MainVersion.props
    git commit -m "Set package version suffix to '$suffixValue'."
    git push
    Pop-Location
}
