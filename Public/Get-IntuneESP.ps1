function Get-IntuneESP {
    <#
    .SYNOPSIS
        List or retrieve Enrollment Status Page (ESP) profiles.

    .DESCRIPTION
        Returns Windows 10 Enrollment Completion Page configurations from
        /deviceManagement/deviceEnrollmentConfigurations.
        Use -Id to retrieve a single ESP profile by name or GUID.

    .PARAMETER Id
        ESP profile name or GUID. When provided, returns a single profile.

    .EXAMPLE
        Get-IntuneESP

    .EXAMPLE
        Get-IntuneESP -Id 'Default ESP'

    .EXAMPLE
        Get-IntuneESP -Id 'a1b2c3d4-0000-0000-0000-000000000000'

    .OUTPUTS
        PSCustomObject per ESP: Id, Name, Priority, ShowInstallationProgress,
        BlockDeviceSetupRetryByUser, AllowDeviceResetOnInstallFailure,
        AllowDeviceUseOnInstallFailure, AllowLogCollectionOnInstallFailure,
        InstallProgressTimeoutInMinutes, TrackInstallProgressForAutopilotOnly,
        TrackedAppCount, Created, Modified.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Id
    )

    $baseFilter = "isOf('microsoft.graph.windows10EnrollmentCompletionPageConfiguration')"

    if ($Id) {
        $resolved = Resolve-IaESPId -Value $Id
        $esp = Invoke-IaRequest -Method GET `
            -Uri (Resolve-IaUri "deviceManagement/deviceEnrollmentConfigurations/$resolved")
        return ConvertTo-IaESPObject -Esp $esp
    }

    $query = "deviceManagement/deviceEnrollmentConfigurations?`$filter=$([uri]::EscapeDataString($baseFilter))&`$orderby=priority"
    $esps = Get-IaCollection (Resolve-IaUri $query)
    foreach ($esp in $esps) {
        ConvertTo-IaESPObject -Esp $esp
    }
}

function Resolve-IaESPId {
    param([string]$Value)
    if (Test-IaGuid $Value) { return $Value }
    $encoded = [uri]::EscapeDataString($Value)
    $filter  = "isOf('microsoft.graph.windows10EnrollmentCompletionPageConfiguration') and displayName eq '$encoded'"
    $results = Get-IaCollection (Resolve-IaUri "deviceManagement/deviceEnrollmentConfigurations?`$filter=$([uri]::EscapeDataString($filter))&`$select=id,displayName")
    if ($results.Count -eq 0) { throw "No ESP profile found matching '$Value'." }
    if ($results.Count -gt 1) { throw "Multiple ESP profiles match '$Value'. Provide a unique id." }
    $results[0].id
}

function ConvertTo-IaESPObject {
    param($Esp)
    [pscustomobject][ordered]@{
        Id                                    = $Esp.id
        Name                                  = $Esp.displayName
        Priority                              = $Esp.priority
        ShowInstallationProgress              = $Esp.showInstallationProgress
        BlockDeviceSetupRetryByUser           = $Esp.blockDeviceSetupRetryByUser
        AllowDeviceResetOnInstallFailure      = $Esp.allowDeviceResetOnInstallFailure
        AllowDeviceUseOnInstallFailure        = $Esp.allowDeviceUseOnInstallFailure
        AllowLogCollectionOnInstallFailure    = $Esp.allowLogCollectionOnInstallFailure
        InstallProgressTimeoutInMinutes       = $Esp.installProgressTimeoutInMinutes
        TrackInstallProgressForAutopilotOnly  = $Esp.trackInstallProgressForAutopilotOnly
        TrackedAppCount                       = if ($Esp.selectedMobileAppIds) { $Esp.selectedMobileAppIds.Count } else { 0 }
        SelectedMobileAppIds                  = $Esp.selectedMobileAppIds
        Created                               = $Esp.createdDateTime
        Modified                              = $Esp.lastModifiedDateTime
    }
}
