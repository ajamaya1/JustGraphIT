function Get-IntuneLapsCredential {
    <#
    .SYNOPSIS
        Retrieve the Windows LAPS local-administrator account name and password for
        an Intune-managed device.

    .DESCRIPTION
        Resolves the device's Azure AD device ID, then queries Microsoft Graph for
        its Windows LAPS (Local Administrator Password Solution) credentials. The
        password is stored base64-encoded and is decoded here; the most recent
        backup is returned first.

        Graph:  GET /v1.0/directory/deviceLocalCredentials/{azureADDeviceId}?$select=credentials
        The $select=credentials is REQUIRED — without it Graph returns metadata only
        and omits the password.

        Permission: DeviceLocalCredential.Read.All  (delegated or application).
        Note: DeviceLocalCredential.ReadBasic.All returns metadata WITHOUT the
        password — use the full Read.All scope to retrieve it.

    .PARAMETER Device
        Device name or managed-device GUID.

    .EXAMPLE
        Get-IntuneLapsCredential -Device DESKTOP-ABC123

        Show the local admin account and password (newest backup first).

    .EXAMPLE
        (Get-IntuneLapsCredential -Device DESKTOP-ABC123)[0].Password | Set-Clipboard

        Copy the current password (Windows).

    .OUTPUTS
        PSCustomObject: Device, Account, Password, Sid, BackupDateTime.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Device
    )

    $id  = Resolve-IaManagedDeviceId -Value $Device
    $mdm = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/managedDevices/${id}?`$select=id,deviceName,azureADDeviceId")
    if (-not $mdm.azureADDeviceId) {
        throw "No Azure AD device ID found for '$Device' — Windows LAPS requires an Entra-joined (or hybrid-joined) device."
    }

    $aadId = $mdm.azureADDeviceId
    $info  = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -V1 "directory/deviceLocalCredentials/${aadId}?`$select=credentials")

    $creds = @($info.credentials) | Sort-Object -Property backupDateTime -Descending
    if (-not $creds) {
        Write-Warning "No LAPS credentials backed up for '$($mdm.deviceName)'. Is the Windows LAPS policy assigned and the device backing up to Entra?"
        return
    }

    foreach ($c in $creds) {
        $plain = $null
        if ($c.passwordBase64) {
            try   { $plain = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($c.passwordBase64)) }
            catch { $plain = '(could not decode password)' }
        }
        [pscustomobject][ordered]@{
            Device         = $mdm.deviceName
            Account        = $c.accountName
            Password       = $plain
            Sid            = $c.accountSid
            BackupDateTime = $c.backupDateTime
        }
    }
}
