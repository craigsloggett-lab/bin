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

# Create the extraction directory.
$tempFolderPath = Join-Path $Env:Temp $(New-Guid)
New-Item -Type Directory -Path $tempFolderPath | Out-Null

$artifactoryHeaders = @{
    "X-JFrog-Art-Api" = $ArtifactoryApiKey
}

$terraformEnterpriseHeaders = @{
    "Authorization" = "Bearer $TerraformEnterpriseToken"
    "Content-Type" = "application/vnd.api+json"
}

$artifactoryBaseUri = "$ArtifactoryUrl/artifactory/api/storage/$ArtifactoryRepository/$ArtifactoryBasePath/terraform-providers"

$namespaces = Invoke-RestMethod `
    -Uri "$artifactoryBaseUri" `
    -Method GET `
    -Headers $artifactoryHeaders `
    -ContentType "application/json"

# Iterate through each Terraform provider namespace found in Artifactory.
foreach ($namespace in $namespaces.children.uri) {
    Write-Output "Found the $namespace Terraform provider namespace..."

    $providers = Invoke-RestMethod `
        -Uri "$artifactoryBaseUri/$namespace" `
        -Method GET `
        -Headers $artifactoryHeaders `
        -ContentType "application/json"

    foreach ($provider in $providers.children.uri) {
        Write-Output "Found the $provider Terraform provider..."
        
        $versions = Invoke-RestMethod `
            -Uri "$artifactoryBaseUri/$namespace/$provider" `
            -Method GET `
            -Headers $artifactoryHeaders `
            -ContentType "application/json"

        foreach ($version in $versions.children.uri) {
            Write-Output "Found the $version Terraform provider version..."
        }
    }
}
