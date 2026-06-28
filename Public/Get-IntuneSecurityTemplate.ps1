function Get-IntuneSecurityTemplate {
    <#
    .SYNOPSIS
        List available Intune endpoint security policy templates.

    .DESCRIPTION
        Returns templates from /deviceManagement/configurationPolicyTemplates that
        represent security baselines (templateFamily != none). Use the template Id
        with New-IntuneSecurityBaseline -TemplateId to create a policy.

        Also returns legacy intent templates from /deviceManagement/templates for
        older baseline types.

    .PARAMETER Category
        Filter by template family/category.

    .PARAMETER IncludeLegacy
        Also include legacy intent-based templates from /deviceManagement/templates.

    .EXAMPLE
        Get-IntuneSecurityTemplate

    .EXAMPLE
        Get-IntuneSecurityTemplate -Category Antivirus

    .EXAMPLE
        Get-IntuneSecurityTemplate -IncludeLegacy | Format-Table Id, Name, Category

    .OUTPUTS
        PSCustomObject: Id, Name, Category, Platform, Description, Version, IsDeprecated, Source.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('All','Baseline','Antivirus','DiskEncryption','Firewall',
                     'EndpointDetectionResponse','AttackSurfaceReduction','AccountProtection')]
        [string]$Category = 'All',
        [switch]$IncludeLegacy
    )

    $results = [System.Collections.Generic.List[object]]::new()

    # New-style: configurationPolicyTemplates where templateFamily != none
    $newTemplates = Get-IaCollection (Resolve-IaUri "deviceManagement/configurationPolicyTemplates?`$filter=templateFamily ne 'none'")
    foreach ($t in $newTemplates) {
        $family = $t.templateFamily
        if ($Category -ne 'All' -and $family -ne $Category) { continue }
        $results.Add([pscustomobject][ordered]@{
            Id          = $t.id
            Name        = $t.displayName
            Category    = $family
            Platform    = $t.platforms -join ', '
            Description = $t.description
            Version     = $t.version
            IsDeprecated = $t.isDeprecated
            Source      = 'ConfigurationPolicyTemplate'
        })
    }

    # Legacy: deviceManagement/templates (intents)
    if ($IncludeLegacy) {
        $legacyTemplates = Get-IaCollection (Resolve-IaUri 'deviceManagement/templates')
        foreach ($t in $legacyTemplates) {
            $results.Add([pscustomobject][ordered]@{
                Id          = $t.id
                Name        = $t.displayName
                Category    = $t.templateType
                Platform    = $null
                Description = $t.description
                Version     = $t.versionInfo
                IsDeprecated = $t.isDeprecated
                Source      = 'LegacyIntent'
            })
        }
    }

    $results.ToArray()
}
