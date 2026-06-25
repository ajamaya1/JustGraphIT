function Start-IntuneTide {
    <#
    .SYNOPSIS
        Launch the interactive retro Spectre.Console TUI.
    .DESCRIPTION
        A keyboard-driven terminal UI: browse assignments, reverse-lookup a
        group, compare two groups, run what-if for a user/device, and — the
        headline — MIRROR a group's assignments onto another with a multi-select
        checklist so you choose exactly which ones (e.g. config profiles but not
        endpoint security). Cross-platform; needs the PwshSpectreConsole module.
    .EXAMPLE
        Connect-IntuneTide -UseDeviceCode; Start-IntuneTide
    #>
    [CmdletBinding()]
    param([ValidateSet('green', 'amber', 'lego', 'deepsea')][string]$Theme = 'deepsea')

    if (-not (Get-Command Read-SpectreSelection -ErrorAction SilentlyContinue)) {
        throw "The TUI needs PwshSpectreConsole. Install it with: Install-Module PwshSpectreConsole -Scope CurrentUser"
    }
    if (-not (Get-MgContext)) {
        Write-SpectreHost "[yellow]Not connected.[/] Starting device-code sign-in…"
        Connect-IntuneTide -UseDeviceCode | Out-Null
    }

    $accent = switch ($Theme) { 'amber' { 'orange1' } 'lego' { 'yellow' } 'deepsea' { 'turquoise2' } default { 'green' } }
    $script:IaTuiInventory = $null
    $script:IaTuiShowLog   = $true

    function Get-IaTuiInventory {
        if ($null -eq $script:IaTuiInventory) {
            if ($script:IaTuiShowLog) {
                Write-SpectreHost "[grey]reading intune — live graph calls:[/]"
                Set-IaCallSink {
                    param($c)
                    $items = if ($c.Count) { " · $($c.Count) items" } else { '' }
                    Write-Host ("  → {0,-6} {1}  {2}ms{3}" -f $c.Method, $c.Uri, $c.Ms, $items)
                }
                try { $script:IaTuiInventory = Get-IaInventory } finally { Set-IaCallSink $null }
            } else {
                $script:IaTuiInventory = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Reading Intune assignments…' -ScriptBlock {
                    Get-IaInventory
                }
            }
        }
        $script:IaTuiInventory
    }

    Clear-Host
    Write-SpectreFigletText -Text 'TIDE' -Color $accent
    $ctx  = Get-MgContext
    $elev = try { if (Test-IaPrivileged) { "[green]● elevated[/]" } else { "[yellow]○ not elevated[/]" } } catch { '' }
    Write-SpectreHost "[$accent]●[/] $($ctx.Account)  ·  tenant [grey]$($ctx.TenantId)[/]  ·  $elev"
    Write-SpectreRule -Title 'TIDE · targeted intune deployment & endpoints' -Color $accent

    # Store for per-screen sub-lines
    $script:IaTuiAccount = $ctx.Account
    $script:IaTuiElev    = $elev

    while ($true) {
        $choice = Read-SpectreSelection -Title "Choose an action" -Color $accent -Choices @(
            'View all assignments',
            'Group lookup (what is a group assigned to)',
            'Compare two groups',
            'What-if (user / device effective assignments)',
            'Mirror assignments (copy A -> B, pick which)',
            'Assign a group to many (pick which)',
            'Templates (capture / apply)',
            'Backup / Restore / Drift',
            'Reports (status · audit · approvals)',
            'Elevate (PIM) — activate an eligible role',
            'Audit',
            'Export report (HTML · Excel · Rich HTML)',
            'Toggle graph-call pane',
            'Refresh data',
            'Quit'
        )
        try {
            switch -Wildcard ($choice) {
                'View all*'       { Invoke-IaTuiViewAll    -Accent $accent }
                'Group lookup*'   { Invoke-IaTuiGroupLookup -Accent $accent }
                'Compare*'        { Invoke-IaTuiCompare     -Accent $accent }
                'What-if*'        { Invoke-IaTuiWhatIf      -Accent $accent }
                'Mirror*'         { Invoke-IaTuiMirror       -Accent $accent }
                'Assign a group*' { Invoke-IaTuiBulkAssign   -Accent $accent }
                'Templates*'      { Invoke-IaTuiTemplates    -Accent $accent }
                'Backup*'         { Invoke-IaTuiBackup       -Accent $accent }
                'Reports*'        { Invoke-IaTuiReports      -Accent $accent }
                'Elevate*'        { Invoke-IaTuiElevate      -Accent $accent }
                'Audit'           { Invoke-IaTuiAudit        -Accent $accent }
                'Export*'         { Invoke-IaTuiExport       -Accent $accent }
                'Refresh*'        { $script:IaTuiInventory = $null; Get-IaTuiInventory | Out-Null
                                    Write-SpectreHost "[$accent]Refreshed.[/]" }
                'Toggle graph*'   { $script:IaTuiShowLog = -not $script:IaTuiShowLog
                                    Write-SpectreHost "graph-call pane: $(if ($script:IaTuiShowLog) { "[$accent]on[/]" } else { '[grey]off[/]' })" }
                'Quit'            { $host.UI.RawUI.WindowTitle = 'pwsh'; return }
            }
        } catch {
            Write-SpectreHost "[red]Error:[/] $($_.Exception.Message)"
        }
        if ($choice -ne 'Quit') {
            if ($script:IaTuiShowLog) { Show-IaTuiCallLog -Accent $accent }
            Read-SpectrePause | Out-Null
        }
    }
}

