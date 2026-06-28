function Resolve-IaManagedDeviceId {
    param([string]$Value)

    if (Test-IaGuid $Value) { return $Value }

    # OData string literals escape a single quote by DOUBLING it; the whole filter
    # is then URL-encoded for transport. (URL-encoding the value alone — the old bug —
    # turned an apostrophe into %27, which Graph decodes back to a quote that breaks
    # the literal, so a device named e.g. O'Brien-PC never matched.)
    $odv     = $Value.Replace("'", "''")
    $results = Get-IaCollection (Resolve-IaUri "deviceManagement/managedDevices?`$select=id,deviceName,serialNumber&`$filter=$([uri]::EscapeDataString("deviceName eq '$odv'"))")

    if ($results.Count -eq 0) {
        $results = Get-IaCollection (Resolve-IaUri "deviceManagement/managedDevices?`$select=id,deviceName,serialNumber&`$filter=$([uri]::EscapeDataString("serialNumber eq '$odv'"))")
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
