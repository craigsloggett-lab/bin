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
                Authorization = "Bearer $TerraformEnterpriseBearerToken"
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

                [Parameter(Mandatory = $true)]
                [string]$DownloadPath
            )
            begin {
                $headers  = $ArtifactoryContext.Headers
                $uri      = $ArtifactoryUri.Replace($ArtifactoryContext.ItemPropertiesApiUrl, $ArtifactoryContext.ApiUrl)
                $filename = $uri.Split('/')[-1] # Assumes the filename is after the final '/' in the URL.
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

        function Invoke-ParseProviderFileFullPath {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$ProviderFileFullPath
            )
            begin {
                $filename  = Split-Path $ProviderFileFullPath -Leaf
                $extension = [System.IO.Path]::GetExtension($filename)
                $name      = ($filename.Split('_')[0]).Split('-')[2] # terraform-provider-<name>
                $version   = $filename.Split('_')[1]
            }
            process {
                if ($extension -like '.zip') {
                    $os        = $filename.Split('_')[2]
                    $arch      = ($filename.Split('_')[3]).Replace($extension, '') # Drop the extension.
                    $sha256sum = (Get-FileHash -Algorithm SHA256 "$ProviderFileFullPath").Hash.ToLower()
                }
                $providerFileData = @{
                    Namespace = 'hashicorp' # Only the HashiCorp namespace is valid at this time.
                    Name = $name
                    Version = $version
                    OS = $os
                    Arch = $arch
                    SHA256SUM = $sha256sum
                    Filename = $filename
                    KeyID = '34365D9472D7468F' # TODO: Get the Key ID.
                }

                $providerFileData
            }
        }

        function New-TerraformRegistryProvider {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [hashtable]$TerraformEnterpriseContext,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$ProviderNamespace,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$ProviderName
            )
            begin {
                $headers           = $TerraformEnterpriseContext.Headers
                $providersEndpoint = ("/organizations/{0}/registry-providers" -f $TerraformEnterpriseContext.Organization)
                $uri               = ("{0}/{1}" -f $TerraformEnterpriseContext.ApiUrl,
                                                   $providersEndpoint.TrimStart('/')).TrimEnd('/')
            }
            process {
                Write-Verbose "Found the following provider: $Providername"
                Write-Verbose "Checking if the provider already exists..."
                try {
                    Write-Verbose "Listing all of the Terraform providers published in the registry..."
                    $response = Invoke-RestMethod -Headers $headers -Method GET -Uri $uri
                }
                catch {
                    Write-Error "Failed to query Artifactory with the following error: $_"
                    return
                }

                if ($response.data.attributes.name -like $ProviderName) {
                    # Process Terraform providers, this condition is if they exist in the registry so no need to create them.

                }
            }
        }
    }
    process {
        # Discover Terraform provider files in Artifactory.
        $HashArguments = @{
            ArtifactoryContext = $ArtifactoryContext
            CurrentPath        = "terraform-providers"
        }

        $artifactoryProviderFilePaths = Get-ArtifactoryProviderFilePaths @HashArguments

        # Download Terraform provider files locally.
        $downloadPath = Join-Path "$Env:USERPROFILE\Downloads" "TerraformProviders"

        foreach ($uri in $artifactoryProviderFilePaths) {
            $HashArguments = @{
                ArtifactoryContext = $ArtifactoryContext
                ArtifactoryUri     = $uri
                DownloadPath       = $downloadPath
            }

            Invoke-ArtifactoryDownload @HashArguments
        }

        # Capture provider data from the downloaded files.
        $providerData = @()

        Get-ChildItem $downloadPath | ForEach-Object {
            $HashArguments = @{
                ProviderFileFullPath = $_.FullName
            }

            $providerData += Invoke-ParseProviderFileFullPath @HashArguments
        }

        # Create the necessary Terraform registry objects in preparation for publication.
        $providerData.Name | Get-Unique | ForEach-Object {
            $HashArguments = @{
                TerraformEnterpriseContext = $TerraformEnterpriseContext
                ProviderNamespace          = "hashicorp"
                ProviderName               = $_
            }

            New-TerraformRegistryProvider @HashArguments
        }
    }
}
