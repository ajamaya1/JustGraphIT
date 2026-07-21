function Get-IaConfigMonitorNameMap {
    <#
    .SYNOPSIS
        Internal: monitorId → displayName map for the tenant's configuration
        monitors. Returns an empty map (never throws) so name-joins degrade
        gracefully when the monitors list cannot be read.
    #>
    $map = @{}
    try {
        foreach ($m in @(Get-IaCollection (Resolve-IaUri 'admin/configurationManagement/configurationMonitors'))) {
            if ($m.id) { $map["$($m.id)"] = $m.displayName }
        }
    } catch { }
    $map
}

function ConvertTo-IaDriftValue {
    <#
    .SYNOPSIS
        Internal: render a driftedProperty value (Edm.Untyped — may be a scalar,
        array or object) as a single display string. Objects/arrays become
        compact JSON so desired-vs-current stays diffable in a table cell.
    #>
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [string] -or $Value -is [bool] -or $Value -is [datetime] -or $Value.GetType().IsPrimitive -or $Value -is [decimal]) { return "$Value" }
    # -InputObject (not pipeline) so a one-element array keeps its brackets
    try { ConvertTo-Json -InputObject $Value -Compress -Depth 6 } catch { "$Value" }
}

function Get-TenantConfigMonitor {
    <#
    .SYNOPSIS
        Microsoft 365 configuration monitors — the tenant's server-side config
        baselines (beta admin/configurationManagement). One row per monitor with
        its baseline size and most recent run. Read-only.

    .DESCRIPTION
        Microsoft's configuration-management service continuously compares live
        tenant configuration against a baseline you define in the M365 admin
        center and records drift — even while nobody is signed in. This lists
        the monitors: what is being watched, how often, whether the last run
        succeeded and how many drifts it found.

        Requires ConfigurationMonitoring.Read.All (in the module's default
        connect scopes). Tenants that have never defined a monitor return an
        empty result — that is not an error.

    .EXAMPLE
        Get-TenantConfigMonitor

        Every monitor with baseline size and last-run outcome.

    .EXAMPLE
        Get-TenantConfigMonitor | Where-Object LastDriftCount -gt 0

        Only the monitors currently reporting drift.

    .OUTPUTS
        PSCustomObject: Monitor, Status, Mode, FrequencyHours, BaselineResources,
        LastRun, LastRunStatus, LastDriftCount, CreatedBy, Modified, Id.
    #>
    [CmdletBinding()]
    param()

    $monitors = $null
    try {
        $monitors = Get-IaCollection (Resolve-IaUri 'admin/configurationManagement/configurationMonitors?$expand=baseline')
        $monitors = @($monitors)
    } catch {
        # Some rings reject $expand — fall back to the plain list + per-monitor baseline.
        $monitors = @(Get-IaCollection (Resolve-IaUri 'admin/configurationManagement/configurationMonitors'))
        $monitors = @($monitors | ForEach-Object {
            $m = $_
            if ($m.id -and -not $m.baseline) {
                try {
                    $b = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "admin/configurationManagement/configurationMonitors/$($m.id)/baseline")
                    $m | Add-Member -NotePropertyName baseline -NotePropertyValue $b -Force
                } catch { }
            }
            $m
        })
    }

    # Most recent run per monitor (one extra call; ascending sort → last write wins).
    $lastRun = @{}
    try {
        $runs = @(Get-IaCollection (Resolve-IaUri 'admin/configurationManagement/configurationMonitoringResults'))
        foreach ($r in ($runs | Sort-Object { ConvertTo-IaSafeDateTime ($_.runCompletionDateTime ?? $_.runInitiationDateTime) })) {
            if ($r.monitorId) { $lastRun["$($r.monitorId)"] = $r }
        }
    } catch { }

    @($monitors | ForEach-Object {
        $r = if ($_.id) { $lastRun["$($_.id)"] } else { $null }
        [pscustomobject][ordered]@{
            Monitor           = $_.displayName
            Status            = $_.status
            Mode              = $_.mode
            FrequencyHours    = $_.monitorRunFrequencyInHours
            BaselineResources = if ($_.baseline -and $null -ne $_.baseline.resources) { @($_.baseline.resources).Count } else { $null }
            LastRun           = ConvertTo-IaSafeDateTime $r.runCompletionDateTime
            LastRunStatus     = $r.runStatus
            LastDriftCount    = $r.driftsCount
            CreatedBy         = $_.createdBy.user.displayName ?? $_.createdBy.application.displayName
            Modified          = ConvertTo-IaSafeDateTime $_.lastModifiedDateTime
            Id                = $_.id
        }
    } | Sort-Object Monitor)
}

