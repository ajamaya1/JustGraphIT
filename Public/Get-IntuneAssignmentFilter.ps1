function Get-IntuneAssignmentFilter {
    <#
    .SYNOPSIS
        List or retrieve Intune assignment filters.

    .DESCRIPTION
        Returns assignment filters from /deviceManagement/assignmentFilters.
        Use -Id to retrieve a single filter by name or GUID.
        Use -Platform to narrow results to a specific OS family.

    .PARAMETER Id
        Filter name or GUID. Returns a single matching filter.

    .PARAMETER Platform
        Limit results to filters for a given platform. Default: All.
        Valid values: All, Windows, iOS, macOS, Android, AndroidForWork.

    .EXAMPLE
        Get-IntuneAssignmentFilter

    .EXAMPLE
        Get-IntuneAssignmentFilter -Platform Windows

    .EXAMPLE
        Get-IntuneAssignmentFilter -Id 'Corp Windows Devices'

    .OUTPUTS
        PSCustomObject: Id, Name, Platform, Description, Rule, Created, Modified.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Id,
        [ValidateSet('All','Windows','iOS','macOS','Android','AndroidForWork')]
        [string]$Platform = 'All'
    )

    if ($Id) {
        $resolved = Resolve-IaFilterId -Value $Id
        $filter   = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/assignmentFilters/$resolved")
        return ConvertTo-IaFilterObject -Filter $filter
    }

    $platformApiMap = @{
        'Windows'      = 'windows10AndLater'
        'iOS'          = 'iOS'
        'macOS'        = 'macOS'
        'Android'      = 'android'
        'AndroidForWork' = 'androidForWork'
    }

    $uri = 'deviceManagement/assignmentFilters'
    if ($Platform -ne 'All') {
        $apiPlatform = $platformApiMap[$Platform] ?? $Platform
        $uri = "${uri}?`$filter=platform eq '$apiPlatform'"
    }

    $all = Get-IaCollection (Resolve-IaUri $uri)
    foreach ($f in $all) {
        ConvertTo-IaFilterObject -Filter $f
    }
}

function Resolve-IaFilterId {
    param([string]$Value)
    if (Test-IaGuid $Value) { return $Value }
    $encoded = [uri]::EscapeDataString($Value)
    $results = Get-IaCollection (Resolve-IaUri "deviceManagement/assignmentFilters?`$filter=displayName eq '$encoded'&`$select=id,displayName")
    if ($results.Count -eq 0) { throw "No assignment filter found matching '$Value'." }
    if ($results.Count -gt 1) { throw "Multiple assignment filters match '$Value'. Provide a unique id." }
    $results[0].id
}

function ConvertTo-IaFilterObject {
    param($Filter)
    [pscustomobject][ordered]@{
        Id          = $Filter.id
        Name        = $Filter.displayName
        Platform    = $Filter.platform
        Description = $Filter.description
        Rule        = $Filter.rule
        Created     = $Filter.createdDateTime
        Modified    = $Filter.lastModifiedDateTime
    }
}
