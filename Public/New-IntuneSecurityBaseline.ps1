function New-IntuneSecurityBaseline {
    <#
    .SYNOPSIS
        Create a new endpoint security policy from a security template.

    .DESCRIPTION
        POSTs to deviceManagement/configurationPolicies with a templateReference
        body so the result is a Settings Catalog-based security baseline / endpoint
        security policy (the modern Graph approach, as opposed to legacy intents).

        Two creation modes:

          Standard  — Supply -Name and -TemplateId (and optionally -Settings).
          Clone     — Supply -CopyFrom with an existing policy name or GUID; the
                      source policy's settings are copied and -Name overrides the
                      display name.  -TemplateId is inferred from the source when
                      -CopyFrom is used.

    .PARAMETER Name
        Display name for the new security policy.

    .PARAMETER TemplateId
        GUID of the security template that backs this policy. Use
        Get-IntuneSecurityTemplate to discover available template GUIDs.
        Not required when -CopyFrom is supplied (inferred from the source).

    .PARAMETER Description
        Optional description for the policy.

    .PARAMETER Settings
        Array of setting objects in the Graph configurationPolicies format:
          @{ settingInstance = @{ ... } }
        When omitted the policy is created with no settings (you can add them later).

    .PARAMETER CopyFrom
        Name or GUID of an existing security policy to clone. Settings are copied
        from the source. -TemplateId defaults to the source's templateId when not
        also specified.

    .EXAMPLE
        New-IntuneSecurityBaseline -Name 'Win Antivirus Prod' `
            -TemplateId '804ae97d-7d62-4640-a930-fe15f8948f00'

        Creates an Antivirus policy with no pre-configured settings.

    .EXAMPLE
        $settings = (Get-IntuneSecurityBaseline -Id 'Source AV Policy').Settings
        New-IntuneSecurityBaseline -Name 'Win Antivirus Dev' `
            -TemplateId '804ae97d-7d62-4640-a930-fe15f8948f00' -Settings $settings

        Creates a policy pre-loaded with settings from another policy object.

    .EXAMPLE
        New-IntuneSecurityBaseline -Name 'Win Antivirus Dev' -CopyFrom 'Win Antivirus Prod'

        Clones an existing security policy under a new name.

    .OUTPUTS
        PSCustomObject: Id, Name, BaselineType, Platform, Created.

    .NOTES
        Requires DeviceManagementConfiguration.ReadWrite.All.
        SupportsShouldProcess: use -WhatIf to preview without creating.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$TemplateId,

        [string]$Description,

        [object[]]$Settings,

        [string]$CopyFrom
    )

    # ---- resolve CopyFrom source if provided ----------------------------------
    if ($CopyFrom) {
        Write-Verbose "Resolving clone source: '$CopyFrom'"
        $sourceId = if (Test-IaGuid $CopyFrom) {
            $CopyFrom
        } else {
            $encoded = ConvertTo-IaODataValue $CopyFrom
            $hits = Get-IaCollection (Resolve-IaUri "deviceManagement/configurationPolicies?`$filter=name eq '$encoded' and templateReference/templateFamily ne 'none'&`$select=id,name")
            if ($hits.Count -eq 0) { throw "Clone source '$CopyFrom' not found." }
            if ($hits.Count -gt 1) { throw "Clone source '$CopyFrom' matches multiple policies. Provide a unique id." }
            $hits[0].id
        }

        $source = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/configurationPolicies/${sourceId}?`$expand=settings")

        if (-not $PSBoundParameters.ContainsKey('TemplateId')) {
            $TemplateId = $source.templateReference.templateId
            if (-not $TemplateId) { throw "Could not infer TemplateId from clone source '$CopyFrom'. Provide -TemplateId explicitly." }
            Write-Verbose "Inferred TemplateId '$TemplateId' from source policy."
        }

        if (-not $PSBoundParameters.ContainsKey('Settings') -and $source.settings) {
            $Settings = @($source.settings)
            Write-Verbose "Copied $($Settings.Count) setting(s) from source policy."
        }

        if (-not $PSBoundParameters.ContainsKey('Description') -and $source.description) {
            $Description = $source.description
        }
    }

    if (-not $TemplateId) {
        throw '-TemplateId is required unless -CopyFrom is supplied.'
    }

    $body = [ordered]@{
        name             = $Name
        description      = $Description ?? ''
        templateReference = @{
            templateId = $TemplateId
        }
        settings         = if ($Settings) { @($Settings) } else { @() }
    }

    if (-not $PSCmdlet.ShouldProcess($Name, 'New-IntuneSecurityBaseline')) { return }

    Write-Verbose "POST deviceManagement/configurationPolicies (template: $TemplateId)"
    $created = Invoke-IaRequest -Method POST `
        -Uri (Resolve-IaUri 'deviceManagement/configurationPolicies') `
        -Body $body

    [pscustomobject][ordered]@{
        Id           = $created.id
        Name         = $created.name
        BaselineType = $created.templateReference.templateDisplayName
        Platform     = $created.platforms
        Created      = $created.createdDateTime
    }
}
