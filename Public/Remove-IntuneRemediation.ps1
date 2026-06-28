function Remove-IntuneRemediation {
    <#
    .SYNOPSIS
        Delete an Intune remediation (device health script).

    .DESCRIPTION
        Permanently deletes a remediation from /deviceManagement/deviceHealthScripts.

    .PARAMETER Id
        Remediation name or GUID to delete.

    .EXAMPLE
        Remove-IntuneRemediation -Id 'Fix Defender'

    .EXAMPLE
        Get-IntuneRemediation | Where-Object Name -like '*Test*' |
            ForEach-Object { Remove-IntuneRemediation -Id $_.Id -Confirm:$false }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)][string]$Id
    )

    process {
        $resolved = Resolve-IaRemediationId -Value $Id
        if ($PSCmdlet.ShouldProcess($Id, 'Remove-IntuneRemediation')) {
            Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri "deviceManagement/deviceHealthScripts/$resolved") | Out-Null
            Write-Verbose "Deleted remediation '$Id'."
        }
    }
}
