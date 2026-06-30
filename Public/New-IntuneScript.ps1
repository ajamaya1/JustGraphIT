function New-IntuneScript {
    <#
    .SYNOPSIS
        Upload a new PowerShell or shell script to Intune.

    .DESCRIPTION
        Creates a device management script (Windows PowerShell) or device shell
        script (macOS) from a local file. The script content is base64-encoded
        before upload.

    .PARAMETER Name
        Display name for the script.

    .PARAMETER Path
        Path to the local script file (.ps1 for Windows, .sh for macOS).

    .PARAMETER Platform
        Windows or macOS. Defaults to Windows for .ps1 files, macOS for .sh files.

    .PARAMETER Description
        Optional description.

    .PARAMETER RunAs
        Windows only: system or user (default: system).

    .PARAMETER EnforceSignatureCheck
        Windows only: require script to be signed.

    .PARAMETER Run32Bit
        Windows only: run in 32-bit PowerShell.

    .PARAMETER RetryCount
        macOS only: number of retry attempts (0-3). Default 3.

    .PARAMETER BlockExecutionNotifications
        macOS only: suppress execution notification to the user.

    .EXAMPLE
        New-IntuneScript -Name 'Set-TimeZone' -Path ./Set-TimeZone.ps1

    .EXAMPLE
        New-IntuneScript -Name 'Configure Dock' -Path ./dock.sh -Platform macOS

    .OUTPUTS
        PSCustomObject: Id, Name, Platform, FileName, Created.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Windows','macOS')][string]$Platform,
        [string]$Description,
        # Windows-specific
        [ValidateSet('system','user')][string]$RunAs = 'system',
        [switch]$EnforceSignatureCheck,
        [switch]$Run32Bit,
        # macOS-specific
        [ValidateRange(0,3)][int]$RetryCount = 3,
        [switch]$BlockExecutionNotifications
    )

    if (-not (Test-Path $Path)) { throw "File not found: '$Path'" }

    $file = Get-Item $Path
    if (-not $Platform) {
        $Platform = if ($file.Extension -eq '.sh') { 'macOS' } else { 'Windows' }
    }

    $encoded = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($file.FullName))

    if (-not $PSCmdlet.ShouldProcess($Name, 'New-IntuneScript')) { return }

    if ($Platform -eq 'Windows') {
        $body = @{
            '@odata.type'          = '#microsoft.graph.deviceManagementScript'
            displayName            = $Name
            description            = $Description ?? ''
            fileName               = $file.Name
            scriptContent          = $encoded
            runAsAccount           = $RunAs
            enforceSignatureCheck  = [bool]$EnforceSignatureCheck
            runAs32Bit             = [bool]$Run32Bit
        }
        $created = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri 'deviceManagement/deviceManagementScripts') -Body $body
    } else {
        $body = @{
            '@odata.type'                = '#microsoft.graph.deviceShellScript'
            displayName                  = $Name
            description                  = $Description ?? ''
            fileName                     = $file.Name
            scriptContent                = $encoded
            runAsAccount                 = $RunAs   # deviceShellScript uses runAsAccount, not executionContext
            retryCount                   = $RetryCount
            blockExecutionNotifications  = [bool]$BlockExecutionNotifications
        }
        $created = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri 'deviceManagement/deviceShellScripts') -Body $body
    }

    [pscustomobject][ordered]@{
        Id       = $created.id
        Name     = $created.displayName
        Platform = $Platform
        FileName = $created.fileName
        Created  = $created.createdDateTime
    }
}
