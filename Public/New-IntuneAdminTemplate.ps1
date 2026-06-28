function New-IntuneAdminTemplate {
    <#
    .SYNOPSIS
        Create a new Administrative Template (ADMX) policy.

    .DESCRIPTION
        Creates a Group Policy configuration object in Intune under
        /deviceManagement/groupPolicyConfigurations. This creates the container;
        use Set-IntuneAdminTemplateValue to configure individual settings.

    .PARAMETER Name
        Display name for the policy.

    .PARAMETER Description
        Optional description.

    .PARAMETER CopyFrom
        Name or GUID of an existing template to clone (copies definition values).

    .EXAMPLE
        New-IntuneAdminTemplate -Name 'Windows Settings - Baseline'

    .EXAMPLE
        New-IntuneAdminTemplate -Name 'Windows Settings - Dev' -CopyFrom 'Windows Settings - Baseline'

    .OUTPUTS
        PSCustomObject: Id, Name, Created.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'New')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [string]$Description,
        [Parameter(ParameterSetName = 'CopyFrom')][string]$CopyFrom
    )

    if (-not $PSCmdlet.ShouldProcess($Name, 'New-IntuneAdminTemplate')) { return }

    $body = @{
        displayName = $Name
        description = $Description ?? ''
    }

    $created = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri 'deviceManagement/groupPolicyConfigurations') -Body $body

    # If CopyFrom, read source definition values and replicate them
    if ($CopyFrom) {
        $srcId = Resolve-IaAdminTemplateId -Value $CopyFrom
        $defs  = Get-IaCollection (Resolve-IaUri "deviceManagement/groupPolicyConfigurations/$srcId/definitionValues?`$expand=definition,presentationValues")
        foreach ($def in $defs) {
            try {
                $defBody = @{
                    enabled                     = $def.enabled
                    'definition@odata.bind'     = "$(Resolve-IaUri "deviceManagement/groupPolicyDefinitions/$($def.definition.id)")"
                }
                $newDef = Invoke-IaRequest -Method POST `
                    -Uri (Resolve-IaUri "deviceManagement/groupPolicyConfigurations/$($created.id)/definitionValues") `
                    -Body $defBody
                # Copy presentation values
                foreach ($pv in $def.presentationValues) {
                    Invoke-IaRequest -Method POST `
                        -Uri (Resolve-IaUri "deviceManagement/groupPolicyConfigurations/$($created.id)/definitionValues/$($newDef.id)/presentationValues") `
                        -Body @{
                            '@odata.type' = $pv.'@odata.type'
                            value         = $pv.value
                            presentation  = @{ id = $pv.presentation.id }
                        } | Out-Null
                }
            } catch {
                Write-Warning "Failed to copy definition '$($def.definition.displayName)': $_"
            }
        }
    }

    [pscustomobject][ordered]@{
        Id      = $created.id
        Name    = $created.displayName
        Created = $created.createdDateTime
    }
}
