function Get-EntraExpiringSecret {
    <#
    .SYNOPSIS
        App registrations (and optionally enterprise apps) whose client secrets or
        certificates are expiring soon, or already expired — the most common cause of
        silent app-integration outages. Beta GET /beta/applications + /servicePrincipals.

    .DESCRIPTION
        Scans every application registration's passwordCredentials (client secrets) and
        keyCredentials (certificates), computes days-to-expiry against now (UTC), and
        returns each credential expiring within -Days, soonest first. This is the report
        to run every morning and before any change freeze.

        By default only upcoming expiries (still valid) are returned; add -IncludeExpired
        to also surface credentials that have already lapsed. Add -IncludeServicePrincipals
        to extend the scan to enterprise apps (service principals), which carry their own
        credentials for SAML signing, provisioning, etc.

    .PARAMETER Days
        Include credentials expiring within this many days (default 30).

    .PARAMETER IncludeExpired
        Also include credentials that have already expired (negative DaysLeft).

    .PARAMETER IncludeServicePrincipals
        Also scan enterprise apps (service principals), not just app registrations.

    .PARAMETER App
        Optional: limit the scan to a single app registration (display name, appId or
        object id). Omit to scan the whole tenant.

    .EXAMPLE
        Get-EntraExpiringSecret

        Secrets/certs on app registrations expiring in the next 30 days.

    .EXAMPLE
        Get-EntraExpiringSecret -Days 90 -IncludeExpired -IncludeServicePrincipals

        The full 90-day expiry picture across app registrations AND enterprise apps,
        including anything already lapsed.

    .OUTPUTS
        PSCustomObject: Type, App, AppId, Kind, Name, Expires, DaysLeft, Status, KeyId,
        ObjectId. Status is Expired / Critical (<=7d) / Warning.
    #>
    [CmdletBinding()]
    param(
        [int]$Days = 30,
        [switch]$IncludeExpired,
        [switch]$IncludeServicePrincipals,
        [string]$App
    )

    $sel = 'id,appId,displayName,passwordCredentials,keyCredentials'
    $now = (Get-Date).ToUniversalTime()

    # Build the (object, kind-label) work list.
    $sources = [System.Collections.Generic.List[object]]::new()
    if ($App) {
        $sources.Add([pscustomobject]@{ Type = 'App registration'; Obj = (Get-EntraApplicationObject -App $App) })
    } else {
        foreach ($a in (Get-IaCollection (Resolve-IaUri -Path "applications?`$select=$sel"))) {
            $sources.Add([pscustomobject]@{ Type = 'App registration'; Obj = $a })
        }
        if ($IncludeServicePrincipals) {
            foreach ($s in (Get-IaCollection (Resolve-IaUri -Path "servicePrincipals?`$select=$sel"))) {
                $sources.Add([pscustomobject]@{ Type = 'Enterprise app'; Obj = $s })
            }
        }
    }

    $rows = foreach ($src in $sources) {
        $a = $src.Obj
        foreach ($pair in @(
                @{ Kind = 'Secret';      Creds = $a.passwordCredentials },
                @{ Kind = 'Certificate'; Creds = $a.keyCredentials })) {
            foreach ($c in @($pair.Creds)) {
                $dt = ConvertTo-IaSafeDateTime $c.endDateTime
                if (-not $dt) { continue }
                $daysLeft = [int][math]::Floor($dt.ToUniversalTime().Subtract($now).TotalDays)
                if ($daysLeft -gt $Days) { continue }                       # beyond the window
                if ($daysLeft -lt 0 -and -not $IncludeExpired) { continue } # already expired, not requested
                $status = if ($daysLeft -lt 0) { 'Expired' }
                          elseif ($daysLeft -le 7) { 'Critical' }
                          else { 'Warning' }
                [pscustomobject][ordered]@{
                    Type     = $src.Type
                    App      = $a.displayName
                    AppId    = $a.appId
                    Kind     = $pair.Kind
                    Name     = $c.displayName
                    Expires  = $dt
                    DaysLeft = $daysLeft
                    Status   = $status
                    KeyId    = $c.keyId
                    ObjectId = $a.id
                }
            }
        }
    }
    @($rows | Sort-Object DaysLeft)
}