# ─── shared header ────────────────────────────────────────────────────────────

function Write-IaTuiHeader {
    param([string]$Screen, [string]$Sub = '', [string]$Accent)
    $host.UI.RawUI.WindowTitle = "TIDE — $Screen"
    Write-SpectreHost ""
    Write-SpectreHost "[$Accent]≈ TIDE[/]  [bold]· $Screen[/]"
    if ($Sub) {
        Write-SpectreHost "[grey]$Sub[/]"
    } elseif ($script:IaTuiAccount) {
        Write-SpectreHost "[grey]●·$($script:IaTuiAccount)  ·  [/]$script:IaTuiElev"
    }
    Write-SpectreRule -Color darkslategray1
}

# ─── view all ─────────────────────────────────────────────────────────────────

function Invoke-IaTuiViewAll {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'View all assignments' -Accent $Accent
    $inv  = Get-IaTuiInventory
    $rows = foreach ($it in $inv) {
        $targets = @($it.Assignments | ForEach-Object {
            $disp = Get-IaTargetDisplay -Target $_.Target
            if ($_.Target.IsExclude) { "[coral]EXCLUDE $disp[/]" }
            elseif ($_.Target.FilterId) { "$disp [grey](filter)[/]" }
            else { $disp }
        })
        [pscustomobject]@{
            Area        = "[$Accent]$($it.Area)[/]"
            Resource    = $it.Name
            Platform    = $it.Platform
            'Assigned To' = if ($targets) { $targets -join '; ' } else { '[grey](unassigned)[/]' }
        }
    }
    $rows | Format-SpectreTable -Color $Accent
    $assignedCount = @($inv | Where-Object { $_.Assignments }).Count
    Write-SpectreHost "[grey]… $($inv.Count) resource types · $assignedCount assigned[/]"
}

# ─── group lookup ─────────────────────────────────────────────────────────────

function Invoke-IaTuiGroupLookup {
    param([string]$Accent)
    $name = Read-SpectreText -Question 'Group name or id'
    $g    = Resolve-IaGroup -Value $name
    Write-IaTuiHeader -Screen 'Group lookup' -Sub "assignments for $($g.DisplayName)" -Accent $Accent
    $hits = foreach ($it in (Get-IaTuiInventory)) {
        foreach ($e in (Get-IaItemGroupEdges -Item $it -GroupId $g.Id)) {
            [pscustomobject]@{
                Area     = "[$Accent]$($it.Area)[/]"
                Resource = $it.Name
                Mode     = if ($e.Target.IsExclude) { '[coral]EXCLUDE[/]' } else { 'include' }
                Intent   = $e.Intent
            }
        }
    }
    Write-SpectreHost "[$Accent]$($g.DisplayName)[/] is assigned to [$Accent]$(@($hits).Count)[/] resource(s)"
    if ($hits) { $hits | Format-SpectreTable -Color $Accent }
}

# ─── compare two groups ───────────────────────────────────────────────────────