function Get-TenantConfigDrift {
    <#
    .SYNOPSIS
        Microsoft-detected configuration drift — live tenant config that no
        longer matches a monitored baseline (beta admin/configurationManagement).
        The "who changed what while nobody was looking" report. Read-only.

    .DESCRIPTION
        One row per drifted resource by default (active drift only), with the
        drifted property names. -Detail expands to one row per property with
        the DESIRED (baseline) and CURRENT (live) values — the diff itself.
        Detection is Microsoft's, continuous and server-side; pair it with the
        module's backup/restore tooling to put things back.

        Requires ConfigurationMonitoring.Read.All. No monitors defined → empty
        result, not an error.

    .PARAMETER Monitor
        Only drift from this monitor — display name (substring, case-insensitive)
        or monitor id.

    .PARAMETER IncludeFixed
        Also return drift Microsoft has observed as fixed (status 'fixed'),
        for a full history rather than the open items.

    .PARAMETER Detail
        One row per drifted property with Desired and Current values.

    .EXAMPLE
        Get-TenantConfigDrift

        Every actively drifted resource across all monitors.

    .EXAMPLE
        Get-TenantConfigDrift -Detail | Export-Csv .\config-drift.csv

        The property-level desired-vs-current diff, as CSV for the change ticket.

    .OUTPUTS
        Summary: PSCustomObject Monitor, Resource, Type, Status, FirstReported, Drifts, Properties.
        Detail:  PSCustomObject Monitor, Resource, Property, Desired, Current, Status, FirstReported.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Monitor,
        [switch]$IncludeFixed,
        [switch]$Detail
    )

    $drifts = Get-IaCollection (Resolve-IaUri 'admin/configurationManagement/configurationDrifts')
    $drifts = @($drifts)
    if (-not $IncludeFixed) { $drifts = @($drifts | Where-Object { "$($_.status)" -ne 'fixed' }) }

    $monMap = Get-IaConfigMonitorNameMap

    if ($Monitor) {
        # Name substring first (unique match), then exact monitor id.
        $hits = @($monMap.GetEnumerator() | Where-Object { "$($_.Value)" -like "*$Monitor*" })
        $mid = if ($hits.Count -eq 1) { $hits[0].Key }
               elseif ($hits.Count -gt 1) { throw "Multiple monitors match '$Monitor': $(@($hits | ForEach-Object Value) -join ', '). Use the id." }
               elseif ($monMap.ContainsKey($Monitor)) { $Monitor }
               else { Write-Warning "No configuration monitor matches '$Monitor'."; return @() }
        $drifts = @($drifts | Where-Object { "$($_.monitorId)" -eq "$mid" })
    }

    if (-not $Detail) {
        return @($drifts | ForEach-Object {
            [pscustomobject][ordered]@{
                Monitor       = $monMap["$($_.monitorId)"] ?? $_.monitorId
                Resource      = $_.baselineResourceDisplayName
                Type          = $_.resourceType
                Status        = $_.status
                FirstReported = ConvertTo-IaSafeDateTime $_.firstReportedDateTime
                Drifts        = @($_.driftedProperties).Count
                Properties    = (@($_.driftedProperties | ForEach-Object propertyName) -join ', ')
            }
        } | Sort-Object Status, Monitor, Resource)
    }

    @(foreach ($d in $drifts) {
        foreach ($p in @($d.driftedProperties)) {
            [pscustomobject][ordered]@{
                Monitor       = $monMap["$($d.monitorId)"] ?? $d.monitorId
                Resource      = $d.baselineResourceDisplayName
                Property      = $p.propertyName
                Desired       = ConvertTo-IaDriftValue $p.desiredValue
                Current       = ConvertTo-IaDriftValue $p.currentValue
                Status        = $d.status
                FirstReported = ConvertTo-IaSafeDateTime $d.firstReportedDateTime
            }
        }
    }) | Sort-Object Monitor, Resource, Property
}

function Get-TenantConfigMonitorResult {
    <#
    .SYNOPSIS
        Run history of the tenant's configuration monitors — when each drift
        scan ran, whether it succeeded, and how many drifts it found. Read-only.

    .DESCRIPTION
        The evidence trail behind Get-TenantConfigDrift: one row per monitoring
        run (beta admin/configurationManagement/configurationMonitoringResults),
        newest first. A run that is failed/partiallySuccessful means the drift
        picture may be incomplete — check Errors.

    .EXAMPLE
        Get-TenantConfigMonitorResult | Select-Object -First 10

        The ten most recent drift-scan runs.

    .OUTPUTS
        PSCustomObject: Monitor, RunStatus, Drifts, Started, Completed, Errors.
    #>
    [CmdletBinding()]
    param()

    $runs = Get-IaCollection (Resolve-IaUri 'admin/configurationManagement/configurationMonitoringResults')
    $runs = @($runs)
    $monMap = Get-IaConfigMonitorNameMap

    @($runs | ForEach-Object {
        [pscustomobject][ordered]@{
            Monitor   = $monMap["$($_.monitorId)"] ?? $_.monitorId
            RunStatus = $_.runStatus
            Drifts    = $_.driftsCount
            Started   = ConvertTo-IaSafeDateTime $_.runInitiationDateTime
            Completed = ConvertTo-IaSafeDateTime $_.runCompletionDateTime
            Errors    = (@($_.errorDetails | ForEach-Object { $_.message ?? "$_" }) -join '; ')
        }
    } | Sort-Object Completed -Descending)
}
