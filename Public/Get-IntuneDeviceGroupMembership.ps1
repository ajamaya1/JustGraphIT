function Get-IntuneDeviceGroupMembership {
    <#
    .SYNOPSIS
        List the Entra ID groups an Intune-managed device belongs to (transitive) —
        the groups that drive its policy and app assignments.

    .DESCRIPTION
        Resolves the device's Entra device object, then returns its transitive group
        membership (direct groups plus the groups those belong to). This answers the
        everyday help-desk question "why does this device get policy X?" — match these
        groups against the assignment list (View all / Group lookup).

        Graph:  GET /beta/devices/{id}/transitiveMemberOf/microsoft.graph.group
                     ?$select=id,displayName,membershipRule
        Permission: Directory.Read.All (or Device.Read.All + GroupMember.Read.All).

    .PARAMETER Device
        Device name or Entra device GUID.

    .EXAMPLE
        Get-IntuneDeviceGroupMembership -Device LAPTOP-01

        Show every group LAPTOP-01 is a member of (dynamic groups include their rule).

    .OUTPUTS
        PSCustomObject: GroupName, GroupId, MembershipRule.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Device
    )

    $dev = Resolve-IaDevice -Value $Device
    if (-not $dev.Id) { throw "Could not resolve '$Device' to an Entra device object." }

    $groups = Get-IaCollection -Path "devices/$($dev.Id)/transitiveMemberOf/microsoft.graph.group?`$select=id,displayName,membershipRule"
    foreach ($g in $groups) {
        [pscustomobject][ordered]@{
            GroupName      = $g.displayName
            GroupId        = $g.id
            MembershipRule = $g.membershipRule    # populated for dynamic groups
        }
    }
}
