function Export-IntuneHealthReport {
    <#
    .SYNOPSIS
        One self-contained HTML page with the tenant's health verdicts, KPIs, top
        offenders, expiring credentials and connector status — the report you
        attach to the Monday email.

    .DESCRIPTION
        Runs the same probes as the TUI Tenant overview (device inventory once,
        the nine-point health check, expiring credentials, connector health) and
        renders them as a single portable HTML file: no external assets, no
        JavaScript, safe to email. Sections that cannot load (permission/licence)
        are shown as "unavailable" rather than breaking the report.

        Read-only against the tenant. Secret-bearing data (key values, passwords)
        is never queried, so the file is safe to share.

    .PARAMETER Path
        Output file (default intune-health-<yyyyMMdd-HHmm>.html in the current
        directory).

    .PARAMETER StaleDays
        Stale-device threshold passed to the health check (default 30).

    .PARAMETER SecretWindowDays
        Credential-expiry window (default 30).

    .PARAMETER TopOffenders
        How many devices to list per problem table (default 15).

    .EXAMPLE
        Export-IntuneHealthReport

        Writes the report and returns its path.

    .EXAMPLE
        Export-IntuneHealthReport -Path .\weekly-health.html -SecretWindowDays 60

    .OUTPUTS
        The report file path.
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [int]$StaleDays = 30,
        [int]$SecretWindowDays = 30,
        [ValidateRange(1, 200)][int]$TopOffenders = 15
    )

    if (-not $Path) { $Path = Join-Path (Get-Location) ("intune-health-{0:yyyyMMdd-HHmm}.html" -f (Get-Date)) }

    # One fetch per data set — the health check reuses these instead of re-sweeping.
    # Assign INSIDE try: `$x = try { @(...) }` captures the block's pipeline output,
    # so an empty result would unroll to AutomationNull and read as "probe failed".
    $devs = $null; $creds = $null; $conn = $null
    try { $devs  = @(Get-IntuneDeviceInventory) } catch { }
    try { $creds = @(Get-EntraExpiringSecret -Days $SecretWindowDays -IncludeExpired) } catch { }
    try { $conn  = @(Get-IntuneConnectorHealth) } catch { }
    $hcp = @{ StaleDays = $StaleDays; SecretWindowDays = $SecretWindowDays }
    if ($null -ne $devs)  { $hcp.DeviceInventory     = $devs }
    if ($null -ne $creds) { $hcp.CredentialInventory = $creds }
    if ($null -ne $conn)  { $hcp.ConnectorInventory  = $conn }
    # Assign inside try, and keep the array wrapper: rows carry their own 'Count'
    # property, so an unrolled scalar row would shadow the collection count.
    $checks = @()
    try { $checks = @(Invoke-IntuneHealthCheck @hcp) } catch { }

    function esc { param($s) [System.Net.WebUtility]::HtmlEncode("$s") }
    function badge { param($status)
        $c = switch ("$status") {
            'Pass' { '#2e9e5b' } 'OK' { '#2e9e5b' }
            'Warn' { '#b98300' }
            'Fail' { '#c8442c' } 'Expired' { '#c8442c' } 'Critical' { '#c8442c' }
            'NotConfigured' { '#7a8494' }
            default { '#7a8494' }
        }
        "<span style=""display:inline-block;padding:1px 10px;border-radius:10px;background:$c;color:#fff;font-size:12px;font-weight:600"">$(esc $status)</span>"
    }
    function table { param($rows, [string[]]$cols)
        if (-not $rows -or -not @($rows).Count) { return '<p class="dim">none</p>' }
        $h = (@($cols | ForEach-Object { "<th>$(esc $_)</th>" }) -join '')
        $b = foreach ($r in @($rows)) {
            '<tr>' + (@($cols | ForEach-Object {
                $v = $r.$_
                if ($_ -in 'Status') { badge $v } else { esc $v }
            } | ForEach-Object { "<td>$_</td>" }) -join '') + '</tr>'
        }
        "<table><thead><tr>$h</tr></thead><tbody>$($b -join '')</tbody></table>"
    }

    # KPI + offender data (device sweep may be unavailable)
    $kpiHtml = '<p class="dim">device inventory unavailable</p>'
    $offHtml = ''
    if ($null -ne $devs) {
        $total = $devs.Count
        $nc    = @($devs | Where-Object { $_.Compliance -eq 'noncompliant' })
        $stale = @($devs | Where-Object { $null -ne $_.DaysSinceSync -and $_.DaysSinceSync -ge $StaleDays })
        $unenc = @($devs | Where-Object { -not $_.Encrypted })
        $pct   = if ($total) { [math]::Round(100 * ($total - $nc.Count) / $total) } else { 100 }
        $kpi   = { param($label, $value) "<div class=""kpi""><div class=""kv"">$(esc $value)</div><div class=""kl"">$(esc $label)</div></div>" }
        $kpiHtml = '<div class="kpis">' +
            (& $kpi 'Devices' $total) + (& $kpi 'Compliant' "$pct%") + (& $kpi 'Noncompliant' $nc.Count) +
            (& $kpi "Stale ${StaleDays}d+" $stale.Count) + (& $kpi 'Unencrypted' $unenc.Count) + '</div>'
        $offCols = 'Device', 'User', 'OS', 'Compliance', 'DaysSinceSync'
        $offHtml =
            "<h2>Noncompliant devices (top $TopOffenders)</h2>" + (table @($nc    | Select-Object -First $TopOffenders) $offCols) +
            "<h2>Stale devices (top $TopOffenders)</h2>"        + (table @($stale | Select-Object -First $TopOffenders) $offCols) +
            "<h2>Unencrypted devices (top $TopOffenders)</h2>"  + (table @($unenc | Select-Object -First $TopOffenders) $offCols)
    }

    $checksHtml = if ($checks.Count) { table $checks @('Status', 'Check', 'Count', 'Detail') } else { '<p class="dim">health checks unavailable</p>' }
    $credsHtml  = if ($null -ne $creds) { table @($creds | Select-Object Type, App, Kind, Name, Expires, DaysLeft, Status) @('Status', 'Type', 'App', 'Kind', 'Name', 'Expires', 'DaysLeft') } else { '<p class="dim">unavailable</p>' }
    $connHtml   = if ($null -ne $conn)  { table $conn @('Status', 'Connector', 'Name', 'Expires', 'DaysLeft', 'Detail') } else { '<p class="dim">unavailable</p>' }

    $fails = @($checks | Where-Object Status -eq 'Fail').Count
    $warns = @($checks | Where-Object Status -in 'Warn', 'Error').Count
    $verdict = if ($fails) { badge 'Fail' } elseif ($warns) { badge 'Warn' } else { badge 'Pass' }

    $html = @"
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Intune tenant health</title><style>
body{font:14px/1.5 'Segoe UI',system-ui,sans-serif;color:#1b2733;margin:0;background:#f2f4f7}
.wrap{max-width:980px;margin:0 auto;padding:28px 22px}
h1{font-size:22px;margin:0 0 2px} h2{font-size:15px;margin:26px 0 8px}
.sub{color:#5b6672;margin:0 0 18px;font-size:13px}
.kpis{display:flex;gap:12px;flex-wrap:wrap;margin:14px 0}
.kpi{background:#fff;border:1px solid #dde2e8;border-radius:8px;padding:10px 18px;min-width:110px}
.kv{font-size:22px;font-weight:700} .kl{font-size:12px;color:#5b6672}
table{border-collapse:collapse;width:100%;background:#fff;border:1px solid #dde2e8;border-radius:8px;overflow:hidden}
th{background:#e9edf2;text-align:left;padding:7px 10px;font-size:12px;text-transform:uppercase;letter-spacing:.4px;color:#42505e}
td{padding:7px 10px;border-top:1px solid #eef1f5;font-size:13px}
.dim{color:#7a8494;font-size:13px}
.foot{color:#7a8494;font-size:12px;margin-top:26px}
</style></head><body><div class="wrap">
<h1>Intune tenant health $verdict</h1>
<p class="sub">Generated $(esc (Get-Date -Format 'yyyy-MM-dd HH:mm')) · JustGraphIT · read-only report, no secret values included</p>
$kpiHtml
<h2>Health checks</h2>
$checksHtml
<h2>Expiring app credentials (${SecretWindowDays}d window, incl. expired)</h2>
$credsHtml
<h2>Enrollment connectors &amp; tokens</h2>
$connHtml
$offHtml
<p class="foot">JustGraphIT · Export-IntuneHealthReport · data live from Microsoft Graph (beta) at generation time.</p>
</div></body></html>
"@

    Set-Content -Path $Path -Value $html -Encoding utf8NoBOM
    Write-Verbose "Wrote health report: $Path"
    $Path
}
