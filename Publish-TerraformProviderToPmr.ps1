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

$tfeRegistryProvidersUri = "$tfeUrl/api/v2/organizations/$TerraformEnterpriseOrganization/registry-providers"

try {
    $tfeListProvidersResponse = Invoke-RestMethod `
        -Uri $tfeRegistryProvidersUri `
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
            $tfeRegistryProviderVersionsUri = "$tfeRegistryProvidersUri/private/$TerraformEnterpriseOrganization/$provider/versions"
            $tfeRegistryProviderVersionsResponse = Invoke-RestMethod `
                -Uri $tfeRegistryProviderVersionsUri `
                -Method GET `
                -Headers $tfeHeaders `
                -ContentType "application/vnd.api+json"
        } else {
            # Create a provider with the TFE API.
            Write-Output "Creating a private provider in Terraform Enterprise for: $provider"
            try {
                # Build the payload.
                $providerPayload = @{
                    data = @{
                        type = "registry-providers"
                        attributes = @{
                            name = ($provider)
                            namespace = ($providerNamespace)
                            "registry-name" = "private"
                        }
                    }
                } | ConvertTo-Json -Depth 10

                # Create the provider.
                $providerResponse = Invoke-RestMethod `
                    -Uri $tfeRegistryProvidersUri `
                    -Method POST `
                    -Headers $tfeHeaders `
                    -Body $providerPayload `
                    -ContentType "application/vnd.api+json"
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

            $versionResponse = ($tfeRegistryProviderVersionsResponse.data | Where-Object { $_.attributes.version -eq $version })
            if ($versionResponse) {
                # The version has been published to TFE, grab the SHA256SUMS upload URLs.
                $shasumsUploadUri = $versionResponse.links."shasums-upload"
                $shasumsSigUploadUri = $versionResponse.links."shasums-sig-upload"

                # Get a list of platforms published to the PMR for this version.
                $tfeRegistryProviderVersionPlatformsUri = "$tfeRegistryProviderVersionsUri/$version/platforms"
                $tfeRegistryProviderVersionPlatformsResponse = Invoke-RestMethod `
                    -Uri $tfeRegistryProviderVersionPlatformsUri `
                    -Method GET `
                    -Headers $tfeHeaders `
                    -ContentType "application/vnd.api+json"
            } else {
                # Create a provider version with the TFE API.
                Write-Output "Creating a provider version in Terraform Enterprise for: $version"
                try {
                    $providerVersionPayload = @{
                        data = @{
                            type = "registry-provider-versions"
                            attributes = @{
                                version = ($version)
                                "key-id" = "34365D9472D7468F" # TODO: Get the Key ID.
                                protocols = @("5.0")
                            }
                        }
                    } | ConvertTo-Json -Depth 10

                    # Create the provider version.
                    $providerVersionResponse = Invoke-RestMethod `
                        -Uri $tfeRegistryProviderVersionsUri `
                        -Method POST `
                        -Headers $tfeHeaders `
                        -Body $providerVersionPayload `
                        -ContentType "application/vnd.api+json"

                    $shasumsUploadUri = $providerVersionResponse.data.links."shasums-upload"
                    $shasumsSigUploadUri = $providerVersionResponse.data.links."shasums-sig-upload"
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

                $extension = [System.IO.Path]::GetExtension($file)
                switch ($extension) {
                    ".sig" {
                        Write-Output "Found the SHA256SUMS signature file, publishing it to the PMR using this URL: $shasumsSigUploadUri"
                        try {
                            Invoke-RestMethod `
                                -Uri $shasumsSigUploadUri `
                                -Method PUT `
                                -InFile "$tempFolderPath\$file"
                        } catch {
                            Write-Error "Failed to publish to Terraform Enterprise: $_"
                            exit 1
                        }
                    }
                    ".zip" {
                        Write-Output "Found the provider file, capturing the OS and Architecture as: $fileNameSplit[2] and $fileNameSplit[3]"
                        $os = $fileNameSplit[2]
                        $arch = $fileNameSplit[3]

                        if ($tfeRegistryProviderVersionPlatformsResponse) {
                            if (
                                $tfeRegistryProviderVersionPlatformsResponse.data.attributes.os.Contains($os) -and
                                $tfeRegistryProviderVersionPlatformsResponse.data.attributes.arch.Contains($arch)
                            ) {
                                # A platform for this OS and architecture has been published to TFE, grab the binary upload URL.
                                $platformResponse = ($tfeRegistryProviderVersionPlatformsResponse.data | Where-Object { 
                                    $_.attributes.os -eq $os -and $_.attributes.arch -eq $arch 
                                })
                                $providerBinaryUploadUri = $platformResponse.links."provider-binary-upload"
                            }
                        } else {
                            # Create a platform for this OS and architecture with the TFE API.
                            Write-Output "Creating a provider platform in Terraform Enterprise for: $os_$arch"

                            # Get the SHASUM
                            $shasum = (Get-FileHash -Algorithm SHA256 $file).Hashi.ToLower()

                            try {
                                $providerVersionPlatformPayload = @{
                                    data = @{
                                        type = "registry-provider-version-platforms"
                                        attributes = @{
                                            os = $os
                                            arch = $arch
                                            shasum = $shasum
                                            filename = $file
                                        }
                                    }
                                } | ConvertTo-Json -Depth 10

                                # Create the provider version platform.
                                $providerPlatformResponse = Invoke-RestMethod `
                                    -Uri $tfeRegistryProviderVersionPlatformsUri `
                                    -Method POST `
                                    -Headers $tfeHeaders `
                                    -Body $providerVersionPlatformPayload `
                                    -ContentType "application/vnd.api+json"

                                $providerBinaryUploadUri = $providerPlatformResponse.data.links."provider-binary-upload"
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
                    default {
                        if ($file -like "*SHA256SUMS") {
                            Write-Output "Found the SHA256SUMS file, publishing it to the PMR using this URL: $shasumsUploadUri"
                            try {
                                Invoke-RestMethod `
                                    -Uri $shasumsUploadUri `
                                    -Method PUT `
                                    -InFile "$tempFolderPath\$file"
                            } catch {
                                Write-Error "Failed to publish to Terraform Enterprise: $_"
                                exit 1
                            }
                        }
                        else {
                            Write-Output "Unknown file, skipping..."
                        }
                    }
                }
            }
        }
    }
}
