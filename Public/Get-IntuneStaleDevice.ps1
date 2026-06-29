function Get-IntuneStaleDevice {
    <#
    .SYNOPSIS
        Managed devices that haven't checked in (synced) for N+ days. Beta GET
        /beta/deviceManagement/managedDevices filtered on lastSyncDateTime.
    .DESCRIPTION
        The "stale device" report — the population you'd target for clean-up or a
        dynamic/assigned group. Each row carries the Entra azureADDeviceId so the set
        can be pushed straight into a group (see Add-EntraGroupMemberBulk, or the
        TUI's "stale devices → group" flow). -Raw returns the untouched device objects.
    .PARAMETER Days
        Staleness threshold in days (default 30).
    .PARAMETER OS
        Optional client-side operating-system filter (e.g. Windows, iOS, Android, macOS).
    .OUTPUTS
        PSCustomObject: DeviceName, OS, OSVersion, LastSync, DaysStale, User,
        Ownership, Compliance, AzureAdDeviceId, Id.
    #>
    [CmdletBinding()]
    param([int]$Days = 30, [string]$OS, [switch]$Raw)
    $cutoff = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $sel    = 'id,deviceName,operatingSystem,osVersion,lastSyncDateTime,userPrincipalName,' +
              'managedDeviceOwnerType,complianceState,azureADDeviceId,model,manufacturer'
    $filter = "lastSyncDateTime le $cutoff"
    $devices = @(Get-IaCollection (Resolve-IaUri "deviceManagement/managedDevices?`$filter=$([uri]::EscapeDataString($filter))&`$select=$sel"))
    if ($OS) { $devices = @($devices | Where-Object { $_.operatingSystem -like "*$OS*" }) }
    if ($Raw) { return $devices }
    $now = (Get-Date).ToUniversalTime()
    @($devices | ForEach-Object {
        $last  = $_.lastSyncDateTime
        $lastDt = ConvertTo-IaSafeDateTime $last
        $stale = if ($lastDt) { [int][math]::Floor(($now - $lastDt.ToUniversalTime()).TotalDays) } else { $null }
        [pscustomobject][ordered]@{
            DeviceName      = $_.deviceName
            OS              = $_.operatingSystem
            OSVersion       = $_.osVersion
            LastSync        = if ($lastDt) { $lastDt.ToString('yyyy-MM-dd') } else { 'never' }
            DaysStale       = $stale
            User            = $_.userPrincipalName
            Ownership       = $_.managedDeviceOwnerType
            Compliance      = $_.complianceState
            AzureAdDeviceId = $_.azureADDeviceId
            Id              = $_.id
        }
    } | Sort-Object DaysStale -Descending)
}
