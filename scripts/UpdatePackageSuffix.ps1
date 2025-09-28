param([Parameter(Mandatory=$true)][ValidateSet("none", "preview", "rc")][string]$Suffix)

$root = Resolve-Path "$PSScriptRoot/../.."
$suffixValue = if ($Suffix -eq "none") { "" } else { "-$Suffix" }

# Find files matching pattern $root/*/eng*/MainVersions.props
Get-ChildItem -Path "$root\*\eng*\MainVersion.props" -File | ForEach-Object {

    $file = $_.FullName
    $dir = Split-Path $file -Parent

    Push-Location $dir

    git pull --no-edit
    
    Write-Host "Writing $file"
    [xml]$xml = Get-Content $file
    $xml.Project.PropertyGroup.PackageVersionSuffix = $suffixValue
    $xml.Save($file)
    
    git commit --all -m "Set package version suffix to '$suffixValue'."
    git push
    Pop-Location
}
