function Get-IntuneEnrollmentRestriction {
    <#
    .SYNOPSIS
        List or retrieve device enrollment restrictions.

    .DESCRIPTION
        Returns enrollment restriction configurations from
        /deviceManagement/deviceEnrollmentConfigurations, filtered to
        platform restriction and limit types.
        Use -Id to retrieve a single restriction by name or GUID.
        Use -Type to narrow results to PlatformRestriction or Limit only.

    .PARAMETER Id
        Restriction name or GUID. When provided, returns a single restriction.

    .PARAMETER Type
        Filter by restriction type: All (default), PlatformRestriction, Limit.

    .EXAMPLE
        Get-IntuneEnrollmentRestriction

    .EXAMPLE
        Get-IntuneEnrollmentRestriction -Type PlatformRestriction

    .EXAMPLE
        Get-IntuneEnrollmentRestriction -Id 'Default Limit'

    .OUTPUTS
        PSCustomObject per restriction: Id, Name, Priority, Type, Description,
        PlatformRestrictions, Created, Modified.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Id,
        [ValidateSet('All', 'PlatformRestriction', 'Limit')]
        [string]$Type = 'All'
    )

    if ($Id) {
        $resolved = Resolve-IaEnrollmentRestrictionId -Value $Id -Type $Type
        $item = Invoke-IaRequest -Method GET `
            -Uri (Resolve-IaUri "deviceManagement/deviceEnrollmentConfigurations/$resolved")
        return ConvertTo-IaEnrollmentRestrictionObject -Item $item
    }

    $odataFilter = switch ($Type) {
        'PlatformRestriction' {
            "isOf('microsoft.graph.deviceEnrollmentPlatformRestrictionConfiguration')"
        }
        'Limit' {
            "isOf('microsoft.graph.deviceEnrollmentLimitConfiguration')"
        }
        default {
            "isOf('microsoft.graph.deviceEnrollmentPlatformRestrictionConfiguration') or isOf('microsoft.graph.deviceEnrollmentLimitConfiguration')"
        }
    }

    $query = "deviceManagement/deviceEnrollmentConfigurations?`$filter=$([uri]::EscapeDataString($odataFilter))&`$orderby=priority"
    $items = Get-IaCollection (Resolve-IaUri $query)
    foreach ($item in $items) {
        ConvertTo-IaEnrollmentRestrictionObject -Item $item
    }
}

function Resolve-IaEnrollmentRestrictionId {
    param([string]$Value, [string]$Type = 'All')
    if (Test-IaGuid $Value) { return $Value }
    $encoded = [uri]::EscapeDataString($Value)
    $odataFilter = switch ($Type) {
        'PlatformRestriction' {
            "isOf('microsoft.graph.deviceEnrollmentPlatformRestrictionConfiguration') and displayName eq '$encoded'"
        }
        'Limit' {
            "isOf('microsoft.graph.deviceEnrollmentLimitConfiguration') and displayName eq '$encoded'"
        }
        default {
            "(isOf('microsoft.graph.deviceEnrollmentPlatformRestrictionConfiguration') or isOf('microsoft.graph.deviceEnrollmentLimitConfiguration')) and displayName eq '$encoded'"
        }
    }
    $results = Get-IaCollection (Resolve-IaUri "deviceManagement/deviceEnrollmentConfigurations?`$filter=$([uri]::EscapeDataString($odataFilter))&`$select=id,displayName")
    if ($results.Count -eq 0) { throw "No enrollment restriction found matching '$Value'." }
    if ($results.Count -gt 1) { throw "Multiple restrictions match '$Value'. Provide a unique id." }
    $results[0].id
}

function ConvertTo-IaEnrollmentRestrictionObject {
    param($Item)
    $odataType = $Item.'@odata.type'
    $derivedType = switch ($odataType) {
        '#microsoft.graph.deviceEnrollmentPlatformRestrictionConfiguration' { 'PlatformRestriction' }
        '#microsoft.graph.deviceEnrollmentLimitConfiguration'               { 'Limit' }
        default { $odataType -replace '#microsoft.graph.deviceEnrollment', '' -replace 'Configuration', '' }
    }

    [pscustomobject][ordered]@{
        Id                   = $Item.id
        Name                 = $Item.displayName
        Priority             = $Item.priority
        Type                 = $derivedType
        Description          = $Item.description
        PlatformRestrictions = $Item.platformRestrictions  # null for Limit type
        Created              = $Item.createdDateTime
        Modified             = $Item.lastModifiedDateTime
    }
}
