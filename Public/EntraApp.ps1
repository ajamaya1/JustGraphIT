function Get-EntraAppRegistration {
    <#
    .SYNOPSIS
        App registrations with secret/cert expiry. Beta GET /beta/applications.
    .DESCRIPTION
        One row per app with the soonest-expiring credential and how many days remain
        (negative = already expired). -Raw returns the full application object.
    #>
    [CmdletBinding()]
    param([Parameter(Position = 0)][string]$Name, [int]$Top = 200, [switch]$Raw)
    $sel = 'id,appId,displayName,signInAudience,createdDateTime,publisherDomain,passwordCredentials,keyCredentials,tags'
    if ($Name) {
        $f = "displayName eq '$($Name.Replace("'","''"))'"
        $apps = @(Get-IaCollection (Resolve-IaUri -Path "applications?`$filter=$([uri]::EscapeDataString($f))&`$select=$sel"))
    } else {
        $apps = @(Get-IaCollection (Resolve-IaUri -Path "applications?`$select=$sel&`$top=$Top"))
    }
    if ($Raw) { return $apps }
    $now = (Get-Date).ToUniversalTime()
    @($apps | ForEach-Object {
        $creds = @($_.passwordCredentials) + @($_.keyCredentials)
        $next  = $null
        foreach ($c in $creds) { if ($c.endDateTime) { $d = [datetime]$c.endDateTime; if (-not $next -or $d -lt $next) { $next = $d } } }
        $days = if ($next) { [int][math]::Floor(($next.ToUniversalTime() - $now).TotalDays) } else { $null }
        [pscustomobject][ordered]@{
            DisplayName  = $_.displayName
            AppId        = $_.appId
            SignInAudience = $_.signInAudience
            Secrets      = @($_.passwordCredentials).Count
            Certificates = @($_.keyCredentials).Count
            SoonestExpiry = $next
            DaysToExpiry = $days
            Publisher    = $_.publisherDomain
            Created      = $_.createdDateTime
            Id           = $_.id
        }
    } | Sort-Object DaysToExpiry)
}

function Get-EntraAppCredential {
    <#
    .SYNOPSIS
        List an app registration's secrets and certificates with expiry. Beta /beta/applications.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Name)
    $f   = "displayName eq '$($Name.Replace("'","''"))'"
    $app = @(Get-IaCollection (Resolve-IaUri -Path "applications?`$filter=$([uri]::EscapeDataString($f))&`$select=id,displayName,passwordCredentials,keyCredentials"))
    if (-not $app) { Write-Warning "No app registration named '$Name'."; return }
    $a = $app[0]; $now = (Get-Date).ToUniversalTime()
    $rows = @()
    foreach ($c in @($a.passwordCredentials)) { $rows += [pscustomobject][ordered]@{ Kind = 'Secret'; Name = $c.displayName; Start = $c.startDateTime; Expires = $c.endDateTime; DaysLeft = $(if ($c.endDateTime) { [int][math]::Floor(([datetime]$c.endDateTime).ToUniversalTime().Subtract($now).TotalDays) }); KeyId = $c.keyId } }
    foreach ($c in @($a.keyCredentials))      { $rows += [pscustomobject][ordered]@{ Kind = 'Certificate'; Name = $c.displayName; Start = $c.startDateTime; Expires = $c.endDateTime; DaysLeft = $(if ($c.endDateTime) { [int][math]::Floor(([datetime]$c.endDateTime).ToUniversalTime().Subtract($now).TotalDays) }); KeyId = $c.keyId } }
    @($rows | Sort-Object DaysLeft)
}

function Get-EntraEnterpriseApp {
    <#
    .SYNOPSIS
        Enterprise applications (service principals). Beta GET /beta/servicePrincipals.
    #>
    [CmdletBinding()]
    param([Parameter(Position = 0)][string]$Name, [int]$Top = 200, [switch]$Raw)
    $sel = 'id,appId,displayName,servicePrincipalType,accountEnabled,appRoleAssignmentRequired,signInAudience,homepage,preferredSingleSignOnMode,tags'
    if ($Name) {
        $f = "displayName eq '$($Name.Replace("'","''"))'"
        $sps = @(Get-IaCollection (Resolve-IaUri -Path "servicePrincipals?`$filter=$([uri]::EscapeDataString($f))&`$select=$sel"))
    } else {
        $sps = @(Get-IaCollection (Resolve-IaUri -Path "servicePrincipals?`$select=$sel&`$top=$Top"))
    }
    if ($Raw) { return $sps }
    @($sps | ForEach-Object {
        [pscustomobject][ordered]@{
            DisplayName      = $_.displayName
            AppId            = $_.appId
            Type             = $_.servicePrincipalType
            Enabled          = $_.accountEnabled
            AssignmentRequired = $_.appRoleAssignmentRequired
            SSO              = $_.preferredSingleSignOnMode
            Audience         = $_.signInAudience
            Id               = $_.id
        }
    } | Sort-Object DisplayName)
}

