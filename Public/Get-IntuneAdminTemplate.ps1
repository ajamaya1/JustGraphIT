function Get-IntuneAdminTemplate {
    <#
    .SYNOPSIS
        List or retrieve Administrative Template (ADMX) group policy configurations.

    .DESCRIPTION
        Returns group policy configurations from
        /deviceManagement/groupPolicyConfigurations.
        Use -Id to retrieve a single template by name or GUID.
        Use -IncludeDefinitionValues to expand each template's configured settings,
        including the definition metadata and presentation values.

    .PARAMETER Id
        Template name or GUID. When provided, returns a single template.

    .PARAMETER IncludeDefinitionValues
        When specified, fetches and embeds the configured definition values
        (with definition and presentationValues expanded) for each template.
        This significantly increases the number of API calls when listing.

    .EXAMPLE
        Get-IntuneAdminTemplate

    .EXAMPLE
        Get-IntuneAdminTemplate -Id 'Windows Security Settings'

    .EXAMPLE
        Get-IntuneAdminTemplate -Id 'Windows Security Settings' -IncludeDefinitionValues

    .EXAMPLE
        Get-IntuneAdminTemplate | Get-IntuneAdminTemplate -IncludeDefinitionValues

    .OUTPUTS
        PSCustomObject per template: Id, Name, Description, DefinitionValueCount,
        Created, Modified. With -IncludeDefinitionValues, adds DefinitionValues
        (array of: DefinitionId, DisplayName, OmaUri, Value, DataType).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipelineByPropertyName)][string]$Id,
        [switch]$IncludeDefinitionValues
    )

    process {
        if ($Id) {
            $resolved = Resolve-IaAdminTemplateId -Value $Id
            $template = Invoke-IaRequest -Method GET `
                -Uri (Resolve-IaUri "deviceManagement/groupPolicyConfigurations/$resolved")
            return ConvertTo-IaAdminTemplateObject -Template $template -IncludeDefinitionValues:$IncludeDefinitionValues
        }

        $templates = Get-IaCollection (Resolve-IaUri 'deviceManagement/groupPolicyConfigurations?$orderby=displayName')
        foreach ($t in $templates) {
            ConvertTo-IaAdminTemplateObject -Template $t -IncludeDefinitionValues:$IncludeDefinitionValues
        }
    }
}

function Resolve-IaAdminTemplateId {
    param([string]$Value)
    if (Test-IaGuid $Value) { return $Value }
    $encoded = [uri]::EscapeDataString($Value)
    $results = Get-IaCollection (Resolve-IaUri "deviceManagement/groupPolicyConfigurations?`$filter=displayName eq '$encoded'&`$select=id,displayName")
    if ($results.Count -eq 0) { throw "No administrative template found matching '$Value'." }
    if ($results.Count -gt 1) { throw "Multiple templates match '$Value'. Provide a unique id." }
    $results[0].id
}

function Get-IaAdminTemplateDefinitionValues {
    param([string]$TemplateId)
    $uri = Resolve-IaUri "deviceManagement/groupPolicyConfigurations/$TemplateId/definitionValues?`$expand=definition,presentationValues"
    $rawValues = Get-IaCollection $uri

    foreach ($dv in $rawValues) {
        $def = $dv.definition

        # Resolve the scalar value: prefer presentationValues, fall back to enabled bool
        $value = if ($dv.presentationValues -and $dv.presentationValues.Count -gt 0) {
            # Most definitions have a single presentation; take the first concrete value
            $pv = $dv.presentationValues[0]
            if ($null -ne $pv.value)   { $pv.value }
            elseif ($null -ne $pv.values) { $pv.values -join '; ' }
            else { $dv.enabled }
        } else {
            $dv.enabled
        }

        [pscustomobject][ordered]@{
            DefinitionId = $def.id
            DisplayName  = $def.displayName
            OmaUri       = $def.oemUrl ?? $def.categoryPath   # Graph beta exposes categoryPath; oemUrl is less common
            Value        = $value
            DataType     = $dv.presentationValues?[0].'@odata.type' -replace '#microsoft.graph.groupPolicyPresentationValue', '' -replace '^$', 'Boolean'
        }
    }
}

function ConvertTo-IaAdminTemplateObject {
    param($Template, [switch]$IncludeDefinitionValues)

    $obj = [pscustomobject][ordered]@{
        Id                   = $Template.id
        Name                 = $Template.displayName
        Description          = $Template.description
        DefinitionValueCount = $Template.definitionValueCount  # populated by Graph on some versions
        Created              = $Template.createdDateTime
        Modified             = $Template.lastModifiedDateTime
    }

    if ($IncludeDefinitionValues) {
        $defValues = @(Get-IaAdminTemplateDefinitionValues -TemplateId $Template.id)
        $obj | Add-Member -NotePropertyName DefinitionValueCount -NotePropertyValue $defValues.Count -Force
        $obj | Add-Member -NotePropertyName DefinitionValues     -NotePropertyValue $defValues
    }

    $obj
}
