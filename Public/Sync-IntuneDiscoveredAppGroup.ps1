function Sync-IntuneDiscoveredAppGroup {
    <#
    .SYNOPSIS
        Keep an Entra security group in sync with a discovered-app query —
        "every device with <app> (optionally below <version>) is a member".
        Built for scheduled runbooks: idempotent, re-runnable, -WhatIf-able.

    .DESCRIPTION
        Runs the discovered-app device report (Get-IntuneDiscoveredApp -Devices),
        resolves each Intune device to its Entra directory object, then makes the
        target group's DEVICE membership match the query:

          - the group is created (Security, assigned membership) on first run
          - devices that match and aren't members are added (already-members are
            left alone — safe to re-run on any schedule)
          - with -RemoveHealed, device members that no longer match the query are
            removed; users and any other member types in the group are NEVER touched

        Point anything that targets a group at the result: a remediation script,
        a required app deployment, Conditional Access, or an Azure Automation /
        Scheduled Task runbook that re-runs this to keep membership current.
        App-only auth needs DeviceManagementManagedDevices.Read.All +
        Group.ReadWrite.All (both in the module's default scopes).

        Devices whose Intune record has no Entra device id (or whose id cannot be
        resolved) are counted in Unresolved and skipped, never fatal.

    .PARAMETER Name
        App-name fragment to match (same matching as Get-IntuneDiscoveredApp,
        e.g. 'zscaler' finds every Zscaler component).

    .PARAMETER GroupName
        Target Entra group — display name or object id. Created as a Security
        group if no group by that name exists.

    .PARAMETER BelowVersion
        Only devices with a version strictly below this one (unparseable versions
        are included — they can't be proven patched).

    .PARAMETER Description
        Description for the group when it is created (ignored for an existing
        group). Defaults to a self-documenting one naming the query.

    .PARAMETER RemoveHealed
        Also remove device members that no longer match the query — the group
        then tracks the report exactly (devices leave as they're remediated).

    .EXAMPLE
        Sync-IntuneDiscoveredAppGroup -Name zscaler -BelowVersion 4.3 -GroupName 'sec-zscaler-below-4.3' -WhatIf

        Preview: what would be created/added/removed, no writes.

    .EXAMPLE
        Sync-IntuneDiscoveredAppGroup -Name zscaler -BelowVersion 4.3 -GroupName 'sec-zscaler-below-4.3' -RemoveHealed

        The InfoSec loop: group tracks every device still below the fixed build;
        devices drop out as they update.

    .EXAMPLE
        Connect-JustGraphIT -TenantId $tid -ClientId $appId -CertificateThumbprint $thumb
        Sync-IntuneDiscoveredAppGroup -Name 'Zscaler Client Connector' -BelowVersion 4.3 `
            -GroupName 'sec-zscaler-below-4-3' -RemoveHealed -Confirm:$false

        The runbook shape: app-only auth, unattended, idempotent on every run.

    .OUTPUTS
        PSCustomObject: Group, GroupId, Created, MatchedDevices, Resolved,
        Unresolved, Added, Removed, InSync.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Mandatory, Position = 1)][string]$GroupName,
        [string]$BelowVersion,
        [string]$Description,
        [switch]$RemoveHealed
    )

    # ── 1. The population: devices carrying the app ───────────────────────────
    $p = @{ Name = $Name; Devices = $true }
    if ($BelowVersion) { $p.BelowVersion = $BelowVersion }
    $rows   = @(Get-IntuneDiscoveredApp @p)
    $aadIds = @($rows | ForEach-Object { "$($_.AzureAdDeviceId)" } | Where-Object { $_ } | Select-Object -Unique)

    # ── 2. Intune device → Entra directory object ─────────────────────────────
    $target = @{}
    $unresolved = 0
    foreach ($aad in $aadIds) {
        $obj = $null
        try { $obj = Resolve-EntraDeviceObjectId -AzureAdDeviceId $aad } catch { }
        if ($obj) { $target["$obj"] = $true } else { $unresolved++ }
    }
    $targetIds = @($target.Keys)
    if ($unresolved) { Write-Warning "$unresolved device(s) have no resolvable Entra device object and were skipped." }

    # ── 3. The group: reuse when it exists, create on first run ───────────────
    $gid = $null; $created = $false
    try { $gid = Resolve-EntraGroupId -Group $GroupName }
    catch {
        if ("$_" -notmatch 'No Entra group found') { throw }
        if (-not $Description) {
            $Description = "Devices with discovered app '$Name'" +
                $(if ($BelowVersion) { " below $BelowVersion" }) +
                ' — managed by Sync-IntuneDiscoveredAppGroup'
        }
        if ($PSCmdlet.ShouldProcess($GroupName, 'Create security group')) {
            $g = New-EntraGroup -Name $GroupName -Description $Description -Type Security -Confirm:$false
            $gid = $g.Id; $created = $true
        } else {
            # -WhatIf against a group that doesn't exist yet: report the plan.
            return [pscustomobject][ordered]@{
                Group = $GroupName; GroupId = $null; Created = $false
                MatchedDevices = $aadIds.Count; Resolved = $targetIds.Count; Unresolved = $unresolved
                Added = 0; Removed = 0; InSync = $false
            }
        }
    }

    if (-not $created) {
        $ginfo = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "groups/$gid`?`$select=id,groupTypes")
        if (@($ginfo.groupTypes) -contains 'DynamicMembership') {
            throw "Group '$GroupName' is dynamic — its members are rule-driven and cannot be synced manually."
        }
    }

    # ── 4. Diff current DEVICE members against the query ──────────────────────
    $devMembers = if ($created) { @() } else { @(Get-EntraGroupMember -Group $gid | Where-Object { $_.Type -eq 'device' }) }
    $have = @{}
    foreach ($m in $devMembers) { if ($m.Id) { $have["$($m.Id)"] = $true } }
    $toAdd    = @($targetIds | Where-Object { -not $have.ContainsKey("$_") })
    $toRemove = if ($RemoveHealed) { @($devMembers | Where-Object { -not $target.ContainsKey("$($_.Id)") }) } else { @() }

    # ── 5. Converge ───────────────────────────────────────────────────────────
    $addedCount = 0
    if ($toAdd.Count -and $PSCmdlet.ShouldProcess($GroupName, "Add $($toAdd.Count) device(s)")) {
        $res = Add-EntraGroupMemberBulk -Group $gid -MemberId $toAdd -Confirm:$false
        $addedCount = [int]$res.Added
        if ($res.Failed) { Write-Warning "$($res.Failed) member add(s) failed for '$GroupName'." }
    }
    $removedCount = 0
    foreach ($m in $toRemove) {
        if ($PSCmdlet.ShouldProcess($GroupName, "Remove healed device '$($m.Name ?? $m.Id)'")) {
            try { Remove-EntraGroupMember -Group $gid -Member $m.Id -Confirm:$false; $removedCount++ }
            catch { Write-Warning "Could not remove member $($m.Id): $($_.Exception.Message)" }
        }
    }

    [pscustomobject][ordered]@{
        Group          = $GroupName
        GroupId        = $gid
        Created        = $created
        MatchedDevices = $aadIds.Count
        Resolved       = $targetIds.Count
        Unresolved     = $unresolved
        Added          = $addedCount
        Removed        = $removedCount
        InSync         = ($toAdd.Count -eq $addedCount -and $toRemove.Count -eq $removedCount)
    }
}
