function Remove-IntuneDeviceConfiguration {
    <#
    .SYNOPSIS
        Delete a legacy device configuration profile.

    .DESCRIPTION
        Permanently deletes a profile from /deviceManagement/deviceConfigurations.
        Requires confirmation by default (ConfirmImpact = High).
        Accepts pipeline input from Get-IntuneDeviceConfiguration.

    .PARAMETER Id
        Profile name or GUID to delete.

    .EXAMPLE
        Remove-IntuneDeviceConfiguration -Id 'Old Windows Profile'

    .EXAMPLE
        Get-IntuneDeviceConfiguration -Platform Windows |
            Where-Object Name -like '*Test*' |
            Remove-IntuneDeviceConfiguration -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)][string]$Id
    )

    process {
        $resolved = Resolve-IaDeviceConfigId -Value $Id
        if ($PSCmdlet.ShouldProcess($Id, 'Remove-IntuneDeviceConfiguration')) {
            Invoke-IaRequest -Method DELETE `
                -Uri (Resolve-IaUri "deviceManagement/deviceConfigurations/$resolved") | Out-Null
            Write-Verbose "Deleted device configuration '$Id'."
        }
    }
}
