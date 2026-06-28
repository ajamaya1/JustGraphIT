function Get-IntuneSecurityBaseline {
    <#
    .SYNOPSIS
        List or retrieve Intune endpoint security policies (security baselines).

    .DESCRIPTION
        Queries two complementary Graph endpoints to surface all security baseline
        and endpoint security policies in the tenant:

          a) New-style Settings Catalog security policies:
             deviceManagement/configurationPolicies?$filter=templateReference/templateFamily ne 'none'
             These carry a templateReference with templateFamily (Category) and
             templateDisplayName (BaselineType).

          b) Legacy intent-based security policies:
             deviceManagement/intents
             These predate Settings Catalog and cover older baseline templates.

        When -Id is supplied the new-style endpoint is tried first; if not found the
        legacy intents endpoint is tried. When -Category is supplied only policies
        whose templateFamily (or templateType for intents) matches are returned.

    .PARAMETER Id
        Policy GUID or display name. Returns a single matching policy.
        Tries configurationPolicies first, then deviceManagement/intents.

    .PARAMETER Category
        Filter to a specific endpoint security category. Choices map to the Graph
        templateFamily / templateType values:
          All (default), Baseline, Antivirus, DiskEncryption, Firewall,
          EndpointDetectionResponse, AttackSurfaceReduction, AccountProtection.

    .EXAMPLE
        Get-IntuneSecurityBaseline

        Lists all security baselines and endpoint security policies.

    .EXAMPLE
        Get-IntuneSecurityBaseline -Category Antivirus

        Lists only Antivirus endpoint security policies.

    .EXAMPLE
        Get-IntuneSecurityBaseline -Id 'Windows Security Baseline 2023'

        Retrieves a single policy by display name.

    .EXAMPLE
        Get-IntuneSecurityBaseline -Id 'a1b2c3d4-0000-0000-0000-000000000000'

        Retrieves a single policy by GUID.

    .OUTPUTS
        PSCustomObject per policy: Id, Name, Category, BaselineType, Platform,
        Created, Modified, SettingCount.

    .NOTES
        Requires DeviceManagementConfiguration.Read.All (new-style) and
        DeviceManagementConfiguration.Read.All / DeviceManagementManagedDevices.Read.All
        for legacy intents.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Id,

        [ValidateSet('All','Baseline','Antivirus','DiskEncryption','Firewall',
                     'EndpointDetectionResponse','AttackSurfaceReduction','AccountProtection')]
        [string]$Category = 'All'
    )

    if ($Id) {
        $resolved = Resolve-IaSecurityPolicyId -Value $Id
        return $resolved
    }

    # ---- new-style: Settings Catalog-based security policies ------------------
    $newPath = "deviceManagement/configurationPolicies?`$filter=templateReference/templateFamily ne 'none'&`$expand=settings"
    $newPolicies = Get-IaCollection (Resolve-IaUri $newPath)

    foreach ($p in $newPolicies) {
        $obj = ConvertTo-IaSecurityBaselineObject -Policy $p -IsIntent $false
        if ($Category -ne 'All' -and $obj.Category -ne $Category) { continue }
        $obj
    }

    # ---- legacy: intent / baseline policies -----------------------------------
    $intents = Get-IaCollection (Resolve-IaUri 'deviceManagement/intents')

    foreach ($intent in $intents) {
        $obj = ConvertTo-IaSecurityBaselineObject -Policy $intent -IsIntent $true
        if ($Category -ne 'All' -and $obj.Category -ne $Category) { continue }
        $obj
    }
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

function Resolve-IaSecurityPolicyId {
    <#
    .SYNOPSIS
        Resolves a security policy name or GUID — tries new-style first, then intents.
    #>
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$Value)

    # ---- attempt 1: new-style configurationPolicies ---------------------------
    if (Test-IaGuid $Value) {
        try {
            $p = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/configurationPolicies/${Value}?`$expand=settings")
            if ($p -and $p.templateReference -and $p.templateReference.templateFamily -ne 'none') {
                return ConvertTo-IaSecurityBaselineObject -Policy $p -IsIntent $false
            }
        } catch { }

        try {
            $intent = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/intents/$Value")
            if ($intent) { return ConvertTo-IaSecurityBaselineObject -Policy $intent -IsIntent $true }
        } catch { }

        throw "No security policy found with id '$Value'."
    }

    # Name-based lookup — new-style
    $encoded = ConvertTo-IaODataValue $Value
    $results = Get-IaCollection (Resolve-IaUri "deviceManagement/configurationPolicies?`$filter=name eq '$encoded' and templateReference/templateFamily ne 'none'&`$expand=settings")
    if ($results.Count -gt 0) {
        if ($results.Count -gt 1) { throw "Multiple security policies match '$Value'. Provide a unique id." }
        return ConvertTo-IaSecurityBaselineObject -Policy $results[0] -IsIntent $false
    }

    # Name-based lookup — legacy intents
    $allIntents = Get-IaCollection (Resolve-IaUri 'deviceManagement/intents')
    $matches = @($allIntents | Where-Object { $_.displayName -eq $Value })
    if ($matches.Count -eq 0) { throw "No security policy found matching '$Value'." }
    if ($matches.Count -gt 1) { throw "Multiple intents match '$Value'. Provide a unique id." }
    ConvertTo-IaSecurityBaselineObject -Policy $matches[0] -IsIntent $true
}

function ConvertTo-IaSecurityBaselineObject {
    <#
    .SYNOPSIS
        Maps a raw Graph security policy (new-style or intent) to the standard object shape.
    #>
    param(
        [Parameter(Mandatory)]$Policy,
        [Parameter(Mandatory)][bool]$IsIntent
    )

    # Map templateFamily strings (new-style) to the validated Category set
    $familyMap = @{
        'baseline'                  = 'Baseline'
        'endpointSecurityAntivirus' = 'Antivirus'
        'endpointSecurityDiskEncryption' = 'DiskEncryption'
        'endpointSecurityFirewall'  = 'Firewall'
        'endpointSecurityEndpointDetectionAndResponse' = 'EndpointDetectionResponse'
        'endpointSecurityAttackSurfaceReduction'       = 'AttackSurfaceReduction'
        'endpointSecurityAccountProtection'            = 'AccountProtection'
    }

    if ($IsIntent) {
        # Legacy intent — templateType is a free-form string; best-effort map
        $rawType = [string]$Policy.templateId
        $catGuess = 'Baseline'   # intents are typically baselines

        [pscustomobject][ordered]@{
            Id           = $Policy.id
            Name         = $Policy.displayName
            Category     = $catGuess
            BaselineType = $Policy.displayName   # intent has no separate template display name
            Platform     = 'windows10AndLater'   # intents are historically Windows-only
            Created      = $Policy.createdDateTime
            Modified     = $Policy.lastModifiedDateTime
            SettingCount = $Policy.settingCount ?? 0
        }
    } else {
        $ref      = $Policy.templateReference
        $rawFamily = [string]$ref.templateFamily
        $category  = $familyMap[$rawFamily]
        if (-not $category) { $category = $rawFamily }

        [pscustomobject][ordered]@{
            Id           = $Policy.id
            Name         = $Policy.name
            Category     = $category
            BaselineType = $ref.templateDisplayName
            Platform     = $Policy.platforms
            Created      = $Policy.createdDateTime
            Modified     = $Policy.lastModifiedDateTime
            SettingCount = $Policy.settingCount ?? 0
        }
    }
}
