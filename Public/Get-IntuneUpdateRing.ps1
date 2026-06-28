function Get-IntuneUpdateRing {
    <#
    .SYNOPSIS
        List or retrieve Windows Update for Business rings.

    .DESCRIPTION
        Returns windowsUpdateForBusinessConfiguration device configuration profiles
        from /deviceManagement/deviceConfigurations. Use -Id to retrieve a single
        ring by name or GUID.

    .PARAMETER Id
        Ring name or GUID. When provided, returns a single ring.

    .EXAMPLE
        Get-IntuneUpdateRing

    .EXAMPLE
        Get-IntuneUpdateRing -Id 'Pilot Ring'

    .EXAMPLE
        Get-IntuneUpdateRing -Id 'a1b2c3d4-0000-0000-0000-000000000000'

    .OUTPUTS
        PSCustomObject per ring: Id, Name, Description, QualityUpdateDeferralDays,
        FeatureUpdateDeferralDays, BusinessReadyUpdatesOnly, AutomaticUpdateMode,
        DeliveryOptimizationMode, PauseQualityUpdates, PauseFeatureUpdates,
        Created, Modified.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Id
    )

    $baseFilter = "isOf('microsoft.graph.windowsUpdateForBusinessConfiguration')"

    if ($Id) {
        $resolved = Resolve-IaUpdateRingId -Value $Id
        $ring = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/deviceConfigurations/$resolved")
        return ConvertTo-IaUpdateRingObject -Ring $ring
    }

    $query = "deviceManagement/deviceConfigurations?`$filter=$([uri]::EscapeDataString($baseFilter))&`$orderby=displayName"
    $rings = Get-IaCollection (Resolve-IaUri $query)
    foreach ($r in $rings) {
        ConvertTo-IaUpdateRingObject -Ring $r
    }
}

function Resolve-IaUpdateRingId {
    param([string]$Value)
    if (Test-IaGuid $Value) { return $Value }
    $encoded = ConvertTo-IaODataValue $Value
    $filter  = "isOf('microsoft.graph.windowsUpdateForBusinessConfiguration') and displayName eq '$encoded'"
    $results = Get-IaCollection (Resolve-IaUri "deviceManagement/deviceConfigurations?`$filter=$([uri]::EscapeDataString($filter))&`$select=id,displayName")
    if ($results.Count -eq 0) { throw "No Windows Update ring found matching '$Value'." }
    if ($results.Count -gt 1) { throw "Multiple rings match '$Value'. Provide a unique id." }
    $results[0].id
}

function ConvertTo-IaUpdateRingObject {
    param($Ring)
    [pscustomobject][ordered]@{
        Id                          = $Ring.id
        Name                        = $Ring.displayName
        Description                 = $Ring.description
        QualityUpdateDeferralDays   = $Ring.qualityUpdatesDeferralPeriodInDays
        FeatureUpdateDeferralDays   = $Ring.featureUpdatesDeferralPeriodInDays
        BusinessReadyUpdatesOnly    = $Ring.businessReadyUpdatesOnly
        AutomaticUpdateMode         = $Ring.automaticUpdateMode
        DeliveryOptimizationMode    = $Ring.deliveryOptimizationMode
        PauseQualityUpdates         = $Ring.qualityUpdatesPaused
        PauseFeatureUpdates         = $Ring.featureUpdatesPaused
        Created                     = $Ring.createdDateTime
        Modified                    = $Ring.lastModifiedDateTime
    }
}
