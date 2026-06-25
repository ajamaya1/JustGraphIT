function Get-IntuneConfigurationPolicy {
    <#
    .SYNOPSIS
        List or retrieve Settings Catalog configuration policies.

    .DESCRIPTION
        Returns Settings Catalog policies from /deviceManagement/configurationPolicies.
        Supports filtering by Platform and Technology, and can retrieve a single policy
        by name or GUID with its settings expanded.

    .PARAMETER Id
        Policy GUID or display name. Returns a single policy with settings expanded.

    .PARAMETER Platform
        Filter by platform: windows10, macOS, iOS, android, linux, all (default).

    .PARAMETER Technology
        Filter by technology: mdm, windows10XManagement, appleRemoteManagement, etc.

    .PARAMETER IncludeSettings
        When listing, also expand settings for each policy (slower).

    .EXAMPLE
        Get-IntuneConfigurationPolicy

    .EXAMPLE
        Get-IntuneConfigurationPolicy -Platform macOS

    .EXAMPLE
        Get-IntuneConfigurationPolicy -Id 'My Windows Security Baseline'

    .OUTPUTS
        PSCustomObject per policy: Id, Name, Platform, Technologies, Description,
        Created, Modified, SettingCount. With -Id or -IncludeSettings, Settings is populated.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Id,
        [ValidateSet('windows10','macOS','iOS','android','linux','all')]
        [string]$Platform = 'all',
        [string]$Technology,
        [switch]$IncludeSettings
    )

    if ($Id) {
        $resolved = Resolve-IaConfigPolicyId -Value $Id
        $policy = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/configurationPolicies/${resolved}?`$expand=settings")
        return ConvertTo-IaConfigPolicyObject -Policy $policy -WithSettings
    }

    $filter = @()
    if ($Platform -ne 'all') { $filter += "platforms eq '$Platform'" }
    if ($Technology)         { $filter += "technologies eq '$Technology'" }

    $query = 'deviceManagement/configurationPolicies?$orderby=name'
    if ($filter) { $query += '&$filter=' + ($filter -join ' and ') }
    if ($IncludeSettings) { $query += '&$expand=settings' }

    $policies = Get-IaCollection (Resolve-IaUri $query)
    foreach ($p in $policies) {
        ConvertTo-IaConfigPolicyObject -Policy $p -WithSettings:$IncludeSettings
    }
}

function Resolve-IaConfigPolicyId {
    param([string]$Value)
    if (Test-IaGuid $Value) { return $Value }
    $encoded = [uri]::EscapeDataString($Value)
    $results = Get-IaCollection (Resolve-IaUri "deviceManagement/configurationPolicies?`$filter=name eq '$encoded'&`$select=id,name")
    if ($results.Count -eq 0) { throw "No configuration policy found matching '$Value'." }
    if ($results.Count -gt 1) { throw "Multiple policies match '$Value'. Provide a unique id." }
    $results[0].id
}

function ConvertTo-IaConfigPolicyObject {
    param($Policy, [switch]$WithSettings)
    $obj = [pscustomobject][ordered]@{
        Id             = $Policy.id
        Name           = $Policy.name
        Platform       = $Policy.platforms
        Technologies   = $Policy.technologies
        Description    = $Policy.description
        SettingCount   = $Policy.settingCount
        Created        = $Policy.createdDateTime
        Modified       = $Policy.lastModifiedDateTime
        ScopeTags      = $Policy.roleScopeTagIds -join ', '
    }
    if ($WithSettings) {
        $obj | Add-Member -NotePropertyName Settings -NotePropertyValue $Policy.settings
    }
    $obj
}
