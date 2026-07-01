function Invoke-IntuneHealthCheck {
    <#
    .SYNOPSIS
        Headless tenant health check — the "is anything on fire?" morning sweep as
        one pipeable command. Read-only.

    .DESCRIPTION
        Runs six checks and emits one Pass/Warn/Fail row per check: device compliance,
        stale devices, disk encryption, expiring/expired app credentials, users flagged
        at risk by Identity Protection, and Conditional Access coverage. A check that
        cannot run (missing permission / not licensed) reports Status 'Error' with the
        reason instead of aborting the sweep — the remaining checks still run.

        Designed for scheduled use: run it from a runbook or cron with app-only auth
        and alert on anything where Status -ne 'Pass'.

    .PARAMETER StaleDays
        A device counts as stale after this many days without a sync (default 30).

    .PARAMETER MinCompliancePercent
        Compliance percentage below this fails the check (default 90). A value between
        this and 100 warns.

    .PARAMETER SecretWindowDays
        Credential-expiry horizon for the app-secret check (default 30).

    .EXAMPLE
        Invoke-IntuneHealthCheck

        The full sweep, one row per check.

    .EXAMPLE
        Invoke-IntuneHealthCheck | Where-Object Status -ne 'Pass'

        Only the problems — the line to put in a scheduled alert.

    .OUTPUTS
        PSCustomObject: Check, Status (Pass/Warn/Fail/Error), Count, Detail.
    #>
    [CmdletBinding()]
    param(
        [int]$StaleDays = 30,
        [ValidateRange(1, 100)][int]$MinCompliancePercent = 90,
        [int]$SecretWindowDays = 30
    )

    function New-IaCheckRow {
        param([string]$Check, [string]$Status, [int]$Count, [string]$Detail)
        [pscustomobject][ordered]@{ Check = $Check; Status = $Status; Count = $Count; Detail = $Detail }
    }

    # One device sweep feeds the first three checks.
    $devices = $null
    try { $devices = @(Get-IntuneDeviceInventory) } catch { }

    if ($null -ne $devices) {
        $total        = $devices.Count
        $noncompliant = @($devices | Where-Object { $_.Compliance -eq 'noncompliant' })
        $stale        = @($devices | Where-Object { $null -ne $_.DaysSinceSync -and $_.DaysSinceSync -ge $StaleDays })
        $unencrypted  = @($devices | Where-Object { -not $_.Encrypted })

        $pct = if ($total) { [math]::Round(100 * ($total - $noncompliant.Count) / $total) } else { 100 }
        New-IaCheckRow 'Device compliance' $(if ($pct -lt $MinCompliancePercent) { 'Fail' } elseif ($pct -lt 100) { 'Warn' } else { 'Pass' }) `
            $noncompliant.Count "$pct% compliant ($($total - $noncompliant.Count)/$total)$(if ($noncompliant.Count) { ' — noncompliant: ' + (@($noncompliant | Select-Object -First 5 | ForEach-Object Device) -join ', ') + $(if ($noncompliant.Count -gt 5) { '…' }) })"

        New-IaCheckRow "Stale devices (${StaleDays}d+)" $(if ($total -and ($stale.Count / [double]$total) -gt 0.10) { 'Fail' } elseif ($stale.Count) { 'Warn' } else { 'Pass' }) `
            $stale.Count $(if ($stale.Count) { "no sync in ${StaleDays}d: " + (@($stale | Select-Object -First 5 | ForEach-Object Device) -join ', ') + $(if ($stale.Count -gt 5) { '…' }) } else { 'every device has synced recently' })

        New-IaCheckRow 'Disk encryption' $(if ($total -and ($unencrypted.Count / [double]$total) -gt 0.10) { 'Fail' } elseif ($unencrypted.Count) { 'Warn' } else { 'Pass' }) `
            $unencrypted.Count $(if ($unencrypted.Count) { 'unencrypted: ' + (@($unencrypted | Select-Object -First 5 | ForEach-Object Device) -join ', ') + $(if ($unencrypted.Count -gt 5) { '…' }) } else { 'all reporting devices encrypted' })
    } else {
        New-IaCheckRow 'Device compliance' 'Error' 0 'device inventory unavailable (permission / connectivity)'
        New-IaCheckRow "Stale devices (${StaleDays}d+)" 'Error' 0 'device inventory unavailable'
        New-IaCheckRow 'Disk encryption' 'Error' 0 'device inventory unavailable'
    }

    try {
        $creds    = @(Get-EntraExpiringSecret -Days $SecretWindowDays -IncludeExpired)
        $urgent   = @($creds | Where-Object { $_.Status -in 'Expired', 'Critical' })
        New-IaCheckRow "App credentials (${SecretWindowDays}d window)" $(if ($urgent.Count) { 'Fail' } elseif ($creds.Count) { 'Warn' } else { 'Pass' }) `
            $creds.Count $(if ($creds.Count) { "$($urgent.Count) expired/critical, $($creds.Count - $urgent.Count) upcoming — worst: " + (@($creds | Select-Object -First 3 | ForEach-Object { "$($_.App) ($($_.DaysLeft)d)" }) -join ', ') } else { 'no secrets or certificates expiring in the window' })
    } catch {
        New-IaCheckRow "App credentials (${SecretWindowDays}d window)" 'Error' 0 "check failed: $($_.Exception.Message)"
    }

    try {
        $risky = @(Get-EntraRiskyUser -AtRiskOnly)
        New-IaCheckRow 'Risky users (Identity Protection)' $(if ($risky.Count) { 'Fail' } else { 'Pass' }) `
            $risky.Count $(if ($risky.Count) { 'users at risk — review in Identity Protection' } else { 'no users currently flagged at risk' })
    } catch {
        New-IaCheckRow 'Risky users (Identity Protection)' 'Error' 0 "check failed (needs Entra ID P2 + IdentityRiskyUser.Read): $($_.Exception.Message)"
    }

    try {
        $ca      = @(Get-EntraConditionalAccessPolicy)
        $enabled = @($ca | Where-Object { $_.State -eq 'enabled' })
        New-IaCheckRow 'Conditional Access coverage' $(if (-not $enabled.Count) { 'Fail' } elseif ($enabled.Count -lt 2) { 'Warn' } else { 'Pass' }) `
            $enabled.Count "$($enabled.Count) enabled / $($ca.Count) total policies"
    } catch {
        New-IaCheckRow 'Conditional Access coverage' 'Error' 0 "check failed: $($_.Exception.Message)"
    }
}
