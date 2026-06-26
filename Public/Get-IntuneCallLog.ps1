function Get-IntuneCallLog {
    <#
    .SYNOPSIS
        Show the Microsoft Graph calls TIDE has made this session.

    .DESCRIPTION
        Every Graph request flows through one seam that records the method, URL
        (host trimmed), HTTP status, duration in ms, and returned item count.
        This is the data behind the TUI's "graph calls" pane — use it from the
        cmdline to see exactly what the tool is doing (great for debugging,
        learning the Graph endpoints, or proving least-privilege reads).

    .PARAMETER Tail
        Only the most recent N calls.

    .PARAMETER Errors
        Only calls that failed (non-2xx).

    .EXAMPLE
        Get-IntuneAssignment -Type mobileApps | Out-Null
        Get-IntuneCallLog -Tail 10 | Format-Table

        Run something, then see the last 10 Graph calls it made.

    .OUTPUTS
        PSCustomObject: Time, Method, Uri, Status, Ms, Count, Error.

    .LINK
        Clear-IntuneCallLog
    #>
    [CmdletBinding()]
    param([int]$Tail, [switch]$Errors)
    # Assign first, THEN normalise with @() on the variable. Wrapping the call
    # itself — @(Get-IaCallLogEntries) — collapses the (comma-returned) array to a
    # single nested element, so it must not be done.
    $log = Get-IaCallLogEntries
    $log = @($log)
    if ($Errors) { $log = @($log | Where-Object { $_.Status -lt 200 -or $_.Status -ge 300 }) }
    if ($Tail -and $Tail -gt 0) { $log = @($log | Select-Object -Last $Tail) }
    $log
}

