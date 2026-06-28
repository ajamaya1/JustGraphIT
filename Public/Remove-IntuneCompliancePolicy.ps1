function Remove-IntuneCompliancePolicy {
    <#
    .SYNOPSIS
        Delete an Intune compliance policy.

    .DESCRIPTION
        Permanently deletes a compliance policy. Requires confirmation by default.

    .PARAMETER Id
        Policy name or GUID to delete.

    .EXAMPLE
        Remove-IntuneCompliancePolicy -Id 'Old iOS Policy'

    .EXAMPLE
        Get-IntuneCompliancePolicy -Platform Android | Where-Object Name -like '*Test*' |
            ForEach-Object { Remove-IntuneCompliancePolicy -Id $_.Id -Confirm:$false }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)][string]$Id
    )

    process {
        $resolved = Resolve-IaCompliancePolicyId -Value $Id
        if ($PSCmdlet.ShouldProcess($Id, 'Remove-IntuneCompliancePolicy')) {
            Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri "deviceManagement/deviceCompliancePolicies/$resolved") | Out-Null
            Write-Verbose "Deleted compliance policy '$Id'."
        }
    }
}
