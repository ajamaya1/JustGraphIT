function Get-IntuneCloudPCSnapshot {
    <#
    .SYNOPSIS
        List Windows 365 Cloud PC snapshots.

    .DESCRIPTION
        Returns restore-point snapshots across all Cloud PCs, optionally filtered
        to one Cloud PC by name or id.

    .PARAMETER CloudPC
        Cloud PC display name or id. Omit to return snapshots for all Cloud PCs.

    .EXAMPLE
        Get-IntuneCloudPCSnapshot

        All snapshots in the tenant.

    .EXAMPLE
        Get-IntuneCloudPCSnapshot -CloudPC "Alice-W365"

        Only snapshots belonging to Alice's Cloud PC.

    .OUTPUTS
        PSCustomObject: CloudPC, CreatedAt, ExpiresAt, Status, SnapshotType, Id.
    #>
    [CmdletBinding()]
    param(
        [string]$CloudPC
    )

    # Resolve to id if a name was supplied so we can filter by cloudPcId.
    $filterPcId = $null
    if ($CloudPC) {
        $filterPcId = Resolve-IaCloudPCId -Value $CloudPC
    }

    $items = Get-IaCollection (Get-IaW365Path 'snapshots')

    foreach ($snap in $items) {
        if ($filterPcId -and $snap.cloudPcId -ne $filterPcId) { continue }
        [pscustomobject][ordered]@{
            CloudPC      = if ($snap.PSObject.Properties['cloudPcDisplayName'] -and $snap.cloudPcDisplayName) { $snap.cloudPcDisplayName } else { $snap.cloudPcId }
            CreatedAt    = $snap.createdDateTime
            ExpiresAt    = $snap.expirationDateTime
            Status       = $snap.statusDetail
            SnapshotType = $snap.snapshotType
            Id           = $snap.id
        }
    }
}
