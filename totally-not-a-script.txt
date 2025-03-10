<#
.SYNOPSIS
    Extracts and publishes Terraform providers to Artifactory.

.DESCRIPTION
    This script unzips a Terraform providers archive, processes each provider,
    and uploads them to Artifactory under a structured path.

.PARAMETER ArchivePath
    Path to the ZIP archive containing Terraform providers.

.PARAMETER ArtifactoryUrl
    URL of the Artifactory instance.

.PARAMETER ArtifactoryRepository
    Name of the Artifactory repository.

.PARAMETER ArtifactoryBasePath
    Base path in the Artifactory repository where files should be uploaded.

.PARAMETER ArtifactoryApiKey
    API key for authenticating with Artifactory.

.EXAMPLE
    .\Publish-TerraformProvider.ps1 `
      -ArchivePath "C:\Downloads\hashicorp-providers-20250310112047.zip" `
      -ArtifactoryUrl "https://artifactory.example.com" `
      -ArtifactoryRepository "terraform-providers" `
      -ArtifactoryBasePath "terraform/providers" `
      -ArtifactoryApiKey "your-api-key"
#>

param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ArchivePath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ArtifactoryUrl,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ArtifactoryRepository,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ArtifactoryBasePath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ArtifactoryApiKey
)

# Validate the ZIP archive file exists.
if (!(Test-Path -Path $ArchivePath -PathType Leaf)) {
    Write-Error "Archive file not found at: $ArchivePath"
    exit 1
}

# Create the extraction directory.
$tempFolderPath = Join-Path $Env:Temp $(New-Guid)
New-Item -Type Directory -Path $tempFolderPath | Out-Null

# Extract the ZIP archive.
try {
    Write-Output "Extracting archive: $ArchivePath to $tempFolderPath..."
    Expand-Archive -Path $ArchivePath -DestinationPath $tempFolderPath -Force
} catch {
    Write-Error "Failed to extract archive: $_"
    exit 1
}

# Iterate through each file and upload it to Artifactory.
foreach ($file in Get-ChildItem -Path $tempFolderPath -Recurse -File) {
    $fileName = $file.Name

    # Extract product, version, os, and arch from the filename.
    $fileNameSplit = $fileName -split '_'
    $product = ($fileNameSplit[0] -split '-')[2] # terraform-provider-<product>
    $version = $fileNameSplit[1]

    if ($fileNameSplit[2] -like "SHA256SUMS*") {
        $targetPath = "terraform-providers/hashicorp/$product/$version/$fileName"
        $metadata = "version=v$version"
    } else {
        $os = $fileNameSplit[2]
        $arch = $fileNameSplit[3]

        $targetPath = "terraform-providers/hashicorp/$product/$version/$fileName"
        $metadata = "os=$os;arch=$arch;version=v$version"
    }

    $uploadUri = "$ArtifactoryUrl/artifactory/$ArtifactoryRepository/$ArtifactoryBasePath/$targetPath;$metadata"

    $headers = @{
        "X-JFrog-Art-Api" = $ArtifactoryApiKey
    }

    try {
        Write-Output "Checking if $fileName already exists..."

        Invoke-RestMethod `
            -Uri "$ArtifactoryUrl/artifactory/api/storage/$ArtifactoryRepository/$ArtifactoryBasePath/$targetPath" `
            -Method GET `
            -Headers $headers `
            -ContentType "application/json"

        Write-Output "$fileName already exists, skipping upload."
    } catch {
        try {
            Write-Output "Uploading $fileName to $uploadUri..."

            Invoke-RestMethod `
                -Uri $uploadUri `
                -Method PUT `
                -Headers $headers `
                -InFile $file.FullName `
                -ContentType "application/octet-stream"

            Write-Output "Successfully uploaded $fileName"
        } catch {
            Write-Error "Failed to upload $fileName. Error: $_"
        }
    }
}

Write-Output "Successfully uploaded releases to Artifactory."

Write-Output "Cleaning up $tempFolderPath..."
Remove-Item $tempFolderPath -Recurse
Write-Output "Successfully removed $tempFolderPath."
