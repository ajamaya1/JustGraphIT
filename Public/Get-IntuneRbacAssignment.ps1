function Get-IntuneRbacAssignment {
    <#
    .SYNOPSIS
        List Intune RBAC role assignments.

    .DESCRIPTION
        Returns role assignments from /deviceManagement/roleAssignments.
        When -RoleId is supplied (name or GUID), only assignments for that
        specific role definition are returned via the nested navigation path
        deviceManagement/roleDefinitions/{id}/roleAssignments.

    .PARAMETER RoleId
        Role name or GUID. When provided, returns only assignments for
        that role definition.

    .EXAMPLE
        Get-IntuneRbacAssignment

    .EXAMPLE
        Get-IntuneRbacAssignment -RoleId 'Help Desk Operator'

    .EXAMPLE
        Get-IntuneRbacAssignment -RoleId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

    .OUTPUTS
        PSCustomObject: Id, DisplayName, RoleDefinitionId, Members,
        ScopeMembers, ScopeType.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$RoleId
    )

    if ($RoleId) {
        $resolvedRole = Resolve-IaRbacRoleId -Value $RoleId
        $assignments  = Get-IaCollection (Resolve-IaUri "deviceManagement/roleDefinitions/$resolvedRole/roleAssignments")
    } else {
        $assignments = Get-IaCollection (Resolve-IaUri 'deviceManagement/roleAssignments')
    }

    foreach ($a in $assignments) {
        ConvertTo-IaRbacAssignmentObject -Assignment $a
    }
}

function ConvertTo-IaRbacAssignmentObject {
    param($Assignment)

    # members and resourceScopes can come back as arrays of IDs or nested objects
    $members      = @($Assignment.members      | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.id } })
    $scopeMembers = @($Assignment.resourceScopes | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.id } })

    [pscustomobject][ordered]@{
        Id               = $Assignment.id
        DisplayName      = $Assignment.displayName
        RoleDefinitionId = $Assignment.roleDefinitionId
        Members          = $members
        ScopeMembers     = $scopeMembers
        ScopeType        = $Assignment.scopeType
    }
}
