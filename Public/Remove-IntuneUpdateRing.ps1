function Remove-IntuneUpdateRing {
    <#
    .SYNOPSIS
        Delete a Windows Update for Business ring.

    .DESCRIPTION
        Permanently deletes a windowsUpdateForBusinessConfiguration profile from
        /deviceManagement/deviceConfigurations. Requires confirmation by default.
        Accepts pipeline input so you can pipe from Get-IntuneUpdateRing.

    .PARAMETER Id
        Ring name or GUID to delete.

    .EXAMPLE
        Remove-IntuneUpdateRing -Id 'Old Pilot Ring'

    .EXAMPLE
        Remove-IntuneUpdateRing -Id 'a1b2c3d4-0000-0000-0000-000000000000' -Confirm:$false

    .EXAMPLE
        Get-IntuneUpdateRing | Where-Object Name -like '*Test*' |
            Remove-IntuneUpdateRing -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)][string]$Id
    )

    process {
        $resolved = Resolve-IaUpdateRingId -Value $Id
        if ($PSCmdlet.ShouldProcess($Id, 'Remove-IntuneUpdateRing')) {
            Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri "deviceManagement/deviceConfigurations/$resolved") | Out-Null
            Write-Verbose "Deleted Windows Update ring '$Id'."
        }
    }
}
