function Get-IntuneDeviceInventory {
    <#
    .SYNOPSIS
        Managed-device inventory: name, OS, compliance, owner, last check-in.

    .DESCRIPTION
        Reads deviceManagement/managedDevices and emits one row per enrolled
        device with the fields you actually scan for in the console: platform,
        OS version, compliance state, ownership, primary user, and how many days
        since the device last synced. Rows come back most-stale first. Filter by
        platform, compliance state, or staleness.

    .PARAMETER Platform
        Limit to one or more operating systems (Windows, iOS, Android, macOS…).

    .PARAMETER ComplianceState
        Limit to a single compliance state.

    .PARAMETER StaleDays
        Only return devices whose last sync is older than this many days.

    .PARAMETER Top
        Cap the number of rows returned (after sorting most-stale first).

    .EXAMPLE
        Get-IntuneDeviceInventory -ComplianceState noncompliant | Format-Table

        Every noncompliant device.

    .EXAMPLE
        Get-IntuneDeviceInventory -Platform Windows -StaleDays 30

        Windows devices that haven't checked in for a month.

    .OUTPUTS
        PSCustomObject: Device, OS, OSVersion, Compliance, Owner, User, LastSync,
        DaysSinceSync, Model, Serial, Encrypted, Agent.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Platform,
        [ValidateSet('compliant', 'noncompliant', 'conflict', 'error', 'inGracePeriod', 'notApplicable', 'configManager', 'unknown')]
        [string]$ComplianceState,
        [int]$StaleDays,
        [int]$Top
    )
    $select  = 'id,deviceName,operatingSystem,osVersion,complianceState,managedDeviceOwnerType,' +
               'lastSyncDateTime,userPrincipalName,userDisplayName,model,serialNumber,isEncrypted,managementAgent'
    $devices = Get-IaCollection "deviceManagement/managedDevices?`$select=$select"
    $now     = (Get-Date).ToUniversalTime()
    $plat    = if ($Platform) { @($Platform | ForEach-Object { $_.ToLower() }) } else { $null }

    $rows = foreach ($d in $devices) {
        if ($ComplianceState -and $d.complianceState -ne $ComplianceState) { continue }
        if ($plat -and (("$($d.operatingSystem)").ToLower() -notin $plat)) { continue }
        $sync = $null; $days = $null
        if ($d.lastSyncDateTime) {
            try { $sync = [datetime]$d.lastSyncDateTime; $days = [int][math]::Floor(($now - $sync.ToUniversalTime()).TotalDays) } catch { }
        }
        if ($PSBoundParameters.ContainsKey('StaleDays') -and ($null -eq $days -or $days -lt $StaleDays)) { continue }
        [pscustomobject][ordered]@{
            Device        = $d.deviceName
            OS            = $d.operatingSystem
            OSVersion     = $d.osVersion
            Compliance    = $d.complianceState
            Owner         = $d.managedDeviceOwnerType
            User          = if ($d.userDisplayName) { $d.userDisplayName } else { $d.userPrincipalName }
            LastSync      = $sync
            DaysSinceSync = $days
            Model         = $d.model
            Serial        = $d.serialNumber
            Encrypted     = [bool]$d.isEncrypted
            Agent         = $d.managementAgent
        }
    }
    $rows = @($rows) | Sort-Object @{ Expression = { if ($null -eq $_.DaysSinceSync) { -1 } else { $_.DaysSinceSync } }; Descending = $true }
    if ($Top -gt 0) { $rows = @($rows) | Select-Object -First $Top }
    $rows
}
