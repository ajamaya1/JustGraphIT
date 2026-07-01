function New-IntuneCompliancePolicy {
    <#
    .SYNOPSIS
        Create a new Intune compliance policy.

    .DESCRIPTION
        Creates a compliance policy under /deviceManagement/deviceCompliancePolicies.
        Supports CopyFrom (clone existing) or FromJson (import raw JSON).

    .PARAMETER Name
        Display name for the new policy.

    .PARAMETER CopyFrom
        Name or GUID of an existing compliance policy to clone.

    .PARAMETER Json
        Raw JSON body of a compliance policy.

    .PARAMETER Platform
        Platform for a blank policy shell: Windows, macOS, iOS, Android.

    .PARAMETER Description
        Description text.

    .EXAMPLE
        New-IntuneCompliancePolicy -Name 'iOS Compliance Copy' -CopyFrom 'iOS Compliance Baseline'

    .EXAMPLE
        Get-IntuneCompliancePolicy -Id 'My Policy' | ConvertTo-Json -Depth 20 |
            New-IntuneCompliancePolicy -Name 'My Policy - Dev'

    .OUTPUTS
        PSCustomObject: Id, Name, Platform, Created.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Manual')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Mandatory, ParameterSetName = 'CopyFrom')][string]$CopyFrom,
        [Parameter(Mandatory, ParameterSetName = 'FromJson', ValueFromPipeline)][string]$Json,
        [Parameter(ParameterSetName = 'Manual')]
        [ValidateSet('Windows','macOS','iOS','Android')]
        [string]$Platform = 'Windows',
        [string]$Description
    )

    $platformTypeMap = @{
        'Windows' = '#microsoft.graph.windows10CompliancePolicy'
        'macOS'   = '#microsoft.graph.macOSCompliancePolicy'
        'iOS'     = '#microsoft.graph.iosCompliancePolicy'
        'Android' = '#microsoft.graph.androidCompliancePolicy'
    }

    process {
        $body = switch ($PSCmdlet.ParameterSetName) {
            'CopyFrom' {
                $srcId = Resolve-IaCompliancePolicyId -Value $CopyFrom
                # Expand the noncompliance schedule so the clone keeps the source's real
                # actions (grace period, retire, notify) instead of the block/0h default
                # the fallback below would inject.
                $src   = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/deviceCompliancePolicies/${srcId}?`$expand=scheduledActionsForRule(`$expand=scheduledActionConfigurations)")
                $clone = $src | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
                $clone['displayName'] = $Name
                if ($Description) { $clone['description'] = $Description }
                $clone.Remove('id'); $clone.Remove('createdDateTime'); $clone.Remove('lastModifiedDateTime')
                $clone.Remove('version'); $clone.Remove('assignments')
                foreach ($k in @($clone.Keys | Where-Object { $_ -like '*@odata*' })) { $clone.Remove($k) }
                if ($clone['scheduledActionsForRule']) {
                    # strip server-assigned ids/annotations; keep ruleName + action configs
                    $clone['scheduledActionsForRule'] = @(foreach ($rule in @($clone['scheduledActionsForRule'])) {
                        foreach ($k in @($rule.Keys | Where-Object { $_ -eq 'id' -or $_ -like '*@odata*' })) { $rule.Remove($k) }
                        if ($rule['scheduledActionConfigurations']) {
                            $rule['scheduledActionConfigurations'] = @(foreach ($cfg in @($rule['scheduledActionConfigurations'])) {
                                foreach ($k in @($cfg.Keys | Where-Object { $_ -eq 'id' -or $_ -like '*@odata*' })) { $cfg.Remove($k) }
                                $cfg
                            })
                        }
                        $rule
                    })
                }
                $clone
            }
            'FromJson' {
                $parsed = $Json | ConvertFrom-Json -AsHashtable
                $parsed['displayName'] = $Name
                if ($Description) { $parsed['description'] = $Description }
                $parsed.Remove('id'); $parsed.Remove('createdDateTime'); $parsed.Remove('lastModifiedDateTime')
                $parsed
            }
            'Manual' {
                @{
                    '@odata.type' = $platformTypeMap[$Platform]
                    displayName   = $Name
                    description   = $Description ?? ''
                }
            }
        }

        # Graph rejects a compliance-policy create that has no scheduledActionsForRule
        # ("The scheduled actions for this rule is required"). Manual shells never set it,
        # and the CopyFrom clone strips it (the plain GET doesn't return it anyway), so
        # supply a minimal block-on-noncompliance schedule when one is missing.
        if (-not $body['scheduledActionsForRule']) {
            $body['scheduledActionsForRule'] = @(
                @{ ruleName = 'PasswordRequired'; scheduledActionConfigurations = @(
                    @{ actionType = 'block'; gracePeriodHours = 0 }
                ) }
            )
        }

        if (-not $PSCmdlet.ShouldProcess($Name, 'New-IntuneCompliancePolicy')) { return }

        $created = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri 'deviceManagement/deviceCompliancePolicies') -Body $body
        $platform = ($created.'@odata.type' -replace '#microsoft\.graph\.' -replace 'CompliancePolicy', '')

        [pscustomobject][ordered]@{
            Id       = $created.id
            Name     = $created.displayName
            Platform = $platform
            Created  = $created.createdDateTime
        }
    }
}
