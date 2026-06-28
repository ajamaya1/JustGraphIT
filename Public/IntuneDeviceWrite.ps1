function Get-IntuneDeviceCategory {
    <#
    .SYNOPSIS
        Intune device categories. Beta GET /beta/deviceManagement/deviceCategories.
    #>
    [CmdletBinding()]
    param([switch]$Raw)
    $rows = @(Get-IaCollection (Resolve-IaUri -Path "deviceManagement/deviceCategories?`$select=id,displayName,description"))
    if ($Raw) { return $rows }
    @($rows | ForEach-Object { [pscustomobject][ordered]@{ Category = $_.displayName; Description = $_.description; Id = $_.id } } | Sort-Object Category)
}

function Set-IntuneDevicePrimaryUser {
    <#
    .SYNOPSIS
        Set (change) a managed device's primary user. Beta POST
        /beta/deviceManagement/managedDevices/{id}/users/$ref.
    .DESCRIPTION
        Re-points the device's primary user — the common help-desk action after a
        re-issue. Accepts a device name / serial / id and a UPN / id.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, Position = 0)][string]$Device, [Parameter(Mandatory, Position = 1)][string]$User)
    $did = Resolve-IaManagedDeviceId -Value $Device
    $uid = if (Test-IaGuid $User) { $User } else { Resolve-EntraUserId -User $User }
    if ($PSCmdlet.ShouldProcess("$Device → $User", 'Set device primary user')) {
        Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "deviceManagement/managedDevices/$did/users/`$ref") `
            -Body @{ '@odata.id' = "https://graph.microsoft.com/beta/users/$uid" } | Out-Null
        [pscustomobject]@{ Device = $Device; PrimaryUser = $User; Set = $true }
    }
}

function Set-IntuneDeviceCategory {
    <#
    .SYNOPSIS
        Assign a managed device to a device category. Beta PUT
        /beta/deviceManagement/managedDevices/{id}/deviceCategory/$ref.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, Position = 0)][string]$Device, [Parameter(Mandatory, Position = 1)][string]$Category)
    $did = Resolve-IaManagedDeviceId -Value $Device
    $cid = $Category
    if (-not (Test-IaGuid $Category)) {
        $hit = @(Get-IntuneDeviceCategory | Where-Object { $_.Category -eq $Category })
        if ($hit.Count -ne 1) { throw "Device category '$Category' not found (or ambiguous). See Get-IntuneDeviceCategory." }
        $cid = $hit[0].Id
    }
    if ($PSCmdlet.ShouldProcess("$Device → $Category", 'Set device category')) {
        Invoke-IaRequest -Method PUT -Uri (Resolve-IaUri -Path "deviceManagement/managedDevices/$did/deviceCategory/`$ref") `
            -Body @{ '@odata.id' = (Resolve-IaUri -Path "deviceManagement/deviceCategories/$cid") } | Out-Null
        [pscustomobject]@{ Device = $Device; Category = $Category; Set = $true }
    }
}
