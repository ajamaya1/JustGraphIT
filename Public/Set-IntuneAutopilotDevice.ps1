function Set-IntuneAutopilotDevice {
    <#
    .SYNOPSIS
        Update Windows Autopilot device attributes.

    .DESCRIPTION
        Updates the group tag and/or display name of an Autopilot device by
        posting to the Graph action endpoint
        deviceManagement/windowsAutopilotDeviceIdentities/{id}/updateDeviceProperties.
        Accepts a GUID or serial number for -Id.

    .PARAMETER Id
        Autopilot device GUID or serial number.

    .PARAMETER GroupTag
        New group tag to assign to the device.

    .PARAMETER DisplayName
        New display name to assign to the device.

    .EXAMPLE
        Set-IntuneAutopilotDevice -Id 'ABC123XYZ' -GroupTag 'Kiosk'

    .EXAMPLE
        Set-IntuneAutopilotDevice -Id 'a1b2c3d4-0000-0000-0000-000000000000' -DisplayName 'KIOSK-01' -GroupTag 'Kiosk'

    .OUTPUTS
        PSCustomObject: Id, SerialNumber, GroupTag, Updated.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)][string]$Id,
        [string]$GroupTag,
        [string]$DisplayName
    )

    process {
        if (-not $GroupTag -and -not $DisplayName) {
            Write-Warning 'No changes specified. Provide -GroupTag, -DisplayName, or both.'
            return
        }

        $resolved = Resolve-IaAutopilotId -Value $Id

        $body = [ordered]@{}
        if ($PSBoundParameters.ContainsKey('GroupTag'))   { $body['groupTag']    = $GroupTag }
        if ($PSBoundParameters.ContainsKey('DisplayName')) { $body['displayName'] = $DisplayName }

        if ($PSCmdlet.ShouldProcess($Id, 'Set-IntuneAutopilotDevice')) {
            Invoke-IaRequest -Method POST `
                -Uri (Resolve-IaUri "deviceManagement/windowsAutopilotDeviceIdentities/$resolved/updateDeviceProperties") `
                -Body $body | Out-Null

            # Re-fetch the device to return current state
            $device = Invoke-IaRequest -Method GET `
                -Uri (Resolve-IaUri "deviceManagement/windowsAutopilotDeviceIdentities/$resolved")

            [pscustomobject][ordered]@{
                Id           = $device.id
                SerialNumber = $device.serialNumber
                GroupTag     = $device.groupTag
                Updated      = (Get-Date).ToUniversalTime().ToString('o')
            }
        }
    }
}

function Resolve-IaAutopilotId {
    param([string]$Value)
    if (Test-IaGuid $Value) { return $Value }
    $encoded = ConvertTo-IaODataValue $Value
    $results = Get-IaCollection (Resolve-IaUri "deviceManagement/windowsAutopilotDeviceIdentities?`$filter=serialNumber eq '$encoded'&`$select=id,serialNumber")
    if ($results.Count -eq 0) { throw "No Autopilot device found with serial number '$Value'." }
    if ($results.Count -gt 1) { throw "Multiple Autopilot devices match serial number '$Value'. Provide a GUID." }
    $results[0].id
}
