function Set-IntuneCloudPCProvisioningPolicy {
    <#
    .SYNOPSIS
        Update an existing Windows 365 provisioning policy.

    .DESCRIPTION
        Resolves the policy by name or id and PATCHes only the properties that
        were explicitly provided. Unspecified parameters are left unchanged.

    .PARAMETER Policy
        Display name or id of the provisioning policy to update.

    .PARAMETER Name
        New display name for the policy.

    .PARAMETER Description
        New description.

    .PARAMETER ImageId
        New image id.

    .PARAMETER ImageType
        New image type ('gallery' or 'custom').

    .PARAMETER Region
        New Azure region.

    .PARAMETER DomainJoinType
        New join type.

    .PARAMETER OnPremisesConnectionId
        New on-premises connection id.

    .EXAMPLE
        Set-IntuneCloudPCProvisioningPolicy -Policy "Corp W365 Policy" -Region "eastus2"

    .OUTPUTS
        PSCustomObject: Name, JoinType, ImageType, ImageName, Region, WindowsSettings, Id.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$Policy,
        [string]$Name,
        [string]$Description,
        [string]$ImageId,
        [ValidateSet('gallery', 'custom')][string]$ImageType,
        [string]$Region,
        [ValidateSet('azureADJoin', 'hybridAzureADJoin')][string]$DomainJoinType,
        [string]$OnPremisesConnectionId
    )

    $id = Resolve-IaProvisioningPolicyId -Value $Policy

    $body = @{}
    if ($PSBoundParameters.ContainsKey('Name'))                    { $body.displayName            = $Name }
    if ($PSBoundParameters.ContainsKey('Description'))             { $body.description            = $Description }
    if ($PSBoundParameters.ContainsKey('ImageId'))                 { $body.imageId                = $ImageId }
    if ($PSBoundParameters.ContainsKey('ImageType'))               { $body.imageType              = $ImageType }
    if ($PSBoundParameters.ContainsKey('Region'))                  { $body.region                 = $Region }
    if ($PSBoundParameters.ContainsKey('DomainJoinType'))          { $body.domainJoinType         = $DomainJoinType }
    if ($PSBoundParameters.ContainsKey('OnPremisesConnectionId'))  { $body.onPremisesConnectionId = $OnPremisesConnectionId }

    if ($body.Count -eq 0) {
        Write-Warning 'No properties specified; nothing to update.'
        return
    }

    if (-not $PSCmdlet.ShouldProcess($Policy, 'Set-IntuneCloudPCProvisioningPolicy')) { return }

    $uri  = Resolve-IaUri (Get-IaW365Path "provisioningPolicies/$id")
    $resp = Invoke-IaRequest -Method PATCH -Uri $uri -Body $body

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
