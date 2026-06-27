function Get-IntuneUserDevice {
    <#
    .SYNOPSIS
        List the Intune-managed devices that belong to a user.

    .DESCRIPTION
        Returns every managed device whose primary user matches the given UPN — the
        "what does this caller have?" starting point for a help-desk session.

        Graph:  GET /beta/deviceManagement/managedDevices
                     ?$filter=userPrincipalName eq '{upn}'
        Permission: DeviceManagementManagedDevices.Read.All.

    .PARAMETER User
        The user's principal name (UPN), e.g. jdoe@contoso.com.

    .EXAMPLE
        Get-IntuneUserDevice -User jdoe@contoso.com

    .OUTPUTS
        PSCustomObject: Device, OS, Compliance, Owner, Model, Serial, Encrypted,
        Enrolled, LastSync, Id.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$User
    )

    $esc    = $User -replace "'", "''"
    $select = 'id,deviceName,operatingSystem,osVersion,complianceState,' +
              'managedDeviceOwnerType,lastSyncDateTime,manufacturer,model,' +
              'serialNumber,isEncrypted,enrolledDateTime'
    $devices = Get-IaCollection "deviceManagement/managedDevices?`$filter=userPrincipalName eq '$esc'&`$select=$select"

    foreach ($d in $devices) {
        [pscustomobject][ordered]@{
            Device     = $d.deviceName
            OS         = "$($d.operatingSystem) $($d.osVersion)".Trim()
            Compliance = $d.complianceState
            Owner      = $d.managedDeviceOwnerType
            Model      = "$($d.manufacturer) $($d.model)".Trim()
            Serial     = $d.serialNumber
            Encrypted  = [bool]$d.isEncrypted
            Enrolled   = $d.enrolledDateTime
            LastSync   = $d.lastSyncDateTime
            Id         = $d.id
        }
    }
}
