function Remove-IntuneDriverUpdate {
    <#
    .SYNOPSIS
        Delete a Windows driver update profile.

    .PARAMETER Id
        Profile name or GUID to delete.

    .EXAMPLE
        Remove-IntuneDriverUpdate -Id 'Automatic Driver Updates'

    .EXAMPLE
        Get-IntuneDriverUpdate | Where-Object Name -like '*Test*' |
            ForEach-Object { Remove-IntuneDriverUpdate -Id $_.Id -Confirm:$false }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)][string]$Id
    )

    process {
        $resolved = Resolve-IaDriverUpdateId -Value $Id
        if ($PSCmdlet.ShouldProcess($Id, 'Remove-IntuneDriverUpdate')) {
            Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri "deviceManagement/windowsDriverUpdateProfiles/$resolved") | Out-Null
            Write-Verbose "Deleted driver update profile '$Id'."
        }
    }
}
