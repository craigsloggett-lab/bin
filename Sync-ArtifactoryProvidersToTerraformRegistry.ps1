<#
.SYNOPSIS
    TODO: Add a meaninful synopsis.

.DESCRIPTION
    TODO: Add a meaningful description.

.EXAMPLE
    TODO: Add a meaningful example.
#>

[CmdletBinding()]

param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ArtifactoryApiUrl,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ArtifactoryItemPropertiesApiUrl,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ArtifactoryAccessToken,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ArtifactoryRepositoryKey,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ArtifactoryRootItemPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TerraformEnterpriseApiUrl,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TerraformEnterpriseOrganization,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TerraformEnterpriseBearerToken
)

begin {
    # Remove all leading and trailing slashes to make path definitions consistent.
    $ArtifactoryApiUrl = $ArtifactoryApiUrl.TrimEnd('/')
    $ArtifactoryItemPropertiesApiUrl = $ArtifactoryItemPropertiesApiUrl.TrimEnd('/')
    $ArtifactoryRepositoryKey = $ArtifactoryRepositoryKey.TrimStart('/')
    $ArtifactoryRepositoryKey = $ArtifactoryRepositoryKey.TrimEnd('/')
    $ArtifactoryRootItemPath = $ArtifactoryRootItemPath.TrimStart('/')
    $ArtifactoryRootItemPath = $ArtifactoryRootItemPath.TrimEnd('/')
    $TerraformEnterpriseApiUrl = $TerraformEnterpriseApiUrl.TrimEnd('/')

    # Create context maps for Artifactory and Terraform Enterprise.
    $ArtifactoryContext = @{
        ApiUrl               = $ArtifactoryApiUrl 
        ItemPropertiesApiUrl = $ArtifactoryItemPropertiesApiUrl
        RepositoryKey        = $ArtifactoryRepositoryKey
        RootItemPath         = $ArtifactoryRootItemPath

        Headers = @{
            'X-JFrog-Art-Api' = $ArtifactoryAccessToken
        }
    }

    $TerraformEnterpriseContext = @{
        ApiUrl       = $TerraformEnterpriseApiUrl
        Organization = $TerraformEnterpriseOrganization

        Headers = @{
            'Authorization' = "Bearer $TerraformEnterpriseBearerToken"
        }
    }
}

process {
    Write-Verbose "..."
    Get-ArtifactoryRepositoryItems -ArtifactoryContext $ArtifactoryContext
}

# Test if an Artifactory path is a folder, returns True if it is.
# ((Invoke-RestMethod -Uri "$uri" -Method GET -Headers $headers -ContentType "application/json").children)

function Get-ArtifactoryRepositoryItems {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$ArtifactoryContext
    )
    begin {
        $headers = $ArtifactoryContext.Headers
        $uri = "$ArtifactoryContext.ItemPropertiesApiUrl/$ArtifactoryContext.RepositoryKey/$ArtifactoryContext.RootItemPath"
    }
    process {
    }
}
