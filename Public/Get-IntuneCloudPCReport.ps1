function Get-IntuneCloudPCReport {
    <#
    .SYNOPSIS
        Retrieve Windows 365 usage and quality reports from Graph.

    .DESCRIPTION
        Posts to the Cloud PC report action endpoints (deviceManagement/virtualEndpoint
        /reports/*), which return a schema and a values matrix. The schema is used as
        column names to normalize each row into a PSCustomObject. Optionally filter the
        results by Cloud PC name or id.

        Report types (each verified against the beta cloudPcReports schema):
          RemoteConnection  — per-session remote connection history
          DailyAggregate    — daily aggregated usage per Cloud PC
          TotalUsage        — total aggregated usage (active hours / connection counts)
          ConnectionQuality — per-session connection quality (round-trip time, region)
          Frontline         — frontline (shared) Cloud PC license utilization
          Inaccessible      — Cloud PCs that failed health checks / can't be connected to

    .PARAMETER Report
        The report to retrieve.

    .PARAMETER CloudPC
        Cloud PC display name or id to filter results client-side (matched against
        any column whose name contains 'CloudPcId' or 'CloudPcName').

    .EXAMPLE
        Get-IntuneCloudPCReport -Report TotalUsage

        Total aggregated usage per Cloud PC — the "how much is each one used / which are
        idle" view.

    .EXAMPLE
        Get-IntuneCloudPCReport -Report DailyAggregate -CloudPC "Alice-W365"

    .OUTPUTS
        PSCustomObject per row, with property names drawn from the report schema.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('RemoteConnection', 'DailyAggregate', 'TotalUsage', 'ConnectionQuality', 'Frontline', 'Inaccessible')]
        [string]$Report,
        [string]$CloudPC
    )

    # action = the bound report function; reportName = the required enum value for the
    # reports that take one (Frontline / Inaccessible). Verified against the beta CSDL:
    # cloudPcReports actions + cloudPcReportName / cloudPCInaccessibleReportName enums.
    $reportMap = @{
        RemoteConnection  = @{ Action = 'getRemoteConnectionHistoricalReports' }
        DailyAggregate    = @{ Action = 'getDailyAggregatedRemoteConnectionReports' }
        TotalUsage        = @{ Action = 'getTotalAggregatedRemoteConnectionReports' }
        ConnectionQuality = @{ Action = 'getConnectionQualityReports' }
        Frontline         = @{ Action = 'getFrontlineReport';            ReportName = 'frontlineLicenseUsageReport' }
        Inaccessible      = @{ Action = 'getInaccessibleCloudPcReports'; ReportName = 'inaccessibleCloudPcReports' }
    }

    $spec = $reportMap[$Report]
    $uri  = Resolve-IaUri (Get-IaW365Path "reports/$($spec.Action)")

    $body = @{
        filter = ''
        select = @()
        top    = 50
        skip   = 0
    }
    if ($spec.ReportName) { $body.reportName = $spec.ReportName }   # required by getFrontlineReport / getInaccessibleCloudPcReports

    # Resolve filter PC id once if supplied.
    $filterPcId = $null
    if ($CloudPC) {
        if (Test-IaGuid $CloudPC) { $filterPcId = $CloudPC }
        else {
            try { $filterPcId = Resolve-IaCloudPCId -Value $CloudPC } catch { }
        }
    }

    $allRows = [System.Collections.Generic.List[object]]::new()
    $pageSize = 50

    do {
        $resp = Invoke-IaRequest -Method POST -Uri $uri -Body $body

        $schema = @()
        if ($resp.PSObject.Properties['schema']) { $schema = @($resp.schema | ForEach-Object { $_.column }) }

        $values = @()
        if ($resp.PSObject.Properties['values']) { $values = @($resp.values) }

        foreach ($row in $values) {
            $obj = [pscustomobject]@{}
            if ($schema.Count -gt 0 -and $row -is [array]) {
                for ($i = 0; $i -lt $schema.Count; $i++) {
                    Add-Member -InputObject $obj -NotePropertyName $schema[$i] -NotePropertyValue ($row[$i])
                }
            } else {
                # Row is already an object (some endpoints return objects, not arrays).
                $obj = $row
            }
            [void]$allRows.Add($obj)
        }

        # Page through if the response returned a full page.
        if ($values.Count -lt $pageSize) { break }
        $body.skip += $pageSize
    } while ($true)

    # Filter by Cloud PC client-side using any id or name column.
    $rows = $allRows.ToArray()
    if ($filterPcId -or $CloudPC) {
        $rows = @($rows | Where-Object {
            $r = $_
            $props = $r.PSObject.Properties
            $idProp   = $props | Where-Object { $_.Name -match 'CloudPcId' }   | Select-Object -First 1
            $nameProp = $props | Where-Object { $_.Name -match 'CloudPcName' } | Select-Object -First 1
            ($filterPcId -and $idProp   -and $r.($idProp.Name)   -eq $filterPcId) -or
            ($CloudPC    -and $nameProp -and $r.($nameProp.Name) -eq $CloudPC)
        })
    }

    $rows
}
