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

        Entity pickers (groups, apps, profiles, policies) are arrow-key
        selection lists, not free-text fields — pick from what's there instead
        of typing names that might 404.
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
    $script:IaCaps         = @{}     # cmdlet/param capability cache

    function Get-IaTuiInventory {
        if ($null -eq $script:IaTuiInventory) {
            $script:IaTuiInventory = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Reading Intune assignments…' -ScriptBlock {
                Get-IaInventory
            }
        }
        $script:IaTuiInventory
    }

    $ctx  = Get-MgContext
    $elev = try { if (Test-IaPrivileged) { "[green]● elevated[/]" } else { "[yellow]○ not elevated[/]" } } catch { '' }
    $script:IaTuiAccount = $ctx.Account
    $script:IaTuiElev    = $elev

    function Show-IaTuiSplash {
        Clear-Host
        Write-SpectreFigletText -Text 'TIDE' -Color $accent
        Write-SpectreHost "[$accent]●[/] $($ctx.Account)  ·  tenant [grey]$($ctx.TenantId)[/]  ·  $elev"
        Write-SpectreRule -Title 'TIDE · targeted intune deployment & endpoints' -Color $accent
    }

    Show-IaTuiSplash
    # One-time inventory load: watch the graph calls stream in, then wipe to a clean workspace
    # so every screen renders as a tidy bordered table instead of below a wall of GET lines.
    Get-IaTuiInventory | Out-Null
    Show-IaTuiSplash

    while ($true) {
        $choice = Read-SpectreSelection -Title "Choose an action" -Color $accent -PageSize 16 -Choices @(
            'View all assignments',
            'Group lookup (what is a group assigned to)',
            'Compare two groups',
            'What-if (user / device effective assignments)',
            'Mirror assignments (copy A -> B, pick which)',
            'Assign a group to many (pick which)',
            'Templates (capture / apply)',
            'Backup / Restore / Drift',
            'Reports (status · audit · approvals)',
            'Windows 365 (Cloud PCs · provisioning · connections)',
            'Elevate (PIM) — activate an eligible role',
            'Audit',
            'Export report (HTML · Excel · Rich HTML)',
            'Refresh data',
            'Quit'
        )
        try {
            switch -Wildcard ($choice) {
                'View all*'       { Invoke-IaTuiViewAll     -Accent $accent }
                'Group lookup*'   { Invoke-IaTuiGroupLookup -Accent $accent }
                'Compare*'        { Invoke-IaTuiCompare     -Accent $accent }
                'What-if*'        { Invoke-IaTuiWhatIf      -Accent $accent }
                'Mirror*'         { Invoke-IaTuiMirror      -Accent $accent }
                'Assign a group*' { Invoke-IaTuiBulkAssign  -Accent $accent }
                'Templates*'      { Invoke-IaTuiTemplates   -Accent $accent }
                'Backup*'         { Invoke-IaTuiBackup      -Accent $accent }
                'Reports*'        { Invoke-IaTuiReports     -Accent $accent }
                'Windows 365*'    { Invoke-IaTuiCloudPC     -Accent $accent }
                'Elevate*'        { Invoke-IaTuiElevate     -Accent $accent }
                'Audit'           { Invoke-IaTuiAudit       -Accent $accent }
                'Export*'         { Invoke-IaTuiExport      -Accent $accent }
                'Refresh*'        { $script:IaTuiInventory = $null; Get-IaTuiInventory | Out-Null
                                    Write-SpectreHost "[$accent]Refreshed.[/]" }
                'Quit'            { try { $host.UI.RawUI.WindowTitle = 'pwsh' } catch { }; return }
            }
        } catch {
            Write-SpectreHost "[red]Error:[/] $($_.Exception.Message)"
        }
        if ($choice -ne 'Quit') {
            Read-SpectrePause | Out-Null
            Show-IaTuiSplash
        }
    }
}

# ─── capability-aware wrappers ────────────────────────────────────────────────
# PwshSpectreConsole's parameter surface varies by version. Detect once, degrade
# gracefully — so a colored cell renders where supported and never leaks raw
# "[grey]…[/]" markup where it isn't.

function Test-IaCap {
    param([string]$Command, [string]$Parameter)
    $key = "$Command/$Parameter"
    if (-not $script:IaCaps) { $script:IaCaps = @{} }
    if (-not $script:IaCaps.ContainsKey($key)) {
        $script:IaCaps[$key] = try { (Get-Command $Command -ErrorAction Stop).Parameters.ContainsKey($Parameter) } catch { $false }
    }
    $script:IaCaps[$key]
}

function Format-IaTable {
    # Format-SpectreTable, but render inline [color] markup when the installed
    # version supports -AllowMarkup; otherwise strip the tags so nothing leaks.
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline)]$InputObject, [string]$Color)
    begin { $rows = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($i in @($InputObject)) { if ($null -ne $i) { $rows.Add($i) } } }
    end {
        if ($rows.Count -eq 0) { return }
        if (Test-IaCap 'Format-SpectreTable' 'AllowMarkup') {
            $rows | Format-SpectreTable -Color $Color -AllowMarkup
        } else {
            $clean = foreach ($r in $rows) {
                $o = [ordered]@{}
                foreach ($p in $r.PSObject.Properties) {
                    $o[$p.Name] = if ($p.Value -is [string]) { [regex]::Replace($p.Value, '\[/?[^\[\]]*\]', '') } else { $p.Value }
                }
                [pscustomobject]$o
            }
            $clean | Format-SpectreTable -Color $Color
        }
    }
}

