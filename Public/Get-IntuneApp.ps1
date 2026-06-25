function Get-IntuneApp {
    <#
    .SYNOPSIS
        List or retrieve Intune mobile apps.

    .DESCRIPTION
        Returns apps from deviceManagement/mobileApps. Without -Id all apps are
        returned; use -AppType to filter to a specific category. With -Id a single
        app is resolved by GUID or display name. -IncludeAssignments appends the
        full assignment collection to each result object.

    .PARAMETER Id
        App display name or GUID. When supplied, returns a single matching app.

    .PARAMETER AppType
        Restrict the listing to a particular app category:
        All (default), Win32, Store, WebApp, LOB, VPP, iOS, Android, macOS, Office365.

    .PARAMETER IncludeAssignments
        When present, fetches and attaches the assignments list to every returned object.

    .EXAMPLE
        Get-IntuneApp

        Lists all mobile apps.

    .EXAMPLE
        Get-IntuneApp -AppType Win32

        Lists only Win32 (win32LobApp) apps.

    .EXAMPLE
        Get-IntuneApp -Id 'Microsoft Teams' -IncludeAssignments

        Returns the Teams app with its assignments expanded.

    .EXAMPLE
        Get-IntuneApp -Id 'a1b2c3d4-0000-0000-0000-000000000000'

        Retrieves a single app by GUID.

    .OUTPUTS
        PSCustomObject with properties: Id, Name, AppType, Publisher, Version,
        Created, Modified. Adds Assignments (array) when -IncludeAssignments is used.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Id,

        [ValidateSet('All','Win32','Store','WebApp','LOB','VPP','iOS','Android','macOS','Office365')]
        [string]$AppType = 'All',

        [switch]$IncludeAssignments
    )

    if ($Id) {
        $resolvedId = Resolve-IaAppId -Value $Id
        $app = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/mobileApps/$resolvedId")
        $obj = ConvertTo-IaAppObject -App $app
        if ($IncludeAssignments) {
            $assignments = Get-IaCollection (Resolve-IaUri "deviceManagement/mobileApps/$resolvedId/assignments")
            $obj | Add-Member -NotePropertyName Assignments -NotePropertyValue $assignments -Force
        }
        return $obj
    }

    # Build optional OData filter for AppType
    $odataFilter = switch ($AppType) {
        'Win32'    { "isOf('microsoft.graph.win32LobApp')" }
        'Store'    { "isOf('microsoft.graph.windowsStoreApp')" }
        'WebApp'   { "isOf('microsoft.graph.webApp')" }
        'LOB'      { "isOf('microsoft.graph.windowsMobileMSI')" }
        'VPP'      { "isOf('microsoft.graph.iosVppApp')" }
        'iOS'      { "isOf('microsoft.graph.iosStoreApp')" }
        'Android'  { "isOf('microsoft.graph.managedAndroidStoreApp')" }
        'macOS'    { "isOf('microsoft.graph.macOSOfficeSuiteApp')" }
        'Office365'{ "isOf('microsoft.graph.officeSuiteApp')" }
        default    { $null }
    }

    $path = 'deviceManagement/mobileApps'
    if ($odataFilter) {
        $encoded = [uri]::EscapeDataString($odataFilter)
        $path = "${path}?`$filter=${encoded}"
    }

    $apps = Get-IaCollection (Resolve-IaUri $path)

    foreach ($app in $apps) {
        $obj = ConvertTo-IaAppObject -App $app
        if ($IncludeAssignments) {
            $assignments = Get-IaCollection (Resolve-IaUri "deviceManagement/mobileApps/$($app.id)/assignments")
            $obj | Add-Member -NotePropertyName Assignments -NotePropertyValue $assignments -Force
        }
        $obj
    }
}

function Resolve-IaAppId {
    <#
    .SYNOPSIS
        Resolves an app name or GUID to a GUID.
    .DESCRIPTION
        If the value is already a GUID it is returned unchanged.
        Otherwise a displayName filter is applied to mobileApps and the first
        matching id is returned.  Throws when no match is found or ambiguous.
    #>
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Value)

    if (Test-IaGuid $Value) { return $Value }

    $encoded = [uri]::EscapeDataString($Value)
    $results = Get-IaCollection (Resolve-IaUri "deviceManagement/mobileApps?`$filter=displayName eq '$encoded'&`$select=id,displayName")

    if ($results.Count -eq 0) { throw "No app found matching '$Value'." }
    if ($results.Count -gt 1) { throw "Multiple apps match '$Value'. Provide a unique GUID." }

    $results[0].id
}

function ConvertTo-IaAppObject {
    <#
    .SYNOPSIS
        Maps a raw Graph mobileApps item to the standard IntuneTide app object.
    #>
    param([Parameter(Mandatory)]$App)

    $typeMap = @{
        '#microsoft.graph.win32LobApp'                   = 'Win32'
        '#microsoft.graph.windowsStoreApp'               = 'Store'
        '#microsoft.graph.webApp'                        = 'WebApp'
        '#microsoft.graph.windowsMobileMSI'              = 'LOB'
        '#microsoft.graph.iosVppApp'                     = 'VPP'
        '#microsoft.graph.iosStoreApp'                   = 'iOS'
        '#microsoft.graph.managedAndroidStoreApp'        = 'Android'
        '#microsoft.graph.androidStoreApp'               = 'Android'
        '#microsoft.graph.managedAndroidLobApp'          = 'Android'
        '#microsoft.graph.macOSOfficeSuiteApp'           = 'macOS'
        '#microsoft.graph.macOSLobApp'                   = 'macOS'
        '#microsoft.graph.macOSMicrosoftEdgeApp'         = 'macOS'
        '#microsoft.graph.officeSuiteApp'                = 'Office365'
        '#microsoft.graph.windowsUniversalAppX'          = 'Store'
        '#microsoft.graph.microsoftStoreForBusinessApp'  = 'Store'
    }

    $odataType = $App.'@odata.type'
    $appType   = $typeMap[$odataType]

    if (-not $appType) {
        # Regex fallback: strip prefix/suffix to derive a readable type name
        $appType = $odataType -replace '^#microsoft\.graph\.', '' `
                              -replace 'App$', '' `
                              -replace 'Lob$', 'LOB'
    }

    [pscustomobject][ordered]@{
        Id        = $App.id
        Name      = $App.displayName
        AppType   = $appType
        Publisher = $App.publisher
        Version   = $App.displayVersion ?? $App.appVersion
        Created   = $App.createdDateTime
        Modified  = $App.lastModifiedDateTime
    }
}
