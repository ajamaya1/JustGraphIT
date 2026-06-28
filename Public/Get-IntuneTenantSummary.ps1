function Get-IntuneTenantSummary {
    <#
    .SYNOPSIS
        Tenant dashboard data: device-health KPIs plus assignment posture.

    .DESCRIPTION
        Combines a managed-device roll-up (total devices, compliance %, per-
        platform compliance, ownership split, stale devices) with a resource /
        assignment summary (how many resources exist per area and how many are
        assigned). Useful as the dashboard backing data or for scheduled KPI
        reporting.

    .PARAMETER StaleDays
        A device counts as stale if it hasn't synced in this many days (def 30).

    .PARAMETER Items
        A pre-loaded inventory (from Get-IaInventory) to compute resource counts
        from, avoiding a second read. Optional.

    .EXAMPLE
        Get-IntuneTenantSummary

        Device health and assignment posture for the whole tenant.

    .EXAMPLE
        (Get-IntuneTenantSummary).ByPlatform

        Per-platform device compliance.

    .OUTPUTS
        PSCustomObject: DeviceCount, CompliantCount, NonCompliantCount, OtherCount,
        CompliancePercent, StaleDays, StaleCount, ByPlatform, ByOwnership,
        ResourceCount, AssignedCount, UnassignedCount, ByArea.
    #>
    [CmdletBinding()]
    param([int]$StaleDays = 30, [object[]]$Items)

    $dev = Get-IaDeviceSummary -StaleDays $StaleDays
    if (-not $Items) { $Items = Get-IaInventory }
    $assigned = @($Items | Where-Object { $_.Assignments.Count -gt 0 })
    $byArea = @($Items | Group-Object Area | ForEach-Object {
            [pscustomobject]@{
                Area     = $_.Name
                Total    = $_.Count
                Assigned = @($_.Group | Where-Object { $_.Assignments.Count -gt 0 }).Count
            }
        } | Sort-Object Area)

    [pscustomobject][ordered]@{
        DeviceCount       = $dev.DeviceCount
        CompliantCount    = $dev.CompliantCount
        NonCompliantCount = $dev.NonCompliantCount
        OtherCount        = $dev.OtherCount
        CompliancePercent = $dev.CompliancePercent
        StaleDays         = $dev.StaleDays
        StaleCount        = $dev.StaleCount
        ByPlatform        = $dev.ByPlatform
        ByOwnership       = $dev.ByOwnership
        ResourceCount     = @($Items).Count
        AssignedCount     = $assigned.Count
        UnassignedCount   = @($Items).Count - $assigned.Count
        ByArea            = $byArea
    }
}
