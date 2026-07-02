function Get-IntuneConnectorHealth {
    <#
    .SYNOPSIS
        Health and expiry of the tenant's enrollment connectors and tokens — the
        Apple MDM push certificate, VPP and DEP tokens, Managed Google Play binding
        and NDES certificate connectors. Read-only.

    .DESCRIPTION
        These are the silent killers: an expired Apple MDM push certificate stops
        iOS/macOS management tenant-wide, an expired VPP or DEP token stalls app
        licensing and Automated Device Enrollment, and a dead NDES connector stops
        certificate issuance. None of them shout before they die — this surfaces
        them all as one table.

        Status per row: OK, Warn (expiring within -WarnDays or degraded sync),
        Fail (expired / invalid / inactive), NotConfigured (feature not in use —
        informational, not a problem), or Error (the probe itself failed, e.g.
        missing permission).

    .PARAMETER WarnDays
        Warn when a certificate/token expires within this many days (default 30;
        anything at or under 7 days, or already expired, is Fail).

    .EXAMPLE
        Get-IntuneConnectorHealth

        The full connector/token table.

    .EXAMPLE
        Get-IntuneConnectorHealth | Where-Object Status -in 'Warn','Fail','Error'

        Only what needs attention — pair with a scheduled run.

    .OUTPUTS
        PSCustomObject: Connector, Name, Status, Expires, DaysLeft, Detail.
    #>
    [CmdletBinding()]
    param([int]$WarnDays = 30)

    $now = (Get-Date).ToUniversalTime()

    function New-IaConnRow {
        param([string]$Connector, [string]$Name, [string]$Status, $Expires, $DaysLeft, [string]$Detail)
        [pscustomobject][ordered]@{
            Connector = $Connector; Name = $Name; Status = $Status
            Expires   = $Expires;   DaysLeft = $DaysLeft; Detail = $Detail
        }
    }

    function Get-IaExpiryStatus {
        param($ExpiresUtc)   # [datetime] or $null
        if ($null -eq $ExpiresUtc) { return @{ Status = 'Warn'; Days = $null; Note = 'no expiry date reported' } }
        $days = [int][math]::Floor($ExpiresUtc.Subtract($now).TotalDays)
        if ($days -lt 0)          { return @{ Status = 'Fail'; Days = $days; Note = "EXPIRED $(-$days)d ago" } }
        if ($days -le 7)          { return @{ Status = 'Fail'; Days = $days; Note = "expires in ${days}d" } }
        if ($days -le $WarnDays)  { return @{ Status = 'Warn'; Days = $days; Note = "expires in ${days}d" } }
        @{ Status = 'OK'; Days = $days; Note = "expires in ${days}d" }
    }

    function Test-IaNotConfigured { param($Err) "$Err" -match '404|Not Found|ResourceNotFound|does not exist' }

    # ── Apple MDM push certificate (tenant-wide iOS/macOS management) ─────────
    try {
        $apns = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri 'deviceManagement/applePushNotificationCertificate')
        if ($apns -and $apns.expirationDateTime) {
            $exp = ConvertTo-IaSafeDateTime $apns.expirationDateTime
            $s = Get-IaExpiryStatus ($exp ? $exp.ToUniversalTime() : $null)
            New-IaConnRow 'Apple MDM push certificate' ($apns.appleIdentifier ?? '(configured)') $s.Status $exp $s.Days "$($s.Note) — expiry BREAKS all iOS/macOS management"
        } else {
            New-IaConnRow 'Apple MDM push certificate' '—' 'NotConfigured' $null $null 'no certificate uploaded (no Apple devices managed)'
        }
    } catch {
        if (Test-IaNotConfigured $_) { New-IaConnRow 'Apple MDM push certificate' '—' 'NotConfigured' $null $null 'not configured' }
        else { New-IaConnRow 'Apple MDM push certificate' '—' 'Error' $null $null "probe failed: $($_.Exception.Message)" }
    }

    # ── Apple VPP tokens (app licensing) ───────────────────────────────────────
    try {
        $vpp = @(Get-IaCollection (Resolve-IaUri 'deviceAppManagement/vppTokens'))
        if (-not $vpp.Count) { New-IaConnRow 'Apple VPP token' '—' 'NotConfigured' $null $null 'no VPP tokens' }
        foreach ($t in $vpp) {
            $exp = ConvertTo-IaSafeDateTime $t.expirationDateTime
            $s = Get-IaExpiryStatus ($exp ? $exp.ToUniversalTime() : $null)
            $status = $s.Status; $note = $s.Note
            if ("$($t.state)" -and $t.state -ne 'valid') { $status = 'Fail'; $note = "state=$($t.state); $note" }
            elseif ("$($t.lastSyncStatus)" -and $t.lastSyncStatus -notin 'completed', 'success') { if ($status -eq 'OK') { $status = 'Warn' }; $note = "lastSync=$($t.lastSyncStatus); $note" }
            New-IaConnRow 'Apple VPP token' ($t.appleId ?? $t.displayName ?? $t.id) $status $exp $s.Days $note
        }
    } catch {
        if (Test-IaNotConfigured $_) { New-IaConnRow 'Apple VPP token' '—' 'NotConfigured' $null $null 'not configured' }
        else { New-IaConnRow 'Apple VPP token' '—' 'Error' $null $null "probe failed: $($_.Exception.Message)" }
    }

    # ── Apple DEP / Automated Device Enrollment tokens ─────────────────────────
    try {
        $dep = @(Get-IaCollection (Resolve-IaUri 'deviceManagement/depOnboardingSettings'))
        if (-not $dep.Count) { New-IaConnRow 'Apple DEP/ADE token' '—' 'NotConfigured' $null $null 'no DEP tokens' }
        foreach ($t in $dep) {
            $exp = ConvertTo-IaSafeDateTime $t.tokenExpirationDateTime
            $s = Get-IaExpiryStatus ($exp ? $exp.ToUniversalTime() : $null)
            New-IaConnRow 'Apple DEP/ADE token' ($t.appleIdentifier ?? $t.tokenName ?? $t.id) $s.Status $exp $s.Days "$($s.Note) — expiry stalls Automated Device Enrollment"
        }
    } catch {
        if (Test-IaNotConfigured $_) { New-IaConnRow 'Apple DEP/ADE token' '—' 'NotConfigured' $null $null 'not configured' }
        else { New-IaConnRow 'Apple DEP/ADE token' '—' 'Error' $null $null "probe failed: $($_.Exception.Message)" }
    }

    # ── Managed Google Play binding ────────────────────────────────────────────
    try {
        $mgp = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri 'deviceManagement/androidManagedStoreAccountEnterpriseSettings')
        if ($mgp -and $mgp.bindStatus -eq 'bound') {
            $status = if ("$($mgp.lastAppSyncStatus)" -and $mgp.lastAppSyncStatus -ne 'success') { 'Warn' } else { 'OK' }
            New-IaConnRow 'Managed Google Play' ($mgp.ownerUserPrincipalName ?? '(bound)') $status $null $null "bindStatus=bound, lastAppSync=$($mgp.lastAppSyncStatus)"
        } else {
            New-IaConnRow 'Managed Google Play' '—' 'NotConfigured' $null $null "bindStatus=$($mgp.bindStatus ?? 'notBound')"
        }
    } catch {
        if (Test-IaNotConfigured $_) { New-IaConnRow 'Managed Google Play' '—' 'NotConfigured' $null $null 'not configured' }
        else { New-IaConnRow 'Managed Google Play' '—' 'Error' $null $null "probe failed: $($_.Exception.Message)" }
    }

    # ── NDES certificate connectors ────────────────────────────────────────────
    try {
        $ndes = @(Get-IaCollection (Resolve-IaUri 'deviceManagement/ndesConnectors'))
        if (-not $ndes.Count) { New-IaConnRow 'NDES connector' '—' 'NotConfigured' $null $null 'no NDES connectors' }
        foreach ($c in $ndes) {
            $last = ConvertTo-IaSafeDateTime $c.lastConnectionDateTime
            $status = if ("$($c.state)" -eq 'active') { 'OK' } else { 'Fail' }
            $ago = if ($last) { "last connection $([int][math]::Floor($now.Subtract($last.ToUniversalTime()).TotalDays))d ago" } else { 'never connected' }
            if ($status -eq 'OK' -and $last -and $now.Subtract($last.ToUniversalTime()).TotalDays -gt 2) { $status = 'Warn' }
            New-IaConnRow 'NDES connector' ($c.displayName ?? $c.id) $status $null $null "state=$($c.state), $ago"
        }
    } catch {
        if (Test-IaNotConfigured $_) { New-IaConnRow 'NDES connector' '—' 'NotConfigured' $null $null 'not configured' }
        else { New-IaConnRow 'NDES connector' '—' 'Error' $null $null "probe failed: $($_.Exception.Message)" }
    }
}