function Get-EntraAppPermission {
    <#
    .SYNOPSIS
        Every API permission an enterprise app (service principal) actually holds —
        delegated (OAuth2 consent) and application (app-role) — with friendly names
        and a High-risk flag. Beta GET /beta/servicePrincipals/{id}/oauth2PermissionGrants
        and /appRoleAssignments.
    .DESCRIPTION
        This is the "what can this app do" report. Delegated rows come from consent
        grants (each scope split out, with admin-vs-user consent); application rows
        come from granted app roles, resolved from the resource SP's appRoles. -Raw
        returns the untouched grant/assignment objects.
    .PARAMETER App
        Enterprise-app display name, appId (client id) or SP object id.
    .OUTPUTS
        PSCustomObject: Type, Resource, Permission, Consent, Risk.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$App, [switch]$Raw)
    $spId = Resolve-EntraServicePrincipalId -App $App
    $grants      = @(Get-IaCollection (Resolve-IaUri -Path "servicePrincipals/$spId/oauth2PermissionGrants"))
    $assignments = @(Get-IaCollection (Resolve-IaUri -Path "servicePrincipals/$spId/appRoleAssignments"))
    if ($Raw) { return [pscustomobject]@{ Delegated = $grants; Application = $assignments } }

    $cache = @{}
    $rows  = @()
    foreach ($g in $grants) {
        $res     = Get-EntraResourceSp -Id $g.resourceId -Cache $cache
        $resName = if ($res) { $res.displayName } else { $g.resourceId }
        foreach ($s in (($g.scope -split '\s+') | Where-Object { $_ })) {
            $rows += [pscustomobject][ordered]@{
                Type       = 'Delegated'
                Resource   = $resName
                Permission = $s
                Consent    = if ($g.consentType -eq 'AllPrincipals') { 'Admin (all users)' } else { 'User' }
                Risk       = if (Test-EntraHighRiskPermission $s) { 'High' } else { '' }
            }
        }
    }
    foreach ($a in $assignments) {
        $res      = Get-EntraResourceSp -Id $a.resourceId -Cache $cache
        $map      = Get-EntraAppRoleMap -ResourceSp $res
        $resolved = $map.ContainsKey([string]$a.appRoleId)
        $name     = if ($resolved) { $map[[string]$a.appRoleId] } else { [string]$a.appRoleId }
        $rows += [pscustomobject][ordered]@{
            Type       = 'Application'
            Resource   = if ($res) { $res.displayName } else { $a.resourceDisplayName }
            Permission = $name
            Consent    = 'Admin'
            # an unresolved appRoleId is surfaced as Unknown, never silently benign
            Risk       = if (Test-EntraHighRiskPermission $name) { 'High' } elseif (-not $resolved) { 'Unknown' } else { '' }
        }
    }
    @($rows | Sort-Object @{ Expression = { switch ($_.Risk) { 'High' { 0 } 'Unknown' { 1 } default { 2 } } } }, Type, Resource, Permission)
}

