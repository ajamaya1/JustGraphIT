function Remove-IntuneConfigurationPolicy {
    <#
    .SYNOPSIS
        Delete a Settings Catalog configuration policy.

    .DESCRIPTION
        Permanently deletes a policy from /deviceManagement/configurationPolicies.
        Requires confirmation by default.

    .PARAMETER Id
        Policy name or GUID to delete.

    .EXAMPLE
        Remove-IntuneConfigurationPolicy -Id 'Old Windows Policy'

    .EXAMPLE
        Get-IntuneConfigurationPolicy -Platform macOS | Where-Object Name -like '*Test*' |
            ForEach-Object { Remove-IntuneConfigurationPolicy -Id $_.Id -Confirm:$false }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)][string]$Id
    )

    process {
        $resolved = Resolve-IaConfigPolicyId -Value $Id
        if ($PSCmdlet.ShouldProcess($Id, 'Remove-IntuneConfigurationPolicy')) {
            Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri "deviceManagement/configurationPolicies/$resolved") | Out-Null
            Write-Verbose "Deleted configuration policy '$Id'."
        }
    }
}
