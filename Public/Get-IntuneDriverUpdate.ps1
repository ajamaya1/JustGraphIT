function Get-IntuneDriverUpdate {
    <#
    .SYNOPSIS
        List or retrieve Windows driver update profiles.

    .DESCRIPTION
        Returns windowsDriverUpdateProfile objects from
        /deviceManagement/windowsDriverUpdateProfiles. Use -Id to retrieve a
        single profile by name or GUID. Use -IncludeInventory to also fetch the
        driver inventory (applicable drivers) for each returned profile.

    .PARAMETER Id
        Profile name or GUID. When provided, returns a single profile.

    .PARAMETER IncludeInventory
        When set, fetches the driver inventory list for each profile by calling
        /windowsDriverUpdateProfiles/{id}/driverInventories and attaches it as
        the Inventory property.

    .EXAMPLE
        Get-IntuneDriverUpdate

    .EXAMPLE
        Get-IntuneDriverUpdate -Id 'Automatic Driver Updates'

    .EXAMPLE
        Get-IntuneDriverUpdate -Id 'a1b2c3d4-0000-0000-0000-000000000000' -IncludeInventory

    .EXAMPLE
        # Retrieve all profiles and their inventories
        Get-IntuneDriverUpdate -IncludeInventory

    .OUTPUTS
        PSCustomObject per profile: Id, Name, ApprovalType, DeploymentDeferralInDays,
        Created, Modified, and (with -IncludeInventory) Inventory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Id,
        [switch]$IncludeInventory
    )

    if ($Id) {
        $resolved = Resolve-IaDriverUpdateId -Value $Id
        $profile  = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/windowsDriverUpdateProfiles/$resolved")
        return ConvertTo-IaDriverUpdateObject -Profile $profile -IncludeInventory:$IncludeInventory
    }

    $profiles = Get-IaCollection (Resolve-IaUri 'deviceManagement/windowsDriverUpdateProfiles?$orderby=displayName')
    foreach ($p in $profiles) {
        ConvertTo-IaDriverUpdateObject -Profile $p -IncludeInventory:$IncludeInventory
    }
}

function Resolve-IaDriverUpdateId {
    param([string]$Value)
    if (Test-IaGuid $Value) { return $Value }
    $encoded = [uri]::EscapeDataString($Value)
    $results = Get-IaCollection (Resolve-IaUri "deviceManagement/windowsDriverUpdateProfiles?`$filter=displayName eq '$encoded'&`$select=id,displayName")
    if ($results.Count -eq 0) { throw "No driver update profile found matching '$Value'." }
    if ($results.Count -gt 1) { throw "Multiple profiles match '$Value'. Provide a unique id." }
    $results[0].id
}

function ConvertTo-IaDriverUpdateObject {
    param($Profile, [switch]$IncludeInventory)
    $obj = [pscustomobject][ordered]@{
        Id                       = $Profile.id
        Name                     = $Profile.displayName
        ApprovalType             = $Profile.approvalType
        DeploymentDeferralInDays = $Profile.deploymentDeferralInDays
        Created                  = $Profile.createdDateTime
        Modified                 = $Profile.lastModifiedDateTime
    }
    if ($IncludeInventory) {
        $inventory = Get-IaCollection (Resolve-IaUri "deviceManagement/windowsDriverUpdateProfiles/$($Profile.id)/driverInventories")
        $obj | Add-Member -NotePropertyName Inventory -NotePropertyValue $inventory
    }
    $obj
}
