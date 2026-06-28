function Get-IntuneDeviceConfigConflict {
    <#
    .SYNOPSIS
        Settings on a device that two configuration profiles disagree on (conflicts).

    .DESCRIPTION
        When two profiles target the same device and set the same setting to different
        values, Intune reports that setting as 'conflict' and neither value is applied.
        This surfaces exactly which settings are in conflict and **which profiles are
        fighting over them** (the per-setting `sources`) — the information you need to
        decide which profile to change or exclude.

        Graph (beta):
            GET /beta/deviceManagement/managedDevices/{id}/deviceConfigurationStates
        Each deviceConfigurationState carries its per-setting results inline in the
        `settingStates` structural property (a Collection(deviceConfigurationSettingState),
        not a navigable sub-resource); the conflicting profiles are in each setting's
        `sources`. Read inline from the collection, with a single-entity fallback.
        Permission: DeviceManagementManagedDevices.Read.All.

    .PARAMETER Device
        Device name or managed-device GUID.

    .PARAMETER IncludeErrors
        Also include settings in an 'error' state (not just 'conflict').

    .EXAMPLE
        Get-IntuneDeviceConfigConflict -Device LAPTOP-01

    .OUTPUTS
        PSCustomObject: Setting, State, Profiles, CurrentValue, Policy.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Device,
        [switch]$IncludeErrors
    )

    $wanted = if ($IncludeErrors) { @('conflict', 'error') } else { @('conflict') }
    $id     = Resolve-IaManagedDeviceId -Value $Device
    $states = Get-IaCollection "deviceManagement/managedDevices/$id/deviceConfigurationStates"

    foreach ($s in $states) {
        # Skip profiles that are wholly fine — only descend into ones flagged conflict/error.
        if ("$($s.state)" -notin $wanted) { continue }
        # settingStates is an inline structural property; re-read the single entity only
        # if the collection omitted it.
        $settings = @($s.settingStates)
        if (-not $settings -and $s.id) {
            try {
                $full = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/managedDevices/$id/deviceConfigurationStates/$($s.id)")
                $settings = @($full.settingStates)
            } catch {
                Write-Verbose "Could not read settingStates for profile '$($s.displayName)': $($_.Exception.Message)"
            }
        }
        foreach ($ss in $settings) {
            if ("$($ss.state)" -notin $wanted) { continue }
            $sources = @($ss.sources | ForEach-Object { $_.displayName } | Where-Object { $_ }) -join ', '
            [pscustomobject][ordered]@{
                Setting      = if ($ss.settingName) { $ss.settingName } else { $ss.setting }
                State        = $ss.state
                Profiles     = if ($sources) { $sources } else { $s.displayName }
                CurrentValue = $ss.currentValue
                Policy       = $s.displayName
            }
        }
    }
}
