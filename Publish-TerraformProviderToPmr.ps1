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
    "Content-Type" = "application/vnd.api+json"
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
    $namespaces = Invoke-RestMethod `
        -Uri "$artifactoryQueryUri" `
        -Method GET `
        -Headers $artifactoryHeaders `
        -ContentType "application/json"
} catch {
    Write-Error "Failed to query Artifactory: $_"
    exit 1
}

# Iterate through each Terraform provider namespace found in Artifactory.
foreach ($namespace in $namespaces.children.uri.Trim('/')) {
    Write-Output "Found the following Terraform provider namespace: $namespace"

    $providers = Invoke-RestMethod `
        -Uri "$artifactoryQueryUri/$namespace" `
        -Method GET `
        -Headers $artifactoryHeaders `
        -ContentType "application/json"

    foreach ($provider in $providers.children.uri.Trim('/')) {
        Write-Output "Found the following Terraform provider: $provider"
        
        $versions = Invoke-RestMethod `
            -Uri "$artifactoryQueryUri/$namespace/$provider" `
            -Method GET `
            -Headers $artifactoryHeaders `
            -ContentType "application/json"

        foreach ($version in $versions.children.uri.Trim('/')) {
            Write-Output "Found the following Terraform provider version: $version"

            $files = Invoke-RestMethod `
                -Uri "$artifactoryQueryUri/$namespace/$provider/$version" `
                -Method GET `
                -Headers $artifactoryHeaders `
                -ContentType "application/json"

            foreach ($file in $files.children.uri.Trim('/')) {
                Write-Output "Found the following Terraform provider file: $file"

                try {
                    if (Test-Path -Path "$tempFolderPath\$file" -PathType Leaf) {
                        Write-Output "$file already exists at $tempFolderPath, skipping download."
                    } else {
                        Write-Output "Downloading $file to $tempFolderPath..."

                        $files = Invoke-RestMethod `
                            -Uri "$artifactoryDownloadUri/$namespace/$provider/$version/$file" `
                            -Method GET `
                            -Headers $artifactoryHeaders `
                            -OutFile "$tempFolderPath\$file"
                    }

                    try {
                        $providerData = @{
                            data = @{
                                type = "registry-providers"
                                attributes = @{
                                    name = ($provider)
                                    namespace = ($namespace)
                                    "registry-name" = "private"
                                }
                            }
                        }
                    } catch {
                        Write-Output "Terraform provider already exists: ($provider)"
                    }
                } catch {
                    Write-Error "Failed to download $file. Error: $_"
                }
            }
        }
    }
}
