function Get-IntuneRbacRole {
    <#
    .SYNOPSIS
        List or retrieve Intune RBAC role definitions.

    .DESCRIPTION
        Returns role definitions from /deviceManagement/roleDefinitions.
        Use -Id to retrieve a single role with its full resource action permissions.
        Use -BuiltIn or -Custom to filter to Microsoft-defined or tenant-defined roles.

    .PARAMETER Id
        Role name or GUID. Returns a single role with full permission detail.

    .PARAMETER BuiltIn
        Return only built-in (Microsoft-defined) roles.

    .PARAMETER Custom
        Return only custom (tenant-defined) roles.

    .EXAMPLE
        Get-IntuneRbacRole

    .EXAMPLE
        Get-IntuneRbacRole -BuiltIn

    .EXAMPLE
        Get-IntuneRbacRole -Custom

    .EXAMPLE
        Get-IntuneRbacRole -Id 'Help Desk Operator'

    .OUTPUTS
        PSCustomObject: Id, Name, Description, IsBuiltIn, Permissions.
        When -Id is used, also includes ResourceActions array with full permission detail.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Id,
        [switch]$BuiltIn,
        [switch]$Custom
    )

    if ($Id) {
        $resolved = Resolve-IaRbacRoleId -Value $Id
        $role     = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/roleDefinitions/$resolved")
        return ConvertTo-IaRbacRoleObject -Role $role -IncludeResourceActions
    }

    $uri = 'deviceManagement/roleDefinitions'
    if ($BuiltIn -and -not $Custom) {
        $uri = "${uri}?`$filter=isBuiltIn eq true"
    } elseif ($Custom -and -not $BuiltIn) {
        $uri = "${uri}?`$filter=isBuiltIn eq false"
    }

    $all = Get-IaCollection (Resolve-IaUri $uri)
    foreach ($r in $all) {
        ConvertTo-IaRbacRoleObject -Role $r
    }
}

function Resolve-IaRbacRoleId {
    param([string]$Value)
    if (Test-IaGuid $Value) { return $Value }
    $encoded = ConvertTo-IaODataValue $Value
    $results = Get-IaCollection (Resolve-IaUri "deviceManagement/roleDefinitions?`$filter=displayName eq '$encoded'&`$select=id,displayName")
    if ($results.Count -eq 0) { throw "No RBAC role found matching '$Value'." }
    if ($results.Count -gt 1) { throw "Multiple RBAC roles match '$Value'. Provide a unique id." }
    $results[0].id
}

function ConvertTo-IaRbacRoleObject {
    param($Role, [switch]$IncludeResourceActions)

    $permissionCount = 0
    if ($Role.rolePermissions) {
        foreach ($perm in $Role.rolePermissions) {
            if ($perm.resourceActions) {
                $permissionCount += $perm.resourceActions.Count
            }
        }
    }

    $obj = [pscustomobject][ordered]@{
        Id          = $Role.id
        Name        = $Role.displayName
        Description = $Role.description
        IsBuiltIn   = $Role.isBuiltIn
        Permissions = $permissionCount
    }
    # NOTE: the Intune roleDefinition entity has no createdDateTime / lastModifiedDateTime
    # (verified against the beta CSDL) — there is nothing to surface here.

    if ($IncludeResourceActions) {
        $resourceActions = [System.Collections.Generic.List[object]]::new()
        foreach ($perm in $Role.rolePermissions) {
            foreach ($ra in $perm.resourceActions) {
                $resourceActions.Add([pscustomobject][ordered]@{
                    AllowedActions = $ra.allowedResourceActions
                    NotAllowed     = $ra.notAllowedResourceActions
                })
            }
        }
        $obj | Add-Member -NotePropertyName ResourceActions -NotePropertyValue $resourceActions.ToArray()
    }

    $obj
}
