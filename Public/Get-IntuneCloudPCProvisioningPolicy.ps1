function Get-IntuneCloudPCProvisioningPolicy {
    <#
    .SYNOPSIS
        Retrieve Windows 365 provisioning policies.

    .DESCRIPTION
        Without -Policy, returns all provisioning policies. With a GUID, fetches
        the specific policy. With a display name, fetches all and filters locally.
        Use -IncludeAssignments to expand the assignments navigation property.

    .PARAMETER Policy
        Display name or id of a specific provisioning policy. Omit to list all.

    .PARAMETER IncludeAssignments
        Expand and return the assignments for each policy.

    .EXAMPLE
        Get-IntuneCloudPCProvisioningPolicy

        All provisioning policies.

    .EXAMPLE
        Get-IntuneCloudPCProvisioningPolicy -Policy "Corp Windows 365" -IncludeAssignments

    .OUTPUTS
        PSCustomObject: Name, JoinType, ImageType, ImageName, Region,
        WindowsSettings, Id, Assignments (when -IncludeAssignments).
    #>
    [CmdletBinding()]
    param(
        [string]$Policy,
        [switch]$IncludeAssignments
    )

    $expand = if ($IncludeAssignments) { '?$expand=assignments' } else { '' }
    $base   = Get-IaW365Path 'provisioningPolicies'

    function ConvertTo-PolicyObject {
        param([object]$p, [switch]$WithAssignments)
        $obj = [pscustomobject][ordered]@{
            Name           = $p.displayName
            JoinType       = $p.domainJoinType
            ImageType      = $p.imageType
            ImageName      = $p.imageDisplayName
            Region         = $p.region
            WindowsSettings = $p.windowsSettings
            Id             = $p.id
        }
        if ($WithAssignments) {
            Add-Member -InputObject $obj -NotePropertyName 'Assignments' -NotePropertyValue $p.assignments
        }
        $obj
    }

    if (-not $Policy) {
        $items = Get-IaCollection "$base$expand"
        foreach ($p in $items) { ConvertTo-PolicyObject -p $p -WithAssignments:$IncludeAssignments }
        return
    }

    if (Test-IaGuid $Policy) {
        $p = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "$base/$Policy$expand")
        ConvertTo-PolicyObject -p $p -WithAssignments:$IncludeAssignments
        return
    }

    # Name lookup: fetch all and filter locally.
    $items = Get-IaCollection "$base$expand"
    $hits  = @($items | Where-Object { $_.displayName -eq $Policy })
    if ($hits.Count -eq 0) { throw "No provisioning policy named '$Policy' was found." }
    foreach ($p in $hits) { ConvertTo-PolicyObject -p $p -WithAssignments:$IncludeAssignments }
}
