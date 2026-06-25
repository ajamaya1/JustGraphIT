function New-IntuneAssignmentFilter {
    <#
    .SYNOPSIS
        Create a new Intune assignment filter.

    .DESCRIPTION
        POSTs a new assignment filter to /deviceManagement/assignmentFilters.
        Assignment filters let you target policy assignments to a subset of
        devices that match an OData rule expression.

    .PARAMETER Name
        Display name for the new filter.

    .PARAMETER Rule
        OData filter rule that defines which devices match.
        Example: (device.osVersion -startsWith "10.0.2")

    .PARAMETER Platform
        Target platform for the filter.
        Valid values: windows10AndLater, iOS, macOS, androidForWork, android, linux.

    .PARAMETER Description
        Optional description for the filter.

    .PARAMETER AssignmentFilterManagementType
        Specifies how the filter is used during assignment.
        include — the filter is applied as an include filter (default).
        exclude — the filter is applied as an exclude filter.
        none    — no management type restriction.

    .EXAMPLE
        New-IntuneAssignmentFilter -Name 'Win11 Devices' -Platform windows10AndLater `
            -Rule '(device.osVersion -startsWith "10.0.22")'

    .EXAMPLE
        New-IntuneAssignmentFilter -Name 'Corp iOS' -Platform iOS `
            -Rule '(device.ownership -eq "Corporate")' -Description 'Corporate-owned iOS'

    .OUTPUTS
        PSCustomObject: Id, Name, Platform, Rule, Created.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Rule,
        [Parameter(Mandatory)]
        [ValidateSet('windows10AndLater','iOS','macOS','androidForWork','android','linux')]
        [string]$Platform,
        [string]$Description,
        [ValidateSet('include','exclude','none')]
        [string]$AssignmentFilterManagementType = 'include'
    )

    $body = [ordered]@{
        displayName                      = $Name
        description                      = $Description ?? ''
        platform                         = $Platform
        rule                             = $Rule
        assignmentFilterManagementType   = $AssignmentFilterManagementType
    }

    if (-not $PSCmdlet.ShouldProcess($Name, 'New-IntuneAssignmentFilter')) { return }

    $created = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri 'deviceManagement/assignmentFilters') -Body $body

    [pscustomobject][ordered]@{
        Id       = $created.id
        Name     = $created.displayName
        Platform = $created.platform
        Rule     = $created.rule
        Created  = $created.createdDateTime
    }
}
