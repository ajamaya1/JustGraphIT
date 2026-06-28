function New-IntuneRemediation {
    <#
    .SYNOPSIS
        Create a new Intune remediation (device health script).

    .DESCRIPTION
        Uploads a detection script and optional remediation script to
        /deviceManagement/deviceHealthScripts. Both scripts are base64-encoded.

    .PARAMETER Name
        Display name for the remediation.

    .PARAMETER DetectionScript
        Path to the PowerShell detection script file (.ps1).

    .PARAMETER RemediationScript
        Path to the PowerShell remediation script file (.ps1). Optional.

    .PARAMETER Publisher
        Publisher name (default: 'PSGraphIT').

    .PARAMETER Description
        Optional description.

    .PARAMETER RunAs
        system or user (default: system).

    .PARAMETER EnforceSignatureCheck
        Require scripts to be signed.

    .PARAMETER Version
        Version string (default: '1.0').

    .EXAMPLE
        New-IntuneRemediation -Name 'Fix Defender' -DetectionScript ./Detect-Defender.ps1 -RemediationScript ./Fix-Defender.ps1

    .EXAMPLE
        New-IntuneRemediation -Name 'Check Disk Space' -DetectionScript ./Detect-DiskSpace.ps1

    .OUTPUTS
        PSCustomObject: Id, Name, Publisher, Version, Created.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Mandatory)][string]$DetectionScript,
        [string]$RemediationScript,
        [string]$Publisher = 'PSGraphIT',
        [string]$Description,
        [ValidateSet('system','user')][string]$RunAs = 'system',
        [switch]$EnforceSignatureCheck,
        [string]$Version = '1.0'
    )

    if (-not (Test-Path $DetectionScript)) { throw "Detection script not found: '$DetectionScript'" }
    $detectEncoded = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Resolve-Path $DetectionScript).Path))

    $remediateEncoded = $null
    if ($RemediationScript) {
        if (-not (Test-Path $RemediationScript)) { throw "Remediation script not found: '$RemediationScript'" }
        $remediateEncoded = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Resolve-Path $RemediationScript).Path))
    }

    if (-not $PSCmdlet.ShouldProcess($Name, 'New-IntuneRemediation')) { return }

    $body = @{
        displayName             = $Name
        publisher               = $Publisher
        description             = $Description ?? ''
        version                 = $Version
        runAsAccount            = $RunAs
        enforceSignatureCheck   = [bool]$EnforceSignatureCheck
        detectionScriptContent  = $detectEncoded
    }
    if ($remediateEncoded) { $body['remediationScriptContent'] = $remediateEncoded }

    $created = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri 'deviceManagement/deviceHealthScripts') -Body $body

    [pscustomobject][ordered]@{
        Id        = $created.id
        Name      = $created.displayName
        Publisher = $created.publisher
        Version   = $created.version
        Created   = $created.createdDateTime
    }
}
