function Remove-IntuneCloudPCProvisioningPolicy {
    <#
    .SYNOPSIS
        Delete a Windows 365 provisioning policy.

    .DESCRIPTION
        Resolves the policy by name or id and sends a DELETE request to Graph.
        Prompts for confirmation because this action cannot be undone.

    .PARAMETER Policy
        Display name or id of the provisioning policy to delete.

    .EXAMPLE
        Remove-IntuneCloudPCProvisioningPolicy -Policy "Old Corp Policy"

    .OUTPUTS
        PSCustomObject: Policy, Deleted.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$Policy
    )

    $id = Resolve-IaProvisioningPolicyId -Value $Policy

    if (-not $PSCmdlet.ShouldProcess($Policy, 'Remove-IntuneCloudPCProvisioningPolicy')) { return }

    $uri = Resolve-IaUri (Get-IaW365Path "provisioningPolicies/$id")
    Invoke-IaRequest -Method DELETE -Uri $uri | Out-Null

    [pscustomobject]@{
        Policy  = $Policy
        Deleted = $true
    }
}
