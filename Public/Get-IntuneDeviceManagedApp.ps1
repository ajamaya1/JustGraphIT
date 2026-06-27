function Get-IntuneDeviceManagedApp {
    <#
    .SYNOPSIS
        List the Intune-MANAGED apps targeted to a device and their install state.

    .DESCRIPTION
        Unlike detected (discovered) apps — the raw inventory of everything installed
        on the device — this shows the apps Intune is actively managing (assigned via
        app policy) together with each one's intent (required / available / uninstall)
        and install state (installed / failed / pending / notInstalled).

        Graph:  GET /beta/users/{userId}/mobileAppIntentAndStates/{managedDeviceId}
        The collection is keyed by the device's primary user, so a device with no
        primary user (shared / kiosk) reports nothing here.
        Permission: DeviceManagementApps.Read.All.

        NOTE: this beta path was implemented from the documented Graph schema; verify
        the install-state values against your tenant on first use.

    .PARAMETER Device
        Device name or managed-device GUID.

    .EXAMPLE
        Get-IntuneDeviceManagedApp -Device LAPTOP-01

    .OUTPUTS
        PSCustomObject: App, Intent, State, Version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Device
    )

    $id  = Resolve-IaManagedDeviceId -Value $Device
    $mdm = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/managedDevices/${id}?`$select=id,deviceName,userId,userPrincipalName")
    if (-not $mdm.userId) {
        Write-Warning "'$($mdm.deviceName)' has no primary user — managed-app state is reported per user/device, so none is available for a shared/kiosk device."
        return
    }

    $state = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "users/$($mdm.userId)/mobileAppIntentAndStates/${id}")
    foreach ($a in @($state.mobileAppList)) {
        [pscustomobject][ordered]@{
            App     = $a.displayName
            Intent  = $a.mobileAppIntent       # required / available / uninstall
            State   = $a.installState           # installed / failed / pending / notInstalled
            Version = $a.displayVersion
        }
    }
}
