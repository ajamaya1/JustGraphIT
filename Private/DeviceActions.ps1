function Resolve-IaManagedDeviceId {
    param([string]$Value)

    if (Test-IaGuid $Value) { return $Value }

    $encoded = [uri]::EscapeDataString($Value)
    $results = Get-IaCollection (Resolve-IaUri "deviceManagement/managedDevices?`$select=id,deviceName,serialNumber&`$filter=deviceName eq '$encoded'")

    if ($results.Count -eq 0) {
        $results = Get-IaCollection (Resolve-IaUri "deviceManagement/managedDevices?`$select=id,deviceName,serialNumber&`$filter=serialNumber eq '$encoded'")
    }

    if ($results.Count -eq 0) { throw "No managed device found matching '$Value'." }
    if ($results.Count -gt 1) { throw "Multiple devices match '$Value'. Provide a unique id." }

    $results[0].id
}

function Invoke-IaDevicePost {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Action,
        [hashtable]$Body = @{}
    )
    $uri = Resolve-IaUri "deviceManagement/managedDevices/$Id/$Action"
    if ($Body.Count -gt 0) {
        Invoke-IaRequest -Method POST -Uri $uri -Body $Body | Out-Null
    } else {
        Invoke-IaRequest -Method POST -Uri $uri | Out-Null
    }
}
