function New-IntuneCloudPCProvisioningPolicy {
    <#
    .SYNOPSIS
        Create a new Windows 365 provisioning policy.

    .DESCRIPTION
        Builds the policy body from the provided parameters and POSTs to Graph.
        Optionally assigns the new policy to one or more AAD groups immediately.

    .PARAMETER Name
        Display name for the new provisioning policy.

    .PARAMETER ImageId
        Gallery or custom image id to use for provisioning.

    .PARAMETER ImageType
        'gallery' (default) or 'custom'.

    .PARAMETER DomainJoinType
        Join type for provisioned Cloud PCs. Default: 'azureADJoin'.

    .PARAMETER Region
        Azure region for the provisioning policy.

    .PARAMETER Description
        Optional description.

    .PARAMETER WindowsSetting
        Hashtable of Windows settings (e.g. locale). Maps to windowsSettings.

    .PARAMETER OnPremisesConnectionId
        On-premises connection id — required when DomainJoinType is 'hybridAzureADJoin'.

    .PARAMETER GroupIds
        AAD group ids to assign the policy to immediately after creation.

    .EXAMPLE
        New-IntuneCloudPCProvisioningPolicy -Name "Corp W365 Policy" -ImageId "MicrosoftWindowsDesktop_windows-ent-cpc_win11-22h2-ent-cpc-os" -ImageType gallery -GroupIds "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

    .OUTPUTS
        PSCustomObject: Name, JoinType, ImageType, ImageName, Region, WindowsSettings, Id.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ImageId,
        [ValidateSet('gallery', 'custom')][string]$ImageType = 'gallery',
        [ValidateSet('azureADJoin', 'hybridAzureADJoin')][string]$DomainJoinType = 'azureADJoin',
        [string]$Region,
        [string]$Description,
        [hashtable]$WindowsSetting,
        [string]$OnPremisesConnectionId,
        [string[]]$GroupIds
    )

    $body = [ordered]@{
        displayName    = $Name
        imageId        = $ImageId
        imageType      = $ImageType
        domainJoinType = $DomainJoinType
    }
    if ($Description)             { $body.description = $Description }
    if ($Region)                  { $body.region = $Region }
    if ($WindowsSetting)          { $body.windowsSettings = $WindowsSetting }
    if ($OnPremisesConnectionId)  { $body.onPremisesConnectionId = $OnPremisesConnectionId }

    if (-not $PSCmdlet.ShouldProcess($Name, 'New-IntuneCloudPCProvisioningPolicy')) { return }

    $base  = Get-IaW365Path 'provisioningPolicies'
    $resp  = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri $base) -Body $body
    $newId = $resp.id

    if ($GroupIds) {
        $assignments = @($GroupIds | ForEach-Object {
            @{
                target = @{
                    '@odata.type' = '#microsoft.graph.cloudPcManagementGroupAssignmentTarget'
                    groupId       = $_
                }
            }
        })
        $assignUri = Resolve-IaUri "$base/$newId/assign"
        Invoke-IaRequest -Method POST -Uri $assignUri -Body @{ assignments = $assignments } | Out-Null
    }

    [pscustomobject][ordered]@{
        Name            = $resp.displayName
        JoinType        = $resp.domainJoinType
        ImageType       = $resp.imageType
        ImageName       = $resp.imageDisplayName
        Region          = $resp.region
        WindowsSettings = $resp.windowsSettings
        Id              = $resp.id
    }
}
