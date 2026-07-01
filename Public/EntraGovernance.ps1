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
        foreach ($c in $creds) { if ($c.endDateTime) { $dt = ConvertTo-IaSafeDateTime $c.endDateTime; if ($dt -and (-not $next -or $dt -lt $next)) { $next = $dt } } }
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
