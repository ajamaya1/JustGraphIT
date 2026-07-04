function Get-IntuneBitLockerEscrowGap {
    <#
    .SYNOPSIS
        Windows devices that report BitLocker-encrypted but have NO recovery key
        escrowed to Entra ID — the gap you otherwise discover mid-recovery.

    .DESCRIPTION
        Cross-references the managed-device inventory (isEncrypted) against the
        tenant's escrowed BitLocker recovery keys. A device that is encrypted with
        no escrowed key is unrecoverable through Entra if the disk locks — the
        report to drive "rotate/escrow keys" remediation before it bites.

        Only key METADATA is read (id + device id) — key values are never touched,
        so BitLockerKey.ReadBasic.All is sufficient and nothing sensitive is in
        the output.

    .PARAMETER IncludeHealthy
        Also return the devices that DO have a key escrowed (KeyEscrowed = True),
        for a full posture export rather than just the gaps.

    .EXAMPLE
        Get-IntuneBitLockerEscrowGap

        Every encrypted Windows device with no recovery key in Entra.

    .EXAMPLE
        Get-IntuneBitLockerEscrowGap -IncludeHealthy | Export-Csv .\bitlocker-posture.csv

        The full estate posture for an audit.

    .OUTPUTS
        PSCustomObject: Device, User, Encrypted, KeyEscrowed, Keys, LastSync,
        AzureADDeviceId, Note.
    #>
    [CmdletBinding()]
    param([switch]$IncludeHealthy)

    $sel  = 'id,deviceName,operatingSystem,isEncrypted,azureADDeviceId,userPrincipalName,lastSyncDateTime'
    $devs = Get-IaCollection (Resolve-IaUri "deviceManagement/managedDevices?`$filter=operatingSystem eq 'Windows'&`$select=$sel")
    $devs = @($devs | Where-Object { $_.operatingSystem -eq 'Windows' })   # belt-and-braces re-filter

    # Key METADATA only — no $select=key, so the key values are never requested.
    $keys = Get-IaCollection (Resolve-IaUri "informationProtection/bitlocker/recoveryKeys?`$select=id,deviceId,createdDateTime")
    $keyCount = @{}
    foreach ($k in @($keys)) { if ($k.deviceId) { $keyCount[$k.deviceId] = 1 + [int]$keyCount[$k.deviceId] } }

    $rows = foreach ($d in $devs) {
        $aad      = [string]$d.azureADDeviceId
        $escrowed = $aad -and $keyCount.ContainsKey($aad)
        $note     = if (-not $d.isEncrypted) { 'not encrypted' }
                    elseif (-not $aad)       { 'encrypted but no Entra device id — key cannot be escrowed' }
                    elseif (-not $escrowed)  { 'ENCRYPTED, NO KEY IN ENTRA — unrecoverable via portal' }
                    else                     { 'key escrowed' }
        [pscustomobject][ordered]@{
            Device          = $d.deviceName
            User            = $d.userPrincipalName
            Encrypted       = [bool]$d.isEncrypted
            KeyEscrowed     = [bool]$escrowed
            Keys            = if ($aad) { [int]$keyCount[$aad] } else { 0 }
            LastSync        = ConvertTo-IaSafeDateTime $d.lastSyncDateTime
            AzureADDeviceId = $aad
            Note            = $note
        }
    }

    if ($IncludeHealthy) { return @($rows | Sort-Object KeyEscrowed, Device) }
    @($rows | Where-Object { $_.Encrypted -and -not $_.KeyEscrowed } | Sort-Object Device)
}
