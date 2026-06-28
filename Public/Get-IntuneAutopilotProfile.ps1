function Get-IntuneAutopilotProfile {
    <#
    .SYNOPSIS
        List or retrieve Windows Autopilot deployment profiles.

    .DESCRIPTION
        Returns Autopilot deployment profiles from
        /deviceManagement/windowsAutopilotDeploymentProfiles.
        Use -Id to retrieve a single profile by name or GUID.

    .PARAMETER Id
        Profile name or GUID. When provided, returns a single profile.

    .EXAMPLE
        Get-IntuneAutopilotProfile

    .EXAMPLE
        Get-IntuneAutopilotProfile -Id 'Standard User OOBE'

    .EXAMPLE
        Get-IntuneAutopilotProfile -Id 'a1b2c3d4-0000-0000-0000-000000000000'

    .OUTPUTS
        PSCustomObject per profile: Id, Name, Description, Language, OobeSettings,
        OutOfBoxExperienceSettings, Created, Modified.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Id
    )

    if ($Id) {
        $resolved = Resolve-IaAutopilotProfileId -Value $Id
        $profile = Invoke-IaRequest -Method GET `
            -Uri (Resolve-IaUri "deviceManagement/windowsAutopilotDeploymentProfiles/$resolved")
        return ConvertTo-IaAutopilotProfileObject -Profile $profile
    }

    $profiles = Get-IaCollection (Resolve-IaUri 'deviceManagement/windowsAutopilotDeploymentProfiles?$orderby=displayName')
    foreach ($p in $profiles) {
        ConvertTo-IaAutopilotProfileObject -Profile $p
    }
}

function Resolve-IaAutopilotProfileId {
    param([string]$Value)
    if (Test-IaGuid $Value) { return $Value }
    $encoded = ConvertTo-IaODataValue $Value
    $results = Get-IaCollection (Resolve-IaUri "deviceManagement/windowsAutopilotDeploymentProfiles?`$filter=displayName eq '$encoded'&`$select=id,displayName")
    if ($results.Count -eq 0) { throw "No Autopilot deployment profile found matching '$Value'." }
    if ($results.Count -gt 1) { throw "Multiple profiles match '$Value'. Provide a unique id." }
    $results[0].id
}

function ConvertTo-IaAutopilotProfileObject {
    param($Profile)
    # Normalise OOBE settings — the property name changed in Graph beta
    $oobe = if ($Profile.outOfBoxExperienceSettings) {
        $Profile.outOfBoxExperienceSettings
    } elseif ($Profile.outOfBoxExperienceSetting) {
        $Profile.outOfBoxExperienceSetting
    }

    $oobeOut = if ($oobe) {
        [pscustomobject][ordered]@{
            HidePrivacySettings        = $oobe.hidePrivacySettings
            HideEULA                   = $oobe.hideEULA
            SkipKeyboardSelectionPage  = $oobe.skipKeyboardSelectionPage
            DeviceUsageType            = $oobe.deviceUsageType   # singleUser | shared
        }
    }

    [pscustomobject][ordered]@{
        Id                        = $Profile.id
        Name                      = $Profile.displayName
        Description               = $Profile.description
        Language                  = $Profile.language
        OobeSettings              = $oobeOut
        OutOfBoxExperienceSettings = $oobe
        # NOTE: windowsAutopilotDeploymentProfile has no assignedDeviceCount property
        # (verified vs beta CSDL — it exposes the assignedDevices navigation instead),
        # so that field is not surfaced here.
        Created                   = $Profile.createdDateTime
        Modified                  = $Profile.lastModifiedDateTime
    }
}
