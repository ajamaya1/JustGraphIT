function Get-IntuneCloudPCServicePlan {
    <#
    .SYNOPSIS
        List Windows 365 service plans (Cloud PC SKUs).

    .DESCRIPTION
        Returns available Cloud PC service plans with their hardware specs.
        Filter by plan type (enterprise or business) using -Type.

    .PARAMETER Type
        Filter by plan type: 'enterprise', 'business', or 'all' (default).

    .EXAMPLE
        Get-IntuneCloudPCServicePlan -Type enterprise

        All enterprise Cloud PC SKUs.

    .EXAMPLE
        Get-IntuneCloudPCServicePlan | Sort-Object RAM, Storage

        All plans sorted by spec.

    .OUTPUTS
        PSCustomObject: Name, Type, RAM, Storage, vCPU, SupportedOS, Id.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('enterprise', 'business', 'all')][string]$Type = 'all'
    )

    $items = Get-IaCollection (Get-IaW365Path 'servicePlans')

    foreach ($sp in $items) {
        if ($Type -ne 'all' -and $sp.type -ne $Type) { continue }
        [pscustomobject][ordered]@{
            Name        = $sp.displayName
            Type        = $sp.type
            RAM         = $sp.ramInGB
            Storage     = $sp.storageInGB
            vCPU        = $sp.vCpuCount
            SupportedOS = $sp.supportedSolution
            Id          = $sp.id
        }
    }
}
