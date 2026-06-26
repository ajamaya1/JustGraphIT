function Remove-IntuneFeatureUpdate {
    <#
    .SYNOPSIS
        Delete a Windows feature update profile.

    .PARAMETER Id
        Profile name or GUID to delete.

    .EXAMPLE
        Remove-IntuneFeatureUpdate -Id 'Windows 11 23H2 Rollout'

    .EXAMPLE
        Get-IntuneFeatureUpdate | Where-Object Name -like '*Pilot*' |
            ForEach-Object { Remove-IntuneFeatureUpdate -Id $_.Id -Confirm:$false }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)][string]$Id
    )

    process {
        $resolved = Resolve-IaFeatureUpdateId -Value $Id
        if ($PSCmdlet.ShouldProcess($Id, 'Remove-IntuneFeatureUpdate')) {
            Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri "deviceManagement/windowsFeatureUpdateProfiles/$resolved") | Out-Null
            Write-Verbose "Deleted feature update profile '$Id'."
        }
    }
}
