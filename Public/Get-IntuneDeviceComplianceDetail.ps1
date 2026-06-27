function Get-IntuneDeviceComplianceDetail {
    <#
    .SYNOPSIS
        The per-setting compliance results for a device — *why* it is non-compliant.

    .DESCRIPTION
        `Get-IntuneDeviceDetail -IncludeComplianceState` tells you a policy is
        non-compliant; this drills one level deeper to the individual settings that
        failed (e.g. "BitLocker required", "Minimum OS version") with their current
        value and error code — the actionable list a help-desk tech needs to fix it.

        Graph (beta):
            GET /beta/deviceManagement/managedDevices/{id}/deviceCompliancePolicyStates
            GET /beta/deviceManagement/managedDevices/{id}/deviceCompliancePolicyStates/{stateId}/settingStates
        Permission: DeviceManagementManagedDevices.Read.All.

        NOTE: settingStates is a per-policy-state sub-collection; verify the values
        against your tenant on first use.

    .PARAMETER Device
        Device name or managed-device GUID.

    .PARAMETER FailingOnly
        Return only settings that are not compliant (drop compliant / notApplicable).

    .EXAMPLE
        Get-IntuneDeviceComplianceDetail -Device LAPTOP-01 -FailingOnly

    .OUTPUTS
        PSCustomObject: Policy, Setting, State, CurrentValue, ErrorCode, ErrorReason.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Device,
        [switch]$FailingOnly
    )

    $id     = Resolve-IaManagedDeviceId -Value $Device
    $states = Get-IaCollection "deviceManagement/managedDevices/$id/deviceCompliancePolicyStates"

    foreach ($s in $states) {
        $settings = @()
        try {
            $settings = Get-IaCollection "deviceManagement/managedDevices/$id/deviceCompliancePolicyStates/$($s.id)/settingStates"
        } catch {
            Write-Verbose "No settingStates for policy '$($s.displayName)': $($_.Exception.Message)"
        }
        foreach ($ss in $settings) {
            $state = "$($ss.state)"
            if ($FailingOnly -and $state -in 'compliant', 'notApplicable', 'unknown', '') { continue }
            [pscustomobject][ordered]@{
                Policy       = $s.displayName
                Setting      = if ($ss.settingName) { $ss.settingName } else { $ss.setting }
                State        = $state
                CurrentValue = $ss.currentValue
                ErrorCode    = $ss.errorCode
                ErrorReason  = $ss.errorDescription
            }
        }
    }
}
