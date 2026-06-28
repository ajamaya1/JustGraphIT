function Get-EntraExpiringSecret {
    <#
    .SYNOPSIS
        Every app secret / certificate expiring within -Days (or already expired),
        across app registrations and (optionally) service principals. Beta Graph.
    .DESCRIPTION
        Reads passwordCredentials + keyCredentials from /beta/applications (and
        /beta/servicePrincipals with -IncludeServicePrincipals) and returns one row
        per credential, soonest expiry first. The classic "what's about to break"
        report. -IncludeExpired keeps already-expired credentials.
    .PARAMETER Days
        Expiry window in days (default 30).
    .OUTPUTS
        PSCustomObject: Object, Name, AppId, Kind, Credential, Expires, DaysLeft.
    #>
    [CmdletBinding()]
    param([int]$Days = 30, [switch]$IncludeExpired, [switch]$IncludeServicePrincipals)
    $now  = (Get-Date).ToUniversalTime()
    $rows = [System.Collections.Generic.List[object]]::new()

    $emit = {
        param($obj, $label)
        foreach ($pair in @(@{ K = 'Secret'; C = $obj.passwordCredentials }, @{ K = 'Certificate'; C = $obj.keyCredentials })) {
            foreach ($c in @($pair.C)) {
                if (-not $c.endDateTime) { continue }
                $d = [int][math]::Floor(([datetime]$c.endDateTime).ToUniversalTime().Subtract($now).TotalDays)
                if ($d -le $Days -and ($IncludeExpired -or $d -ge 0)) {
                    $rows.Add([pscustomobject][ordered]@{
                        Object     = $label
                        Name       = $obj.displayName
                        AppId      = $obj.appId
                        Kind       = $pair.K
                        Credential = $c.displayName
                        Expires    = $c.endDateTime
                        DaysLeft   = $d
                    })
                }
            }
        }
    }

    $sel = 'id,displayName,appId,passwordCredentials,keyCredentials'
    foreach ($a in @(Get-IaCollection (Resolve-IaUri -Path "applications?`$select=$sel&`$top=500"))) { & $emit $a 'App registration' }
    if ($IncludeServicePrincipals) {
        foreach ($s in @(Get-IaCollection (Resolve-IaUri -Path "servicePrincipals?`$select=$sel&`$top=500"))) { & $emit $s 'Enterprise app' }
    }
    @($rows | Sort-Object DaysLeft)
}

function Get-EntraAppWithoutOwner {
    <#
    .SYNOPSIS
        App registrations (or enterprise apps) that have NO owners — an accountability
        gap. Beta GET with $expand=owners.
    .PARAMETER EnterpriseApps
        Check servicePrincipals instead of applications.
    #>
    [CmdletBinding()]
    param([switch]$EnterpriseApps)
    $path  = if ($EnterpriseApps) { 'servicePrincipals' } else { 'applications' }
    $label = if ($EnterpriseApps) { 'Enterprise app' } else { 'App registration' }
    @(Get-IaCollection (Resolve-IaUri -Path "$path`?`$select=id,displayName,appId,createdDateTime&`$expand=owners(`$select=id)&`$top=500") |
        Where-Object { @($_.owners).Count -eq 0 } |
        ForEach-Object {
            [pscustomobject][ordered]@{ Type = $label; Name = $_.displayName; AppId = $_.appId; Owners = 0; Created = $_.createdDateTime; Id = $_.id }
        } | Sort-Object Name)
}

function Get-EntraAppCredentialSummary {
    <#
    .SYNOPSIS
        Tenant-wide app-credential hygiene: per app the secret/cert counts, soonest
        expiry, and a status (OK / Expiring / Expired / None). Beta /beta/applications.
    #>
    [CmdletBinding()]
    param([int]$WarnDays = 30)
    $now = (Get-Date).ToUniversalTime()
    @(Get-IaCollection (Resolve-IaUri -Path "applications?`$select=id,displayName,appId,passwordCredentials,keyCredentials&`$top=500") | ForEach-Object {
        $creds = @($_.passwordCredentials) + @($_.keyCredentials)
        $next  = $null
        foreach ($c in $creds) { if ($c.endDateTime) { $dt = [datetime]$c.endDateTime; if (-not $next -or $dt -lt $next) { $next = $dt } } }
        $days = if ($next) { [int][math]::Floor($next.ToUniversalTime().Subtract($now).TotalDays) } else { $null }
        $status = if (-not $creds.Count) { 'None' } elseif ($null -eq $days) { 'NoExpiry' } elseif ($days -lt 0) { 'Expired' } elseif ($days -le $WarnDays) { 'Expiring' } else { 'OK' }
        [pscustomobject][ordered]@{
            Name         = $_.displayName
            AppId        = $_.appId
            Secrets      = @($_.passwordCredentials).Count
            Certificates = @($_.keyCredentials).Count
            SoonestExpiry = $next
            DaysLeft     = $days
            Status       = $status
            Id           = $_.id
        }
    } | Sort-Object @{ E = { if ($null -eq $_.DaysLeft) { [int]::MaxValue } else { $_.DaysLeft } } })
}