function Read-IaSelection {
    # Read-SpectreSelection with type-to-filter search on long lists when available.
    param([string]$Title, [object[]]$Choices, [string]$Color, [int]$PageSize = 0)
    $list = @($Choices)
    $p = @{ Title = $Title; Choices = $list; Color = $Color }
    if     ($PageSize -gt 0)  { $p.PageSize = $PageSize }
    elseif ($list.Count -gt 15) { $p.PageSize = 15 }
    if ($list.Count -gt 12 -and (Test-IaCap 'Read-SpectreSelection' 'EnableSearch')) { $p.EnableSearch = $true }
    Read-SpectreSelection @p
}

# ─── entity pickers (lists, not typing) ───────────────────────────────────────

function Select-IaGroup {
    # Pick a group from a searchable list. Falls back to typing only if the
    # directory can't be read (Group.Read.All not consented → 403).
    param([string]$Accent, [string]$Title = 'Select a group')
    if ($script:IaDirectoryBlocked) {
        throw "Can't read directory groups — Group.Read.All isn't consented. A Global Admin must grant admin consent to the Microsoft Graph PowerShell app, then reconnect."
    }
    $groups = $null
    try {
        $groups = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Loading groups…' -ScriptBlock {
            Get-IaCollection -V1 -Path "groups?`$select=id,displayName&`$top=999"
        }
    } catch { $groups = $null }
    $groups = @($groups | Where-Object displayName)
    if (-not $groups.Count) {
        throw "Can't list groups — directory read is blocked (needs Group.Read.All admin consent), or no groups exist."
    }
    $map = @{}; foreach ($g in $groups) { $map[$g.displayName] = $g.id }
    $name = Read-IaSelection -Title $Title -Choices (@($map.Keys) | Sort-Object) -Color $Accent
    [pscustomobject]@{ Id = $map[$name]; DisplayName = $name }
}

function Select-IaInventoryItem {
    # Pick a resource (app, profile, policy, script…) from the loaded inventory.
    # No extra Graph calls, no directory permissions needed.
    param([string]$Accent, [string]$Area, [string]$Title)
    $items = @(Get-IaTuiInventory | Where-Object Area -eq $Area | Sort-Object Name)
    if (-not $items) { Write-SpectreHost "[yellow]No $Area resources found.[/]"; return $null }
    $pick = Read-IaSelection -Title $Title -Choices (@($items | ForEach-Object Name)) -Color $Accent
    $items | Where-Object Name -eq $pick | Select-Object -First 1
}

# ─── shared header ────────────────────────────────────────────────────────────

function Write-IaTuiHeader {
    param([string]$Screen, [string]$Sub = '', [string]$Accent)
    Clear-Host
    try { $host.UI.RawUI.WindowTitle = "TIDE — $Screen" } catch { }
    Write-SpectreHost "[$Accent]≈ TIDE[/]  [bold]· $Screen[/]"
    if ($Sub) {
        Write-SpectreHost "[grey]$Sub[/]"
    } elseif ($script:IaTuiAccount) {
        Write-SpectreHost "[grey]● $($script:IaTuiAccount)  ·  [/]$script:IaTuiElev"
    }
    Write-SpectreRule -Color darkslategray1
}

# ─── shared change-plan renderer ──────────────────────────────────────────────

function Show-IaRestorePlan {
    # Render restore/apply change plans (OK / FAIL / SKIP / PREVIEW) for both the
    # assignment-restore and full-config-restore flows.
    param([object[]]$Plans, [string]$Accent)
    $rows = @($Plans) | ForEach-Object {
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
    }
    if (-not $rows) { Write-SpectreHost '[yellow]Nothing to restore.[/]'; return }
    $rows | Format-IaTable -Color $Accent
}

# ─── view all ─────────────────────────────────────────────────────────────────

