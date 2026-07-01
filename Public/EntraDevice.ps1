# Entra ID > Devices blade — the directory device objects (registered / joined /
# hybrid), distinct from Intune managedDevices. Enable/disable, rename, delete and
# read registered owners, all beta. Enable/disable is a PATCH of accountEnabled (Graph
# has no dedicated enable/disable action).

function Resolve-EntraDeviceId {
    # Device OBJECT id / deviceId (GUID) / displayName → the device OBJECT id that the
    # write endpoints key on.
    param([Parameter(Mandatory)][string]$Device)
    if (Test-IaGuid $Device) {
        # a GUID may be the object id (direct GET) or the deviceId (filter)
        try { $d = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "devices/${Device}?`$select=id"); if ($d.id) { return [string]$d.id } } catch { }
        $byDev = @(Get-IaCollection (Resolve-IaUri -Path "devices?`$filter=deviceId eq '$Device'&`$select=id"))
        if ($byDev) { return [string]$byDev[0].id }
        throw "No Entra device with object id / deviceId '$Device'."
    }
    $f   = "displayName eq '$($Device.Replace("'", "''"))'"
    $res = @(Get-IaCollection (Resolve-IaUri -Path "devices?`$filter=$([uri]::EscapeDataString($f))&`$select=id,displayName&`$top=5"))
    if ($res.Count -eq 1) { return [string]$res[0].id }
    if ($res.Count -gt 1) { throw "Multiple devices named '$Device'. Use the object id or deviceId." }
    throw "No Entra device found matching '$Device'."
}

function Get-EntraDevice {
    <#
    .SYNOPSIS
        Entra registered / joined devices (Entra ID > Devices > All devices). Beta GET
        /beta/devices.
    .DESCRIPTION
        The directory device objects — distinct from Intune managedDevices. Carries the
        object Id (for writes) and the deviceId. Filter with -Disabled, -StaleDays
        (no interactive sign-in in N days), or a raw -Filter.
    .PARAMETER StaleDays
        Only devices whose approximateLastSignInDateTime is older than N days (advanced
        query — sends the ConsistencyLevel header).
    .EXAMPLE
        Get-EntraDevice -Disabled
    .EXAMPLE
        Get-EntraDevice -Filter "operatingSystem eq 'Windows'" -Top 500
    #>
    [CmdletBinding()]
    param([string]$Filter, [int]$Top = 200, [switch]$Disabled, [int]$StaleDays, [switch]$Raw)
    $sel = 'id,deviceId,displayName,accountEnabled,operatingSystem,operatingSystemVersion,trustType,isCompliant,isManaged,approximateLastSignInDateTime,registrationDateTime'
    $clauses = @(); $advanced = $false
    if ($Disabled)        { $clauses += 'accountEnabled eq false' }
    if ($StaleDays -gt 0) { $clauses += "approximateLastSignInDateTime le $([DateTime]::UtcNow.AddDays(-$StaleDays).ToString('yyyy-MM-ddTHH:mm:ssZ'))"; $advanced = $true }
    if ($Filter)          { $clauses += "($Filter)" }
    $q = "devices?`$top=$Top&`$select=$sel"
    if ($clauses) {
        $q += "&`$filter=$([uri]::EscapeDataString($clauses -join ' and '))"
        if ($advanced) { $q += '&$count=true' }
    }
    $rows = @(Get-IaCollection (Resolve-IaUri -Path $q) -ConsistencyLevel:$advanced)
    if ($Raw) { return $rows }
    @($rows | ForEach-Object {
        $last = $_.approximateLastSignInDateTime
        $lastDt = ConvertTo-IaSafeDateTime $last
        [pscustomobject][ordered]@{
            DisplayName = $_.displayName
            Enabled     = $_.accountEnabled
            OS          = $_.operatingSystem
            OSVersion   = $_.operatingSystemVersion
            Trust       = $_.trustType
            Compliant   = $_.isCompliant
            Managed     = $_.isManaged
            LastSignIn  = if ($lastDt) { $lastDt.ToString('yyyy-MM-dd') } else { $null }
            DaysStale   = if ($lastDt) { [int]([DateTime]::UtcNow - $lastDt.ToUniversalTime()).TotalDays } else { $null }
            DeviceId    = $_.deviceId
            Id          = $_.id
        }
    } | Sort-Object DisplayName)
}

function Set-EntraDevice {
    <#
    .SYNOPSIS
        Enable / disable, rename, or set extension attributes on an Entra device. Beta
        PATCH /beta/devices/{id}.
    .DESCRIPTION
        Disabling a device blocks it from authenticating (Conditional Access "device" /
        Entra-joined sign-in) — reversible by enabling it again. Enabling/disabling needs
        at least Cloud Device Administrator.
    .PARAMETER AccountEnabled
        $true to enable, $false to disable.
    .PARAMETER ExtensionAttribute
        Hashtable of extensionAttribute1..15 to set (e.g. @{ extensionAttribute1 = 'BYOD' }).
    .EXAMPLE
        Set-EntraDevice -Device 'LAPTOP-7' -AccountEnabled $false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Device,
        [System.Nullable[bool]]$AccountEnabled,
        [string]$DisplayName,
        [hashtable]$ExtensionAttribute
    )
    $id   = Resolve-EntraDeviceId -Device $Device
    $body = [ordered]@{}
    if ($PSBoundParameters.ContainsKey('AccountEnabled')) { $body.accountEnabled = [bool]$AccountEnabled }
    if ($DisplayName)        { $body.displayName = $DisplayName }
    if ($ExtensionAttribute) { $body.extensionAttributes = $ExtensionAttribute }
    if (-not $body.Count) { Write-Warning 'Nothing to update.'; return }
    $verb = if ($PSBoundParameters.ContainsKey('AccountEnabled')) { if ($AccountEnabled) { 'Enable' } else { 'Disable' } } else { 'Update' }
    if ($PSCmdlet.ShouldProcess($Device, "$verb device")) {
        Invoke-IaRequest -Method PATCH -Uri (Resolve-IaUri -Path "devices/$id") -Body $body | Out-Null
        [pscustomobject]@{ Device = $Device; Updated = (@($body.Keys) -join ', ') }
    }
}

function Remove-EntraDevice {
    <#
    .SYNOPSIS
        Delete an Entra device object. Beta DELETE /beta/devices/{id}.
    .DESCRIPTION
        Removes the directory device record (the device must re-register to come back).
        This is NOT an Intune wipe/retire — use the Intune device actions for that.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory, Position = 0)][string]$Device)
    $id = Resolve-EntraDeviceId -Device $Device
    if ($PSCmdlet.ShouldProcess($Device, 'Delete Entra device object')) {
        Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri -Path "devices/$id") | Out-Null
        [pscustomobject]@{ Device = $Device; Deleted = $true }
    }
}

function Get-EntraDeviceRegisteredOwner {
    <#
    .SYNOPSIS
        The registered owner(s) of an Entra device. Beta GET
        /beta/devices/{id}/registeredOwners.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Device)
    $id = Resolve-EntraDeviceId -Device $Device
    @(Get-IaCollection (Resolve-IaUri -Path "devices/$id/registeredOwners?`$select=id,displayName,userPrincipalName") | ForEach-Object {
        [pscustomobject][ordered]@{ Name = $_.displayName; UPN = $_.userPrincipalName; Id = $_.id }
    })
}
