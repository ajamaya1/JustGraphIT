function New-EntraConditionalAccessPolicy {
    <#
    .SYNOPSIS
        Create a Conditional Access policy. Beta POST
        /beta/identity/conditionalAccess/policies.
    .DESCRIPTION
        Builds a CA policy from common knobs (who / which apps / which controls) and
        creates it. Defaults to report-only state so you can validate impact before
        enforcing. For full control pass -BodyObject (a complete conditions/grantControls
        hashtable) and the named parameters are ignored.
    .PARAMETER Name
        Policy display name.
    .PARAMETER State
        enabled, disabled, or enabledForReportingButNotEnforced (default — report-only).
    .PARAMETER IncludeUsers
        'All', 'None', 'GuestsOrExternalUsers', or user object ids (default All).
    .PARAMETER RequireMfa / -RequireCompliantDevice / -RequireHybridJoined / -BlockAccess
        Grant controls. -BlockAccess overrides the others (block wins).
    .EXAMPLE
        New-EntraConditionalAccessPolicy -Name 'MFA for admins' -IncludeGroups $adminGroupId -RequireMfa -State enabled
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [ValidateSet('enabled', 'disabled', 'enabledForReportingButNotEnforced')][string]$State = 'enabledForReportingButNotEnforced',
        [string[]]$IncludeUsers,
        [string[]]$ExcludeUsers,
        [string[]]$IncludeGroups,
        [string[]]$ExcludeGroups,
        [string[]]$IncludeApplications = @('All'),
        [string[]]$ExcludeApplications,
        [string[]]$ClientAppTypes = @('all'),
        [string[]]$IncludePlatforms,
        [string[]]$IncludeLocations,
        [string[]]$ExcludeLocations,
        [switch]$RequireMfa,
        [switch]$RequireCompliantDevice,
        [switch]$RequireHybridJoined,
        [switch]$BlockAccess,
        [ValidateSet('OR', 'AND')][string]$GrantOperator = 'OR',
        [hashtable]$BodyObject
    )
    if ($BodyObject) {
        $body = $BodyObject
        $body.displayName = $Name
    } else {
        # CA unions includeUsers + includeGroups, so DON'T force includeUsers='All'
        # when the operator scoped by group — that would silently hit the whole tenant.
        $incUsers = if ($PSBoundParameters.ContainsKey('IncludeUsers')) { @($IncludeUsers) }
                    elseif ($IncludeGroups) { @('None') }
                    else { @('All') }
        $users = [ordered]@{ includeUsers = $incUsers }
        if ($ExcludeUsers)  { $users.excludeUsers  = @($ExcludeUsers) }
        if ($IncludeGroups) { $users.includeGroups = @($IncludeGroups) }
        if ($ExcludeGroups) { $users.excludeGroups = @($ExcludeGroups) }
        $apps = [ordered]@{ includeApplications = @($IncludeApplications) }
        if ($ExcludeApplications) { $apps.excludeApplications = @($ExcludeApplications) }
        $conditions = [ordered]@{ clientAppTypes = @($ClientAppTypes); applications = $apps; users = $users }
        if ($IncludePlatforms) { $conditions.platforms = @{ includePlatforms = @($IncludePlatforms) } }
        if ($IncludeLocations -or $ExcludeLocations) {
            $loc = [ordered]@{}
            if ($IncludeLocations) { $loc.includeLocations = @($IncludeLocations) }
            if ($ExcludeLocations) { $loc.excludeLocations = @($ExcludeLocations) }
            $conditions.locations = $loc
        }
        $controls = @()
        if ($RequireMfa)             { $controls += 'mfa' }
        if ($RequireCompliantDevice) { $controls += 'compliantDevice' }
        if ($RequireHybridJoined)    { $controls += 'domainJoinedDevice' }
        if ($BlockAccess)            { $controls = @('block') }
        $body = [ordered]@{ displayName = $Name; state = $State; conditions = $conditions }
        if ($controls) { $body.grantControls = [ordered]@{ operator = $GrantOperator; builtInControls = @($controls) } }
        # break-glass guard: an enabled block-all policy with no exclusions locks
        # everyone out — including you. Warn loudly (report-only is the safe default).
        if ($State -eq 'enabled' -and $BlockAccess -and ($incUsers -contains 'All') -and -not ($ExcludeUsers -or $ExcludeGroups)) {
            Write-Warning "This policy BLOCKS all users (including you) with no exclusion. Add -ExcludeUsers/-ExcludeGroups for a break-glass account, or use -State enabledForReportingButNotEnforced first."
        }
    }
    if ($PSCmdlet.ShouldProcess($Name, "Create Conditional Access policy (state=$State)")) {
        $p = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "identity/conditionalAccess/policies") -Body $body
        [pscustomobject]@{ Name = $p.displayName; State = $p.state; Id = $p.id }
    }
}

