function Get-IntuneFeatureUpdate {
    <#
    .SYNOPSIS
        List or retrieve Windows feature update profiles.

    .DESCRIPTION
        Returns windowsFeatureUpdateProfile objects from
        /deviceManagement/windowsFeatureUpdateProfiles. Use -Id to retrieve a
        single profile by name or GUID, including rollout schedule details.

    .PARAMETER Id
        Profile name or GUID. When provided, returns a single profile.

    .EXAMPLE
        Get-IntuneFeatureUpdate

    .EXAMPLE
        Get-IntuneFeatureUpdate -Id 'Windows 11 23H2 - Broad'

    .EXAMPLE
        Get-IntuneFeatureUpdate -Id 'a1b2c3d4-0000-0000-0000-000000000000'

    .OUTPUTS
        PSCustomObject per profile: Id, Name, FeatureUpdateVersion, RolloutSettings
        (OfferStartDate, OfferEndDate, OfferIntervalDays), Created, Modified.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Id
    )

    if ($Id) {
        $resolved = Resolve-IaFeatureUpdateId -Value $Id
        $profile  = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/windowsFeatureUpdateProfiles/$resolved")
        return ConvertTo-IaFeatureUpdateObject -Profile $profile
    }

    $profiles = Get-IaCollection (Resolve-IaUri 'deviceManagement/windowsFeatureUpdateProfiles?$orderby=displayName')
    foreach ($p in $profiles) {
        ConvertTo-IaFeatureUpdateObject -Profile $p
    }
}

function Resolve-IaFeatureUpdateId {
    param([string]$Value)
    if (Test-IaGuid $Value) { return $Value }
    $encoded = [uri]::EscapeDataString($Value)
    $results = Get-IaCollection (Resolve-IaUri "deviceManagement/windowsFeatureUpdateProfiles?`$filter=displayName eq '$encoded'&`$select=id,displayName")
    if ($results.Count -eq 0) { throw "No feature update profile found matching '$Value'." }
    if ($results.Count -gt 1) { throw "Multiple profiles match '$Value'. Provide a unique id." }
    $results[0].id
}

function ConvertTo-IaFeatureUpdateObject {
    param($Profile)
    $rollout = $Profile.rolloutSettings
    [pscustomobject][ordered]@{
        Id                   = $Profile.id
        Name                 = $Profile.displayName
        FeatureUpdateVersion = $Profile.featureUpdateVersion
        RolloutSettings      = [pscustomobject][ordered]@{
            OfferStartDate    = $rollout.offerStartDateTimeInUTC
            OfferEndDate      = $rollout.offerEndDateTimeInUTC
            OfferIntervalDays = $rollout.offerIntervalInDays
        }
        Created              = $Profile.createdDateTime
        Modified             = $Profile.lastModifiedDateTime
    }
}
