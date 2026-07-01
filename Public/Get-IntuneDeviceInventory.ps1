function Get-IntuneDeviceInventory {
    <#
    .SYNOPSIS
        Managed-device inventory with enrollment type, model, manufacturer, and
        Cloud PC / Autopilot detection.

    .DESCRIPTION
        Reads deviceManagement/managedDevices and emits one row per enrolled
        device. Filter by platform, compliance, staleness, manufacturer,
        enrollment type, or device source (CloudPC / Autopilot / Standard).

    .PARAMETER Platform
        Limit to one or more operating systems (Windows, iOS, Android, macOS…).

    .PARAMETER ComplianceState
        Limit to a single compliance state.

    .PARAMETER StaleDays
        Only return devices whose last sync is older than this many days.

    .PARAMETER Manufacturer
        Limit to devices whose Manufacturer contains this string (case-insensitive).

    .PARAMETER EnrollmentType
        Limit to a specific deviceEnrollmentType value (e.g. windowsAutoEnrollment).

    .PARAMETER Source
        Limit to: CloudPC, Autopilot, or Standard.

    .PARAMETER Top
        Cap the number of rows returned (after sorting most-stale first).

    .EXAMPLE
        Get-IntuneDeviceInventory -Source CloudPC

        All Cloud PC devices.

    .EXAMPLE
        Get-IntuneDeviceInventory -Source Autopilot -ComplianceState noncompliant

        Autopilot-enrolled devices that are noncompliant.

    .EXAMPLE
        Get-IntuneDeviceInventory -Platform Windows -StaleDays 30

        Windows devices that haven't checked in for a month.

    .OUTPUTS
        PSCustomObject: Device, OS, OSVersion, Compliance, Owner, User,
        LastSync, DaysSinceSync, Manufacturer, Model, Serial, Encrypted,
        EnrollmentType, JoinType, Source, Agent.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Platform,
        [ValidateSet('compliant','noncompliant','conflict','error','inGracePeriod',
                     'notApplicable','configManager','unknown')]
        [string]$ComplianceState,
        [int]$StaleDays,
        [string]$Manufacturer,
        [string]$EnrollmentType,
        [ValidateSet('CloudPC','Autopilot','Standard')]
        [string]$Source,
        [int]$Top
    )

    $select = 'id,deviceName,operatingSystem,osVersion,complianceState,' +
              'managedDeviceOwnerType,lastSyncDateTime,userPrincipalName,' +
              'userDisplayName,model,serialNumber,isEncrypted,managementAgent,' +
              'manufacturer,deviceEnrollmentType,joinType,deviceType'

    $devices = Get-IaCollection "deviceManagement/managedDevices?`$select=$select"
    $now     = (Get-Date).ToUniversalTime()
    $plat    = if ($Platform) { @($Platform | ForEach-Object { $_.ToLower() }) } else { $null }

    # Autopilot enrollment type values (Graph SDK names)
    $autopilotTypes = @(
        'windowsAutoEnrollment','windowsAzureADJoin','windowsBulkAzureDomainJoined',
        'windowsBulkUserless','windowsAzureADJoinUsingDeviceAuth'
    )

    $rows = foreach ($d in $devices) {
        if ($ComplianceState -and $d.complianceState -ne $ComplianceState) { continue }
        if ($plat -and ("$($d.operatingSystem)".ToLower() -notin $plat))   { continue }
        if ($Manufacturer -and "$($d.manufacturer)" -notmatch [regex]::Escape($Manufacturer)) { continue }
        if ($EnrollmentType -and $d.deviceEnrollmentType -ne $EnrollmentType) { continue }

        # Derive Source label
        $srcLabel = if ($d.deviceType -eq 'cloudPC') { 'CloudPC' }
                    elseif ($d.deviceEnrollmentType -in $autopilotTypes) { 'Autopilot' }
                    else { 'Standard' }

        if ($Source -and $srcLabel -ne $Source) { continue }

        $sync = $null; $days = $null
        if ($d.lastSyncDateTime) {
            $sync = ConvertTo-IaSafeDateTime $d.lastSyncDateTime
            if ($sync) { $days = [int][math]::Floor(($now - $sync.ToUniversalTime()).TotalDays) }
        }
        if ($PSBoundParameters.ContainsKey('StaleDays') -and ($null -eq $days -or $days -lt $StaleDays)) { continue }

        [pscustomobject][ordered]@{
            Device        = $d.deviceName
            OS            = $d.operatingSystem
            OSVersion     = $d.osVersion
            Compliance    = $d.complianceState
            Owner         = $d.managedDeviceOwnerType
            User          = if ($d.userDisplayName) { $d.userDisplayName } else { $d.userPrincipalName }
            UPN           = $d.userPrincipalName
            LastSync      = $sync
            DaysSinceSync = $days
            Manufacturer  = $d.manufacturer
            Model         = $d.model
            Serial        = $d.serialNumber
            Encrypted     = [bool]$d.isEncrypted
            EnrollmentType = $d.deviceEnrollmentType
            JoinType      = $d.joinType
            Source        = $srcLabel
            Agent         = $d.managementAgent
        }
    }
    $rows = @($rows) | Sort-Object @{
        Expression = { if ($null -eq $_.DaysSinceSync) { -1 } else { $_.DaysSinceSync } }
        Descending = $true
    }
    if ($Top -gt 0) { $rows = @($rows) | Select-Object -First $Top }
    $rows
}
