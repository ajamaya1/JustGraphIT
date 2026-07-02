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

    .PARAMETER BelowVersion
        Only return versions strictly below this one — the vulnerability-response
        filter ("CVE fixed in 126: who's still below it?"). Versions are compared
        numerically segment by segment. A version string that cannot be parsed is
        INCLUDED (it can't be proven patched), flagged in the row.

    .PARAMETER MinDeviceCount
        With the app-level view, only return apps installed on at least this many
        devices. Handy for "what's widespread in my estate".

    .EXAMPLE
        Get-IntuneDiscoveredApp -Name zscaler -Devices | Export-Csv .\zscaler-devices.csv

        The InfoSec report: every device with any Zscaler component, as CSV.

    .EXAMPLE
        Get-IntuneDiscoveredApp -Name chrome -BelowVersion 126 -Devices

        Every device still running Chrome older than 126.

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
        [string]$BelowVersion,
        [int]$MinDeviceCount
    )

    $path = 'deviceManagement/detectedApps'
    if ($Name) {
        $path += "?`$filter=contains(displayName,'$(ConvertTo-IaODataValue $Name)')"
    }
    $apps = Get-IaCollection (Resolve-IaUri $path)
    $apps = @($apps)
    if ($MinDeviceCount) { $apps = @($apps | Where-Object { [int]$_.deviceCount -ge $MinDeviceCount }) }
    if ($BelowVersion) {
        # keep versions strictly below the bar, PLUS unparseable ones (can't prove patched)
        $apps = @($apps | Where-Object {
            $c = Compare-IaAppVersion -A ([string]$_.version) -B $BelowVersion
            $null -eq $c -or $c -lt 0
        })
    }

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
        $vNote = if ($BelowVersion -and $null -eq (Compare-IaAppVersion -A ([string]$a.version) -B $BelowVersion)) { ' (unparseable)' } else { '' }
        $devs = Get-IaCollection (Resolve-IaUri "deviceManagement/detectedApps/$($a.id)/managedDevices?`$select=id,deviceName,userPrincipalName,emailAddress,operatingSystem")
        foreach ($d in @($devs)) {
            [pscustomobject][ordered]@{
                App      = $a.displayName
                Version  = "$($a.version)$vNote"
                Device   = $d.deviceName
                User     = $d.userPrincipalName
                OS       = $d.operatingSystem
                DeviceId = $d.id
            }
        }
    }) | Sort-Object App, Device
}

function Compare-IaAppVersion {
    <#
    .SYNOPSIS
        Numeric segment-by-segment version compare tolerant of vendor version strings.
        Returns -1 / 0 / 1, or $null when either side has no leading dotted-numeric
        prefix to compare (callers decide how to treat unknowns).
    #>
    param([string]$A, [string]$B)
    $rx = '^\s*[vV]?(\d+(?:\.\d+)*)'
    if ($A -notmatch $rx) { return $null }
    $pa = @($Matches[1] -split '\.')
    if ($B -notmatch $rx) { return $null }
    $pb = @($Matches[1] -split '\.')
    $len = [Math]::Max($pa.Count, $pb.Count)
    for ($i = 0; $i -lt $len; $i++) {
        $x = if ($i -lt $pa.Count) { [long]$pa[$i] } else { 0 }
        $y = if ($i -lt $pb.Count) { [long]$pb[$i] } else { 0 }
        if ($x -lt $y) { return -1 }
        if ($x -gt $y) { return 1 }
    }
    0
}
