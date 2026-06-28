function Get-IntuneCloudPC {
    <#
    .SYNOPSIS
        List Windows 365 Cloud PCs with rich status.

    .DESCRIPTION
        Returns all Cloud PCs in the tenant, optionally filtered by assigned user,
        provisioning status, provisioning policy name, or a result cap.

    .PARAMETER User
        Filter by userPrincipalName (case-insensitive substring match).

    .PARAMETER Status
        Only return Cloud PCs with this provisioning status.

    .PARAMETER ProvisioningPolicy
        Filter by provisioning policy name (exact match).

    .PARAMETER Top
        Limit the number of results returned.

    .EXAMPLE
        Get-IntuneCloudPC -Status provisioned

        All successfully provisioned Cloud PCs.

    .EXAMPLE
        Get-IntuneCloudPC -User jdoe@contoso.com

        Cloud PCs assigned to a specific user.

    .OUTPUTS
        PSCustomObject: CloudPC, Status, User, ServicePlan, ProvisioningPolicy,
        Region, LastLogin, GracePeriodEnd, ManagedDeviceId, AadDeviceId, Id.
    #>
    [CmdletBinding()]
    param(
        [string]$User,
        [ValidateSet(
            'notProvisioned', 'provisioning', 'provisioned', 'upgrading',
            'inGracePeriod', 'deprovisioning', 'failed', 'provisioningFailed',
            'restoreInProgress', 'upgradePending', 'unknownFutureValue'
        )]
        [string[]]$Status,
        [string]$ProvisioningPolicy,
        [int]$Top
    )

    $items = Get-IaCollection (Get-IaW365Path 'cloudPCs')

    $rows = foreach ($pc in $items) {
        if ($User -and $pc.userPrincipalName -notlike "*$User*") { continue }
        if ($Status -and $pc.status -notin $Status) { continue }
        if ($ProvisioningPolicy -and $pc.provisioningPolicyName -ne $ProvisioningPolicy) { continue }

        [pscustomobject][ordered]@{
            CloudPC            = $pc.displayName
            Status             = $pc.status
            User               = $pc.userPrincipalName
            ServicePlan        = $pc.servicePlanName
            ProvisioningPolicy = $pc.provisioningPolicyName
            Region             = $pc.deviceRegionName
            LastLogin          = $pc.lastLoginResult.time
            GracePeriodEnd     = $pc.gracePeriodEndDateTime
            ManagedDeviceId    = $pc.managedDeviceId
            AadDeviceId        = $pc.aadDeviceId
            Id                 = $pc.id
        }
    }

    if ($Top -gt 0) { $rows = @($rows) | Select-Object -First $Top }
    $rows
}
