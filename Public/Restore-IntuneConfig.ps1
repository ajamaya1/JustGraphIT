function Restore-IntuneConfig {
    <#
    .SYNOPSIS
        Restore configs from a Backup-IntuneConfig folder (preview-first).

    .DESCRIPTION
        Reads a full-config backup folder and, for each config:
          • UPDATES the live config when it still exists (PATCH), and
          • CREATES it when missing — only with -CreateMissing, and only for
            self-contained types (settings catalog, device configuration,
            compliance, platform/shell/remediation scripts). Complex types that
            need child resources or a server template are reported, not written.
        Assignments from the backup are re-applied too, unless -SkipAssignments.

        This writes to the tenant, so it is preview-first: run with -WhatIf (the
        default in the TUI) to see the plan, then re-run with -Confirm:$false to
        apply. Each resource is handled independently — one failure never aborts
        the run; the error lands on that row.

    .PARAMETER Path
        The backup folder produced by Backup-IntuneConfig.

    .PARAMETER Area
        Restrict the restore to one or more areas.

    .PARAMETER Type
        Restrict to one or more resource type keys.

    .PARAMETER CreateMissing
        Re-create configs that no longer exist in the tenant (where supported).

    .PARAMETER SkipAssignments
        Don't re-apply the backed-up assignments (config bodies only).

    .EXAMPLE
        Restore-IntuneConfig -Path .\intunetide-config-2026-06-25-1430 -WhatIf

        Preview exactly what restoring would change.

    .EXAMPLE
        Restore-IntuneConfig -Path .\baseline -CreateMissing -Confirm:$false

        Update existing configs, re-create any that were deleted, and re-apply
        assignments.

    .OUTPUTS
        Change-plan objects (Area, ResourceName, Added/Skipped/Applied/Error).

    .LINK
        Backup-IntuneConfig
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$Area,
        [string[]]$Type,
        [switch]$CreateMissing,
        [switch]$SkipAssignments
    )
    foreach ($rec in (Read-IaConfigBackup -Path $Path)) {
        if ($Area -and $rec.area -notin $Area) { continue }
        if ($Type -and $rec.resourceType -notin $Type) { continue }

        $rt = Find-IaResourceType -Key $rec.resourceType
        $planItem = [pscustomobject]@{ Area = $rec.area; ResourceType = $rec.resourceType; Name = $rec.name; Id = $rec.id }
        if (-not $rt) { New-IaChangePlan -Item $planItem -Skipped "unknown resource type '$($rec.resourceType)'"; continue }

        $live = Find-IaLiveResource -Record $rec -ResourceType $rt
        $added = @(); $applied = $false; $err = $null; $liveId = $null

        try {
            if ($live) {
                $liveId = $live.id
                $body = Remove-IaReadOnlyField -Config $rec.config
                if ($PSCmdlet.ShouldProcess($rec.name, 'Update config (PATCH)')) {
                    Invoke-IaRequest -Method PATCH -Uri (Resolve-IaUri -Path "$($rt.ListPath)/$liveId") -Body $body | Out-Null
                    $applied = $true; $added += 'updated config'
                } else {
                    $added += 'would update config'
                }
            }
            elseif ($CreateMissing) {
                $body = New-IaConfigCreateBody -Record $rec
                if (-not $body) {
                    New-IaChangePlan -Item $planItem -Skipped "missing — automated re-create not supported for '$($rec.resourceType)' (restore manually from the JSON)"
                    continue
                }
                if ($PSCmdlet.ShouldProcess($rec.name, 'Create config (POST)')) {
                    $created = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path $rt.ListPath) -Body $body
                    $liveId = $created.id; $applied = $true; $added += 'created config'
                } else {
                    $added += 'would create config'
                }
            }
            else {
                New-IaChangePlan -Item $planItem -Skipped 'missing — pass -CreateMissing to re-create'
                continue
            }

            if (-not $SkipAssignments -and $rec.assignments) {
                $desired = @(ConvertFrom-IaAssignmentSnapshot -SnapResource $rec)
                if ($desired.Count) {
                    if ($liveId -and $PSCmdlet.ShouldProcess($rec.name, "Re-apply $($desired.Count) assignment(s)")) {
                        Save-IaAssignments -Item ([pscustomobject]@{ ResourceType = $rec.resourceType; Id = $liveId; Name = $rec.name; Area = $rec.area }) -Assignments $desired
                        $applied = $true; $added += "re-applied $($desired.Count) assignment(s)"
                    } elseif (-not $liveId) {
                        $added += "$($desired.Count) assignment(s) pending (config not created)"
                    } else {
                        $added += "would re-apply $($desired.Count) assignment(s)"
                    }
                }
            }
        } catch {
            $err = $_.Exception.Message
        }

        New-IaChangePlan -Item $planItem -Added $added -Applied $applied -ErrorText $err
    }
}
