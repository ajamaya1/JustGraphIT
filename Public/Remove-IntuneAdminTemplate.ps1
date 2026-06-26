function Remove-IntuneAdminTemplate {
    <#
    .SYNOPSIS
        Delete an Administrative Template (ADMX) policy.

    .DESCRIPTION
        Permanently deletes a Group Policy configuration from Intune.

    .PARAMETER Id
        Template name or GUID to delete.

    .EXAMPLE
        Remove-IntuneAdminTemplate -Id 'Windows Settings - Baseline'

    .EXAMPLE
        Get-IntuneAdminTemplate | Where-Object Name -like '*Test*' |
            ForEach-Object { Remove-IntuneAdminTemplate -Id $_.Id -Confirm:$false }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)][string]$Id
    )

    process {
        $resolved = Resolve-IaAdminTemplateId -Value $Id
        if ($PSCmdlet.ShouldProcess($Id, 'Remove-IntuneAdminTemplate')) {
            Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri "deviceManagement/groupPolicyConfigurations/$resolved") | Out-Null
            Write-Verbose "Deleted admin template '$Id'."
        }
    }
}
