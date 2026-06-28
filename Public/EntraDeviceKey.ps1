# Entra ID > Devices > recovery secrets — BitLocker recovery keys and Windows LAPS
# local-admin passwords, read straight from the directory. Both are escalation-sensitive
# reads (BitlockerKey.Read.All / DeviceLocalCredential.Read.All) and are audited by Entra.

function Get-EntraBitLockerKey {
    <#
    .SYNOPSIS
        BitLocker recovery keys from Entra. Beta GET
        /beta/informationProtection/bitlocker/recoveryKeys.
    .DESCRIPTION
        The list is metadata only (no key material). -Reveal does a second, audited GET
        per key (?$select=key) to fetch the actual recovery password. -DeviceId filters to
        one device (the Entra deviceId / azureADDeviceId).
    .EXAMPLE
        Get-EntraBitLockerKey -DeviceId 1f4f… -Reveal
    #>
    [CmdletBinding()]
    param([string]$DeviceId, [switch]$Reveal, [switch]$Raw)
    $q = "informationProtection/bitlocker/recoveryKeys?`$select=id,createdDateTime,deviceId,volumeType"
    if ($DeviceId) { $f = "deviceId eq '$($DeviceId.Replace("'", "''"))'"; $q += "&`$filter=$([uri]::EscapeDataString($f))" }
    $rows = @(Get-IaCollection (Resolve-IaUri -Path $q))
    if ($Raw) { return $rows }
    @($rows | ForEach-Object {
        $key = if ($Reveal) { try { (Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "informationProtection/bitlocker/recoveryKeys/$($_.id)?`$select=key")).key } catch { '(access denied)' } } else { '(use -Reveal)' }
        [pscustomobject][ordered]@{
            DeviceId    = $_.deviceId
            VolumeType  = $_.volumeType
            Created     = $_.createdDateTime
            KeyId       = $_.id
            RecoveryKey = $key
        }
    } | Sort-Object Created -Descending)
}

function Get-EntraLapsCredential {
    <#
    .SYNOPSIS
        Windows LAPS local-admin password(s) for a device, from Entra. Beta GET
        /beta/directory/deviceLocalCredentials/{deviceId}?$select=credentials.
    .DESCRIPTION
        Decodes the Base64 password(s), newest backup first. Keyed by the device's
        deviceId (azureADDeviceId). This reads the actual local-admin password — it is
        audited. (Rotation is Intune-only, not exposed here.)
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][ValidatePattern('^[^/?#\s]+$')][string]$DeviceId, [switch]$Raw)
    $r = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "directory/deviceLocalCredentials/${DeviceId}?`$select=credentials,deviceName")
    if ($Raw) { return $r }
    @($r.credentials | ForEach-Object {
        $pw = if ($_.passwordBase64) { try { [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_.passwordBase64)) } catch { $_.passwordBase64 } } else { $null }
        [pscustomobject][ordered]@{
            Device   = $r.deviceName
            Account  = $_.accountName
            Password = $pw
            Backup   = $_.backupDateTime
        }
    } | Sort-Object Backup -Descending)
}
