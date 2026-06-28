function Copy-IntuneConfigurationPolicy {
    <#
    .SYNOPSIS
        Clone a Settings Catalog configuration policy.

    .DESCRIPTION
        Reads an existing policy (with its settings), creates a duplicate under a new name,
        and optionally assigns it to a group.

    .PARAMETER SourceId
        Name or GUID of the policy to clone.

    .PARAMETER NewName
        Display name for the copy (defaults to "<Source> - Copy").

    .PARAMETER AssignTo
        Group display name or GUID to assign the copy to immediately.

    .EXAMPLE
        Copy-IntuneConfigurationPolicy -SourceId 'Win Security Baseline' -NewName 'Win Security Baseline - Pilot'

    .OUTPUTS
        PSCustomObject: Id, Name, Platform, Technologies, Created.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$SourceId,
        [string]$NewName,
        [string]$AssignTo
    )

    $resolved  = Resolve-IaConfigPolicyId -Value $SourceId
    $src       = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/configurationPolicies/${resolved}?`$expand=settings")
    $targetName = if ($NewName) { $NewName } else { "$($src.name) - Copy" }

    $params = @{
        Name     = $targetName
        CopyFrom = $resolved
    }
    if ($AssignTo) { $params['AssignTo'] = $AssignTo }

    if ($PSCmdlet.ShouldProcess($targetName, 'Copy-IntuneConfigurationPolicy')) {
        New-IntuneConfigurationPolicy @params
    }
}
