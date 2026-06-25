function New-IntuneConfigurationPolicy {
    <#
    .SYNOPSIS
        Create a new Settings Catalog configuration policy.

    .DESCRIPTION
        Creates a policy under /deviceManagement/configurationPolicies.
        Supports three modes:
          CopyFrom  — clone an existing policy (by name or GUID) into a new name.
          FromJson  — supply raw JSON exported from another policy or tenant.
          Manual    — build a bare shell with name, platform, and technologies.

    .PARAMETER Name
        Display name for the new policy.

    .PARAMETER CopyFrom
        Name or GUID of an existing policy to clone.

    .PARAMETER Json
        Raw JSON body (as returned by Get-IntuneConfigurationPolicy -Id | ConvertTo-Json).

    .PARAMETER Platform
        Target platform for manual creation (windows10, macOS, iOS, android, linux).

    .PARAMETER Technologies
        Technologies for manual creation (e.g. mdm, appleRemoteManagement).

    .PARAMETER Description
        Optional description.

    .PARAMETER AssignTo
        Group display name or GUID to assign immediately after creation.

    .EXAMPLE
        New-IntuneConfigurationPolicy -Name 'Win Security Copy' -CopyFrom 'Win Security Baseline'

    .EXAMPLE
        Get-IntuneConfigurationPolicy -Id 'Policy A' | ConvertTo-Json -Depth 20 | New-IntuneConfigurationPolicy -Name 'Policy A - Dev'

    .OUTPUTS
        PSCustomObject: Id, Name, Platform, Technologies, Created.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Manual')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Mandatory, ParameterSetName = 'CopyFrom')][string]$CopyFrom,
        [Parameter(Mandatory, ParameterSetName = 'FromJson', ValueFromPipeline)][string]$Json,
        [Parameter(ParameterSetName = 'Manual')]
        [ValidateSet('windows10','macOS','iOS','android','linux')]
        [string]$Platform = 'windows10',
        [Parameter(ParameterSetName = 'Manual')][string]$Technologies = 'mdm',
        [string]$Description,
        [string]$AssignTo
    )

    process {
        $body = switch ($PSCmdlet.ParameterSetName) {
            'CopyFrom' {
                $srcId  = Resolve-IaConfigPolicyId -Value $CopyFrom
                $src    = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/configurationPolicies/${srcId}?`$expand=settings")
                @{
                    name          = $Name
                    description   = if ($Description) { $Description } else { $src.description }
                    platforms     = $src.platforms
                    technologies  = $src.technologies
                    settings      = @($src.settings | ForEach-Object { @{ settingInstance = $_.settingInstance } })
                }
            }
            'FromJson' {
                $parsed = $Json | ConvertFrom-Json -AsHashtable
                $parsed['name'] = $Name
                if ($Description) { $parsed['description'] = $Description }
                $parsed.Remove('id')
                $parsed.Remove('createdDateTime')
                $parsed.Remove('lastModifiedDateTime')
                $parsed
            }
            'Manual' {
                @{
                    name         = $Name
                    description  = $Description ?? ''
                    platforms    = $Platform
                    technologies = $Technologies
                    settings     = @()
                }
            }
        }

        if (-not $PSCmdlet.ShouldProcess($Name, 'New-IntuneConfigurationPolicy')) { return }

        $created = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri 'deviceManagement/configurationPolicies') -Body $body

        if ($AssignTo) {
            $groupId = if (Test-IaGuid $AssignTo) { $AssignTo } else {
                (Get-IaCollection (Resolve-IaUri "groups?`$filter=displayName eq '$([uri]::EscapeDataString($AssignTo))'&`$select=id") | Select-Object -First 1).id
            }
            if ($groupId) {
                Invoke-IaRequest -Method POST -Uri (Resolve-IaUri "deviceManagement/configurationPolicies/$($created.id)/assign") -Body @{
                    assignments = @(@{ target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $groupId } })
                } | Out-Null
            }
        }

        [pscustomobject][ordered]@{
            Id           = $created.id
            Name         = $created.name
            Platform     = $created.platforms
            Technologies = $created.technologies
            Created      = $created.createdDateTime
        }
    }
}
