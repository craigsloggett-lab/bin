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
                Authorization  = "Bearer $TerraformEnterpriseBearerToken"
                'Content-Type' = 'application/vnd.api+json'
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
                    $response.children | ForEach-Object {
                        Write-Verbose ("Found a child item at the following relative path: {0}" -f $_.uri)
                        Get-ArtifactoryProviderFilePaths -ArtifactoryContext $ArtifactoryContext -CurrentPath ("{0}/{1}" -f $CurrentPath, $_.uri.TrimStart('/'))
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
                $filename     = Split-Path $ProviderFileFullPath -Leaf
                $extension    = [System.IO.Path]::GetExtension($filename)
                $providerName = ($filename.Split('_')[0]).Split('-')[2] # terraform-provider-<name>
                $version      = $filename.Split('_')[1]
            }
            process {
                Write-Verbose "Parsing provider file: $filename"
                if ($extension -like '.zip') {
                    $os        = $filename.Split('_')[2]
                    $arch      = ($filename.Split('_')[3]).Replace($extension, '') # Drop the extension.
                    $sha256sum = (Get-FileHash -Algorithm SHA256 "$ProviderFileFullPath").Hash.ToLower()
                }
                $providerFileData = @{
                    Arch         = $arch
                    Extension    = $extension
                    Filename     = $filename
                    FullPath     = $ProviderFileFullPath
                    KeyID        = '34365D9472D7468F' # TODO: Get the Key ID.
                    Namespace    = $TerraformEnterpriseContext.Organization
                    OS           = $os
                    ProviderName = $providerName
                    SHA256SUM    = $sha256sum
                    Version      = $version
                }

                $providerFileData
            }
        }

        function Get-TerraformRegistryProviderNames {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [hashtable]$TerraformEnterpriseContext
            )
            begin {
                $headers           = $TerraformEnterpriseContext.Headers
                $providersEndpoint = ("/organizations/{0}/registry-providers" -f $TerraformEnterpriseContext.Organization)
                $uri               = ("{0}/{1}" -f $TerraformEnterpriseContext.ApiUrl,
                                                   $providersEndpoint.TrimStart('/')).TrimEnd('/')
            }
            process {
                try {
                    Write-Verbose "Querying the Terraform registry: $uri"
                    $response = Invoke-RestMethod -Headers $headers -Method GET -Uri $uri
                }
                catch {
                    Write-Error "Failed to query the Terraform registry: $_"
                    return
                }

                $response.data.attributes.name
            }
        }

        function Get-TerraformRegistryProviderVersionsData {
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
                $headers          = $TerraformEnterpriseContext.Headers
                $versionsEndpoint = ("/organizations/{0}/registry-providers/private/{1}/{2}/versions" -f $TerraformEnterpriseContext.Organization,
                                                                                                         $ProviderNamespace,
                                                                                                         $ProviderName)
                $uri              = ("{0}/{1}" -f $TerraformEnterpriseContext.ApiUrl,
                                                  $versionsEndpoint.TrimStart('/')).TrimEnd('/')
            }
            process {
                try {
                    Write-Verbose "Querying the Terraform registry: $uri"
                    $response = Invoke-RestMethod -Headers $headers -Method GET -Uri $uri
                }
                catch {
                    Write-Error "Failed to query the Terraform registry: $_"
                    return
                }

                $response.data
            }
        }

        function Get-TerraformRegistryProviderVersionPlatformsData {
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
                [string]$ProviderName,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$ProviderVersion
            )
            begin {
                $headers           = $TerraformEnterpriseContext.Headers
                $platformsEndpoint = ("/organizations/{0}/registry-providers/private/{1}/{2}/versions/{3}/platforms" -f $TerraformEnterpriseContext.Organization,
                                                                                                                        $ProviderNamespace,
                                                                                                                        $ProviderName,
                                                                                                                        $ProviderVersion)
                $uri               = ("{0}/{1}" -f $TerraformEnterpriseContext.ApiUrl,
                                                   $platformsEndpoint.TrimStart('/')).TrimEnd('/')
            }
            process {
                try {
                    Write-Verbose "Querying the Terraform registry: $uri"
                    $response = Invoke-RestMethod -Headers $headers -Method GET -Uri $uri
                }
                catch {
                    Write-Error "Failed to query the Terraform registry: $_"
                    return
                }

                $response.data
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
                $providerPayload = @{
                    data = @{
                        type       = 'registry-providers'
                        attributes = @{
                            name            = $ProviderName
                            namespace       = $ProviderNamespace
                            'registry-name' = 'private'
                        }
                    }
                } | ConvertTo-Json -Depth 10

                try {
                    Write-Verbose "Posting to the Terraform registry: $uri"
                    $response = Invoke-RestMethod -Headers $headers -Method POST -Uri $uri -Body $providerPayload
                }
                catch {
                    Write-Error "Failed to post to the Terraform registry: $_"
                    return
                }
            }
        }

        function New-TerraformRegistryProviderVersion {
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
                [string]$ProviderName,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$ProviderVersion,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$ProviderVersionKeyID
            )
            begin {
                $headers          = $TerraformEnterpriseContext.Headers
                $versionsEndpoint = ("/organizations/{0}/registry-providers/private/{1}/{2}/versions" -f $TerraformEnterpriseContext.Organization,
                                                                                                         $ProviderNamespace,
                                                                                                         $ProviderName)
                $uri              = ("{0}/{1}" -f $TerraformEnterpriseContext.ApiUrl,
                                                  $versionsEndpoint.TrimStart('/')).TrimEnd('/')
            }
            process {
                $providerVersionPayload = @{
                    data = @{
                        type       = 'registry-provider-versions'
                        attributes = @{
                            version   = $ProviderVersion
                            'key-id'  = $ProviderVersionKeyID
                            protocols = @("5.0")
                        }
                    }
                } | ConvertTo-Json -Depth 10

                try {
                    Write-Verbose "Posting to the Terraform registry: $uri"
                    $response = Invoke-RestMethod -Headers $headers -Method POST -Uri $uri -Body $providerVersionPayload
                }
                catch {
                    Write-Error "Failed to post to the Terraform registry: $_"
                    return
                }

                $response.data
            }
        }

        function New-TerraformRegistryProviderVersionPlatform {
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
                [string]$ProviderName,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$ProviderVersion,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$ProviderOS,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$ProviderArch,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$ProviderSHA256SUM,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$ProviderFilename
            )
            begin {
                $headers          = $TerraformEnterpriseContext.Headers
                $versionsEndpoint = ("/organizations/{0}/registry-providers/private/{1}/{2}/versions/{3}/platforms" -f $TerraformEnterpriseContext.Organization,
                                                                                                                       $ProviderNamespace,
                                                                                                                       $ProviderName,
                                                                                                                       $ProviderVersion)
                $uri              = ("{0}/{1}" -f $TerraformEnterpriseContext.ApiUrl,
                                                  $versionsEndpoint.TrimStart('/')).TrimEnd('/')
            }
            process {
                $providerVersionPlatformPayload = @{
                    data = @{
                        type       = 'registry-provider-version-platforms'
                        attributes = @{
                            os       = $ProviderOS
                            arch     = $ProviderArch
                            shasum   = $ProviderSHA256SUM
                            filename = $ProviderFilename
                        }
                    }
                } | ConvertTo-Json -Depth 10

                try {
                    Write-Verbose "Posting to the Terraform registry: $uri"
                    $response = Invoke-RestMethod -Headers $headers -Method POST -Uri $uri -Body $providerVersionPlatformPayload
                }
                catch {
                    Write-Error "Failed to post to the Terraform registry: $_"
                    return
                }

                $response.data
            }
        }

        function Publish-TerraformProviderFile {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [hashtable]$TerraformEnterpriseContext,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$ProviderFileUploadUrl,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$ProviderFileFullPath
            )
            begin {
                $headers = $TerraformEnterpriseContext.Headers
                $uri     = $ProviderFileUploadUrl
            }
            process {
                try {
                    Write-Verbose "Posting to the Terraform registry: $uri"
                    $response = Invoke-RestMethod -Headers $headers -Method PUT -Uri $uri -InFile $ProviderFileFullPath
                }
                catch {
                    Write-Error "Failed to post to the Terraform registry: $_"
                    return
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

        $artifactoryProviderFilePaths | ForEach-Object {
            $HashArguments = @{
                ArtifactoryContext = $ArtifactoryContext
                ArtifactoryUri     = $_
                DownloadPath       = $downloadPath
            }

            Invoke-ArtifactoryDownload @HashArguments
        }

        # Capture provider data from the downloaded files.
        $providerFilesData = @()

        Get-ChildItem $downloadPath | ForEach-Object {
            $HashArguments = @{
                ProviderFileFullPath = $_.FullName
            }

            $providerFilesData += Invoke-ParseProviderFileFullPath @HashArguments
        }

        # Capture provider data from the Terraform registry.
        $publishedProvidersData = @{}

        $HashArguments = @{
            TerraformEnterpriseContext = $TerraformEnterpriseContext
        }

        # Start with a list of providers.
        (Get-TerraformRegistryProviderNames @HashArguments) | ForEach-Object {
            $providerName = $_
            $publishedProvidersData.Add($providerName, @{})

            $HashArguments = @{
                TerraformEnterpriseContext = $TerraformEnterpriseContext
                ProviderNamespace          = $TerraformEnterpriseContext.Organization
                ProviderName               = $providerName
            }
            
            # Next is a list of versions published for a given provider.
            (Get-TerraformRegistryProviderVersionsData @HashArguments) | ForEach-Object {
                $providerVersion = $_.attributes.version

                $publishedProvidersData.$providerName.Add($providerVersion, @{
                    links     = $_.links
                    platforms = @()
                })

                $HashArguments = @{
                    TerraformEnterpriseContext = $TerraformEnterpriseContext
                    ProviderNamespace          = $TerraformEnterpriseContext.Organization
                    ProviderName               = $providerName
                    ProviderVersion            = $providerVersion
                }
                
                # Last is a list of platforms published for a given version of a provider.
                (Get-TerraformRegistryProviderVersionPlatformsData @HashArguments) | ForEach-Object {
                    # Populate a hashtable with the published providers, their versions, and the associated platform details.
                    $publishedProvidersData.$providerName.$providerVersion.platforms += $_
                }
            }
        }

        # Create a provider in the Terraform registry if it hasn't been created yet.
        $providerFilesData.ProviderName | Get-Unique | ForEach-Object {
            if (!$publishedProvidersData.$_) {
                Write-Verbose "The following provider has not been published yet: $_"
                $HashArguments = @{
                    TerraformEnterpriseContext = $TerraformEnterpriseContext
                    ProviderNamespace          = $TerraformEnterpriseContext.Organization
                    ProviderName               = $_
                }

                New-TerraformRegistryProvider @HashArguments

                $publishedProvidersData.Add($_, @{})
            }
        }

        $providerFilesData | ForEach-Object {
            if (!$publishedProvidersData.($_.ProviderName).($_.Version)) {
                # Create a provider version in the Terraform registry.
                $HashArguments = @{
                    TerraformEnterpriseContext = $TerraformEnterpriseContext
                    ProviderNamespace          = $TerraformEnterpriseContext.Organization
                    ProviderName               = $_.ProviderName
                    ProviderVersion            = $_.Version
                    ProviderVersionKeyID       = $_.KeyID
                }

                $response = New-TerraformRegistryProviderVersion @HashArguments

                $publishedProvidersData.($_.ProviderName).Add($_.Version, @{
                    links     = $response.links
                    platforms = @()
                })
            }

            $providerFileData = $_

            switch ($_.Extension) {
                '.zip' {
                    $platform = $publishedProvidersData.$($providerFileData.ProviderName).$($providerFileData.Version).platforms |
                        Where-Object {
                            $_.attributes.os   -eq $providerFileData.OS   -and
                            $_.attributes.arch -eq $providerFileData.Arch
                        }

                    if (!$platform) {
                        # Create a provider version platform in the Terraform registry.
                        $HashArguments = @{
                            TerraformEnterpriseContext = $TerraformEnterpriseContext
                            ProviderNamespace          = $providerFileData.Namespace
                            ProviderName               = $providerFileData.ProviderName
                            ProviderVersion            = $providerFileData.Version
                            ProviderOS                 = $providerFileData.OS
                            ProviderArch               = $providerFileData.Arch
                            ProviderSHA256SUM          = $providerFileData.SHA256SUM
                            ProviderFilename           = $providerFileData.Filename
                        }

                        $response = New-TerraformRegistryProviderVersionPlatform @HashArguments

                        # Append the new platform record so next time we know it’s published
                        $publishedProvidersData.$($providerFileData.ProviderName).$($providerFileData.Version).platforms += $response

                        # Grab the binary upload URL.
                        $providerFileUploadUrl = $response.links.'provider-binary-upload'
                    }

                }
                '.sig' {
                    # Grab the SHA256SUMS signature file upload URL from the version.
                    $version = $publishedProvidersData.$($providerFileData.ProviderName).$($providerFileData.Version)
                    $providerFileUploadUrl = $version.links.'shasums-sig-upload'
                }
                default {
                    # Grab the SHA256SUMS file upload URL from the version.
                    $version = $publishedProvidersData.$($providerFileData.ProviderName).$($providerFileData.Version)
                    $providerFileUploadUrl = $version.links.'shasums-upload'
                }
            }

            if ($providerFileUploadUrl) {
                # Publish the provider file.
                $HashArguments = @{
                    TerraformEnterpriseContext = $TerraformEnterpriseContext
                    ProviderFileUploadUrl      = $providerFileUploadUrl
                    ProviderFileFullPath       = $_.FullPath
                }

                Publish-TerraformProviderFile @HashArguments
            }
        }
    }
}