function Invoke-IaTuiCompare {
    param([string]$Accent)
    $a = Resolve-IaGroup -Value (Read-SpectreText -Question 'Group A')
    $b = Resolve-IaGroup -Value (Read-SpectreText -Question 'Group B')
    Write-IaTuiHeader -Screen 'Compare two groups' -Sub "A = $($a.DisplayName)  ·  B = $($b.DisplayName)" -Accent $Accent

    # Clean rows — used for export (no markup)
    $rows = @(foreach ($it in (Get-IaTuiInventory)) {
        $am = Get-IaItemGroupMode -Item $it -GroupId $a.Id
        $bm = Get-IaItemGroupMode -Item $it -GroupId $b.Id
        if ($am -eq 'none' -and $bm -eq 'none') { continue }
        $rel = if ($am -ne 'none' -and $bm -eq 'none') { 'OnlyA' }
               elseif ($bm -ne 'none' -and $am -eq 'none') { 'OnlyB' }
               elseif (($am -eq 'include' -and $bm -eq 'exclude') -or ($am -eq 'exclude' -and $bm -eq 'include')) { 'Conflict' }
               else { 'Both' }
        [pscustomobject]@{ Area = $it.Area; Resource = $it.Name; Relationship = $rel; AMode = $am; BMode = $bm }
    })

    if (-not $rows) { Write-SpectreHost '[yellow]No assignments differ between these groups.[/]'; return }

    # Display rows — markup only for the table
    $displayRows = $rows | ForEach-Object {
        $relColor = switch ($_.Relationship) {
            'OnlyA'    { $Accent }
            'OnlyB'    { 'deepskyblue1' }
            'Conflict' { 'coral' }
            default    { 'grey' }
        }
        [pscustomobject]@{
            Area         = "[$Accent]$($_.Area)[/]"
            Resource     = $_.Resource
            Relationship = "[$relColor]$($_.Relationship)[/]"
            A            = if ($_.AMode -eq 'exclude') { '[coral]exclude[/]' } elseif ($_.AMode -eq 'none') { '[grey]—[/]' } else { $_.AMode }
            B            = if ($_.BMode -eq 'exclude') { '[coral]exclude[/]' } elseif ($_.BMode -eq 'none') { '[grey]—[/]' } else { $_.BMode }
        }
    }
    $displayRows | Format-SpectreTable -Color $Accent

    $conflicts = @($rows | Where-Object Relationship -eq 'Conflict').Count
    if ($conflicts) { Write-SpectreHost "[coral]$conflicts conflict(s)[/] — one group includes while the other excludes (mirroring would clash)" }

    $export = Read-SpectreSelection -Title 'Export comparison?' -Color $Accent -Choices @('Skip', 'CSV', 'Excel', 'HTML')
    if ($export -eq 'Skip') { return }

    $ext  = switch ($export) { 'Excel' { 'xlsx' } 'HTML' { 'html' } default { 'csv' } }
    $path = Read-SpectreText -Question 'Save to' -DefaultAnswer "group-diff.$ext"

    switch ($export) {
        'CSV'   { $rows | Export-Csv -Path $path -NoTypeInformation -Encoding utf8 }
        'Excel' { $rows | Export-IntuneExcel -Path $path -WorksheetName 'Comparison' `
                      -Title "Group diff: $($a.DisplayName) vs $($b.DisplayName)" }
        'HTML'  { New-IaGroupComparisonHtml -Rows $rows -GroupA $a.DisplayName -GroupB $b.DisplayName |
                      Set-Content -Path $path -Encoding utf8 }
    }
    Write-SpectreHost "[$Accent]Wrote[/] $path"
}

# ─── what-if ──────────────────────────────────────────────────────────────────

function Invoke-IaTuiWhatIf {
    param([string]$Accent)
    $kind = Read-SpectreSelection -Title 'Subject type' -Choices @('user', 'device') -Color $Accent
    $val  = Read-SpectreText -Question "$kind (UPN/name or id)"
    Write-IaTuiHeader -Screen 'What-if: effective assignments' -Sub "subject: $val" -Accent $Accent
    $raw  = if ($kind -eq 'user') { Get-IntuneEffectiveAssignment -User $val }
            else { Get-IntuneEffectiveAssignment -Device $val }
    # Colour-code Effective column when present
    $rows = $raw | ForEach-Object {
        $eff = if ($_.PSObject.Properties['Effective']) { $_.Effective } else { $null }
        $effDisp = if ($eff -eq $false -or "$eff" -like '*BLOCK*') { '[coral]BLOCKED[/]' }
                   elseif ($eff) { 'yes' }
                   else { $null }
        $out = [ordered]@{ Area = "[$Accent]$($_.Area)[/]"; Resource = $_.Resource }
        if ($null -ne $effDisp) { $out.Effective = $effDisp }
        foreach ($p in $_.PSObject.Properties) {
            if ($p.Name -notin 'Area','Resource','Effective') { $out[$p.Name] = $p.Value }
        }
        [pscustomobject]$out
    }
    $rows | Format-SpectreTable -Color $Accent
}

# ─── mirror ───────────────────────────────────────────────────────────────────

function Invoke-IaTuiMirror {
    param([string]$Accent)
    $src   = Resolve-IaGroup -Value (Read-SpectreText -Question 'Source group (copy FROM)')
    $items = Get-IaTuiInventory
    $cands = Get-IaCopyCandidates -Items $items -SrcId $src.Id
    if (-not $cands) { Write-SpectreHost "[yellow]$($src.DisplayName) has no assignments to mirror.[/]"; return }

    $map = @{}; $i = 0
    $labels = foreach ($c in $cands) { $i++; $lbl = "$i. [$($c.Area)] $($c.Name)"; $map[$lbl] = $c.Id; $lbl }
    $picked = Read-SpectreMultiSelection -Title "Select what to mirror from [$Accent]$($src.DisplayName)[/]" `
        -Choices $labels -Color $Accent
    if (-not $picked) { Write-SpectreHost '[yellow]Nothing selected.[/]'; return }
    $ids = @($picked | ForEach-Object { $map[$_] })

    $dst     = Resolve-IaGroup -Value (Read-SpectreText -Question 'Destination group (copy TO)')
    Write-IaTuiHeader -Screen 'Mirror assignments' `
        -Sub "from $($src.DisplayName)  →  $($dst.DisplayName)" -Accent $Accent
    $confirm = Read-SpectreSelection `
        -Title "Apply $($ids.Count) assignment(s) to [$Accent]$($dst.DisplayName)[/]?" `
        -Choices @('Preview only (no changes)', 'Apply now') -Color $Accent
    $commit  = $confirm -eq 'Apply now'

    $plans = Invoke-IaCopy -Items $items -SrcId $src.Id -DstId $dst.Id -DstName $dst.DisplayName `
        -IncludeIds $ids -Commit:$commit
    if (-not $plans) { Write-SpectreHost '[yellow]Nothing to change (already assigned?).[/]'; return }
    $plans | ForEach-Object {
        $status = if ($commit) { if ($_.Applied) { "[$Accent]OK[/]" } else { '[coral]FAILED[/]' } } else { '[grey]PREVIEW[/]' }
        [pscustomobject]@{
            Status   = $status
            Area     = "[$Accent]$($_.Area)[/]"
            Resource = $_.ResourceName
            Added    = ($_.Added -join '; ')
            Error    = $_.Error
        }
    } | Format-SpectreTable -Color $Accent
    if (-not $commit) { Write-SpectreHost "[grey]Preview only — re-run and choose 'Apply now' to write.[/]" }
}

# ─── audit ────────────────────────────────────────────────────────────────────

function Invoke-IaTuiAudit {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Audit' -Sub 'tenant-wide assignment health' -Accent $Accent
    $a = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Auditing…' -ScriptBlock {
        Get-IntuneAssignmentAudit
    }
    Write-SpectreHost (
        "[$Accent]Resources scanned  $($a.ResourceCount)[/]  " +
        "[$Accent]Assigned  $($a.AssignedCount)[/]  " +
        "[grey]Unassigned  $($a.UnassignedCount)[/]  " +
        "Assignment edges  $($a.EdgeCount)  " +
        "Exclusions  $($a.ExclusionCount)"
    )
    Write-SpectreHost ""
    $a.ByArea | Format-SpectreTable -Color $Accent

    if ($a.ByArea) {
        Write-SpectreHost "[$Accent]Assigned by area[/]"
        $chartData = $a.ByArea | ForEach-Object {
            [pscustomobject]@{ Label = $_.Area; Value = [int]$_.Assigned; Color = $Accent }
        }
        $chartData | Format-SpectreBarChart -Color $Accent
    }

    if ($a.TopGroups) {
        Write-SpectreHost "[$Accent]Most-assigned groups[/]"
        $a.TopGroups | Format-SpectreTable -Color $Accent
    }
}

# ─── bulk assign ──────────────────────────────────────────────────────────────

function Invoke-IaTuiBulkAssign {
    param([string]$Accent)
    $g     = Resolve-IaGroup -Value (Read-SpectreText -Question 'Group to assign')
    $areas = @('All areas') + (@(Get-IaResourceRegistry | ForEach-Object Area | Select-Object -Unique | Sort-Object))
    $area  = Read-SpectreSelection -Title 'Which area?' -Choices $areas -Color $Accent

    $items  = Get-IaTuiInventory
    $scoped = if ($area -eq 'All areas') { $items } else { @($items | Where-Object Area -eq $area) }
    if (-not $scoped) { Write-SpectreHost "[yellow]No resources in $area.[/]"; return }

    $intent = $null
    if ($area -eq 'Apps' -or ($scoped | Where-Object { (Find-IaResourceType -Key $_.ResourceType).HasIntent })) {
        $intent = Read-SpectreSelection -Title 'Install intent (apps)' -Color $Accent `
            -Choices @('required', 'available', 'uninstall', 'availableWithoutEnrollment', '(none / non-app)')
        if ($intent -eq '(none / non-app)') { $intent = $null }
    }
    $modeChoice = Read-SpectreSelection -Title 'Assignment mode' -Choices @('include', 'exclude (block)') -Color $Accent
    $exclude    = $modeChoice -like 'exclude*'

    $filterId = $null; $filterType = 'include'
    $filters  = Get-IaFilterList
    if ($filters) {
        $fchoice = Read-SpectreSelection -Title 'Assignment filter' -Color $Accent `
            -Choices (@('(no filter)') + @($filters | ForEach-Object Name))
        if ($fchoice -ne '(no filter)') {
            $filterId   = ($filters | Where-Object Name -eq $fchoice | Select-Object -First 1).Id
            $filterType = Read-SpectreSelection -Title "Filter mode for '$fchoice'" -Choices @('include', 'exclude') -Color $Accent
        }
    }

    $map  = @{}; $i = 0
    $labels = foreach ($it in ($scoped | Sort-Object Area, Name)) {
        $i++; $lbl = "$i. [$($it.Area)] $($it.Name)"; $map[$lbl] = $it; $lbl
    }

    $subTitle = if ($intent) { "group: $($g.DisplayName)  ·  area: $area  ·  intent: $intent" } `
                else          { "group: $($g.DisplayName)  ·  area: $area" }
    Write-IaTuiHeader -Screen 'Assign a group to many' -Sub $subTitle -Accent $Accent

    $picked = Read-SpectreMultiSelection -Title "Select resources to assign [$Accent]$($g.DisplayName)[/]" `
        -Choices $labels -Color $Accent -PageSize 18
    if (-not $picked) { Write-SpectreHost '[yellow]Nothing selected.[/]'; return }
    $sel = @($picked | ForEach-Object { $map[$_] })

    $verb    = if ($exclude) { 'EXCLUDE' } else { 'assign' }
    $confirm = Read-SpectreSelection -Color $Accent `
        -Title "$verb [$Accent]$($g.DisplayName)[/] on $($sel.Count) resource(s)?" `
        -Choices @('Preview only (no changes)', 'Apply now')
    $commit  = $confirm -eq 'Apply now'

    $plans = Invoke-IaBulkAssign -Items $sel -GroupId $g.Id -GroupName $g.DisplayName `
        -Exclude:$exclude -Intent $intent -FilterId $filterId -FilterType $filterType -Commit:$commit
    $plans | ForEach-Object {
        $status = if ($_.Skipped) { '[grey]SKIP[/]' }
                  elseif (-not $commit) { '[grey]PREVIEW[/]' }
                  elseif ($_.Applied) { "[$Accent]OK[/]" }
                  else { '[coral]FAILED[/]' }
        [pscustomobject]@{
            Status   = $status
            Area     = "[$Accent]$($_.Area)[/]"
            Resource = $_.ResourceName
            Detail   = if ($_.Skipped) { $_.Skipped } else { ($_.Added -join '; ') }
        }
    } | Format-SpectreTable -Color $Accent
    if ($commit) { $script:IaTuiInventory = $null }
    else { Write-SpectreHost "[grey]Preview only — choose 'Apply now' to write.[/]" }
}

# ─── templates ────────────────────────────────────────────────────────────────

function Invoke-IaTuiTemplates {
    param([string]$Accent)
    $action = Read-SpectreSelection -Title 'Templates' -Color $Accent -Choices @(
        'Capture a group as a template (save to file)',
        'Apply a template file to a group'
    )
    if ($action -like 'Capture*') {
        $g    = Resolve-IaGroup -Value (Read-SpectreText -Question 'Group to capture')
        $name = Read-SpectreText -Question 'Template name' -DefaultAnswer 'baseline'
        $path = Read-SpectreText -Question 'Save to path' -DefaultAnswer "$name.json"
        Write-IaTuiHeader -Screen 'Templates · capture' -Sub "group: $($g.DisplayName)" -Accent $Accent
        $tmpl = New-IaTemplateFromGroup -Items (Get-IaTuiInventory) -GroupId $g.Id -Name $name
        $tmpl | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding utf8
        Write-SpectreHost "[$Accent]Saved[/] template '$name' with [$Accent]$($tmpl.resources.Count)[/] resource(s) → $path"
    } else {
        $path = Read-SpectreText -Question 'Template file path'
        if (-not (Test-Path $path)) { Write-SpectreHost "[red]Not found:[/] $path"; return }
        $tmpl = Get-Content $path -Raw | ConvertFrom-Json
        $g    = Resolve-IaGroup -Value (Read-SpectreText -Question 'Device group to stamp on')
        Write-IaTuiHeader -Screen 'Templates · apply' `
            -Sub "template: $($tmpl.name)  ·  target: $($g.DisplayName)" -Accent $Accent
        $keys  = @($tmpl.resources | ForEach-Object resource_type | Select-Object -Unique)
        $items = Get-IaInventory -Type $keys
        $confirm = Read-SpectreSelection -Color $Accent `
            -Title "Apply template '$($tmpl.name)' ($($tmpl.resources.Count) resources) to [$Accent]$($g.DisplayName)[/]?" `
            -Choices @('Preview only (no changes)', 'Apply now')
        $commit = $confirm -eq 'Apply now'
        $plans  = Invoke-IaTemplateApply -Template $tmpl -Items $items -GroupId $g.Id -GroupName $g.DisplayName -Commit:$commit
        $plans | ForEach-Object {
            $status = if ($_.Skipped) { '[grey]SKIP[/]' }
                      elseif (-not $commit) { '[grey]PREVIEW[/]' }
                      elseif ($_.Applied) { "[$Accent]OK[/]" }
                      else { '[coral]FAILED[/]' }
            [pscustomobject]@{
                Status   = $status
                Area     = "[$Accent]$($_.Area)[/]"
                Resource = $_.ResourceName
                Detail   = if ($_.Skipped) { $_.Skipped } else { ($_.Added -join '; ') }
            }
        } | Format-SpectreTable -Color $Accent
        if ($commit) { $script:IaTuiInventory = $null }
    }
}

