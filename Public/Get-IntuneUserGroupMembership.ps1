function Get-IntuneUserGroupMembership {
    <#
    .SYNOPSIS
        List every Entra group a user belongs to (transitively), with type + rule.

    .DESCRIPTION
        The "why does this user get these policies?" view. Returns the user's full
        transitive group membership — directly assigned groups AND groups inherited
        through nested membership — so a help-desk tech can see exactly which groups
        drive the assignments that land on the user.

        Graph (beta /users):
            GET /beta/users/{id}?$select=id,displayName,userPrincipalName
            GET /beta/users/{id}/transitiveMemberOf/microsoft.graph.group
                ?$select=id,displayName,membershipRule,groupTypes,securityEnabled,mailEnabled
        Permission: GroupMember.Read.All (or Directory.Read.All).

    .PARAMETER User
        The user's principal name (UPN) or object id.

    .EXAMPLE
        Get-IntuneUserGroupMembership -User jdoe@contoso.com

    .OUTPUTS
        PSCustomObject: GroupName, GroupId, Kind, Membership, MembershipRule.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$User
    )

    $enc = [uri]::EscapeDataString($User)
    $u   = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "users/$enc`?`$select=id,displayName,userPrincipalName")
    if (-not $u.id) { throw "Could not resolve '$User' to an Entra user object." }

    $select = 'id,displayName,membershipRule,groupTypes,securityEnabled,mailEnabled'
    $groups = Get-IaCollection "users/$($u.id)/transitiveMemberOf/microsoft.graph.group?`$select=$select"

    foreach ($g in $groups) {
        [void](Add-IaGroupToCache -Group $g)
        $kind = if (@($g.groupTypes) -contains 'Unified') { 'Microsoft 365' }
                elseif ($g.securityEnabled)               { 'Security' }
                elseif ($g.mailEnabled)                   { 'Distribution' }
                else                                      { 'Other' }
        [pscustomobject][ordered]@{
            GroupName      = $g.displayName
            GroupId        = $g.id
            Kind           = $kind
            Membership     = if ($g.membershipRule) { 'dynamic' } else { 'assigned' }
            MembershipRule = $g.membershipRule
        }
    }
}
