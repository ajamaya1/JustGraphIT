function New-IntuneUpdateRing {
    <#
    .SYNOPSIS
        Create a new Windows Update for Business ring.

    .DESCRIPTION
        Creates a windowsUpdateForBusinessConfiguration profile under
        /deviceManagement/deviceConfigurations. Supports common deferral,
        pause, and update mode settings.

    .PARAMETER Name
        Display name for the ring (required).

    .PARAMETER Description
        Optional description.

    .PARAMETER QualityDeferralDays
        Number of days to defer quality updates (0-30). Default: 0.

    .PARAMETER FeatureDeferralDays
        Number of days to defer feature updates (0-365). Default: 0.

    .PARAMETER QualityPauseDays
        Number of days quality updates are paused. Default: 0.

    .PARAMETER BusinessReadyUpdatesOnly
        Readiness level of updates to receive. Default: businessReadyOnly.

    .PARAMETER AutomaticUpdateMode
        Automatic update behaviour. Default: autoInstallAtMaintenanceTime.

    .PARAMETER PauseQualityUpdates
        Pause quality updates immediately upon ring creation.

    .PARAMETER PauseFeatureUpdates
        Pause feature updates immediately upon ring creation.

    .EXAMPLE
        New-IntuneUpdateRing -Name 'Pilot Ring' -QualityDeferralDays 7 -FeatureDeferralDays 30

    .EXAMPLE
        New-IntuneUpdateRing -Name 'Broad Ring' `
            -QualityDeferralDays 14 `
            -FeatureDeferralDays 60 `
            -BusinessReadyUpdatesOnly businessReadyOnly `
            -AutomaticUpdateMode autoInstallAndRebootAtMaintenanceTime

    .EXAMPLE
        New-IntuneUpdateRing -Name 'Test Ring (paused)' -PauseQualityUpdates -PauseFeatureUpdates -WhatIf

    .OUTPUTS
        PSCustomObject: Id, Name, QualityDeferralDays, FeatureDeferralDays, Created.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [string]$Description,
        [ValidateRange(0, 30)][int]$QualityDeferralDays = 0,
        [ValidateRange(0, 365)][int]$FeatureDeferralDays = 0,
        [ValidateRange(0, 35)][int]$QualityPauseDays = 0,
        [ValidateSet('userDefined','all','businessReadyOnly','windowsInsiderBuildFast','windowsInsiderBuildSlow','windowsInsiderBuildRelease')]
        [string]$BusinessReadyUpdatesOnly = 'businessReadyOnly',
        [ValidateSet('userDefined','notifyDownload','autoInstallAtMaintenanceTime','autoInstallAndRebootAtMaintenanceTime','autoInstallAndRebootAtScheduledTime','autoInstallAndRebootWithoutEndUserControl','windowsDefault')]
        [string]$AutomaticUpdateMode = 'autoInstallAtMaintenanceTime',
        [switch]$PauseQualityUpdates,
        [switch]$PauseFeatureUpdates
    )

    $body = @{
        '@odata.type'                        = '#microsoft.graph.windowsUpdateForBusinessConfiguration'
        displayName                          = $Name
        description                          = $Description ?? ''
        qualityUpdatesDeferralPeriodInDays   = $QualityDeferralDays
        featureUpdatesDeferralPeriodInDays   = $FeatureDeferralDays
        qualityUpdatesPauseDurationInDays    = $QualityPauseDays
        businessReadyUpdatesOnly             = $BusinessReadyUpdatesOnly
        automaticUpdateMode                  = $AutomaticUpdateMode
        qualityUpdatesPaused                 = [bool]$PauseQualityUpdates
        featureUpdatesPaused                 = [bool]$PauseFeatureUpdates
    }

    if (-not $PSCmdlet.ShouldProcess($Name, 'New-IntuneUpdateRing')) { return }

    $created = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri 'deviceManagement/deviceConfigurations') -Body $body

    [pscustomobject][ordered]@{
        Id                        = $created.id
        Name                      = $created.displayName
        QualityDeferralDays       = $created.qualityUpdatesDeferralPeriodInDays
        FeatureDeferralDays       = $created.featureUpdatesDeferralPeriodInDays
        Created                   = $created.createdDateTime
    }
}