function Invoke-IaTuiViewAll {
    param([string]$Accent)
    $inv       = Get-IaTuiInventory
    $areaCount = @($inv | Group-Object Area).Count
    Write-IaTuiHeader -Screen 'View all assignments' `
        -Sub "$($inv.Count) resource types · $areaCount areas · groups resolved" -Accent $Accent
    $rows = foreach ($it in $inv) {
        $targets = @($it.Assignments | ForEach-Object {
            $disp = Get-IaTargetDisplay -Target $_.Target
            if ($_.Target.IsExclude) { "[coral]EXCLUDE $disp[/]" }
            elseif ($_.Target.FilterId) { "$disp [grey](filter)[/]" }
            else { $disp }
        })
        [pscustomobject]@{
            Area          = "[$Accent]$($it.Area)[/]"
            Resource      = $it.Name
            Platform      = $it.Platform
            'Assigned To' = if ($targets) { $targets -join '; ' } else { '[grey](unassigned)[/]' }
        }
    }
    $rows | Format-IaTable -Color $Accent
}

# ─── group lookup ─────────────────────────────────────────────────────────────

function Invoke-IaTuiGroupLookup {
    param([string]$Accent)
    $g = Select-IaGroup -Accent $Accent -Title 'Group to look up'
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
    if ($hits) { $hits | Format-IaTable -Color $Accent }
}

# ─── compare two groups ───────────────────────────────────────────────────────

function Invoke-IaTuiCompare {
    param([string]$Accent)
    $a = Select-IaGroup -Accent $Accent -Title 'Group A'
    $b = Select-IaGroup -Accent $Accent -Title 'Group B'
    Write-IaTuiHeader -Screen 'Compare two groups' -Sub "A = $($a.DisplayName)  ·  B = $($b.DisplayName)" -Accent $Accent

    # Clean rows for export (no markup); display rows get the colour.
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

    $rows | ForEach-Object {
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
    } | Format-IaTable -Color $Accent

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
    $rows = $raw | ForEach-Object {
        $o = [ordered]@{}
        foreach ($p in $_.PSObject.Properties) {
            $v = $p.Value
            if ($p.Name -eq 'Area') { $v = "[$Accent]$v[/]" }
            elseif ($p.Name -eq 'Effective') {
                if ($v -eq $false -or "$v" -match 'block|exclud') { $v = '[coral]BLOCKED[/]' }
                elseif ($v -eq $true) { $v = 'yes' }
            }
            $o[$p.Name] = $v
        }
        [pscustomobject]$o
    }
    $rows | Format-IaTable -Color $Accent
}

# ─── mirror ───────────────────────────────────────────────────────────────────

function Invoke-IaTuiMirror {
    param([string]$Accent)
    $src   = Select-IaGroup -Accent $Accent -Title 'Source group (copy FROM)'
    $items = Get-IaTuiInventory
    $cands = Get-IaCopyCandidates -Items $items -SrcId $src.Id
    if (-not $cands) { Write-SpectreHost "[yellow]$($src.DisplayName) has no assignments to mirror.[/]"; return }

    $map = @{}; $i = 0
    $labels = foreach ($c in $cands) { $i++; $lbl = "$i. [$($c.Area)] $($c.Name)"; $map[$lbl] = $c.Id; $lbl }
    $picked = Read-SpectreMultiSelection -Title "Select what to mirror from [$Accent]$($src.DisplayName)[/]" `
        -Choices $labels -Color $Accent
    if (-not $picked) { Write-SpectreHost '[yellow]Nothing selected.[/]'; return }
    $ids = @($picked | ForEach-Object { $map[$_] })

    $dst = Select-IaGroup -Accent $Accent -Title 'Destination group (copy TO)'
    Write-IaTuiHeader -Screen 'Mirror assignments' -Sub "from $($src.DisplayName)  →  $($dst.DisplayName)" -Accent $Accent
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
    } | Format-IaTable -Color $Accent
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
        "[$Accent]Resources scanned  $($a.ResourceCount)[/]   " +
        "[$Accent]Assigned  $($a.AssignedCount)[/]   " +
        "[grey]Unassigned  $($a.UnassignedCount)[/]   " +
        "Assignment edges  $($a.EdgeCount)   " +
        "Exclusions  $($a.ExclusionCount)"
    )
    Write-SpectreHost ""
    $a.ByArea | ForEach-Object {
        [pscustomobject]@{ Area = "[$Accent]$($_.Area)[/]"; Total = $_.Total; Assigned = $_.Assigned }
    } | Format-IaTable -Color $Accent

    if ($a.ByArea) {
        Write-SpectreHost ""
        Write-SpectreHost "[$Accent]Assigned by area[/]"
        $max = ($a.ByArea | Measure-Object -Property Assigned -Maximum).Maximum
        foreach ($r in ($a.ByArea | Sort-Object Assigned -Descending)) {
            $w   = if ($max) { [int][math]::Round(($r.Assigned / $max) * 32) } else { 0 }
            $bar = '█' * [math]::Max($w, 1)
            Write-SpectreHost ("[grey]{0,-16}[/] [$Accent]{1}[/] {2}" -f $r.Area, $bar, $r.Assigned)
        }
    }

    if ($a.TopGroups) {
        Write-SpectreHost ""
        Write-SpectreHost "[$Accent]Most-assigned groups[/]"
        $a.TopGroups | Format-IaTable -Color $Accent
    }
}

# ─── bulk assign ──────────────────────────────────────────────────────────────

function Invoke-IaTuiBulkAssign {
    param([string]$Accent)
    $g     = Select-IaGroup -Accent $Accent -Title 'Group to assign'
    $areas = @('All areas') + (@(Get-IaResourceRegistry | ForEach-Object Area | Select-Object -Unique | Sort-Object))
    $area  = Read-IaSelection -Title 'Which area?' -Choices $areas -Color $Accent

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
        $fchoice = Read-IaSelection -Title 'Assignment filter' -Color $Accent `
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
    } | Format-IaTable -Color $Accent
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
        $g    = Select-IaGroup -Accent $Accent -Title 'Group to capture'
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
        $g    = Select-IaGroup -Accent $Accent -Title 'Device group to stamp on'
        Write-IaTuiHeader -Screen 'Templates · apply' -Sub "template: $($tmpl.name)  ·  target: $($g.DisplayName)" -Accent $Accent
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
        } | Format-IaTable -Color $Accent
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
        if ($active) { Write-SpectreHost 'Currently active:'; $active | Format-IaTable -Color $Accent }
        return
    }
    $role    = Read-IaSelection -Title 'Activate which eligible role?' -Color $Accent `
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
    Get-IntuneActiveRole | Format-IaTable -Color $Accent
}

