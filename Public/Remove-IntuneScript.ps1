function Remove-IntuneScript {
    <#
    .SYNOPSIS
        Delete an Intune device management or shell script.

    .DESCRIPTION
        Deletes a Windows PowerShell script (deviceManagementScripts) or macOS
        shell script (deviceShellScripts). Platform is auto-detected from the
        GUID if not specified.

    .PARAMETER Id
        Script name or GUID to delete.

    .PARAMETER Platform
        Windows, macOS, or Auto (default: Auto — tries both).

    .EXAMPLE
        Remove-IntuneScript -Id 'Set-TimeZone'

    .EXAMPLE
        Get-IntuneScript -Platform Windows | Where-Object Name -like '*Test*' |
            ForEach-Object { Remove-IntuneScript -Id $_.Id -Platform Windows -Confirm:$false }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)][string]$Id,
        [ValidateSet('Windows','macOS','Auto')][string]$Platform = 'Auto'
    )

    process {
        $resolved = $null
        $endpoint = $null

        if ($Platform -eq 'Auto' -and (Test-IaGuid $Id)) {
            # Try Windows first, then macOS
            try {
                Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/deviceManagementScripts/$Id") | Out-Null
                $resolved = $Id; $endpoint = 'deviceManagement/deviceManagementScripts'
            } catch {
                try {
                    Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/deviceShellScripts/$Id") | Out-Null
                    $resolved = $Id; $endpoint = 'deviceManagement/deviceShellScripts'
                } catch { throw "No script found with id '$Id'." }
            }
        } elseif ($Platform -eq 'Windows' -or (-not (Test-IaGuid $Id))) {
            $all = Get-IntuneScript -Platform Windows | Where-Object { $_.Id -eq $Id -or $_.Name -eq $Id }
            if (-not $all) { $all = Get-IntuneScript -Platform macOS | Where-Object { $_.Id -eq $Id -or $_.Name -eq $Id } }
            if (-not $all) { throw "No script found matching '$Id'." }
            $resolved = $all[0].Id
            $endpoint = if ($all[0].Platform -eq 'Windows') { 'deviceManagement/deviceManagementScripts' } else { 'deviceManagement/deviceShellScripts' }
        } else {
            $resolved = $Id
            $endpoint = if ($Platform -eq 'Windows') { 'deviceManagement/deviceManagementScripts' } else { 'deviceManagement/deviceShellScripts' }
        }

        if ($PSCmdlet.ShouldProcess($Id, 'Remove-IntuneScript')) {
            Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri "$endpoint/$resolved") | Out-Null
            Write-Verbose "Deleted script '$Id'."
        }
    }
}
