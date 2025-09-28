$root = Resolve-Path "$PSScriptRoot/../.."

# Find all Directory.Packages.props and Versions.props files recursively
$packagePropsFiles = Get-ChildItem -Path $root -Recurse -File | Where-Object { $_.Name -eq "Directory.Packages.props" -or $_.Name -eq "Versions.props" }

foreach ($fileObj in $packagePropsFiles) {
    $fullPath = $fileObj.FullName
    $relativePath = $fileObj.FullName.Replace($root.Path + "\", "")
    
    try {
        # Load the XML content
        [xml]$xml = Get-Content $fullPath -ErrorAction Stop
        
        # Find PostSharpEngineeringVersion element by searching through all PropertyGroup elements
        $versionFound = $false
        foreach ($propGroup in $xml.Project.PropertyGroup) {
            if ($propGroup.PostSharpEngineeringVersion) {
                $version = $propGroup.PostSharpEngineeringVersion
                # Get the text content, handling both direct text and InnerText
                $versionText = if ($version -is [string]) { $version } else { $version.InnerText }
                if ($versionText -and $versionText.Trim() -ne "") {
                    Write-Host "$relativePath`: $versionText"
                    $versionFound = $true
                    break
                }
            }
        }
        # If element doesn't exist, display nothing
    }
    catch {
        # If there's an error reading the file, display nothing
    }
}