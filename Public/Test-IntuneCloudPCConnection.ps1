function Test-IntuneCloudPCConnection {
    <#
    .SYNOPSIS
        Trigger a health check run on a Windows 365 on-premises connection.

    .DESCRIPTION
        Resolves the connection by name or id and posts the runHealthChecks action.
        Health checks are asynchronous — use Get-IntuneCloudPCConnection to poll
        the resulting healthCheckStatus.

    .PARAMETER Connection
        Display name or id of the on-premises connection to check.

    .EXAMPLE
        Test-IntuneCloudPCConnection -Connection "Corp HQ Connection"

    .OUTPUTS
        PSCustomObject: Connection, HealthCheckTriggered.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Connection
    )

    $id  = Resolve-IaConnectionId -Value $Connection
    $uri = Resolve-IaUri (Get-IaW365Path "onPremisesConnections/$id/runHealthChecks")
    Invoke-IaRequest -Method POST -Uri $uri | Out-Null

    Write-Information "Health check triggered for '$Connection'. Results are asynchronous — poll with Get-IntuneCloudPCConnection." -InformationAction Continue

    [pscustomobject]@{
        Connection           = $Connection
        HealthCheckTriggered = $true
    }
}
