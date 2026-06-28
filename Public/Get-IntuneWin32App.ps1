function Get-IntuneWin32App {
    <#
    .SYNOPSIS
        List or retrieve Win32 apps with full detail including detection and
        requirement rules.

    .DESCRIPTION
        Returns Win32 LOB apps (win32LobApp) from deviceAppManagement/mobileApps.
        Without -Id all Win32 apps are listed with a summary view. With -Id a
        single app is fetched and the full detail object is returned, including
        detection rules, requirement rules, install/uninstall commands, install
        experience settings, return codes, and minimum OS.

    .PARAMETER Id
        App display name or GUID. When omitted every Win32 app is listed.

    .EXAMPLE
        Get-IntuneWin32App

        Lists all Win32 apps with summary properties.

    .EXAMPLE
        Get-IntuneWin32App -Id 'Notepad++'

        Returns complete detail for the Notepad++ Win32 app.

    .EXAMPLE
        Get-IntuneWin32App -Id 'a1b2c3d4-0000-0000-0000-000000000000'

        Retrieves a Win32 app by GUID.

    .EXAMPLE
        Get-IntuneWin32App | Where-Object Publisher -eq 'Contoso' |
            ForEach-Object { Get-IntuneWin32App -Id $_.Id }

        Fetches full detail for every Contoso Win32 app.

    .OUTPUTS
        Summary (list): Id, Name, Publisher, Version, Created, Modified.
        Detail (single): Id, Name, Publisher, Version, Description, Developer,
        Notes, FileName, SetupFilePath, InstallCommandLine, UninstallCommandLine,
        InstallExperience, MinimumOS, DetectionRules, RequirementRules, ReturnCodes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Id
    )

    if ($Id) {
        # Resolve name to GUID if needed
        $resolvedId = Resolve-IaAppId -Value $Id

        # Verify the resolved app is actually a Win32 app; warn if not
        $app = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceAppManagement/mobileApps/$resolvedId")

        if ($app.'@odata.type' -ne '#microsoft.graph.win32LobApp') {
            Write-Warning "App '$Id' is not a Win32 LOB app (@odata.type: $($app.'@odata.type')). Returning available detail anyway."
        }

        return ConvertTo-IaWin32AppDetailObject -App $app
    }

    # List all Win32 apps
    $encoded = [uri]::EscapeDataString("isOf('microsoft.graph.win32LobApp')")
    $apps = Get-IaCollection (Resolve-IaUri "deviceAppManagement/mobileApps?`$filter=${encoded}")

    foreach ($app in $apps) {
        [pscustomobject][ordered]@{
            Id        = $app.id
            Name      = $app.displayName
            Publisher = $app.publisher
            Version   = $app.displayVersion ?? $app.appVersion
            Created   = $app.createdDateTime
            Modified  = $app.lastModifiedDateTime
        }
    }
}

function ConvertTo-IaWin32AppDetailObject {
    <#
    .SYNOPSIS
        Maps a raw Graph win32LobApp item to the rich PSGraphIT detail object.
    #>
    param([Parameter(Mandatory)]$App)

    $installExp = if ($App.installExperience) {
        [pscustomobject][ordered]@{
            RunAsAccount          = $App.installExperience.runAsAccount
            DeviceRestartBehavior = $App.installExperience.deviceRestartBehavior
        }
    }

    $minOS = if ($App.minimumSupportedWindowsRelease) {
        $App.minimumSupportedWindowsRelease
    } elseif ($App.minimumSupportedOperatingSystem) {
        # Derive a human-readable string from the boolean flags on the OS object
        $osObj = $App.minimumSupportedOperatingSystem
        $osObj.PSObject.Properties |
            Where-Object { $_.Value -eq $true } |
            Select-Object -First 1 -ExpandProperty Name
    }

    # Detection rules — return as-is; callers can inspect @odata.type for rule kind
    $detectionRules = $App.detectionRules ?? @()

    # Requirement rules
    $requirementRules = $App.requirementRules ?? @()

    # Return codes
    $returnCodes = if ($App.returnCodes) {
        $App.returnCodes | ForEach-Object {
            [pscustomobject][ordered]@{
                ReturnCode = $_.returnCode
                Type       = $_.type
            }
        }
    } else { @() }

    [pscustomobject][ordered]@{
        Id                   = $App.id
        Name                 = $App.displayName
        Publisher            = $App.publisher
        Version              = $App.displayVersion ?? $App.appVersion
        Description          = $App.description
        Developer            = $App.developer
        Notes                = $App.notes
        FileName             = $App.fileName
        SetupFilePath        = $App.setupFilePath
        InstallCommandLine   = $App.installCommandLine
        UninstallCommandLine = $App.uninstallCommandLine
        InstallExperience    = $installExp
        MinimumOS            = $minOS
        DetectionRules       = $detectionRules
        RequirementRules     = $requirementRules
        ReturnCodes          = $returnCodes
        Created              = $App.createdDateTime
        Modified             = $App.lastModifiedDateTime
    }
}