# ─── elevate (PIM) ────────────────────────────────────────────────────────────

function Invoke-IaTuiElevate {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Elevate · PIM role activation' -Accent $Accent
    $eligible = Get-IntuneEligibleRole
    if (-not $eligible) {
        Write-SpectreHost '[yellow]You have no PIM-eligible roles to activate (or this is an app-only sign-in).[/]'
        $active = Get-IntuneActiveRole
        if ($active) { Write-SpectreHost 'Currently active:'; $active | Format-SpectreTable -Color $Accent }
        return
    }
    $role    = Read-SpectreSelection -Title 'Activate which eligible role?' -Color $Accent `
        -Choices @($eligible | ForEach-Object Role)
    $just    = Read-SpectreText -Question 'Justification'
    $dur     = Read-SpectreText -Question 'Duration (e.g. 2h, 30m, 8h)' -DefaultAnswer '2h'
    $confirm = Read-SpectreSelection -Title "Activate [$Accent]$role[/] for $dur?" `
        -Choices @('Yes, activate now', 'Cancel') -Color $Accent
    if ($confirm -notlike 'Yes*') { Write-SpectreHost '[grey]Cancelled.[/]'; return }

    $res = Enable-IntuneAdminRole -Role $role -Justification $just -Duration $dur -Confirm:$false
    Write-SpectreHost "[$Accent]$($res.Role)[/] → status [$Accent]$($res.Status)[/] (expires after $($res.Duration))"
    if ($res.Status -in 'PendingApproval', 'PendingProvisioning') {
        Write-SpectreHost '[yellow]Activation needs approval / is provisioning — re-check with Get-IntuneActiveRole.[/]'
    }
    Get-IntuneActiveRole | Format-SpectreTable -Color $Accent
}

