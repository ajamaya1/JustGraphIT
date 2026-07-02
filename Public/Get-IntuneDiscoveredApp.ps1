function Get-IntuneDiscoveredApp {
    <#
    .SYNOPSIS
        Search the tenant-wide discovered-app inventory — and list every device that
        has a given app installed. The "which devices have Zscaler?" report.

    .DESCRIPTION
        Queries deviceManagement/detectedApps (the software inventory Intune collects
        from every managed device) rather than looping devices, so it is two Graph
        calls even in a large tenant. Without -Devices you get the app-level view
        (name, version, publisher, device count); with -Devices you get one row per
        device+app — the list InfoSec actually asks for.

        Matching is case-insensitive substring on the app name, so 'zscaler' finds
        'Zscaler Client Connector', 'Zscaler App', etc. Each version of an app is its
        own inventory row; -Devices expands all matching versions.

    .PARAMETER Name
        App-name fragment to search for (e.g. 'zscaler'). Omit to list the whole
        discovered inventory.

    .PARAMETER Devices
        Expand each matching app to the devices that have it installed
        (device name, primary user, OS).

    .PARAMETER MinDeviceCount
        With the app-level view, only return apps installed on at least this many
        devices. Handy for "what's widespread in my estate".

    .EXAMPLE
        Get-IntuneDiscoveredApp -Name zscaler -Devices | Export-Csv .\zscaler-devices.csv

        The InfoSec report: every device with any Zscaler component, as CSV.

    .EXAMPLE
        Get-IntuneDiscoveredApp -MinDeviceCount 50 | Sort-Object DeviceCount -Descending

        The most widespread software in the estate.

    .OUTPUTS
        App view:    PSCustomObject App, Version, Publisher, Platform, DeviceCount, Id.
        Device view: PSCustomObject App, Version, Device, User, OS, DeviceId.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Name,
        [switch]$Devices,
        [int]$MinDeviceCount
    )

    $path = 'deviceManagement/detectedApps'
    if ($Name) {
        $path += "?`$filter=contains(displayName,'$(ConvertTo-IaODataValue $Name)')"
    }
    $apps = Get-IaCollection (Resolve-IaUri $path)
    $apps = @($apps)
    if ($MinDeviceCount) { $apps = @($apps | Where-Object { [int]$_.deviceCount -ge $MinDeviceCount }) }

    if (-not $Devices) {
        return @($apps | ForEach-Object {
            [pscustomobject][ordered]@{
                App         = $_.displayName
                Version     = $_.version
                Publisher   = $_.publisher
                Platform    = $_.platform
                DeviceCount = $_.deviceCount
                Id          = $_.id
            }
        } | Sort-Object -Property @{ Expression = 'DeviceCount'; Descending = $true }, App)
    }

    @(foreach ($a in $apps) {
        $devs = Get-IaCollection (Resolve-IaUri "deviceManagement/detectedApps/$($a.id)/managedDevices?`$select=id,deviceName,userPrincipalName,emailAddress,operatingSystem")
        foreach ($d in @($devs)) {
            [pscustomobject][ordered]@{
                App      = $a.displayName
                Version  = $a.version
                Device   = $d.deviceName
                User     = $d.userPrincipalName
                OS       = $d.operatingSystem
                DeviceId = $d.id
            }
        }
    }) | Sort-Object App, Device
}
