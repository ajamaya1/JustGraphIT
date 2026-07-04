function Export-IntuneChangeLog {
    <#
    .SYNOPSIS
        Export a receipt of every WRITE this session made to the tenant — the
        POST/PATCH/DELETE entries from the live Graph-call log — as CSV or JSON.

    .DESCRIPTION
        The module records every Graph call it makes (method, path, status, timing)
        in an in-memory session log. This filters that log to mutating verbs and
        writes an audit-friendly change receipt: what was touched, when, and whether
        Graph accepted it. Attach it to a change ticket, or diff two sessions.

        Read-only against the tenant — it exports the local log, nothing else.

    .PARAMETER Path
        Output file. Extension picks the format: .json for JSON, anything else
        (default .csv) for CSV. Defaults to intune-changes-<timestamp>.csv in the
        current directory.

    .PARAMETER IncludeReads
        Include GET calls too — the full session activity, not just writes.

    .PARAMETER PassThru
        Also emit the exported rows to the pipeline.

    .EXAMPLE
        Export-IntuneChangeLog

        Writes intune-changes-<timestamp>.csv with this session's writes.

    .EXAMPLE
        Export-IntuneChangeLog -Path ./ticket-4821.json -PassThru | Format-Table

        JSON receipt for a change ticket, echoed to the console.

    .OUTPUTS
        The export file path (and the rows with -PassThru).
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$IncludeReads,
        [switch]$PassThru
    )

    $log = @(Get-IntuneCallLog)   # entries carry .Full (host-stripped URI incl. query)
    if (-not $IncludeReads) {
        $log = @($log | Where-Object { $_.Method -in 'POST', 'PATCH', 'PUT', 'DELETE' })
    }
    if (-not $log.Count) {
        Write-Warning $(if ($IncludeReads) { 'The session call log is empty.' } else { 'No writes recorded this session — nothing to export.' })
        return
    }

    $rows = @($log | ForEach-Object {
        [pscustomobject][ordered]@{
            Time    = $_.Time
            Method  = $_.Method
            Uri     = $_.Full
            Status  = $_.Status
            Ms      = $_.Ms
            Error   = $_.Error
        }
    })

    if (-not $Path) { $Path = Join-Path (Get-Location) ("intune-changes-{0:yyyyMMdd-HHmmss}.csv" -f (Get-Date)) }
    if ([IO.Path]::GetExtension($Path) -eq '.json') {
        $rows | ConvertTo-Json -Depth 4 | Set-Content -Path $Path -Encoding utf8NoBOM
    } else {
        $rows | Export-Csv -Path $Path -NoTypeInformation -Encoding utf8NoBOM
    }
    Write-Verbose "Wrote $($rows.Count) entr$(if ($rows.Count -eq 1) { 'y' } else { 'ies' }) to $Path"
    $Path
    if ($PassThru) { $rows }
}