# ─── graph call pane ──────────────────────────────────────────────────────────

function Show-IaTuiCallLog {
    param([string]$Accent, [int]$Tail = 12)
    $calls = Get-IaCallLogEntries | Select-Object -Last $Tail
    if (-not $calls) { return }
    $rows = foreach ($c in $calls) {
        $methodColor = switch ($c.Method) {
            'POST'   { 'gold1' }
            'PATCH'  { 'orange1' }
            'DELETE' { 'coral' }
            'PUT'    { 'orange1' }
            default  { 'grey' }
        }
        $statusColor = if ($c.Status -ge 200 -and $c.Status -lt 300) { $Accent }
                       elseif ($c.Status -ge 400) { 'coral' }
                       elseif ($c.Status) { 'yellow' }
                       else { 'grey' }
        [pscustomobject]@{
            Time     = $c.Time.ToString('HH:mm:ss')
            Method   = "[$methodColor]$($c.Method)[/]"
            Endpoint = $c.Uri
            Status   = "[$statusColor]$($c.Status)[/]"
            Ms       = $c.Ms
            Items    = $c.Count
        }
    }
    $okCount = @($calls | Where-Object { $_.Status -ge 200 -and $_.Status -lt 300 }).Count
    Write-SpectreHost "[grey]── graph calls ── last $($rows.Count) · $okCount ok · session total $((Get-IaCallLogEntries).Count) ──[/]"
    $rows | Format-SpectreTable -Color $Accent
    Write-SpectreHost "[grey]toggle with 'Toggle graph-call pane'  ·  Get-IntuneCallLog -Tail 20  ·  -Errors[/]"
}

