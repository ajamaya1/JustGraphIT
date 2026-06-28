function Get-IntuneCloudPCConnection {
    <#
    .SYNOPSIS
        List Windows 365 on-premises network connections.

    .DESCRIPTION
        Returns all Azure network connections (formerly on-premises connections),
        optionally filtered to a single connection by name or id, or filtered by
        health check status.

    .PARAMETER Connection
        Display name or id of a specific connection. Omit to list all.

    .PARAMETER HealthState
        Only return connections with this health check status.

    .EXAMPLE
        Get-IntuneCloudPCConnection

        All connections.

    .EXAMPLE
        Get-IntuneCloudPCConnection -HealthState failed

        Only connections whose health check has failed.

    .OUTPUTS
        PSCustomObject: Name, HealthStatus, Type, VNetId, SubnetId, DomainName,
        OuPath, Region, Id.
    #>
    [CmdletBinding()]
    param(
        [string]$Connection,
        [ValidateSet('running', 'passed', 'failed', 'warning', 'unknownFutureValue')]
        [string]$HealthState
    )

    function ConvertTo-ConnectionObject {
        param([object]$c)
        [pscustomobject][ordered]@{
            Name         = $c.displayName
            HealthStatus = $c.healthCheckStatus
            Type         = $c.type
            VNetId       = $c.virtualNetworkId
            SubnetId     = $c.subnetId
            DomainName   = $c.adDomainName
            OuPath       = $c.organizationalUnit
            Region       = $c.region
            Id           = $c.id
        }
    }

    $base = Get-IaW365Path 'onPremisesConnections'

    if ($Connection -and (Test-IaGuid $Connection)) {
        $c = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "$base/$Connection")
        if ($HealthState -and $c.healthCheckStatus -ne $HealthState) { return }
        ConvertTo-ConnectionObject -c $c
        return
    }

    $items = Get-IaCollection $base

    foreach ($c in $items) {
        if ($Connection -and $c.displayName -ne $Connection) { continue }
        if ($HealthState -and $c.healthCheckStatus -ne $HealthState) { continue }
        ConvertTo-ConnectionObject -c $c
    }
}
