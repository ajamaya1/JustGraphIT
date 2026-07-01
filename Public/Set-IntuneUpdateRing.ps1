function Set-IntuneUpdateRing {
    <#
    .SYNOPSIS
        Update a Windows Update for Business ring.

    .DESCRIPTION
        PATCHes an existing update ring configuration with new deferral periods,
        pause states, update mode, or other settings.

    .PARAMETER Id
        Ring name or GUID to update.

    .PARAMETER NewName
        New display name.

    .PARAMETER Description
        New description.

    .PARAMETER QualityDeferralDays
        Days to defer quality/security updates (0-30).

    .PARAMETER FeatureDeferralDays
        Days to defer feature updates (0-365).

    .PARAMETER AutomaticUpdateMode
        Update installation behavior.

    .PARAMETER PauseQualityUpdates
        Pause or resume quality updates.

    .PARAMETER PauseFeatureUpdates
        Pause or resume feature updates.

    .EXAMPLE
        Set-IntuneUpdateRing -Id 'Pilot Ring' -QualityDeferralDays 7 -FeatureDeferralDays 60

    .EXAMPLE
        Set-IntuneUpdateRing -Id 'Prod Ring' -PauseQualityUpdates:$true

    .OUTPUTS
        PSCustomObject: Id, Name, Modified.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Id,
        [string]$NewName,
        [string]$Description,
        [ValidateRange(0, 30)][int]$QualityDeferralDays,
        [ValidateRange(0, 365)][int]$FeatureDeferralDays,
        [ValidateSet('userDefined','notifyDownload','autoInstallAtMaintenanceTime',
                     'autoInstallAndRebootAtMaintenanceTime','autoInstallAndRebootAtScheduledTime',
                     'autoInstallAndRebootWithoutEndUserControl','windowsDefault')]
        [string]$AutomaticUpdateMode,
        [System.Nullable[bool]]$PauseQualityUpdates,
        [System.Nullable[bool]]$PauseFeatureUpdates
    )

    $resolved = Resolve-IaUpdateRingId -Value $Id

    $patch = @{}
    if ($NewName)          { $patch['displayName']               = $NewName }
    if ($PSBoundParameters.ContainsKey('Description')) { $patch['description'] = $Description }
    if ($PSBoundParameters.ContainsKey('QualityDeferralDays'))  { $patch['qualityUpdatesDeferralPeriodInDays']  = $QualityDeferralDays }
    if ($PSBoundParameters.ContainsKey('FeatureDeferralDays'))  { $patch['featureUpdatesDeferralPeriodInDays']  = $FeatureDeferralDays }
    if ($AutomaticUpdateMode)  { $patch['automaticUpdateMode']   = $AutomaticUpdateMode }
    if ($null -ne $PauseQualityUpdates) { $patch['qualityUpdatesPaused']  = $PauseQualityUpdates }
    if ($null -ne $PauseFeatureUpdates) { $patch['featureUpdatesPaused']  = $PauseFeatureUpdates }

    if ($patch.Count -eq 0) { Write-Warning 'No changes specified.'; return }

    # deviceConfigurations is polymorphic — a PATCH that sets type-specific fields must
    # name the concrete type or Graph 400s ("property X does not exist on deviceConfiguration").
    $patch['@odata.type'] = '#microsoft.graph.windowsUpdateForBusinessConfiguration'

    if (-not $PSCmdlet.ShouldProcess($Id, 'Set-IntuneUpdateRing')) { return }

    Invoke-IaRequest -Method PATCH -Uri (Resolve-IaUri "deviceManagement/deviceConfigurations/$resolved") -Body $patch | Out-Null

    $updated = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/deviceConfigurations/$resolved")
    [pscustomobject][ordered]@{
        Id       = $updated.id
        Name     = $updated.displayName
        Modified = $updated.lastModifiedDateTime
    }
}
