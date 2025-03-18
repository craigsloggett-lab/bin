function Sync-ArtifactoryProvidersToTerraformRegistry {
    <#
    .SYNOPSIS
        TODO: Add a meaninful synopsis.
    
    .DESCRIPTION
        TODO: Add a meaningful description.
    
    .PARAMETER ArtifactoryApiUrl
        TODO: Add parameter descriptions.

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
        $ArtifactoryApiUrl               = $ArtifactoryApiUrl.TrimEnd('/')
        $ArtifactoryItemPropertiesApiUrl = $ArtifactoryItemPropertiesApiUrl.TrimEnd('/')
        $ArtifactoryRepositoryKey        = $ArtifactoryRepositoryKey.TrimStart('/')
        $ArtifactoryRepositoryKey        = $ArtifactoryRepositoryKey.TrimEnd('/')
        $ArtifactoryRootItemPath         = $ArtifactoryRootItemPath.TrimStart('/')
        $ArtifactoryRootItemPath         = $ArtifactoryRootItemPath.TrimEnd('/')
        $TerraformEnterpriseApiUrl       = $TerraformEnterpriseApiUrl.TrimEnd('/')
    
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

        function Get-ArtifactoryRepositoryItems {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [hashtable]$ArtifactoryContext,

                [Parameter(Mandatory = $false)]
                [string]$CurrentPath
            )
            begin {
                $headers = $ArtifactoryContext.Headers
                $uri     = ("{0}/{1}/{2}/{3}" -f $ArtifactoryContext.ItemPropertiesApiUrl,
                                                 $ArtifactoryContext.RepositoryKey,
                                                 $ArtifactoryContext.RootItemPath,
                                                 $CurrentPath).TrimEnd('/')
            }
            process {
                Write-Verbose "Querying Artifactory path: $uri"

                try {
                    $response = Invoke-RestMethod -Headers $headers -Method GET -Uri $uri
                }
                catch {
                    Write-Error "Failed to query Artifactory with the following error: $_"
                    return
                }

                if ($response.children) {
                    foreach ($child in $response.children) {
                        Write-Verbose ("Found a child item at the following relative path: " -f $child.uri)
                        Get-ArtifactoryRepositoryItems -ArtifactoryContext $ArtifactoryContext -CurrentPath ("{0}/{1}" -f $CurrentPath, ($child.uri).TrimStart('/'))
                    }
                } else {
                    Write-Verbose "Determined $CurrentPath is a file."
                    # $CurrentPath is not a folder because it has no children.
                }

                Write-Verbose "..."
            }
        }
    }
    process {
        Write-Verbose "..."
        (Get-ArtifactoryRepositoryItems -ArtifactoryContext $ArtifactoryContext)
    }
}
