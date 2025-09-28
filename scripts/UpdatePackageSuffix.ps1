param([Parameter(Mandatory=$true)][ValidateSet("none", "preview", "rc")][string]$Suffix)

$root = Resolve-Path "$PSScriptRoot/../.."
$suffixValue = if ($Suffix -eq "none") { "" } else { $Suffix }

Get-ChildItem -Path $root -Recurse -File -Name "MainVersion.props" | ForEach-Object {
    $file = Join-Path $root $_
    $dir = Split-Path $file -Parent
    
    Write-Host "Writing $_"
    [xml]$xml = Get-Content $file
    $xml.Project.PropertyGroup.PackageVersionSuffix = $suffixValue
    $xml.Save($file)
    
    Push-Location $dir
    #git add MainVersion.props
    #git commit -m "Set package version suffix to '$suffixValue'"
    #git push
    Pop-Location
}
