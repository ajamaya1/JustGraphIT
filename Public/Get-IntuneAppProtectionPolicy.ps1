function Get-IntuneAppProtectionPolicy {
    <#
    .SYNOPSIS
        List Intune app protection (MAM) policies.

    .DESCRIPTION
        Returns mobile app management (MAM) app protection policies for iOS,
        Android, and Windows from /deviceAppManagement. These policies control
        what users can do with managed app data (copy/paste, save, PIN, etc.)
        without requiring device enrollment.

    .PARAMETER Id
        Policy name or GUID. Returns a single policy.

    .PARAMETER Platform
        Filter by platform: iOS, Android, Windows, All (default).

    .EXAMPLE
        Get-IntuneAppProtectionPolicy

    .EXAMPLE
        Get-IntuneAppProtectionPolicy -Platform iOS

    .EXAMPLE
        Get-IntuneAppProtectionPolicy -Id 'iOS MAM - Managed Devices'

    .OUTPUTS
        PSCustomObject: Id, Name, Platform, Description, Created, Modified, Settings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Id,
        [ValidateSet('All','iOS','Android','Windows')][string]$Platform = 'All'
    )

    $platformEndpoints = @{
        iOS     = 'deviceAppManagement/iosManagedAppProtections'
        Android = 'deviceAppManagement/androidManagedAppProtections'
        Windows = 'deviceAppManagement/mdmWindowsInformationProtectionPolicies'
    }

    $odataTypeMap = @{
        '#microsoft.graph.iosManagedAppProtection'                 = 'iOS'
        '#microsoft.graph.androidManagedAppProtection'             = 'Android'
        '#microsoft.graph.mdmWindowsInformationProtectionPolicy'   = 'Windows'
        '#microsoft.graph.windowsManagedAppProtection'             = 'Windows'
    }

    if ($Id) {
        # Try each platform
        $targets = if ($Platform -eq 'All') { @('iOS','Android','Windows') } else { @($Platform) }
        foreach ($plat in $targets) {
            try {
                if (Test-IaGuid $Id) {
                    $p = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "$($platformEndpoints[$plat])/$Id")
                } else {
                    $encoded = [uri]::EscapeDataString($Id)
                    $found   = Get-IaCollection (Resolve-IaUri "$($platformEndpoints[$plat])?`$filter=displayName eq '$encoded'&`$select=id,displayName")
                    if (-not $found) { continue }
                    $p = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "$($platformEndpoints[$plat])/$($found[0].id)")
                }
                return ConvertTo-IaAppProtectionObject -Policy $p -Platform $plat -ODataMap $odataTypeMap
            } catch { }
        }
        throw "No app protection policy found matching '$Id'."
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $targets  = if ($Platform -eq 'All') { @('iOS','Android','Windows') } else { @($Platform) }

    foreach ($plat in $targets) {
        try {
            $policies = Get-IaCollection (Resolve-IaUri $platformEndpoints[$plat])
            foreach ($p in $policies) {
                $results.Add((ConvertTo-IaAppProtectionObject -Policy $p -Platform $plat -ODataMap $odataTypeMap))
            }
        } catch {
            Write-Warning "Could not retrieve $plat app protection policies: $_"
        }
    }

    $results.ToArray()
}

function ConvertTo-IaAppProtectionObject {
    param($Policy, $Platform, $ODataMap)
    $derivedPlatform = $ODataMap[$Policy.'@odata.type'] ?? $Platform
    [pscustomobject][ordered]@{
        Id          = $Policy.id
        Name        = $Policy.displayName
        Platform    = $derivedPlatform
        Description = $Policy.description
        Created     = $Policy.createdDateTime
        Modified    = $Policy.lastModifiedDateTime
        Settings    = $Policy
    }
}
