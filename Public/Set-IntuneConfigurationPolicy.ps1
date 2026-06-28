function Set-IntuneConfigurationPolicy {
    <#
    .SYNOPSIS
        Update a Settings Catalog configuration policy.

    .DESCRIPTION
        Patches metadata (name, description, scope tags) on an existing policy.
        When -Settings is supplied the full settings array is replaced via PUT to
        /deviceManagement/configurationPolicies/{id}/settings.

    .PARAMETER Id
        Policy name or GUID to update.

    .PARAMETER NewName
        New display name.

    .PARAMETER Description
        New description.

    .PARAMETER ScopeTagIds
        Array of scope-tag GUIDs to apply.

    .PARAMETER Settings
        Replacement settings array (as returned by Get-IntuneConfigurationPolicy -Id ...).
        Replaces the full settings set on the policy.

    .EXAMPLE
        Set-IntuneConfigurationPolicy -Id 'My Policy' -NewName 'My Policy v2' -Description 'Updated'

    .EXAMPLE
        $settings = (Get-IntuneConfigurationPolicy -Id 'Source Policy').Settings
        Set-IntuneConfigurationPolicy -Id 'Target Policy' -Settings $settings

    .OUTPUTS
        PSCustomObject: Id, Name, Modified.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Id,
        [string]$NewName,
        [string]$Description,
        [string[]]$ScopeTagIds,
        [object[]]$Settings
    )

    $resolved = Resolve-IaConfigPolicyId -Value $Id

    if (-not $PSCmdlet.ShouldProcess($Id, 'Set-IntuneConfigurationPolicy')) { return }

    $meta = @{}
    if ($NewName)      { $meta['name']             = $NewName }
    if ($PSBoundParameters.ContainsKey('Description')) { $meta['description'] = $Description }
    if ($ScopeTagIds)  { $meta['roleScopeTagIds']  = $ScopeTagIds }

    if ($meta.Count -gt 0) {
        Invoke-IaRequest -Method PATCH -Uri (Resolve-IaUri "deviceManagement/configurationPolicies/$resolved") -Body $meta | Out-Null
    }

    if ($Settings) {
        $settingsBody = @{ value = @($Settings | ForEach-Object {
            if ($_.settingInstance) { @{ settingInstance = $_.settingInstance } }
            else                    { $_ }
        }) }
        Invoke-IaRequest -Method PUT -Uri (Resolve-IaUri "deviceManagement/configurationPolicies/$resolved/settings") -Body $settingsBody | Out-Null
    }

    $updated = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/configurationPolicies/$resolved")
    [pscustomobject][ordered]@{
        Id       = $updated.id
        Name     = $updated.name
        Modified = $updated.lastModifiedDateTime
    }
}
