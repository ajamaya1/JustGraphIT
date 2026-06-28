function Get-IntunePatchReport {
    <#
    .SYNOPSIS
        Windows patch (update) status across the fleet — quality updates (monthly
        cumulative / security) and feature updates (OS version) — pulled from the
        official Intune report export API.

    .DESCRIPTION
        Runs the Intune reports QualityUpdateDeviceStatusByPolicy and
        FeatureUpdateDeviceState through deviceManagement/reports/exportJobs, then
        normalizes each per-device row to a common shape:

            UpdateType, Device, User, Policy, State, Status, Substatus, Detail, LastEvent

        State is the report's AggregateState (e.g. Success / Error / InProgress /
        Cancelled / Pending). For feature updates Detail carries the target
        FeatureUpdateVersion; for quality updates it carries the latest alert
        message. Use -Summary for per-state counts, or -Raw to get the export rows
        unchanged (columns exactly as Graph returns them) when you need a field
        this cmdlet doesn't surface.

        These are asynchronous, server-side reports: on a large tenant each one
        can take from ~30s to a few minutes (the -TimeoutSec cap is per report).

        Permission: DeviceManagementConfiguration.Read.All (report export).

    .PARAMETER Type
        Which updates to report: Quality, Feature, or Both (default).

    .PARAMETER State
        Only return rows whose AggregateState matches (e.g. Error, Success).

    .PARAMETER Summary
        Return per-(UpdateType, State) device counts instead of per-device rows.

    .PARAMETER Raw
        Return the export rows unchanged (no normalization), each tagged with an
        UpdateType column.

    .PARAMETER TimeoutSec
        Per-report async timeout in seconds (default 300).

    .EXAMPLE
        Get-IntunePatchReport -Type Quality -State Error

        Every device whose latest quality (security) update failed.

    .EXAMPLE
        Get-IntunePatchReport -Summary

        Quality + feature roll-up: how many devices Success / Error / InProgress / …

    .EXAMPLE
        Get-IntunePatchReport -Type Feature | Where-Object State -ne 'Success'

        Devices not yet on their target feature-update version.

    .OUTPUTS
        PSCustomObject: UpdateType, Device, User, Policy, State, Status, Substatus,
        Detail, LastEvent  (or counts with -Summary, or raw rows with -Raw).

    .LINK
        Export-IntuneReport
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Quality', 'Feature', 'Both')][string]$Type = 'Both',
        [string]$State,
        [switch]$Summary,
        [switch]$Raw,
        [int]$TimeoutSec = 300
    )

    # First populated value among candidate column names (the export schemas vary
    # slightly by tenant/version, so probe a few aliases rather than hard-coding).
    $firstProp = {
        param($Row, [string[]]$Names)
        foreach ($n in $Names) {
            $p = $Row.PSObject.Properties[$n]
            if ($p -and $null -ne $p.Value -and "$($p.Value)" -ne '') { return $p.Value }
        }
        $null
    }

    $jobs = @()
    if ($Type -in 'Quality', 'Both') { $jobs += @{ Kind = 'Quality'; Report = 'QualityUpdateDeviceStatusByPolicy' } }
    if ($Type -in 'Feature', 'Both') { $jobs += @{ Kind = 'Feature'; Report = 'FeatureUpdateDeviceState' } }

    $all = foreach ($j in $jobs) {
        $kind = $j.Kind
        $rows = @(Invoke-IaReportExport -ReportName $j.Report -TimeoutSec $TimeoutSec `
            -OnStatus { param($s) Write-Verbose "$($j.Report): $s" })
        foreach ($r in $rows) {
            if ($Raw) {
                [void]($r | Add-Member -NotePropertyName UpdateType -NotePropertyValue $kind -Force)
                $r
                continue
            }
            $detail = if ($kind -eq 'Feature') {
                & $firstProp $r @('FeatureUpdateVersion', 'TargetVersion', 'LatestAlertMessage')
            } else {
                & $firstProp $r @('LatestAlertMessage', 'KBNumber', 'CurrentDeviceUpdateSubstatus')
            }
            [pscustomobject][ordered]@{
                UpdateType = $kind
                Device     = & $firstProp $r @('DeviceName', 'Device')
                User       = & $firstProp $r @('UPN', 'UserPrincipalName', 'UserName')
                Policy     = & $firstProp $r @('PolicyName', 'PolicyId')
                State      = & $firstProp $r @('AggregateState', 'UpdateState', 'State')
                Status     = & $firstProp $r @('CurrentDeviceUpdateStatus', 'UpdateStatus')
                Substatus  = & $firstProp $r @('CurrentDeviceUpdateSubstatus', 'UpdateSubstatus')
                Detail     = $detail
                LastEvent  = & $firstProp $r @('EventDateTimeUTC', 'LastUpdateStatusEventDateTimeUTC', 'LastWUScanTimeUTC')
            }
        }
    }
    $all = @($all)

    if ($Raw) { return $all }

    if ($State) { $all = @($all | Where-Object { "$($_.State)" -eq $State }) }

    if ($Summary) {
        return @($all | Group-Object UpdateType, State | ForEach-Object {
            $parts = $_.Name -split ',\s*', 2
            [pscustomobject][ordered]@{
                UpdateType = $parts[0]
                State      = if ($parts.Count -gt 1 -and "$($parts[1])" -ne '') { $parts[1] } else { '(unknown)' }
                Devices    = $_.Count
            }
        } | Sort-Object UpdateType, State)
    }

    $all
}