function Set-EntraConditionalAccessPolicy {
    <#
    .SYNOPSIS
        Update a Conditional Access policy (rename, state, or a deep body change).
        Beta PATCH /beta/identity/conditionalAccess/policies/{id}.
    .DESCRIPTION
        For a simple state change prefer Set-EntraConditionalAccessState. This cmdlet
        also renames and (via -BodyObject) replaces conditions/grantControls wholesale.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Policy,
        [string]$DisplayName,
        [ValidateSet('enabled', 'disabled', 'enabledForReportingButNotEnforced')][string]$State,
        [hashtable]$BodyObject
    )
    $id   = Resolve-EntraCaPolicyId -Policy $Policy
    $body = if ($BodyObject) { $BodyObject } else { [ordered]@{} }
    if ($PSBoundParameters.ContainsKey('DisplayName')) { $body.displayName = $DisplayName }
    if ($PSBoundParameters.ContainsKey('State'))       { $body.state = $State }
    if (-not $body.Count) { Write-Warning 'Nothing to update.'; return }
    if ($PSCmdlet.ShouldProcess($Policy, "Update Conditional Access policy [$(@($body.Keys) -join ', ')]")) {
        Invoke-IaRequest -Method PATCH -Uri (Resolve-IaUri -Path "identity/conditionalAccess/policies/$id") -Body $body | Out-Null
        [pscustomobject]@{ Policy = $Policy; Updated = (@($body.Keys) -join ', ') }
    }
}

function Remove-EntraConditionalAccessPolicy {
    <#
    .SYNOPSIS
        Delete a Conditional Access policy. Beta DELETE
        /beta/identity/conditionalAccess/policies/{id}.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory, Position = 0)][string]$Policy)
    $id = Resolve-EntraCaPolicyId -Policy $Policy
    if ($PSCmdlet.ShouldProcess($Policy, 'Delete Conditional Access policy')) {
        Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri -Path "identity/conditionalAccess/policies/$id") | Out-Null
        [pscustomobject]@{ Policy = $Policy; Deleted = $true }
    }
}

function Get-EntraNamedLocation {
    <#
    .SYNOPSIS
        Conditional Access named locations (IP ranges & country locations). Beta GET
        /beta/identity/conditionalAccess/namedLocations.
    #>
    [CmdletBinding()]
    param([switch]$Raw)
    $rows = @(Get-IaCollection (Resolve-IaUri -Path "identity/conditionalAccess/namedLocations"))
    if ($Raw) { return $rows }
    @($rows | ForEach-Object {
        $kind = ($_.'@odata.type' -replace '#microsoft\.graph\.', '')
        [pscustomobject][ordered]@{
            Name    = $_.displayName
            Kind    = $kind
            Trusted = if ($null -ne $_.isTrusted) { [bool]$_.isTrusted } else { $null }
            Detail  = if ($kind -eq 'ipNamedLocation') { (@($_.ipRanges | ForEach-Object { $_.cidrAddress }) -join ', ') } else { (@($_.countriesAndRegions) -join ', ') }
            Created = $_.createdDateTime
            Id      = $_.id
        }
    } | Sort-Object Name)
}

function New-EntraNamedLocation {
    <#
    .SYNOPSIS
        Create a named location. Beta POST /beta/identity/conditionalAccess/namedLocations.
    .DESCRIPTION
        Pass -IpRange (CIDR, one or more) for an IP named location, or -Country (ISO
        codes) for a country named location.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Ip')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Mandatory, ParameterSetName = 'Ip')][string[]]$IpRange,
        [Parameter(ParameterSetName = 'Ip')][switch]$Trusted,
        [Parameter(Mandatory, ParameterSetName = 'Country')][string[]]$Country
    )
    if ($PSCmdlet.ParameterSetName -eq 'Ip') {
        $body = [ordered]@{
            '@odata.type' = '#microsoft.graph.ipNamedLocation'
            displayName   = $Name
            isTrusted     = [bool]$Trusted
            ipRanges      = @($IpRange | ForEach-Object { @{ '@odata.type' = '#microsoft.graph.iPv4CidrRange'; cidrAddress = $_ } })
        }
    } else {
        $body = [ordered]@{
            '@odata.type'        = '#microsoft.graph.countryNamedLocation'
            displayName          = $Name
            countriesAndRegions  = @($Country)
            includeUnknownCountriesAndRegions = $false
        }
    }
    if ($PSCmdlet.ShouldProcess($Name, "Create named location ($($PSCmdlet.ParameterSetName))")) {
        $r = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "identity/conditionalAccess/namedLocations") -Body $body
        [pscustomobject]@{ Name = $r.displayName; Id = $r.id }
    }
}

function Remove-EntraNamedLocation {
    <#
    .SYNOPSIS
        Delete a named location. Beta DELETE
        /beta/identity/conditionalAccess/namedLocations/{id}.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory, Position = 0)][string]$Location)
    $id = $Location
    if (-not (Test-IaGuid $Location)) {
        $hit = @(Get-EntraNamedLocation | Where-Object { $_.Name -eq $Location })
        if ($hit.Count -ne 1) { throw "Named location '$Location' not found (or ambiguous). Use the id." }
        $id = $hit[0].Id
    }
    if ($PSCmdlet.ShouldProcess($Location, 'Delete named location')) {
        Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri -Path "identity/conditionalAccess/namedLocations/$id") | Out-Null
        [pscustomobject]@{ Location = $Location; Deleted = $true }
    }
}
