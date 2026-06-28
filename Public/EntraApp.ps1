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
