function New-IntuneFeatureUpdate {
    <#
    .SYNOPSIS
        Create a new Windows feature update profile.

    .DESCRIPTION
        Creates a windowsFeatureUpdateProfile under
        /deviceManagement/windowsFeatureUpdateProfiles. Optionally configures a
        gradual rollout schedule with a start date, end date, and interval.

    .PARAMETER Name
        Display name for the profile (required).

    .PARAMETER FeatureUpdateVersion
        Target Windows version string, e.g. 'Windows 11, version 23H2' (required).

    .PARAMETER Description
        Optional description.

    .PARAMETER RolloutStartDate
        UTC datetime at which devices begin receiving the feature update offer.

    .PARAMETER RolloutEndDate
        UTC datetime after which no new devices are offered the update.

    .PARAMETER RolloutIntervalDays
        Number of days between each incremental rollout group offer.

    .EXAMPLE
        New-IntuneFeatureUpdate -Name 'Win11 23H2 - Pilot' -FeatureUpdateVersion 'Windows 11, version 23H2'

    .EXAMPLE
        New-IntuneFeatureUpdate -Name 'Win11 23H2 - Broad' `
            -FeatureUpdateVersion 'Windows 11, version 23H2' `
            -RolloutStartDate (Get-Date '2025-02-01') `
            -RolloutEndDate   (Get-Date '2025-04-01') `
            -RolloutIntervalDays 7

    .EXAMPLE
        New-IntuneFeatureUpdate -Name 'Win11 23H2 - Test' -FeatureUpdateVersion 'Windows 11, version 23H2' -WhatIf

    .OUTPUTS
        PSCustomObject: Id, Name, FeatureUpdateVersion, Created.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Mandatory)][string]$FeatureUpdateVersion,
        [string]$Description,
        [datetime]$RolloutStartDate,
        [datetime]$RolloutEndDate,
        [ValidateRange(1, 60)][int]$RolloutIntervalDays
    )

    $body = @{
        displayName          = $Name
        description          = $Description ?? ''
        featureUpdateVersion = $FeatureUpdateVersion
    }

    # Build rolloutSettings only when at least one rollout parameter is supplied
    if ($PSBoundParameters.ContainsKey('RolloutStartDate') -or
        $PSBoundParameters.ContainsKey('RolloutEndDate')   -or
        $PSBoundParameters.ContainsKey('RolloutIntervalDays')) {

        $rollout = @{}
        if ($PSBoundParameters.ContainsKey('RolloutStartDate'))    { $rollout.offerStartDateTimeInUTC = $RolloutStartDate.ToUniversalTime().ToString('o') }
        if ($PSBoundParameters.ContainsKey('RolloutEndDate'))      { $rollout.offerEndDateTimeInUTC   = $RolloutEndDate.ToUniversalTime().ToString('o') }
        if ($PSBoundParameters.ContainsKey('RolloutIntervalDays')) { $rollout.offerIntervalInDays     = $RolloutIntervalDays }
        $body.rolloutSettings = $rollout
    }

    if (-not $PSCmdlet.ShouldProcess($Name, 'New-IntuneFeatureUpdate')) { return }

    $created = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri 'deviceManagement/windowsFeatureUpdateProfiles') -Body $body

    [pscustomobject][ordered]@{
        Id                   = $created.id
        Name                 = $created.displayName
        FeatureUpdateVersion = $created.featureUpdateVersion
        Created              = $created.createdDateTime
    }
}
