function Get-IntuneBitLockerKey {
    <#
    .SYNOPSIS
        Retrieve BitLocker recovery keys for an Intune-managed device.

    .DESCRIPTION
        Looks up the Azure AD device ID for the given Intune device, queries the
        BitLocker recovery key index, then fetches each key's value.
        Requires BitLockerKey.ReadBasic.All for metadata;
        BitLockerKey.Read.All to return key values.

    .PARAMETER Device
        Device name or managed device GUID.

    .EXAMPLE
        Get-IntuneBitLockerKey -Device DESKTOP-ABC123

    .OUTPUTS
        PSCustomObject: KeyId, Created, VolumeType, Key.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Device
    )

    $id  = Resolve-IaManagedDeviceId -Value $Device
    $mdm = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/managedDevices/${id}?`$select=id,deviceName,azureADDeviceId")
    if (-not $mdm.azureADDeviceId) { throw "No Azure AD device ID found for '$Device'." }

    $aadId = $mdm.azureADDeviceId
    $keys  = Get-IaCollection (Resolve-IaUri "informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '$aadId'&`$select=id,createdDateTime,volumeType,deviceId")

    foreach ($entry in $keys) {
        $detail = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "informationProtection/bitlocker/recoveryKeys/$($entry.id)?`$select=key")
        [pscustomobject][ordered]@{
            KeyId      = $entry.id
            Created    = $entry.createdDateTime
            VolumeType = $entry.volumeType
            Key        = $detail.key
        }
    }
}
