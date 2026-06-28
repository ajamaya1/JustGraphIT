function Get-IntuneConditionalAccess {
    <#
    .SYNOPSIS
        List Azure AD Conditional Access policies.

    .DESCRIPTION
        Returns Conditional Access policies from the identity/conditionalAccess/policies
        endpoint (v1.0). Requires the Policy.Read.All permission.

        Outputs a summary of conditions (platforms, users, apps) and grant controls
        for each policy so you can see at a glance which policies apply to Intune-enrolled
        devices (e.g. require compliant device, require Intune enrollment).

    .PARAMETER Id
        Policy display name or GUID. Returns a single policy.

    .PARAMETER EnabledOnly
        Only return policies with state 'enabled'.

    .PARAMETER RequireCompliantDevice
        Only return policies that require a compliant device as a grant control.

    .EXAMPLE
        Get-IntuneConditionalAccess

    .EXAMPLE
        Get-IntuneConditionalAccess -EnabledOnly

    .EXAMPLE
        Get-IntuneConditionalAccess -RequireCompliantDevice

    .OUTPUTS
        PSCustomObject: Id, DisplayName, State, UserScope, AppScope, PlatformScope,
        GrantControls, SessionControls, Created, Modified.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Id,
        [switch]$EnabledOnly,
        [switch]$RequireCompliantDevice
    )

    if ($Id) {
        if (Test-IaGuid $Id) {
            $policy = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "identity/conditionalAccess/policies/$Id" -V1)
        } else {
            $encoded = ConvertTo-IaODataValue $Id
            $all     = Get-IaCollection (Resolve-IaUri "identity/conditionalAccess/policies?`$filter=displayName eq '$encoded'" -V1)
            $policy  = $all | Select-Object -First 1
            if (-not $policy) { throw "No Conditional Access policy found matching '$Id'." }
        }
        return ConvertTo-IaCaPolicy -Policy $policy
    }

    $query = 'identity/conditionalAccess/policies'
    if ($EnabledOnly) { $query += "?`$filter=state eq 'enabled'" }

    $all = Get-IaCollection (Resolve-IaUri $query -V1)

    foreach ($p in $all) {
        $obj = ConvertTo-IaCaPolicy -Policy $p
        if ($RequireCompliantDevice) {
            if ($obj.GrantControls -notmatch 'compliantDevice') { continue }
        }
        $obj
    }
}

function ConvertTo-IaCaPolicy {
    param($Policy)

    $cond  = $Policy.conditions
    $grant = $Policy.grantControls

    $userScope = if ($cond.users.includeUsers -contains 'All') { 'All users' }
                 elseif ($cond.users.includeGroups) { "$($cond.users.includeGroups.Count) group(s)" }
                 else { 'Specific users/roles' }

    $appScope = if ($cond.applications.includeApplications -contains 'All') { 'All apps' }
                elseif ($cond.applications.includeApplications) { "$($cond.applications.includeApplications.Count) app(s)" }
                else { 'None specified' }

    $platformScope = if ($cond.platforms.includePlatforms) { $cond.platforms.includePlatforms -join ', ' }
                     else { 'Any platform' }

    $grantSummary = if ($grant.builtInControls) { $grant.builtInControls -join ', ' } else { 'None' }

    [pscustomobject][ordered]@{
        Id               = $Policy.id
        DisplayName      = $Policy.displayName
        State            = $Policy.state
        UserScope        = $userScope
        AppScope         = $appScope
        PlatformScope    = $platformScope
        GrantControls    = $grantSummary
        GrantOperator    = $grant.operator
        SessionControls  = if ($Policy.sessionControls) { ($Policy.sessionControls.PSObject.Properties | Where-Object { $_.Value } | Select-Object -ExpandProperty Name) -join ', ' } else { $null }
        Created          = $Policy.createdDateTime
        Modified         = $Policy.modifiedDateTime
    }
}