# ─── reports submenu ──────────────────────────────────────────────────────────

function Invoke-IaTuiReports {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Reports' -Sub 'status · audit · approvals · any report' -Accent $Accent
    $pick = Read-SpectreSelection -Title 'Reports' -Color $Accent -PageSize 12 -Choices @(
        'Tenant dashboard (devices · compliance · posture)',
        'Device inventory (compliance · last check-in)',
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
        'Tenant dashboard*' {
            $items = Get-IaTuiInventory
            $sum = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Reading device health…' -ScriptBlock {
                Get-IaDeviceSummary -StaleDays 30
            }
            Write-IaTuiHeader -Screen 'Tenant dashboard' -Sub 'device health · assignment posture' -Accent $Accent

            $pctColor = if ($sum.CompliancePercent -ge 90) { $Accent } elseif ($sum.CompliancePercent -ge 75) { 'yellow' } else { 'coral' }
            Write-SpectreHost (
                "[$Accent]Devices  $($sum.DeviceCount)[/]    " +
                "Compliant  [$pctColor]$($sum.CompliancePercent)%[/]    " +
                "[coral]Non-compliant  $($sum.NonCompliantCount)[/]    " +
                "[grey]Other  $($sum.OtherCount)[/]    " +
                "Stale >$($sum.StaleDays)d  $($sum.StaleCount)"
            )
            $assignedCount = @($items | Where-Object { $_.Assignments.Count -gt 0 }).Count
            $byArea = @($items | Group-Object Area | ForEach-Object {
                    [pscustomobject]@{ Area = $_.Name; Total = $_.Count
                        Assigned = @($_.Group | Where-Object { $_.Assignments.Count -gt 0 }).Count }
                })
            Write-SpectreHost (
                "[$Accent]Resources  $(@($items).Count)[/]    " +
                "Assigned  $assignedCount    " +
                "[grey]Unassigned  $(@($items).Count - $assignedCount)[/]"
            )

            if ($sum.ByPlatform) {
                Write-SpectreHost ""
                Write-SpectreHost "[$Accent]Compliance by platform[/]"
                foreach ($p in $sum.ByPlatform) {
                    $w   = [int][math]::Round(($p.CompliantPercent / 100) * 28)
                    $bar = '█' * [math]::Max($w, 0)
                    $bc  = if ($p.CompliantPercent -ge 90) { $Accent } elseif ($p.CompliantPercent -ge 75) { 'yellow' } else { 'coral' }
                    Write-SpectreHost ("[grey]{0,-10}[/] [$bc]{1,-28}[/] {2,3}%  [grey]({3})[/]" -f $p.Platform, $bar, $p.CompliantPercent, $p.Total)
                }
            }
            if ($byArea) {
                Write-SpectreHost ""
                Write-SpectreHost "[$Accent]Assigned by area[/]"
                $max = ($byArea | Measure-Object -Property Assigned -Maximum).Maximum
                foreach ($r in ($byArea | Sort-Object Assigned -Descending)) {
                    $w   = if ($max) { [int][math]::Round(($r.Assigned / $max) * 28) } else { 0 }
                    $bar = '█' * [math]::Max($w, 1)
                    Write-SpectreHost ("[grey]{0,-16}[/] [$Accent]{1}[/] {2}/{3}" -f $r.Area, $bar, $r.Assigned, $r.Total)
                }
            }
        }
        'Device inventory*' {
            $scope = Read-SpectreSelection -Title 'Scope' -Color $Accent -Choices @('All devices', 'Non-compliant only', 'Stale (no sync 30d+)')
            Write-IaTuiHeader -Screen 'Device inventory' -Sub $scope.ToLower() -Accent $Accent
            $rows = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Reading managed devices…' -ScriptBlock {
                switch -Wildcard ($using:scope) {
                    'Non-compliant*' { Get-IntuneDeviceInventory -ComplianceState noncompliant }
                    'Stale*'         { Get-IntuneDeviceInventory -StaleDays 30 }
                    default          { Get-IntuneDeviceInventory }
                }
            }
            if (-not $rows) { Write-SpectreHost '[yellow]No devices match.[/]'; return }
            Write-SpectreHost "[$Accent]$(@($rows).Count)[/] device(s)"
            @($rows) | Select-Object -First 200 | ForEach-Object {
                $cs = "$($_.Compliance)"
                $cc = switch ($cs) { 'compliant' { $Accent } 'noncompliant' { 'coral' } default { 'grey' } }
                $dsc = if ($null -ne $_.DaysSinceSync -and $_.DaysSinceSync -ge 30) { 'coral' }
                       elseif ($null -ne $_.DaysSinceSync -and $_.DaysSinceSync -ge 7) { 'yellow' } else { 'grey' }
                [pscustomobject]@{
                    Device     = $_.Device
                    OS         = "[$Accent]$($_.OS)[/]"
                    Version    = $_.OSVersion
                    Compliance = "[$cc]$cs[/]"
                    Owner      = $_.Owner
                    User       = $_.User
                    'Sync(d)'  = if ($null -ne $_.DaysSinceSync) { "[$dsc]$($_.DaysSinceSync)[/]" } else { '[grey]—[/]' }
                }
            } | Format-IaTable -Color $Accent
            if (@($rows).Count -gt 200) { Write-SpectreHost "[grey]Showing first 200 of $(@($rows).Count) — use Get-IntuneDeviceInventory for the full list.[/]" }
        }
        'App install*' {
            $app = Select-IaInventoryItem -Accent $Accent -Area 'Apps' -Title 'Which app?'
            if (-not $app) { return }
            $by  = Read-SpectreSelection -Title 'Pivot by' -Choices @('Device', 'User') -Color $Accent
            Write-IaTuiHeader -Screen 'App install status' -Sub "app: $($app.Name)  ·  by: $by" -Accent $Accent
            $name = $app.Name
            $rows = Invoke-SpectreCommandWithStatus -Spinner Dots -Title "Querying $name…" -ScriptBlock {
                Get-IntuneAppInstallStatus -App $using:name -By $using:by
            }
            if ($by -eq 'Device') {
                $rows | ForEach-Object {
                    $sc = switch ($_.Status) {
                        'installed'     { $Accent }
                        'failed'        { 'coral'  }
                        'pending'       { 'yellow' }
                        default         { 'grey'   }
                    }
                    [pscustomobject]@{
                        Device      = $_.Device
                        Status      = "[$sc]$($_.Status)[/]"
                        Detail      = $_.Detail
                        ErrorCode   = $_.ErrorCode
                        ErrorReason = $_.ErrorReason
                        User        = $_.User
                    }
                } | Format-IaTable -Color $Accent
                $failHints = @($rows | Where-Object { $_.Hint })
                if ($failHints) {
                    Write-SpectreRule -Title 'Remediation hints' -Color $Accent
                    foreach ($fh in $failHints | Select-Object -First 5) {
                        Write-SpectreHost "[$Accent]$($fh.ErrorCode)[/]  $($fh.ErrorReason)"
                        Write-SpectreHost "  [grey]→ $($fh.Hint)[/]"
                    }
                }
            } else {
                $rows | Format-IaTable -Color $Accent
            }
        }
        'Configuration*' {
            $p = Select-IaInventoryItem -Accent $Accent -Area 'Configuration' -Title 'Which configuration profile?'
            if (-not $p) { return }
            Write-IaTuiHeader -Screen 'Configuration profile status' -Sub "profile: $($p.Name)" -Accent $Accent
            Get-IntuneConfigurationStatus -Profile $p.Name | Format-IaTable -Color $Accent
        }
        'Compliance*' {
            $mode = Read-SpectreSelection -Title 'Compliance by' -Choices @('Tenant summary', 'Policy', 'Device') -Color $Accent
            Write-IaTuiHeader -Screen 'Compliance status' -Sub $mode.ToLower() -Accent $Accent
            $rows = switch -Wildcard ($mode) {
                'Policy'  {
                    $pol = Select-IaInventoryItem -Accent $Accent -Area 'Compliance' -Title 'Which compliance policy?'
                    if ($pol) { Get-IntuneComplianceStatus -Policy $pol.Name }
                }
                'Device'  { Get-IntuneComplianceStatus -Device (Read-SpectreText -Question 'Device name') }
                default   { Get-IntuneComplianceStatus }
            }
            $rows | Format-IaTable -Color $Accent
        }
        'Deployment*' {
            $scope = Read-SpectreSelection -Title 'Scope' -Color $Accent -Choices @('All resources', 'Scope to a group')
            $grp   = $null
            if ($scope -like 'Scope*') { $grp = (Select-IaGroup -Accent $Accent -Title 'Scope to group').DisplayName }
            Write-IaTuiHeader -Screen 'Deployment summary' `
                -Sub "for everything assigned to '$(if ($grp) { $grp } else { 'all resources' })'" -Accent $Accent
            $data = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Rolling up deployment health…' -ScriptBlock {
                if ($using:grp) { Get-IntuneDeploymentSummary -Group $using:grp }
                else { Get-IntuneDeploymentSummary }
            }
            $data | ForEach-Object {
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
            } | Format-IaTable -Color $Accent
            Write-SpectreHost "[grey]FailRate colour-graded — [coral]coral >15%[/] · [yellow]amber >5%[/] · ok otherwise[/]"
        }
        'Audit*' {
            $since = Read-SpectreText -Question 'Since (e.g. 7d, 24h)' -DefaultAnswer '7d'
            $act   = Read-SpectreText -Question 'Activity contains (blank = any)' -DefaultAnswer ''
            Write-IaTuiHeader -Screen 'Audit log' -Sub "since $since$(if ($act) { "  ·  activity: $act" })" -Accent $Accent
            $p = @{ Since = $since }; if ($act) { $p.Activity = $act }
            Get-IntuneAuditLog @p | Select-Object -First 50 | Format-IaTable -Color $Accent
        }
        'Multi Admin*' {
            Write-IaTuiHeader -Screen 'Multi Admin Approval requests' -Accent $Accent
            Get-IntuneApprovalRequest | Format-IaTable -Color $Accent
        }
        'PIM*' {
            Write-IaTuiHeader -Screen 'PIM activations' -Accent $Accent
            Get-IntunePimActivation | Format-IaTable -Color $Accent
        }
        'Run any*' {
            $name = Read-IaSelection -Title 'Pick a report' -Color $Accent `
                -Choices (@(Get-IntuneReportCatalog | ForEach-Object Name) + 'Other (type a name)')
            if ($name -like 'Other*') { $name = Read-SpectreText -Question 'Report name' }
            Write-IaTuiHeader -Screen "Report: $name" -Accent $Accent
            Invoke-SpectreCommandWithStatus -Spinner Dots -Title "Running $name…" -ScriptBlock {
                Export-IntuneReport -Name $using:name
            } | Select-Object -First 100 | Format-IaTable -Color $Accent
        }
        default { return }
    }
}