# ─── reports submenu ──────────────────────────────────────────────────────────

function Invoke-IaTuiReports {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Reports' -Sub 'status · audit · approvals · any report' -Accent $Accent
    $pick = Read-SpectreSelection -Title 'Reports' -Color $Accent -Choices @(
        'App install status (device / user)',
        'Configuration profile status',
        'Compliance status',
        'Deployment summary (success / fail, by group)',
        'Audit log (who changed what)',
        'Multi Admin Approval requests',
        'PIM activations',
        'Run any Intune report',
        'Back'
    )
    switch -Wildcard ($pick) {
        'App install*' {
            $app = Read-SpectreText -Question 'App name (or id)'
            $by  = Read-SpectreSelection -Title 'Pivot by' -Choices @('Device', 'User') -Color $Accent
            Write-IaTuiHeader -Screen 'App install status' -Sub "app: $app  ·  by: $by" -Accent $Accent
            Invoke-SpectreCommandWithStatus -Spinner Dots -Title "Querying $app…" -ScriptBlock {
                Get-IntuneAppInstallStatus -App $using:app -By $using:by
            } | Format-SpectreTable -Color $Accent
        }
        'Configuration*' {
            $p = Read-SpectreText -Question 'Configuration profile name (or id)'
            Write-IaTuiHeader -Screen 'Configuration profile status' -Sub "profile: $p" -Accent $Accent
            Get-IntuneConfigurationStatus -Profile $p | Format-SpectreTable -Color $Accent
        }
        'Compliance*' {
            $mode = Read-SpectreSelection -Title 'Compliance by' -Choices @('Tenant summary', 'Policy', 'Device') -Color $Accent
            Write-IaTuiHeader -Screen 'Compliance status' -Sub $mode.ToLower() -Accent $Accent
            $rows = switch -Wildcard ($mode) {
                'Policy'  { Get-IntuneComplianceStatus -Policy (Read-SpectreText -Question 'Policy name') }
                'Device'  { Get-IntuneComplianceStatus -Device (Read-SpectreText -Question 'Device name') }
                default   { Get-IntuneComplianceStatus }
            }
            $rows | Format-SpectreTable -Color $Accent
        }
        'Deployment*' {
            $grp = Read-SpectreText -Question 'Scope to group (blank = all)' -DefaultAnswer ''
            Write-IaTuiHeader -Screen 'Deployment summary' `
                -Sub "for everything assigned to '$(if ($grp) { $grp } else { 'all resources' })'" -Accent $Accent
            $data = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Rolling up deployment health…' -ScriptBlock {
                if ($using:grp) { Get-IntuneDeploymentSummary -Group $using:grp }
                else { Get-IntuneDeploymentSummary }
            }
            $colorRows = $data | ForEach-Object {
                $fr      = [double]$_.FailRate
                $frColor = if ($fr -gt 15) { 'coral' } elseif ($fr -gt 5) { 'yellow' } else { $Accent }
                [pscustomobject]@{
                    Area     = "[$Accent]$($_.Area)[/]"
                    Resource = $_.Resource
                    OK       = $_.Success
                    FAIL     = if ($_.Failed -gt 0) { "[coral]$($_.Failed)[/]" } else { "$($_.Failed)" }
                    PEND     = $_.Pending
                    TOTAL    = $_.Total
                    'FAIL%'  = "[$frColor]$($_.FailRate)[/]"
                }
            }
            $colorRows | Format-SpectreTable -Color $Accent
            Write-SpectreHost "[grey]sorted by FailRate  ·  -FailuresOnly to show only problems[/]"
        }
        'Audit*' {
            $since = Read-SpectreText -Question 'Since (e.g. 7d, 24h)' -DefaultAnswer '7d'
            $act   = Read-SpectreText -Question 'Activity contains (blank = any)' -DefaultAnswer ''
            Write-IaTuiHeader -Screen 'Audit log' -Sub "since $since$(if ($act) { "  ·  activity: $act" })" -Accent $Accent
            $p = @{ Since = $since }; if ($act) { $p.Activity = $act }
            Get-IntuneAuditLog @p | Select-Object -First 50 | Format-SpectreTable -Color $Accent
        }
        'Multi Admin*' {
            Write-IaTuiHeader -Screen 'Multi Admin Approval requests' -Accent $Accent
            Get-IntuneApprovalRequest | Format-SpectreTable -Color $Accent
        }
        'PIM*' {
            Write-IaTuiHeader -Screen 'PIM activations' -Accent $Accent
            Get-IntunePimActivation | Format-SpectreTable -Color $Accent
        }
        'Run any*' {
            $name = Read-SpectreSelection -Title 'Pick a report' -Color $Accent `
                -Choices (@(Get-IntuneReportCatalog | ForEach-Object Name) + 'Other (type a name)')
            if ($name -like 'Other*') { $name = Read-SpectreText -Question 'Report name' }
            Write-IaTuiHeader -Screen "Report: $name" -Accent $Accent
            Invoke-SpectreCommandWithStatus -Spinner Dots -Title "Running $name…" -ScriptBlock {
                Export-IntuneReport -Name $using:name
            } | Select-Object -First 100 | Format-SpectreTable -Color $Accent
        }
        default { return }
    }
}

