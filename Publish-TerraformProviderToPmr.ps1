<#
.SYNOPSIS
    Downloads Terraform providers from Artifactory and publishes them to the 
    Private Module Registry in a given Terraform Enterprise organization.

.DESCRIPTION
    This script downloads Terraform providers from Artifactory and publishes 
    them to the Private Module Registry in a given Terraform Enterprise 
    organization, creating the necessary resources as needed depending on
    the availability in Artifactory.

.PARAMETER ArtifactoryUrl
    URL of the Artifactory instance.

.PARAMETER ArtifactoryRepository
    Name of the Artifactory repository.

.PARAMETER ArtifactoryBasePath
    Base path in the Artifactory repository where Terraform provider files
    are stored.

.PARAMETER ArtifactoryApiKey
    API key for authenticating with Artifactory.

.PARAMETER TerraformEnterpriseUrl
    URL of the Terraform Enterprise instance.

.PARAMETER TerraformEnterpriseOrganization
    The name of the Terraform Enterprise organization.

.PARAMETER TerraformEnterpriseToken
    The API token for authenticating with Terraform Enterprise.

.EXAMPLE
    .\Publish-TerraformProviderToPmr.ps1 `
      -ArtifactoryUrl "https://artifactory.example.com" `
      -ArtifactoryRepository "terraform-providers" `
      -ArtifactoryBasePath "terraform/providers" `
      -ArtifactoryApiKey "your-api-key" `
      -TerraformEnterpriseUrl "https://tfe.example.com" `
      -TerraformEnterpriseOrganization "tfe-org" `
      -TerraformEnterpriseToken "my-tfe-token"
#>

param (
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
    [string]$ArtifactoryApiKey,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TerraformEnterpriseUrl,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TerraformEnterpriseOrganization,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TerraformEnterpriseToken
)

# Clean-up input URLs.
$artifactoryUrl = ($ArtifactoryUrl.TrimEnd('/'))
$tfeUrl = ($TerraformEnterpriseUrl.TrimEnd('/'))

# Create the extraction directory.
$tempFolderPath = Join-Path "$Env:USERPROFILE\Downloads" "TerraformProviders"
New-Item -Type Directory -Force -Path $tempFolderPath | Out-Null

# Query the Terraform Enterprise Private Module Registry to get existing providers.

$tfeHeaders = @{
    "Authorization" = "Bearer $TerraformEnterpriseToken"
}

$tfeListProvidersUri = "$tfeUrl/api/v2/organizations/$TerraformEnterpriseOrganization/registry-providers"

try {
    $tfeListProvidersResponse = Invoke-RestMethod `
        -Uri $tfeListProvidersUri `
        -Method GET `
        -Headers $tfeHeaders `
        -ContentType "application/vnd.api+json"
} catch {
    Write-Error "Failed to query Terraform Enterprise: $_"
    exit 1
}

$artifactoryHeaders = @{
    "X-JFrog-Art-Api" = $ArtifactoryApiKey
}

$artifactoryQueryUri = "$artifactoryUrl/artifactory/api/storage/$ArtifactoryRepository/$ArtifactoryBasePath/terraform-providers"
$artifactoryDownloadUri = "$artifactoryUrl/artifactory/$ArtifactoryRepository/$ArtifactoryBasePath/terraform-providers"

try {
    $providerNamespaces = Invoke-RestMethod `
        -Uri "$artifactoryQueryUri" `
        -Method GET `
        -Headers $artifactoryHeaders `
        -ContentType "application/json"
} catch {
    Write-Error "Failed to query Artifactory: $_"
    exit 1
}

# Iterate through each Terraform provider namespace found in Artifactory.
foreach ($providerNamespace in $providerNamespaces.children.uri.Trim('/')) {
    Write-Output "Found the following Terraform provider namespace in Artifactory: $providerNamespace"

    $providers = Invoke-RestMethod `
        -Uri "$artifactoryQueryUri/$providerNamespace" `
        -Method GET `
        -Headers $artifactoryHeaders `
        -ContentType "application/json"

    foreach ($provider in $providers.children.uri.Trim('/')) {
        Write-Output "Found the following Terraform provider in Artifactory: $provider"
        
        if ($tfeListProvidersResponse.data.attributes.name.Contains($provider)) {
            # Get a list of versions published to the PMR for this provider.
            $tfeGetAllVersionsUri = "$tfeListProvidersUri/private/$TerraformEnterpriseOrganization/$provider/versions"
            $tfeGetAllVersionsResponse = Invoke-RestMethod `
                -Uri $tfeGetAllVersionsUri `
                -Method GET `
                -Headers $tfeHeaders `
                -ContentType "application/vnd.api+json"
        } else {
            # Create a provider with the TFE API.
            Write-Output "Creating a private provider in Terraform Enterprise for: $provider"
            try {
                $providerData = @{
                    data = @{
                        type = "registry-providers"
                        attributes = @{
                            name = ($provider)
                            namespace = ($providerNamespace)
                            "registry-name" = "private"
                        }
                    }
                }
                # TODO: Add Invoke-RestMethod to POST a new provider.
            } catch {
                Write-Error "Failed to publish to Terraform Enterprise: $_"
                exit 1
            }
        }

        $versions = Invoke-RestMethod `
            -Uri "$artifactoryQueryUri/$providerNamespace/$provider" `
            -Method GET `
            -Headers $artifactoryHeaders `
            -ContentType "application/json"

        foreach ($version in $versions.children.uri.Trim('/')) {
            Write-Output "Found the following Terraform provider version in Artifactory: $version"

            $versionResponse = ($tfeGetAllVersionsResponse.data | Where-Object { $_.attributes.version -eq $version })
            if ($versionResponse) {
                # The version has been published to TFE, grab the SHA256SUMS upload URLs.
                $shasumsUploadUri = $versionResponse.links."shasums-upload"
                $shasumsSigUploadUri = $versionResponse.links."shasums-sig-upload"

                # Get a list of platforms published to the PMR for this version.
                $tfeGetAllPlatformsUri = "$tfeGetAllVersionsUri/$version/platforms"
                $tfeGetAllPlatformsResponse = Invoke-RestMethod `
                    -Uri $tfeGetAllPlatformsUri `
                    -Method GET `
                    -Headers $tfeHeaders `
                    -ContentType "application/vnd.api+json"
            } else {
                # Create a provider version with the TFE API.
                Write-Output "Creating a provider version in Terraform Enterprise for: $version"
                try {
                    $providerData = @{
                        data = @{
                            type = "registry-provider-versions"
                            attributes = @{
                                version = ($version)
                                "key-id" = "34365D9472D7468F"
                                protocols = @("5.0")
                            }
                        }
                    }
                    # TODO: Add Invoke-RestMethod to POST a new provider version.
                    # Capture the $response.data.links."shasums-upload" link.
                } catch {
                    Write-Error "Failed to publish to Terraform Enterprise: $_"
                    exit 1
                }
            }

            $files = Invoke-RestMethod `
                -Uri "$artifactoryQueryUri/$providerNamespace/$provider/$version" `
                -Method GET `
                -Headers $artifactoryHeaders `
                -ContentType "application/json"

            foreach ($file in $files.children.uri.Trim('/')) {
                Write-Output "Found the following Terraform provider file in Artifactory: $file"

                # Extract product, version, os, and arch from the filename.
                $fileNameSplit = $file -split '_'
                $product = ($fileNameSplit[0] -split '-')[2] # terraform-provider-<product>
                $version = $fileNameSplit[1]

                if ($fileNameSplit[2] -like "SHA256SUMS*") {
                  # Upload the signature files using $response.data.links."shasums-upload".
                } else {
                  $os = $fileNameSplit[2]
                  $arch = $fileNameSplit[3]
                }

                if (
                  $tfeGetAllPlatformsResponse.data.attributes.os.Contains($os) -and
                  $tfeGetAllPlatformsResponse.data.attributes.arch.Contains($arch)
                ) {
                    # A platform for this OS and architecture has been published to TFE, grab the binary upload URL.
                    $platformResponse = ($tfeGetAllPlatformsResponse.data | Where-Object { 
                        $_.attributes.os -eq $os -and $_.attributes.arch -eq $arch 
                    })
                    $providerBinaryUploadUri = $platformResponse.links."provider-binary-upload"
                } else {
                    # Create a platform for this OS and architecture with the TFE API.
                    Write-Output "Creating a provider platform in Terraform Enterprise for: $os_$arch"

                    try {
                        $providerData = @{
                            data = @{
                                type = "registry-provider-version-platforms"
                                attributes = @{
                                    os = ($os)
                                    arch = ($arch)
                                    shasum = "" # Get the SHASUM for the file.
                                    filename = $file
                                }
                            }
                        }
                        # TODO: Add Invoke-RestMethod to POST a new provider platform.
                        # Capture the $response.data.links."provider-binary-upload" link.
                    } catch {
                        Write-Error "Failed to publish to Terraform Enterprise: $_"
                        exit 1
                    }
                }

                # Stage the file for publishing to TFE.
                if ($providerBinaryUploadUri) {
                    Write-Output "$file has not been published to the registry, download from Artifactory."

                    if (Test-Path -Path "$tempFolderPath\$file" -PathType Leaf) {
                        Write-Output "$file already exists at $tempFolderPath, skipping download."
                    } else {
                        $files = Invoke-RestMethod `
                            -Uri "$artifactoryDownloadUri/$providerNamespace/$provider/$version/$file" `
                            -Method GET `
                            -Headers $artifactoryHeaders `
                            -OutFile "$tempFolderPath\$file"
                    }

                    # Publish the file to the Private Module Registry in TFE.
                    try {
                        Invoke-RestMethod `
                            -Uri $providerBinaryUploadUri `
                            -Method PUT `
                            -InFile "$tempFolderPath\$file"
                    } catch {
                        Write-Error "Failed to publish to Terraform Enterprise: $_"
                        exit 1
                    }
                } else {
                    Write-Output "$file has already been published to the registry, skipping publication."
                }
            }
        }
    }
}
