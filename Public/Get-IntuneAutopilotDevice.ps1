function Get-IntuneAutopilotDevice {
    <#
    .SYNOPSIS
        List or retrieve Windows Autopilot device identities.

    .DESCRIPTION
        Returns Autopilot device records from
        /deviceManagement/windowsAutopilotDeviceIdentities.
        Use -SerialNumber or -GroupTag to filter the result set.

    .PARAMETER SerialNumber
        Filter by exact serial number (OData eq filter).

    .PARAMETER GroupTag
        Filter by exact group tag (OData eq filter).

    .EXAMPLE
        Get-IntuneAutopilotDevice

    .EXAMPLE
        Get-IntuneAutopilotDevice -SerialNumber 'ABC123XYZ'

    .EXAMPLE
        Get-IntuneAutopilotDevice -GroupTag 'Kiosk'

    .OUTPUTS
        PSCustomObject per device: Id, SerialNumber, Model, Manufacturer, GroupTag,
        PurchaseOrderId, EnrollmentState, LastContactedDateTime,
        AzureADDeviceId, ManagedDeviceId.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$SerialNumber,
        [string]$GroupTag
    )

    $filter = @()
    if ($SerialNumber) { $filter += "serialNumber eq '$($SerialNumber -replace "'", "''")'" }
    if ($GroupTag)     { $filter += "groupTag eq '$($GroupTag -replace "'", "''")'" }

    # NOTE: windowsAutopilotDeviceIdentities returns 500 InternalServerError on
    # server-side $orderby in many tenants, so we sort client-side instead.
    $query = 'deviceManagement/windowsAutopilotDeviceIdentities'
    if ($filter) { $query += '?$filter=' + [uri]::EscapeDataString($filter -join ' and ') }

    $devices = @(Get-IaCollection (Resolve-IaUri $query)) | Sort-Object serialNumber
    foreach ($d in $devices) {
        ConvertTo-IaAutopilotDeviceObject -Device $d
    }
}

function ConvertTo-IaAutopilotDeviceObject {
    param($Device)
    [pscustomobject][ordered]@{
        Id                      = $Device.id
        SerialNumber            = $Device.serialNumber
        Model                   = $Device.model
        Manufacturer            = $Device.manufacturer
        GroupTag                = $Device.groupTag
        PurchaseOrderId         = $Device.purchaseOrderIdentifier
        EnrollmentState         = $Device.enrollmentState
        LastContactedDateTime   = $Device.lastContactedDateTime
        AzureADDeviceId         = $Device.azureAdDeviceId
        ManagedDeviceId         = $Device.managedDeviceId
    }
}
