function Get-IntuneUserSignIn {
    <#
    .SYNOPSIS
        A user's most recent Entra sign-ins — the "why can't they log in?" view.

    .DESCRIPTION
        Returns the latest interactive sign-ins for a user with the result (success or
        the failure reason + error code), the Conditional Access outcome, and — when a
        sign-in was blocked — the specific CA policy/policies that failed. Also surfaces
        the app, client, IP and the device used, so a tech can spot a blocked legacy
        client, a failing MFA prompt or a CA policy gap at a glance.

        Graph (beta):
            GET /beta/auditLogs/signIns
                ?$filter=userPrincipalName eq '{upn}'&$top={n}&$orderby=createdDateTime desc
        Permission: AuditLog.Read.All + Directory.Read.All. Sign-in logs require an
        Entra ID P1/P2 tenant; without it Graph returns 403 (handled upstream as
        "no permission / not licensed").

        Only the first page ($top rows) is returned — this is a triage view, not an export.

    .PARAMETER User
        The user's principal name (UPN).

    .PARAMETER Top
        How many recent sign-ins to return (default 20).

    .EXAMPLE
        Get-IntuneUserSignIn -User jdoe@contoso.com -Top 10

    .OUTPUTS
        PSCustomObject: When, App, Status, Reason, CA, BlockedBy, IP, Client, Device.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$User,
        [ValidateRange(1, 100)][int]$Top = 20
    )

    # Double the apostrophes (OData literal) AND URL-encode the whole clause so a UPN
    # containing # / & / % cannot truncate or reshape the query (cross-user disclosure).
    $f    = "userPrincipalName eq '$($User -replace "'", "''")'"
    $resp = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "auditLogs/signIns?`$filter=$([uri]::EscapeDataString($f))&`$top=$Top&`$orderby=createdDateTime desc")

    foreach ($s in @($resp.value)) {
        $err     = [int]($s.status.errorCode)
        $blocked = @($s.appliedConditionalAccessPolicies |
            Where-Object { $_.result -eq 'failure' } |
            ForEach-Object { $_.displayName }) -join ', '
        [pscustomobject][ordered]@{
            When      = $s.createdDateTime
            App       = $s.appDisplayName
            Status    = if ($err -eq 0) { 'success' } else { "failure ($err)" }
            Reason    = $s.status.failureReason
            CA        = $s.conditionalAccessStatus
            BlockedBy = $blocked
            IP        = $s.ipAddress
            Client    = $s.clientAppUsed
            Device    = $s.deviceDetail.displayName
        }
    }
}
