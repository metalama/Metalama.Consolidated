$root = Resolve-Path "$PSScriptRoot/../.."

# Find MainVersion.props files in eng* subdirectories of direct child directories
$mainVersionFiles = @()

# Iterate through direct child directories of the root
Get-ChildItem -Path $root -Directory | ForEach-Object {
    $childDir = $_
    
    # Look for subdirectories that start with "eng"
    Get-ChildItem -Path $childDir.FullName -Directory | Where-Object { $_.Name -like "eng*" } | ForEach-Object {
        $engDir = $_
        $mainVersionFile = Join-Path $engDir.FullName "MainVersion.props"
        
        if (Test-Path $mainVersionFile) {
            $mainVersionFiles += Get-Item $mainVersionFile
        }
    }
}

foreach ($fileObj in $mainVersionFiles) {
    $fullPath = $fileObj.FullName
    $relativePath = $fileObj.FullName.Replace($root.Path + "\", "")
    
    try {
        # Load the XML content
        [xml]$xml = Get-Content $fullPath -ErrorAction Stop
        
        $mainVersion = $null
        $packageVersionSuffix = $null
        
        # Search through all PropertyGroup elements for MainVersion and PackageVersionSuffix
        foreach ($propGroup in $xml.Project.PropertyGroup) {
            if ($propGroup.MainVersion -and !$mainVersion) {
                $mainVersion = if ($propGroup.MainVersion -is [string]) { $propGroup.MainVersion } else { $propGroup.MainVersion.InnerText }
            }
            if ($propGroup.PackageVersionSuffix -and !$packageVersionSuffix) {
                $packageVersionSuffix = if ($propGroup.PackageVersionSuffix -is [string]) { $propGroup.PackageVersionSuffix } else { $propGroup.PackageVersionSuffix.InnerText }
            }
        }
        
        # Display the results
        Write-Host "${relativePath}: ${mainVersion}${packageVersionSuffix}"
        
    }
    catch {
        Write-Host "${relativePath}: Error reading file - $($_.Exception.Message)"
    }
}