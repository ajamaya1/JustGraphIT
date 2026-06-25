function Get-IntuneDeviceConfiguration {
    <#
    .SYNOPSIS
        List or retrieve legacy device configuration profiles.

    .DESCRIPTION
        Returns device configurations from /deviceManagement/deviceConfigurations
        (the legacy endpoint, not configurationPolicies / Settings Catalog).
        Platform is derived from the @odata.type of each profile.
        Use -Id to retrieve a single profile by name or GUID.
        Use -Platform to filter the result set.

    .PARAMETER Id
        Profile name or GUID. When provided, returns a single profile.

    .PARAMETER Platform
        Filter by platform: All (default), Windows, macOS, iOS, Android,
        AndroidWorkProfile.

    .EXAMPLE
        Get-IntuneDeviceConfiguration

    .EXAMPLE
        Get-IntuneDeviceConfiguration -Platform Windows

    .EXAMPLE
        Get-IntuneDeviceConfiguration -Id 'Windows Defender Baseline'

    .OUTPUTS
        PSCustomObject per profile: Id, Name, Platform, ODataType, Description,
        Created, Modified.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Id,
        [ValidateSet('All', 'Windows', 'macOS', 'iOS', 'Android', 'AndroidWorkProfile')]
        [string]$Platform = 'All'
    )

    if ($Id) {
        $resolved = Resolve-IaDeviceConfigId -Value $Id
        $config = Invoke-IaRequest -Method GET `
            -Uri (Resolve-IaUri "deviceManagement/deviceConfigurations/$resolved")
        return ConvertTo-IaDeviceConfigObject -Config $config
    }

    $configs = Get-IaCollection (Resolve-IaUri 'deviceManagement/deviceConfigurations?$orderby=displayName')
    foreach ($c in $configs) {
        $obj = ConvertTo-IaDeviceConfigObject -Config $c
        if ($Platform -eq 'All' -or $obj.Platform -eq $Platform) { $obj }
    }
}

function Resolve-IaDeviceConfigId {
    param([string]$Value)
    if (Test-IaGuid $Value) { return $Value }
    $encoded = [uri]::EscapeDataString($Value)
    $results = Get-IaCollection (Resolve-IaUri "deviceManagement/deviceConfigurations?`$filter=displayName eq '$encoded'&`$select=id,displayName")
    if ($results.Count -eq 0) { throw "No device configuration found matching '$Value'." }
    if ($results.Count -gt 1) { throw "Multiple device configurations match '$Value'. Provide a unique id." }
    $results[0].id
}

function ConvertTo-IaDeviceConfigObject {
    param($Config)
    $odataType = $Config.'@odata.type'
    $platformMap = @{
        'windows10GeneralConfiguration'             = 'Windows'
        'windows10EndpointProtectionConfiguration'  = 'Windows'
        'windows10CustomConfiguration'              = 'Windows'
        'windows81GeneralConfiguration'             = 'Windows'
        'windowsPhone81GeneralConfiguration'        = 'Windows'
        'windowsUpdateForBusinessConfiguration'     = 'Windows'
        'macOSGeneralDeviceConfiguration'           = 'macOS'
        'macOSCustomConfiguration'                  = 'macOS'
        'macOSExtensionsConfiguration'              = 'macOS'
        'iosGeneralDeviceConfiguration'             = 'iOS'
        'iosCustomConfiguration'                    = 'iOS'
        'iosUpdateConfiguration'                    = 'iOS'
        'androidGeneralDeviceConfiguration'         = 'Android'
        'androidCustomConfiguration'                = 'Android'
        'androidWorkProfileGeneralDeviceConfiguration' = 'AndroidWorkProfile'
        'androidWorkProfileCustomConfiguration'     = 'AndroidWorkProfile'
    }

    $shortType = $odataType -replace '^#microsoft\.graph\.', ''
    $platform  = $platformMap[$shortType] ?? ($shortType -replace '(General|Device|Custom)?Configuration$', '' -replace '(ios|iOS)', 'iOS' -replace '(macos|macOS|macOSX)', 'macOS' -replace '(android|Android)WorkProfile.*', 'AndroidWorkProfile' -replace '(android|Android).*', 'Android' -replace '(windows|Windows).*', 'Windows')

    [pscustomobject][ordered]@{
        Id          = $Config.id
        Name        = $Config.displayName
        Platform    = $platform
        ODataType   = $shortType
        Description = $Config.description
        Created     = $Config.createdDateTime
        Modified    = $Config.lastModifiedDateTime
    }
}