function Get-EntraRiskyAppPermission {
    <#
    .SYNOPSIS
        Tenant-wide consent audit: every app/service principal granted a high-risk
        Microsoft Graph application permission (Directory.ReadWrite.All, RoleManagement
        .ReadWrite.Directory, full app access, etc.). Beta GET
        /beta/servicePrincipals/{graphSpId}/appRoleAssignedTo.
    .DESCRIPTION
        Reads the app-role grants made ON the Microsoft Graph service principal — one
        efficient paged call surfaces every consenting app. -All lists every Graph
        app-role grant; by default the high-risk ones AND any whose permission can't be
        resolved (shown as Unknown — investigate, never assumed safe) are returned.
    .OUTPUTS
        PSCustomObject: App, Permission, Risk, PrincipalType, AppPrincipalId, GrantId.
    #>
    [CmdletBinding()]
    param([switch]$All, [switch]$Raw)
    $graph = @(Get-IaCollection (Resolve-IaUri -Path "servicePrincipals?`$filter=appId eq '$($script:IaGraphAppId)'&`$select=id,displayName,appRoles"))
    if (-not $graph) { throw 'Could not resolve the Microsoft Graph service principal.' }
    $map        = Get-EntraAppRoleMap -ResourceSp $graph[0]
    $assignedTo = @(Get-IaCollection (Resolve-IaUri -Path "servicePrincipals/$($graph[0].id)/appRoleAssignedTo"))
    if ($Raw) { return $assignedTo }
    $rows = @($assignedTo | ForEach-Object {
        $resolved = $map.ContainsKey([string]$_.appRoleId)
        $name     = if ($resolved) { $map[[string]$_.appRoleId] } else { [string]$_.appRoleId }
        [pscustomobject][ordered]@{
            App            = $_.principalDisplayName
            Permission     = $name
            # never hide an unresolved grant from a security audit — flag it Unknown
            Risk           = if (Test-EntraHighRiskPermission $name) { 'High' } elseif (-not $resolved) { 'Unknown' } else { '' }
            PrincipalType  = $_.principalType
            AppPrincipalId = $_.principalId
            GrantId        = $_.id
        }
    })
    if (-not $All) { $rows = @($rows | Where-Object { $_.Risk -in 'High', 'Unknown' }) }
    @($rows | Sort-Object @{ Expression = { switch ($_.Risk) { 'High' { 0 } 'Unknown' { 1 } default { 2 } } } }, App, Permission)
}

function Remove-EntraAppRoleAssignment {
    <#
    .SYNOPSIS
        Revoke an application permission (app-role grant) from a service principal.
        Beta DELETE /beta/servicePrincipals/{spId}/appRoleAssignments/{id}.
    .DESCRIPTION
        The companion to Get-EntraAppPermission / Get-EntraRiskyAppPermission — pass the
        client SP (the app that HOLDS the permission) and the assignment id from those
        reports to take the grant away. High-impact, so it confirms.
    .PARAMETER ServicePrincipal
        The client service principal that holds the permission (object id, appId or name).
    .PARAMETER AssignmentId
        The appRoleAssignment id (the GrantId column from the consent reports).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$ServicePrincipal,
        # reject path/query metacharacters so the id can't reshape the DELETE URL
        [Parameter(Mandatory, Position = 1)][ValidatePattern('^[^/?#\s]+$')][string]$AssignmentId
    )
    $spId = Resolve-EntraServicePrincipalId -App $ServicePrincipal
    if ($PSCmdlet.ShouldProcess("$ServicePrincipal ($AssignmentId)", 'Revoke application permission')) {
        Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri -Path "servicePrincipals/$spId/appRoleAssignments/$AssignmentId") | Out-Null
        [pscustomobject]@{ ServicePrincipal = $ServicePrincipal; AssignmentId = $AssignmentId; Revoked = $true }
    }
}

function Remove-EntraOAuth2Grant {
    <#
    .SYNOPSIS
        Revoke a delegated permission grant (OAuth2 consent). Beta DELETE
        /beta/oauth2PermissionGrants/{id}.
    .DESCRIPTION
        Removes a delegated consent grant by its id (the Delegated grants returned by
        Get-EntraAppPermission -Raw). Revokes the whole grant — every scope it carries.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory, Position = 0)][ValidatePattern('^[^/?#\s]+$')][string]$GrantId)
    if ($PSCmdlet.ShouldProcess($GrantId, 'Revoke delegated consent grant')) {
        Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri -Path "oauth2PermissionGrants/$GrantId") | Out-Null
        [pscustomobject]@{ GrantId = $GrantId; Revoked = $true }
    }
}

function Get-EntraManagedIdentity {
    <#
    .SYNOPSIS
        Managed identities (system- and user-assigned). Beta GET /beta/servicePrincipals
        filtered to servicePrincipalType eq 'ManagedIdentity'.
    #>
    [CmdletBinding()]
    param([switch]$Raw)
    $f   = "servicePrincipalType eq 'ManagedIdentity'"
    $sel = 'id,appId,displayName,accountEnabled,alternativeNames,servicePrincipalType'
    $sps = @(Get-IaCollection (Resolve-IaUri -Path "servicePrincipals?`$filter=$([uri]::EscapeDataString($f))&`$select=$sel&`$top=500"))
    if ($Raw) { return $sps }
    @($sps | ForEach-Object {
        [pscustomobject][ordered]@{
            DisplayName = $_.displayName
            AppId       = $_.appId
            Enabled     = $_.accountEnabled
            # alternativeNames carries the Azure resource id for user-assigned identities
            ResourceId  = (@($_.alternativeNames) -join '; ')
            Id          = $_.id
        }
    } | Sort-Object DisplayName)
}
