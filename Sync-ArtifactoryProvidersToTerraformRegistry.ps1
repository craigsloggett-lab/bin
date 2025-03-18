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

        function Get-ArtifactoryProviderFilePaths {
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

                $filePaths = @()
                if ($response.children) {
                    foreach ($child in $response.children) {
                        Write-Verbose ("Found a child item at the following relative path: {0}" -f $child.uri)
                        Get-ArtifactoryProviderFilePaths -ArtifactoryContext $ArtifactoryContext -CurrentPath ("{0}/{1}" -f $CurrentPath, $child.uri.TrimStart('/'))
                    }
                } else {
                    Write-Verbose ("Determined the following is a file: {0}" -f $CurrentPath)
                    $filePaths += $uri
                }

                # Return an array of Artifactory URIs to the files found after traversing the repository.
                $filePaths
            }
        }

        function Invoke-ArtifactoryDownload {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [hashtable]$ArtifactoryContext,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$ArtifactoryUri,

                [Parameter(Mandatory = $false)]
                [string]$DownloadPath
            )
            begin {
                $headers  = $ArtifactoryContext.Headers
                $uri      = $ArtifactoryUri.Replace($ArtifactoryContext.ItemPropertiesApiUrl, $ArtifactoryContext.ApiUrl)
                $filename = $uri.Split('/')[-1] # Assumes the filename is after the final '/' in the URL.

                if (!$DownloadPath) { $DownloadPath = Join-Path "$Env:USERPROFILE\Downloads" "TerraformProviders" }
            }
            process {
                New-Item -Type Directory -Force -Path $DownloadPath | Out-Null

                if (Test-Path -Path "$DownloadPath\$filename" -PathType Leaf) {
                    Write-Verbose "Found $DownloadPath\$filename, skipping download..."
                } else {
                    try {
                        Write-Verbose "Invoke Artifactory download for file: $uri"
                        $response = Invoke-RestMethod -Headers $headers -Method GET -Uri $uri -OutFile "$DownloadPath\$filename"
                    }
                    catch {
                        Write-Error "Failed to query Artifactory with the following error: $_"
                        return
                    }
                }
            }
        }
    }
    process {
        $HashArguments = @{
            ArtifactoryContext = $ArtifactoryContext
            CurrentPath        = "terraform-providers"
        }

        $artifactoryProviderFilePaths = Get-ArtifactoryProviderFilePaths @HashArguments

        foreach ($uri in $artifactoryProviderFilePaths) {
            $HashArguments = @{
                ArtifactoryContext = $ArtifactoryContext
                ArtifactoryUri     = $uri
            }

            Invoke-ArtifactoryDownload @HashArguments
        }
    }
}
