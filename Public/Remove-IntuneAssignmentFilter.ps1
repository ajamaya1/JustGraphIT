function Remove-IntuneAssignmentFilter {
    <#
    .SYNOPSIS
        Delete an Intune assignment filter.

    .DESCRIPTION
        Permanently deletes an assignment filter by name or GUID.
        Requires confirmation by default due to ConfirmImpact = High.
        Accepts pipeline input from Get-IntuneAssignmentFilter.

    .PARAMETER Id
        Filter name or GUID to delete.

    .EXAMPLE
        Remove-IntuneAssignmentFilter -Id 'Old Windows Filter'

    .EXAMPLE
        Get-IntuneAssignmentFilter -Platform Android | Where-Object Name -like '*Test*' |
            Remove-IntuneAssignmentFilter -Confirm:$false

    .EXAMPLE
        Remove-IntuneAssignmentFilter -Id 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)][string]$Id
    )

    process {
        $resolved = Resolve-IaFilterId -Value $Id
        if ($PSCmdlet.ShouldProcess($Id, 'Remove-IntuneAssignmentFilter')) {
            Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri "deviceManagement/assignmentFilters/$resolved") | Out-Null
            Write-Verbose "Deleted assignment filter '$Id'."
        }
    }
}