# ─── backup / restore / drift ─────────────────────────────────────────────────

function Invoke-IaTuiBackup {
    param([string]$Accent)
    $pick = Read-SpectreSelection -Title 'Backup / Restore / Drift' -Color $Accent -Choices @(
        'Backup all assignments to a file',
        'Drift — compare current vs a snapshot',
        'Restore from a snapshot',
        'Back'
    )
    switch -Wildcard ($pick) {
        'Backup*' {
            $p    = Read-SpectreText -Question 'Save snapshot to' -DefaultAnswer 'intune-assignments.json'
            Write-IaTuiHeader -Screen 'Backup' -Sub "→ $p" -Accent $Accent
            $snap = Backup-IntuneAssignment -Path $p
            Write-SpectreHost "[$Accent]Backed up[/] $($snap.count) resource(s) → $p"
        }
        'Drift*' {
            $p = Read-SpectreText -Question 'Snapshot file to compare against'
            Write-IaTuiHeader -Screen 'Drift' -Sub "snapshot: $p" -Accent $Accent
            $d = @(Get-IntuneAssignmentDrift -Path $p)
            if (-not $d) { Write-SpectreHost "[$Accent]No drift — current state matches the snapshot.[/]"; return }
            Write-SpectreHost "[$Accent]$($d.Count)[/] drifted assignment target(s):"
            $d | ForEach-Object {
                $changeColor = switch ($_.Change) { 'Added' { $Accent } 'Removed' { 'coral' } default { 'yellow' } }
                [pscustomobject]@{
                    Change   = "[$changeColor]$($_.Change)[/]"
                    Area     = "[$Accent]$($_.Area)[/]"
                    Resource = $_.Resource
                    Target   = $_.Target
                }
            } | Format-SpectreTable -Color $Accent
            Write-SpectreHost "[grey]Added = [$Accent]sea-green[/]  ·  Removed = [coral]coral[/]  ·  use Restore to revert[/]"
        }
        'Restore*' {
            $p    = Read-SpectreText -Question 'Snapshot file to restore'
            $mode = Read-SpectreSelection -Title 'Restore mode' -Color $Accent -Choices @('Preview only (no changes)', 'Apply now')
            Write-IaTuiHeader -Screen 'Restore' -Sub "snapshot: $p" -Accent $Accent
            $plans = if ($mode -like 'Apply*') { Restore-IntuneAssignment -Path $p -Confirm:$false }
                     else { Restore-IntuneAssignment -Path $p -WhatIf }
            @($plans) | ForEach-Object {
                $status = if ($_.Skipped) { '[grey]SKIP[/]' }
                          elseif ($_.Error) { '[coral]FAIL[/]' }
                          elseif ($_.Applied) { "[$Accent]OK[/]" }
                          else { '[grey]PREVIEW[/]' }
                [pscustomobject]@{
                    Status   = $status
                    Area     = "[$Accent]$($_.Area)[/]"
                    Resource = $_.ResourceName
                    Detail   = if ($_.Skipped) { $_.Skipped } elseif ($_.Error) { $_.Error } else { ($_.Added -join '; ') }
                }
            } | Format-SpectreTable -Color $Accent
            if ($mode -like 'Apply*') { $script:IaTuiInventory = $null }
        }
        default { return }
    }
}

