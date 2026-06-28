function Get-IntuneRemediation {
    <#
    .SYNOPSIS
        List or retrieve Intune remediations (device health scripts).

    .DESCRIPTION
        Returns remediations from /deviceManagement/deviceHealthScripts.
        Use -Id to get a single remediation with its run summaries.
        Use -IncludeContent to decode and include both detection and
        remediation script content.

    .PARAMETER Id
        Remediation name or GUID.

    .PARAMETER IncludeContent
        Decode and include DetectionContent and RemediationContent.

    .EXAMPLE
        Get-IntuneRemediation

    .EXAMPLE
        Get-IntuneRemediation -Id 'Fix Defender' -IncludeContent

    .OUTPUTS
        PSCustomObject: Id, Name, Publisher, Version, RunSchedule, Description,
        Created, Modified, DetectionContent (opt), RemediationContent (opt).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Id,
        [switch]$IncludeContent
    )

    if ($Id) {
        $resolved = Resolve-IaRemediationId -Value $Id
        $r = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/deviceHealthScripts/$resolved")
        return ConvertTo-IaRemediationObject -Script $r -WithContent:$IncludeContent
    }

    $all = Get-IaCollection (Resolve-IaUri 'deviceManagement/deviceHealthScripts')
    foreach ($r in $all) {
        ConvertTo-IaRemediationObject -Script $r -WithContent:$IncludeContent
    }
}

function Resolve-IaRemediationId {
    param([string]$Value)
    if (Test-IaGuid $Value) { return $Value }
    $encoded = ConvertTo-IaODataValue $Value
    $results = Get-IaCollection (Resolve-IaUri "deviceManagement/deviceHealthScripts?`$filter=displayName eq '$encoded'&`$select=id,displayName")
    if ($results.Count -eq 0) { throw "No remediation found matching '$Value'." }
    if ($results.Count -gt 1) { throw "Multiple remediations match '$Value'. Provide a unique id." }
    $results[0].id
}

function ConvertTo-IaRemediationObject {
    param($Script, [switch]$WithContent)
    $obj = [pscustomobject][ordered]@{
        Id          = $Script.id
        Name        = $Script.displayName
        Publisher   = $Script.publisher
        Version     = $Script.version
        Description = $Script.description
        EnforceSignature = $Script.enforceSignatureCheck
        RunAs       = $Script.runAsAccount
        Created     = $Script.createdDateTime
        Modified    = $Script.lastModifiedDateTime
    }
    if ($WithContent) {
        $decode = { param($b64) if ($b64) { [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) } else { $null } }
        $obj | Add-Member -NotePropertyName DetectionContent   -NotePropertyValue (& $decode $Script.detectionScriptContent)
        $obj | Add-Member -NotePropertyName RemediationContent -NotePropertyValue (& $decode $Script.remediationScriptContent)
    }
    $obj
}
