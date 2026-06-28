function Invoke-IntuneRemediation {
    <#
    .SYNOPSIS
        Trigger an on-demand remediation run on one or more devices.

    .DESCRIPTION
        Calls initiateOnDemandProactiveRemediation for each target device,
        which runs the detection and (if needed) remediation scripts immediately
        rather than waiting for the scheduled execution window.

    .PARAMETER RemediationId
        Remediation (device health script) name or GUID.

    .PARAMETER Device
        One or more device names or managed device GUIDs.

    .EXAMPLE
        Invoke-IntuneRemediation -RemediationId 'Fix Defender' -Device DESKTOP-ABC123

    .EXAMPLE
        Get-IntuneDeviceInventory -ComplianceState noncompliant |
            Invoke-IntuneRemediation -RemediationId 'Fix Compliance Settings' -Device { $_.DeviceName }

    .EXAMPLE
        Invoke-IntuneRemediation -RemediationId 'Fix Defender' -Device 'PC-01','PC-02','PC-03'

    .OUTPUTS
        PSCustomObject per device: Device, RemediationId, Submitted.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$RemediationId,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][string[]]$Device
    )

    begin {
        $scriptId = Resolve-IaRemediationId -Value $RemediationId
    }

    process {
        foreach ($dev in $Device) {
            $deviceId = Resolve-IaManagedDeviceId -Value $dev
            if ($PSCmdlet.ShouldProcess("$dev — $RemediationId", 'Invoke-IntuneRemediation')) {
                Invoke-IaRequest -Method POST `
                    -Uri (Resolve-IaUri "deviceManagement/managedDevices/$deviceId/initiateOnDemandProactiveRemediation") `
                    -Body @{ scriptPolicyId = $scriptId } | Out-Null
                [pscustomobject][ordered]@{
                    Device        = $dev
                    RemediationId = $scriptId
                    Submitted     = $true
                }
            }
        }
    }
}