# ─── export report ────────────────────────────────────────────────────────────

function Invoke-IaTuiExport {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Export report' -Sub 'HTML · Excel · Rich HTML' -Accent $Accent
    $fmt = Read-SpectreSelection -Title 'Export format' -Color $Accent -Choices @(
        'Built-in HTML (themed, no dependencies)',
        'Excel workbook (ImportExcel)',
        'Rich interactive HTML (PSWriteHTML)'
    )
    switch -Wildcard ($fmt) {
        'Built-in*' {
            $p = Read-SpectreText -Question 'Output path' -DefaultAnswer 'intune-assignments.html'
            New-IaHtmlReport -Items (Get-IaTuiInventory) | Set-Content -Path $p -Encoding utf8
            Write-SpectreHost "[$Accent]Wrote[/] $p"
        }
        'Excel*' {
            if (-not (Get-Command Export-Excel -ErrorAction SilentlyContinue)) {
                Write-SpectreHost "[yellow]ImportExcel not installed.[/] Install-Module ImportExcel -Scope CurrentUser"; return
            }
            $p = Read-SpectreText -Question 'Output path' -DefaultAnswer 'intune-assignments.xlsx'
            Get-IntuneAssignment -Flat | Export-IntuneExcel -Path $p -WorksheetName Assignments -Title 'Intune assignments'
            Write-SpectreHost "[$Accent]Wrote[/] $p"
        }
        'Rich*' {
            if (-not (Get-Command New-HTML -ErrorAction SilentlyContinue)) {
                Write-SpectreHost "[yellow]PSWriteHTML not installed.[/] Install-Module PSWriteHTML -Scope CurrentUser"; return
            }
            $p = Read-SpectreText -Question 'Output path' -DefaultAnswer 'intune-assignments-rich.html'
            Export-IntuneHtmlReport -Path $p
            Write-SpectreHost "[$Accent]Wrote[/] $p"
        }
    }
}