# ─── backup / restore / drift ─────────────────────────────────────────────────

function Invoke-IaTuiBackup {
    param([string]$Accent)
    $pick = Read-SpectreSelection -Title 'Backup / Restore / Drift' -Color $Accent -PageSize 8 -Choices @(
        'Backup assignments to a file',
        'Backup full config (one file per config)',
        'Restore assignments from a snapshot',
        'Restore full config (from a folder)',
        'Drift — compare current vs a snapshot',
        'Back'
    )
    switch -Wildcard ($pick) {
        'Backup assignments*' {
            $p    = Read-SpectreText -Question 'Save snapshot to' -DefaultAnswer (Get-IaBackupName)
            Write-IaTuiHeader -Screen 'Backup' -Sub "→ $p" -Accent $Accent
            $snap = Backup-IntuneAssignment -Path $p
            Write-SpectreHost "[$Accent]Backed up[/] $($snap.count) resource(s) → $p"
        }
        'Backup full config*' {
            $p = Read-SpectreText -Question 'Backup folder' -DefaultAnswer (Get-IaBackupName -Prefix 'intunetide-config' -Extension '')
            Write-IaTuiHeader -Screen 'Full config backup' -Sub "→ $p (one file per config)" -Accent $Accent
            $res = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Exporting every config…' -ScriptBlock {
                $ProgressPreference = 'SilentlyContinue'
                Backup-IntuneConfig -Path $using:p
            }
            Write-SpectreHost "[$Accent]Backed up[/] $($res.Count) config(s) across $(@($res.Areas).Count) area(s) → $($res.Path)"
            Write-SpectreHost "[grey]Each config is its own JSON, grouped by area, with a manifest.json index.[/]"
        }
        'Drift*' {
            $latest = Find-IaLatestBackup
            $p = if ($latest) { Read-SpectreText -Question 'Snapshot file to compare against' -DefaultAnswer $latest }
                 else { Read-SpectreText -Question 'Snapshot file to compare against' }
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
            } | Format-IaTable -Color $Accent
            Write-SpectreHost "[grey]Added = [$Accent]sea-green[/]  ·  Removed = [coral]coral[/]  ·  use Restore to revert[/]"
        }
        'Restore assignments*' {
            $latest = Find-IaLatestBackup
            $p    = if ($latest) { Read-SpectreText -Question 'Snapshot file to restore' -DefaultAnswer $latest }
                    else { Read-SpectreText -Question 'Snapshot file to restore' }
            $mode = Read-SpectreSelection -Title 'Restore mode' -Color $Accent -Choices @('Preview only (no changes)', 'Apply now')
            Write-IaTuiHeader -Screen 'Restore' -Sub "snapshot: $p" -Accent $Accent
            $plans = if ($mode -like 'Apply*') { Restore-IntuneAssignment -Path $p -Confirm:$false }
                     else { Restore-IntuneAssignment -Path $p -WhatIf }
            Show-IaRestorePlan -Plans $plans -Accent $Accent
            if ($mode -like 'Apply*') { $script:IaTuiInventory = $null }
        }
        'Restore full config*' {
            $dir = Find-IaLatestConfigBackup
            $p   = if ($dir) { Read-SpectreText -Question 'Backup folder to restore' -DefaultAnswer $dir }
                   else { Read-SpectreText -Question 'Backup folder to restore' }
            $mode = Read-SpectreSelection -Title 'Restore mode' -Color $Accent -Choices @('Preview only (no changes)', 'Apply now')
            $create = Read-SpectreSelection -Title 'Re-create configs that were deleted?' -Color $Accent `
                -Choices @('Update existing only', 'Also create missing (where supported)')
            $createMissing = $create -like 'Also create*'
            Write-IaTuiHeader -Screen 'Full config restore' -Sub "folder: $p" -Accent $Accent
            $apply = $mode -like 'Apply*'
            $plans = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Restoring configs…' -ScriptBlock {
                if ($using:apply) { Restore-IntuneConfig -Path $using:p -CreateMissing:$using:createMissing -Confirm:$false }
                else { Restore-IntuneConfig -Path $using:p -CreateMissing:$using:createMissing -WhatIf }
            }
            Show-IaRestorePlan -Plans $plans -Accent $Accent
            if (-not $apply) { Write-SpectreHost "[grey]Preview only — re-run and choose 'Apply now' to write.[/]" }
            if ($apply) { $script:IaTuiInventory = $null }
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

# ─── Windows 365 / Cloud PC ───────────────────────────────────────────────────

function Invoke-IaTuiCloudPC {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Windows 365 Cloud PCs' -Sub 'browse · actions · policies · connections' -Accent $Accent
    $pick = Read-SpectreSelection -Title 'Windows 365' -Color $Accent -PageSize 12 -Choices @(
        'Browse Cloud PCs',
        'Cloud PC actions',
        'Provisioning policies',
        'Network connections',
        'User settings',
        'Images (gallery · custom)',
        'Service plans (available SKUs)',
        'Snapshots',
        'Reports',
        'Back'
    )
    switch -Wildcard ($pick) {
        'Browse*' {
            Write-IaTuiHeader -Screen 'Cloud PCs' -Accent $Accent
            $pcs = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Loading Cloud PCs…' -ScriptBlock {
                Get-IntuneCloudPC
            }
            if (-not $pcs) { Write-SpectreHost '[grey]No Cloud PCs found.[/]'; return }
            $pcs | ForEach-Object {
                [pscustomobject]@{
                    'Cloud PC'   = $_.CloudPC
                    Status       = Format-IaCloudPCStatus -Status $_.Status -Accent $Accent
                    User         = $_.User
                    'Plan'       = $_.ServicePlan
                    Policy       = $_.ProvisioningPolicy
                    LastLogin    = if ($_.LastLogin) { ([datetime]$_.LastLogin).ToString('yyyy-MM-dd HH:mm') } else { '—' }
                    GracePeriod  = if ($_.GracePeriodEnd) { ([datetime]$_.GracePeriodEnd).ToString('yyyy-MM-dd') } else { '—' }
                }
            } | Format-IaTable -Color $Accent
        }
        'Cloud PC actions*' {
            $pcs = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Loading Cloud PCs…' -ScriptBlock { Get-IntuneCloudPC }
            if (-not $pcs) { Write-SpectreHost '[grey]No Cloud PCs found.[/]'; return }
            $pcNames = @($pcs | ForEach-Object { $_.CloudPC })
            $pcName = Read-SpectreSelection -Title 'Select Cloud PC' -Choices $pcNames -Color $Accent
            $action = Read-SpectreSelection -Title 'Select action' -Color $Accent -Choices @(
                'Restart', 'Reprovision', 'Troubleshoot', 'EndGracePeriod',
                'CreateSnapshot', 'Resize', 'Rename', 'Restore', 'PowerOn', 'PowerOff'
            )
            $extraParams = @{}
            switch ($action) {
                'Resize' {
                    $plans = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Loading service plans…' -ScriptBlock { Get-IntuneCloudPCServicePlan }
                    $planChoice = Read-SpectreSelection -Title 'Target service plan' -Color $Accent `
                        -Choices @($plans | ForEach-Object { "$($_.vCPU)vCPU / $($_.RAM)GB RAM / $($_.Storage)GB  —  $($_.Name)" })
                    $planIndex  = @($plans | ForEach-Object { "$($_.vCPU)vCPU / $($_.RAM)GB RAM / $($_.Storage)GB  —  $($_.Name)" }).IndexOf($planChoice)
                    $extraParams.ServicePlanId = $plans[$planIndex].Id
                }
                'Rename' {
                    $extraParams.NewName = Read-SpectreText -Question 'New display name'
                }
                'Restore' {
                    $snaps = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Loading snapshots…' -ScriptBlock {
                        Get-IntuneCloudPCSnapshot -CloudPC $using:pcName
                    }
                    if (-not $snaps) { Write-SpectreHost '[yellow]No snapshots found for this Cloud PC.[/]'; return }
                    $snapChoice = Read-SpectreSelection -Title 'Restore from snapshot' -Color $Accent `
                        -Choices @($snaps | ForEach-Object { "$($_.CreatedAt)  ($($_.SnapshotType))" })
                    $snapIndex  = @($snaps | ForEach-Object { "$($_.CreatedAt)  ($($_.SnapshotType))" }).IndexOf($snapChoice)
                    $extraParams.SnapshotId = $snaps[$snapIndex].Id
                }
            }
            Write-IaTuiHeader -Screen "Cloud PC action: $action" -Sub $pcName -Accent $Accent
            $result = Invoke-IntuneCloudPCAction -CloudPC $pcName -Action $action @extraParams -Confirm:$false
            if ($result.Submitted) {
                Write-SpectreHost "[$Accent]Submitted.[/] Action '$action' is queued for [$Accent]$pcName[/]."
            }
        }
        'Provisioning policies*' {
            Write-IaTuiHeader -Screen 'Provisioning Policies' -Accent $Accent
            $sub = Read-SpectreSelection -Title 'Provisioning policies' -Color $Accent -Choices @(
                'List all', 'Create new', 'Delete', 'Back'
            )
            switch -Wildcard ($sub) {
                'List*' {
                    $pols = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Loading…' -ScriptBlock {
                        Get-IntuneCloudPCProvisioningPolicy -IncludeAssignments
                    }
                    $pols | Select-Object Name, JoinType, ImageType, ImageName, Region, Id | Format-IaTable -Color $Accent
                }
                'Create*' {
                    $name  = Read-SpectreText -Question 'Policy name'
                    $imgs  = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Loading images…' -ScriptBlock { Get-IntuneCloudPCImage }
                    $imgC  = Read-SpectreSelection -Title 'OS image' -Color $Accent `
                        -Choices @($imgs | ForEach-Object { "$($_.Type): $($_.Name)  [$($_.OS)]" })
                    $imgIdx= @($imgs | ForEach-Object { "$($_.Type): $($_.Name)  [$($_.OS)]" }).IndexOf($imgC)
                    $img   = $imgs[$imgIdx]
                    $join  = Read-SpectreSelection -Title 'Azure AD join type' -Color $Accent `
                        -Choices @('azureADJoin', 'hybridAzureADJoin')
                    Write-IaTuiHeader -Screen 'Create provisioning policy' -Sub $name -Accent $Accent
                    New-IntuneCloudPCProvisioningPolicy -Name $name -ImageId $img.Id `
                        -ImageType ($img.Type.ToLower()) -DomainJoinType $join -WhatIf
                    if ((Read-SpectreSelection -Title 'Apply?' -Choices @('Yes','No') -Color $Accent) -eq 'Yes') {
                        New-IntuneCloudPCProvisioningPolicy -Name $name -ImageId $img.Id `
                            -ImageType ($img.Type.ToLower()) -DomainJoinType $join -Confirm:$false
                        Write-SpectreHost "[$Accent]Policy created.[/]"
                    }
                }
                'Delete*' {
                    $pols = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Loading…' -ScriptBlock { Get-IntuneCloudPCProvisioningPolicy }
                    $polC = Read-SpectreSelection -Title 'Policy to delete' -Color $Accent `
                        -Choices @($pols | ForEach-Object { $_.Name })
                    Remove-IntuneCloudPCProvisioningPolicy -Policy $polC -Confirm:$false
                    Write-SpectreHost "[$Accent]Deleted[/] $polC"
                }
            }
        }
        'Network connections*' {
            Write-IaTuiHeader -Screen 'Network Connections' -Accent $Accent
            $sub = Read-SpectreSelection -Title 'Network connections' -Color $Accent -Choices @(
                'List all', 'Run health check', 'Back'
            )
            switch -Wildcard ($sub) {
                'List*' {
                    $conns = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Loading…' -ScriptBlock { Get-IntuneCloudPCConnection }
                    $conns | ForEach-Object {
                        $hc = switch ($_.HealthStatus) {
                            'passed'  { "[$Accent]passed[/]" }
                            'failed'  { '[coral]failed[/]' }
                            'warning' { '[yellow]warning[/]' }
                            default   { "[grey]$($_.HealthStatus)[/]" }
                        }
                        [pscustomobject]@{
                            Name        = $_.Name
                            Health      = $hc
                            Type        = $_.Type
                            DomainName  = $_.DomainName
                            Region      = $_.Region
                            Id          = $_.Id
                        }
                    } | Format-IaTable -Color $Accent
                }
                'Run*' {
                    $conns = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Loading…' -ScriptBlock { Get-IntuneCloudPCConnection }
                    $connC = Read-SpectreSelection -Title 'Select connection' -Color $Accent `
                        -Choices @($conns | ForEach-Object { $_.Name })
                    Test-IntuneCloudPCConnection -Connection $connC
                    Write-SpectreHost "[$Accent]Health check triggered.[/] Check connection status in a few minutes."
                }
            }
        }
        'User settings*' {
            Write-IaTuiHeader -Screen 'Cloud PC User Settings' -Accent $Accent
            Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Loading…' -ScriptBlock {
                Get-IntuneCloudPCUserSetting
            } | Format-IaTable -Color $Accent
        }
        'Images*' {
            Write-IaTuiHeader -Screen 'Cloud PC Images' -Sub 'gallery · custom' -Accent $Accent
            $type = Read-SpectreSelection -Title 'Image type' -Choices @('All','Gallery','Custom') -Color $Accent
            Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Loading images…' -ScriptBlock {
                Get-IntuneCloudPCImage -Type $using:type
            } | Format-IaTable -Color $Accent
        }
        'Service plans*' {
            Write-IaTuiHeader -Screen 'Cloud PC Service Plans' -Accent $Accent
            Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Loading…' -ScriptBlock {
                Get-IntuneCloudPCServicePlan
            } | Sort-Object vCPU, RAM | Format-IaTable -Color $Accent
        }
        'Snapshots*' {
            Write-IaTuiHeader -Screen 'Cloud PC Snapshots' -Accent $Accent
            $pcs   = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Loading Cloud PCs…' -ScriptBlock { Get-IntuneCloudPC }
            $scope = Read-SpectreSelection -Title 'Scope' -Color $Accent -Choices (@('All Cloud PCs') + @($pcs | ForEach-Object { $_.CloudPC }))
            $snaps = Invoke-SpectreCommandWithStatus -Spinner Dots -Title 'Loading snapshots…' -ScriptBlock {
                if ($using:scope -eq 'All Cloud PCs') { Get-IntuneCloudPCSnapshot }
                else { Get-IntuneCloudPCSnapshot -CloudPC $using:scope }
            }
            $snaps | Format-IaTable -Color $Accent
        }
        'Reports*' {
            Write-IaTuiHeader -Screen 'Cloud PC Reports' -Accent $Accent
            $rpt = Read-SpectreSelection -Title 'Report' -Color $Accent -Choices @(
                'Remote connections', 'Daily aggregate', 'Connection quality', 'Shared PC overview'
            )
            $rptName = switch -Wildcard ($rpt) {
                'Remote*'     { 'RemoteConnection' }
                'Daily*'      { 'DailyAggregate' }
                'Connection*' { 'ConnectionQuality' }
                'Shared*'     { 'SharedPCOverview' }
            }
            Invoke-SpectreCommandWithStatus -Spinner Dots -Title "Running $rpt report…" -ScriptBlock {
                Get-IntuneCloudPCReport -Report $using:rptName
            } | Select-Object -First 100 | Format-IaTable -Color $Accent
        }
        default { return }
    }
}
