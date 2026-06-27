function Invoke-IntuneDeviceAction {
    <#
    .SYNOPSIS
        Send a remote action to an Intune-managed device.

    .DESCRIPTION
        Dispatches one of the supported Graph device actions to a managed device
        identified by name, GUID, or serial number. Destructive actions (Wipe,
        Retire, FreshStart, etc.) require confirmation unless -Confirm:$false is
        supplied.

    .PARAMETER Device
        Device name, managed device GUID, or serial number.

    .PARAMETER Action
        The remote action to execute:
          Wipe                     Factory reset the device.
          Retire                   Remove corporate data and unenroll.
          Sync                     Request an immediate policy sync.
          Reboot                   Remotely restart the device.
          RemoteLock               Lock the device screen.
          ResetPasscode            Remove or reset the device passcode.
          Rename                   Rename the device (requires -NewName).
          CollectDiagnostics       Trigger a diagnostic log collection.
          RotateBitLockerKeys      Force a BitLocker key rotation.
          LocateDevice             Request the device's current GPS location.
          FreshStart               Reinstall Windows, optionally keeping user data.
          DefenderScan             Run a Defender scan (full by default; -QuickScan for quick).
          DefenderUpdateSignatures Force a Defender signature update.
          BypassActivationLock     Remove the iOS Activation Lock.
          EnableLostMode           Enable Lost Mode on a supervised iOS device.
          DisableLostMode          Disable Lost Mode on a supervised iOS device.

    .PARAMETER NewName
        Required for Rename action.

    .PARAMETER KeepEnrollmentState
        Wipe only — device re-enrolls automatically after wipe.

    .PARAMETER KeepUserData
        Wipe only — personal data is preserved; implies KeepEnrollmentState.

    .PARAMETER QuickScan
        DefenderScan only — runs a quick scan instead of a full scan.

    .EXAMPLE
        Invoke-IntuneDeviceAction -Device DESKTOP-ABC123 -Action Sync

    .EXAMPLE
        Invoke-IntuneDeviceAction -Device DESKTOP-ABC123 -Action Wipe -KeepEnrollmentState

    .EXAMPLE
        Get-IntuneDeviceInventory -ComplianceState noncompliant |
            ForEach-Object { Invoke-IntuneDeviceAction -Device $_.Id -Action Sync -Confirm:$false }

    .OUTPUTS
        PSCustomObject: Device, Action, Submitted.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Device,
        [Parameter(Mandatory)]
        [ValidateSet(
            'Wipe','Retire','Sync','Reboot','RemoteLock','ResetPasscode','Rename',
            'CollectDiagnostics','RotateBitLockerKeys','LocateDevice','FreshStart',
            'DefenderScan','DefenderUpdateSignatures','BypassActivationLock',
            'EnableLostMode','DisableLostMode'
        )]
        [string]$Action,
        [string]$NewName,
        [switch]$KeepEnrollmentState,
        [switch]$KeepUserData,
        [switch]$QuickScan
    )

    if ($Action -eq 'Rename' -and -not $PSBoundParameters.ContainsKey('NewName')) {
        throw "Action 'Rename' requires -NewName."
    }

    $id = Resolve-IaManagedDeviceId -Value $Device

    $graphPath = switch ($Action) {
        'Wipe'                     { 'wipe' }
        'Retire'                   { 'retire' }
        'Sync'                     { 'syncDevice' }
        'Reboot'                   { 'rebootNow' }
        'RemoteLock'               { 'remoteLock' }
        'ResetPasscode'            { 'resetPasscode' }
        'Rename'                   { 'setDeviceName' }
        'CollectDiagnostics'       { 'createDeviceLogCollectionRequest' }
        'RotateBitLockerKeys'      { 'rotateBitLockerKeys' }
        'LocateDevice'             { 'locateDevice' }
        'FreshStart'               { 'cleanWindowsDevice' }
        'DefenderScan'             { 'windowsDefenderScan' }
        'DefenderUpdateSignatures' { 'windowsDefenderUpdateSignatures' }
        'BypassActivationLock'     { 'bypassActivationLock' }
        'EnableLostMode'           { 'enableLostMode' }
        'DisableLostMode'          { 'disableLostMode' }
    }

    $body = switch ($Action) {
        'Wipe'               { @{ keepEnrollmentData = [bool]($KeepEnrollmentState -or $KeepUserData); keepUserData = [bool]$KeepUserData } }
        'Rename'             { @{ deviceName = $NewName } }                         # setDeviceName(deviceName)
        'FreshStart'         { @{ keepUserData = [bool]$KeepUserData } }
        'DefenderScan'       { @{ quickScan = [bool]$QuickScan } }
        'CollectDiagnostics' { @{ templateType = @{ templateType = 'predefined' } } }   # createDeviceLogCollectionRequest(templateType)
        default              { @{} }
    }

    if ($PSCmdlet.ShouldProcess("$Device — $Action", 'Invoke-IntuneDeviceAction')) {
        Invoke-IaDevicePost -Id $id -Action $graphPath -Body $body
    }

    [pscustomobject][ordered]@{
        Device    = $Device
        Action    = $Action
        Submitted = $true
    }
}
