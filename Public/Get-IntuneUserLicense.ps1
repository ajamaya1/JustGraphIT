function Get-IntuneUserLicense {
    <#
    .SYNOPSIS
        List the licenses (SKUs) assigned to a user and their service-plan health.

    .DESCRIPTION
        Help-desk "is the caller licensed for what they're trying to use?" view.
        Returns each assigned SKU with a friendly product name, how many of its
        service plans are successfully provisioned, and the raw SKU identifiers.

        A service plan in any state other than 'Success' (e.g. PendingProvisioning,
        Disabled) is surfaced in DisabledPlans so a tech can spot a half-provisioned
        or partially-disabled license at a glance.

        Graph (beta /users):
            GET /beta/users/{id}/licenseDetails
        Permission: User.Read.All (or Directory.Read.All).

    .PARAMETER User
        The user's principal name (UPN) or object id.

    .EXAMPLE
        Get-IntuneUserLicense -User jdoe@contoso.com

    .OUTPUTS
        PSCustomObject: License, SkuPartNumber, Services, DisabledPlans, SkuId.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$User
    )

    $enc     = [uri]::EscapeDataString($User)
    $details = Get-IaCollection "users/$enc/licenseDetails"

    foreach ($l in $details) {
        $plans    = @($l.servicePlans)
        $enabled  = @($plans | Where-Object { $_.provisioningStatus -eq 'Success' })
        $disabled = @($plans | Where-Object { $_.provisioningStatus -ne 'Success' })
        [pscustomobject][ordered]@{
            License       = Get-IaLicenseName -SkuPartNumber $l.skuPartNumber
            SkuPartNumber = $l.skuPartNumber
            Services      = "$($enabled.Count)/$($plans.Count) enabled"
            DisabledPlans = if ($disabled) { (@($disabled | ForEach-Object { $_.servicePlanName }) -join ', ') } else { '' }
            SkuId         = $l.skuId
        }
    }
}
