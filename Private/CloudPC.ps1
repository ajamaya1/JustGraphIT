$script:IaW365Base = 'deviceManagement/virtualEndpoint'

function Get-IaW365Path {
    param([Parameter(Mandatory)][string]$Sub)
    "$script:IaW365Base/$Sub"
}

function Resolve-IaCloudPCId {
    param([Parameter(Mandatory)][string]$Value)
    if (Test-IaGuid $Value) { return $Value }
    $items = Get-IaCollection (Get-IaW365Path 'cloudPCs?$select=id,displayName')
    $matches = @($items | Where-Object { $_.displayName -eq $Value })
    if ($matches.Count -eq 0) { throw "No Cloud PC named '$Value' was found." }
    if ($matches.Count -gt 1) { throw "Ambiguous name '$Value' matches $($matches.Count) Cloud PCs. Use an id." }
    $matches[0].id
}

function Resolve-IaProvisioningPolicyId {
    param([Parameter(Mandatory)][string]$Value)
    if (Test-IaGuid $Value) { return $Value }
    $items = Get-IaCollection (Get-IaW365Path 'provisioningPolicies?$select=id,displayName')
    $matches = @($items | Where-Object { $_.displayName -eq $Value })
    if ($matches.Count -eq 0) { throw "No provisioning policy named '$Value' was found." }
    if ($matches.Count -gt 1) { throw "Ambiguous name '$Value' matches $($matches.Count) provisioning policies. Use an id." }
    $matches[0].id
}

function Resolve-IaConnectionId {
    param([Parameter(Mandatory)][string]$Value)
    if (Test-IaGuid $Value) { return $Value }
    $items = Get-IaCollection (Get-IaW365Path 'onPremisesConnections?$select=id,displayName')
    $matches = @($items | Where-Object { $_.displayName -eq $Value })
    if ($matches.Count -eq 0) { throw "No on-premises connection named '$Value' was found." }
    if ($matches.Count -gt 1) { throw "Ambiguous name '$Value' matches $($matches.Count) connections. Use an id." }
    $matches[0].id
}

function Invoke-IaCloudPCPost {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Action,
        [hashtable]$Body = @{}
    )
    $path = Get-IaW365Path "cloudPCs/$Id/$Action"
    $uri  = Resolve-IaUri -Path $path
    if ($Body.Count -gt 0) {
        Invoke-IaRequest -Method POST -Uri $uri -Body $Body
    } else {
        Invoke-IaRequest -Method POST -Uri $uri
    }
}

function Format-IaCloudPCStatus {
    param(
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Accent
    )
    $color = switch ($Status) {
        'provisioned'         { $Accent }
        'provisioning'        { 'yellow' }
        'upgradePending'      { 'yellow' }
        'restoreInProgress'   { 'yellow' }
        'inGracePeriod'       { 'orange1' }
        'provisioningFailed'  { 'coral' }
        'failed'              { 'coral' }
        'deprovisioned'       { 'grey' }
        'notProvisioned'      { 'grey' }
        default               { 'white' }
    }
    "[$color]$Status[/]"
}
