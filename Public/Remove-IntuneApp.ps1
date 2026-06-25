function Remove-IntuneApp {
    <#
    .SYNOPSIS
        Permanently delete a mobile app from Intune.

    .DESCRIPTION
        Deletes a mobile app from deviceManagement/mobileApps. The app is resolved
        by GUID or display name using Resolve-IaAppId (defined in Get-IntuneApp.ps1).

        WARNING: This operation is irreversible. Deleting an app also removes all
        of its group assignments. If you only want to unassign an app, use
        Set-IntuneAppAssignment -Clear instead.

        Accepts pipeline input from Get-IntuneApp via the Id property.

    .PARAMETER Id
        App display name or GUID to delete.

    .EXAMPLE
        Remove-IntuneApp -Id 'LegacyApp'

        Prompts for confirmation then deletes the app named 'LegacyApp'.

    .EXAMPLE
        Remove-IntuneApp -Id 'a1b2c3d4-0000-0000-0000-000000000000' -Confirm:$false

        Deletes the app by GUID without an interactive confirmation prompt.

    .EXAMPLE
        Get-IntuneApp -AppType Win32 | Where-Object Name -like '*Test*' |
            Remove-IntuneApp

        Deletes every Win32 app whose name contains 'Test', prompting once per app.

    .EXAMPLE
        Get-IntuneApp -Id 'OldApp' | Remove-IntuneApp -WhatIf

        Shows what would be deleted without actually deleting it.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [string]$Id
    )

    process {
        # Resolve display name to GUID (passthrough if already a GUID)
        $resolvedId = Resolve-IaAppId -Value $Id

        Write-Warning "Permanently removing app '$Id' ($resolvedId) and all its assignments. This cannot be undone."

        if ($PSCmdlet.ShouldProcess("$Id ($resolvedId)", 'Remove-IntuneApp: permanently delete app and all assignments')) {
            Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri "deviceManagement/mobileApps/$resolvedId") | Out-Null
            Write-Verbose "Deleted app '$Id' ($resolvedId)."
        }
    }
}
