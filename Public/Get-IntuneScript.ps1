function Get-IntuneScript {
    <#
    .SYNOPSIS
        List or retrieve Intune device management scripts.

    .DESCRIPTION
        Returns Windows PowerShell scripts (deviceManagementScripts) or
        macOS shell scripts (deviceShellScripts). Use -Id to get a single
        script. -IncludeContent decodes and returns the script body.

    .PARAMETER Id
        Script name or GUID.

    .PARAMETER Platform
        Windows or macOS (default: both).

    .PARAMETER IncludeContent
        Decode and include the script content in the output.

    .EXAMPLE
        Get-IntuneScript

    .EXAMPLE
        Get-IntuneScript -Platform Windows

    .EXAMPLE
        Get-IntuneScript -Id 'Set-TimeZone' -IncludeContent

    .OUTPUTS
        PSCustomObject: Id, Name, Platform, Description, RunAs, Created, Modified,
        and (with -IncludeContent) Content.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Id,
        [ValidateSet('Windows','macOS','Both')][string]$Platform = 'Both',
        [switch]$IncludeContent
    )

    if ($Id) {
        $script = $null
        if ($Platform -in 'Windows','Both') {
            try { $script = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/deviceManagementScripts/$Id") } catch { }
        }
        if (-not $script -and $Platform -in 'macOS','Both') {
            try { $script = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/deviceShellScripts/$Id") } catch { }
        }
        if (-not $script) {
            # Try by name
            $script = Get-IntuneScript -Platform $Platform | Where-Object Name -eq $Id | Select-Object -First 1
            if (-not $script) { throw "No script found matching '$Id'." }
        }
        if ($IncludeContent -and $script.scriptContent) {
            $script | Add-Member -NotePropertyName Content -NotePropertyValue ([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($script.scriptContent))) -Force
        }
        return $script
    }

    $results = [System.Collections.Generic.List[object]]::new()

    if ($Platform -in 'Windows','Both') {
        $win = Get-IaCollection (Resolve-IaUri 'deviceManagement/deviceManagementScripts')
        foreach ($s in $win) {
            $obj = [pscustomobject][ordered]@{
                Id          = $s.id
                Name        = $s.displayName
                Platform    = 'Windows'
                Description = $s.description
                FileName    = $s.fileName
                RunAs       = $s.runAsAccount
                EnforceSignature = $s.enforceSignatureCheck
                Run32Bit    = $s.runAs32Bit
                Created     = $s.createdDateTime
                Modified    = $s.lastModifiedDateTime
            }
            if ($IncludeContent -and $s.scriptContent) {
                $obj | Add-Member -NotePropertyName Content -NotePropertyValue ([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s.scriptContent)))
            }
            $results.Add($obj)
        }
    }

    if ($Platform -in 'macOS','Both') {
        $mac = Get-IaCollection (Resolve-IaUri 'deviceManagement/deviceShellScripts')
        foreach ($s in $mac) {
            $obj = [pscustomobject][ordered]@{
                Id          = $s.id
                Name        = $s.displayName
                Platform    = 'macOS'
                Description = $s.description
                FileName    = $s.fileName
                RunAs       = $s.executionContext
                RetryCount  = $s.retryCount
                BlockExec   = $s.blockExecutionNotifications
                Created     = $s.createdDateTime
                Modified    = $s.lastModifiedDateTime
            }
            if ($IncludeContent -and $s.scriptContent) {
                $obj | Add-Member -NotePropertyName Content -NotePropertyValue ([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s.scriptContent)))
            }
            $results.Add($obj)
        }
    }

    $results.ToArray()
}
