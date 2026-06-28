function Start-IntuneTide {
    <#
    .SYNOPSIS
        Launch the interactive retro ANSI TUI.
    .DESCRIPTION
        A keyboard-driven terminal UI: browse assignments, reverse-lookup a
        group, compare two groups, run what-if for a user/device, and — the
        headline — MIRROR a group's assignments onto another with a multi-select
        checklist so you choose exactly which ones (e.g. config profiles but not
        endpoint security). Cross-platform; rendered by a self-contained ANSI
        engine (Private/Tui.ps1) — no external TUI module required.

        Entity pickers (groups, apps, profiles, policies) are arrow-key
        selection lists, not free-text fields — pick from what's there instead
        of typing names that might 404.
    .EXAMPLE
        Connect-IntuneTide -UseDeviceCode; Start-IntuneTide
    #>
    [CmdletBinding()]
    param([ValidateSet('green', 'amber', 'lego', 'deepsea', 'sunset', 'ocean', 'forest', 'mono')][string]$Theme = 'deepsea')

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw "The TIDE TUI requires PowerShell 7+ (you are on $($PSVersionTable.PSVersion))."
    }
    if (-not (Get-MgContext)) {
        Write-IaHost "[yellow]Not connected.[/] Starting device-code sign-in…"
        Connect-IntuneTide -UseDeviceCode | Out-Null
    }

    $accent = switch ($Theme) {
        'amber'  { 'orange1' }
        'lego'   { 'yellow' }
        'deepsea'{ 'turquoise2' }
        'sunset' { 'coral' }
        'ocean'  { 'deepskyblue1' }
        'forest' { 'lime' }
        'mono'   { 'silver' }
        default  { 'green' }
    }
    $script:IaTuiInventory = $null
    $script:IaCaps         = @{}     # cmdlet/param capability cache

    function Get-IaTuiInventory {
        if ($null -eq $script:IaTuiInventory) {
            $script:IaTuiInventory = Invoke-IaStatus -Spinner Dots -Title 'Reading Intune assignments…' -ScriptBlock {
                Get-IaInventory
            }
        }
        $script:IaTuiInventory
    }

    $ctx  = Get-MgContext
    $elev = try { if (Test-IaPrivileged) { "[green]● elevated[/]" } else { "[yellow]○ not elevated[/]" } } catch { '' }
    $script:IaTuiAccount = $ctx.Account
    $script:IaTuiElev    = $elev

    # The main menu is a full-screen redraw, so its banner is passed as a -Header that
    # is repainted with every frame (rather than printed above it, where the redraw
    # would erase it).
    $splashHeader = @(
        (Get-IaFigletString -Text 'TIDE' -Color $accent)
        (ConvertFrom-IaMarkup "[$accent]●[/] $($ctx.Account)  ·  tenant [grey]$(Format-IaMaskedId $ctx.TenantId)[/]  ·  $elev")
        (ConvertFrom-IaMarkup "[$accent]≈ targeted intune deployment & endpoints[/]")
        ''
    ) -join "`n"

    function Show-IaTuiSplash {
        Clear-IaHost
        Write-IaFiglet -Text 'TIDE' -Color $accent
        Write-IaHost "[$accent]●[/] $($ctx.Account)  ·  tenant [grey]$(Format-IaMaskedId $ctx.TenantId)[/]  ·  $elev"
        Write-IaRule -Title 'TIDE · targeted intune deployment & endpoints' -Color $accent
    }

    Show-IaTuiSplash
    # One-time inventory load: stream the live Graph calls as they happen (Tide logs
    # every Invoke-MgGraphRequest via Add-IaCall), then wipe to a clean workspace so
    # each screen renders as a tidy bordered table instead of below a wall of GET lines.
    if ($null -eq $script:IaTuiInventory) {
        Write-IaHost "[grey]Loading Intune assignments — live Graph activity:[/]"
        Set-IaCallSink {
            param($e)
            $sc = if ($e.Status -ge 400 -or $e.Status -eq 0 -or $e.Error) { 'coral' } else { 'green' }
            Write-IaHost ("  [grey]{0,-5}[/] {1} [grey]·[/] [{2}]{3}[/] [grey]· {4}ms · {5} items[/]" -f $e.Method, (Protect-IaMarkup ([string]$e.Uri)), $sc, $e.Status, $e.Ms, $e.Count)
        }
        try { $script:IaTuiInventory = Get-IaInventory } finally { Set-IaCallSink $null }
    }

    while ($true) {
        $choice = Read-IaMenu -Title "Choose an action" -Header $splashHeader -Color $accent -PageSize 16 -ShowGraphFooter -Choices @(
            'View all assignments',
            'Group lookup (what is a group assigned to)',
            'Compare two groups',
            'What-if (user / device effective assignments)',
            'Mirror assignments (copy A -> B, pick which)',
            'Assign a group to many (pick which)',
            'Templates (capture / apply)',
            'Backup / Restore / Drift',
            'Policies (configuration · compliance · scripts · remediations)',
            'Reports (status · audit · approvals)',
            'Windows 365 (Cloud PCs · provisioning · connections)',
            'Apps (list · assign · Win32 details)',
            'Windows Update (rings · feature · driver)',
            'Autopilot & enrollment (devices · profiles · restrictions)',
            'Security baselines',
            'Elevate (PIM) — activate an eligible role',
            'Audit',
            'Export report (HTML · Excel · Rich HTML)',
            'Graph calls (live activity log)',
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
                'Policies*'       { Invoke-IaTuiPolicies    -Accent $accent }
                'Reports*'        { Invoke-IaTuiReports     -Accent $accent }
                'Windows 365*'    { Invoke-IaTuiCloudPC     -Accent $accent }
                'Apps*'           { Invoke-IaTuiApps        -Accent $accent }
                'Windows Update*' { Invoke-IaTuiWindowsUpdate -Accent $accent }
                'Autopilot*'      { Invoke-IaTuiAutopilot   -Accent $accent }
                'Security base*'  { Invoke-IaTuiSecurityBaselines -Accent $accent }
                'Elevate*'        { Invoke-IaTuiElevate     -Accent $accent }
                'Audit'           { Invoke-IaTuiAudit       -Accent $accent }
                'Export*'         { Invoke-IaTuiExport      -Accent $accent }
                'Graph calls*'    { Invoke-IaTuiGraphCalls  -Accent $accent }
                'Refresh*'        { $script:IaTuiInventory = $null; Get-IaTuiInventory | Out-Null
                                    Write-IaHost "[$accent]Refreshed.[/]" }
                'Quit'            { try { $host.UI.RawUI.WindowTitle = 'pwsh' } catch { }; return }
            }
        } catch {
            Write-IaHost "[red]Error:[/] $($_.Exception.Message)"
        }
        if ($choice -ne 'Quit' -and $choice -notlike 'View all*') {
            # 'View all' is self-paced by its interactive table (own q/Esc exit), so
            # it skips the trailing pause to avoid a redundant "press any key".
            Read-IaPause | Out-Null
            # No splash here: the next Read-IaMenu repaints the banner via -Header.
        }
    }
}

# ─── table & selection wrappers (over the ANSI engine in Private/Tui.ps1) ─────
# These keep the call-sites below terse. The engine itself never throws on
# unrecognised markup, so no capability probing or markup-stripping is needed.

function Format-IaTable {
    # Render objects as a bordered, markup-aware table. Accepts -Data (array) or
    # pipeline input; -Accent/-Color set the border colour; -Title shows in the rule.
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)][object]$InputObject,
        [object[]]$Data,
        [string]$Color,
        [string]$Accent,
        [string]$Title
    )
    begin { $rows = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($i in @($InputObject)) { if ($null -ne $i) { $rows.Add($i) } } }
    end {
        if ($Data) { foreach ($i in @($Data)) { if ($null -ne $i) { $rows.Add($i) } } }
        if ($rows.Count -eq 0) { return }
        $col = if ($Accent) { $Accent } elseif ($Color) { $Color } else { 'grey' }
        Show-IaTableObjects -Rows $rows.ToArray() -Color $col -Title $Title
    }
}

function Read-IaSelection {
    # Single-select menu wrapper. Returns the chosen string (or $null).
    param([string]$Title, [object[]]$Choices, [string]$Color, [int]$PageSize = 0)
    $list = @($Choices)
    if ($list.Count -eq 0) { return $null }
    $col = if ($Color) { $Color } else { 'grey' }
    $ps  = if ($PageSize -gt 0) { $PageSize } elseif ($list.Count -gt 15) { 15 } else { $list.Count }
    Read-IaMenu -Title $Title -Choices $list -Color $col -PageSize $ps
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
        $groups = Invoke-IaStatus -Spinner Dots -Title 'Loading groups…' -ScriptBlock {
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
    if (-not $items) { Write-IaHost "[yellow]No $Area resources found.[/]"; return $null }
    $pick = Read-IaSelection -Title $Title -Choices (@($items | ForEach-Object Name)) -Color $Accent
    $items | Where-Object Name -eq $pick | Select-Object -First 1
}

# ─── shared header ────────────────────────────────────────────────────────────

function Write-IaTuiHeader {
    param([string]$Screen, [string]$Sub = '', [string]$Accent)
    Clear-IaHost
    try { $host.UI.RawUI.WindowTitle = "TIDE — $Screen" } catch { }
    Write-IaHost "[$Accent]≈ TIDE[/]  [bold]· $Screen[/]"
    if ($Sub) {
        Write-IaHost "[grey]$Sub[/]"
    } elseif ($script:IaTuiAccount) {
        Write-IaHost "[grey]● $($script:IaTuiAccount)  ·  [/]$script:IaTuiElev"
    }
    Write-IaRule -Color darkslategray1
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
    if (-not $rows) { Write-IaHost '[yellow]Nothing to restore.[/]'; return }
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
    # Scrollable / searchable / exportable — handles a 500-resource tenant instead
    # of dumping every row at once. (↑/↓/PgUp/PgDn · / search · e export · q back)
    Read-IaTablePause -Data $rows -Stem 'assignments-all' -Color $Accent -Title 'View all assignments'
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
    Write-IaHost "[$Accent]$($g.DisplayName)[/] is assigned to [$Accent]$(@($hits).Count)[/] resource(s)"
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

    if (-not $rows) { Write-IaHost '[yellow]No assignments differ between these groups.[/]'; return }

    $displayRows = @($rows | ForEach-Object {
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
    })

    $conflicts = @($rows | Where-Object Relationship -eq 'Conflict').Count
    # Scrollable comparison (e exports here too); the explicit menu below adds HTML / custom path.
    $cmpTitle = if ($conflicts) { "Group comparison · $conflicts conflict(s) — include vs exclude clash" } else { 'Group comparison' }
    Read-IaTablePause -Data $displayRows -Title $cmpTitle -Stem 'group-diff' -Color $Accent

    $export = Read-IaMenu -Title 'Export comparison?' -Color $Accent -Choices @('Skip', 'CSV', 'Excel', 'HTML')
    if ($export -eq 'Skip') { return }

    $ext  = switch ($export) { 'Excel' { 'xlsx' } 'HTML' { 'html' } default { 'csv' } }
    $path = Read-IaSavePath -Prompt 'Save comparison as' -DefaultName "group-diff.$ext"
    if (-not $path) { return }   # cancelled

    switch ($export) {
        'CSV'   { $rows | Export-Csv -Path $path -NoTypeInformation -Encoding utf8 }
        'Excel' { $rows | Export-IntuneExcel -Path $path -WorksheetName 'Comparison' `
                      -Title "Group diff: $($a.DisplayName) vs $($b.DisplayName)" }
        'HTML'  { New-IaGroupComparisonHtml -Rows $rows -GroupA $a.DisplayName -GroupB $b.DisplayName |
                      Set-Content -Path $path -Encoding utf8 }
    }
    Write-IaHost "[$Accent]Wrote[/] $path"
}

# ─── what-if ──────────────────────────────────────────────────────────────────

function Invoke-IaTuiWhatIf {
    param([string]$Accent)
    $kind = Read-IaMenu -Title 'Subject type' -Choices @('user', 'device') -Color $Accent
    $val  = Read-IaText -Question "$kind (UPN/name or id)"
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
    if (-not $cands) { Write-IaHost "[yellow]$($src.DisplayName) has no assignments to mirror.[/]"; return }

    $map = @{}; $i = 0
    $labels = foreach ($c in $cands) { $i++; $lbl = "$i. ($($c.Area)) $($c.Name)"; $map[$lbl] = $c.Id; $lbl }
    $picked = Read-IaMultiMenu -Title "Select what to mirror from [$Accent]$($src.DisplayName)[/]" `
        -Choices $labels -Color $Accent
    if (-not $picked) { Write-IaHost '[yellow]Nothing selected.[/]'; return }
    $ids = @($picked | ForEach-Object { $map[$_] })

    $dst = Select-IaGroup -Accent $Accent -Title 'Destination group (copy TO)'
    Write-IaTuiHeader -Screen 'Mirror assignments' -Sub "from $($src.DisplayName)  →  $($dst.DisplayName)" -Accent $Accent
    $confirm = Read-IaMenu `
        -Title "Apply $($ids.Count) assignment(s) to [$Accent]$($dst.DisplayName)[/]?" `
        -Choices @('Preview only (no changes)', 'Apply now') -Color $Accent
    $commit  = $confirm -eq 'Apply now'

    $plans = Invoke-IaCopy -Items $items -SrcId $src.Id -DstId $dst.Id -DstName $dst.DisplayName `
        -IncludeIds $ids -Commit:$commit
    if (-not $plans) { Write-IaHost '[yellow]Nothing to change (already assigned?).[/]'; return }
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
    if (-not $commit) { Write-IaHost "[grey]Preview only — re-run and choose 'Apply now' to write.[/]" }
}

# ─── audit ────────────────────────────────────────────────────────────────────

function Invoke-IaTuiAudit {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Audit' -Sub 'tenant-wide assignment health' -Accent $Accent
    $a = Invoke-IaStatus -Spinner Dots -Title 'Auditing…' -ScriptBlock {
        Get-IntuneAssignmentAudit
    }
    Write-IaHost (
        "[$Accent]Resources scanned  $($a.ResourceCount)[/]   " +
        "[$Accent]Assigned  $($a.AssignedCount)[/]   " +
        "[grey]Unassigned  $($a.UnassignedCount)[/]   " +
        "Assignment edges  $($a.EdgeCount)   " +
        "Exclusions  $($a.ExclusionCount)"
    )
    Write-IaHost ""
    $a.ByArea | ForEach-Object {
        [pscustomobject]@{ Area = "[$Accent]$($_.Area)[/]"; Total = $_.Total; Assigned = $_.Assigned }
    } | Format-IaTable -Color $Accent

    if ($a.ByArea) {
        Write-IaHost ""
        Write-IaHost "[$Accent]Assigned by area[/]"
        $max = ($a.ByArea | Measure-Object -Property Assigned -Maximum).Maximum
        foreach ($r in ($a.ByArea | Sort-Object Assigned -Descending)) {
            $w   = if ($max) { [int][math]::Round(($r.Assigned / $max) * 32) } else { 0 }
            $bar = '█' * [math]::Max($w, 1)
            Write-IaHost ("[grey]{0,-16}[/] [$Accent]{1}[/] {2}" -f $r.Area, $bar, $r.Assigned)
        }
    }

    if ($a.TopGroups) {
        Write-IaHost ""
        Write-IaHost "[$Accent]Most-assigned groups[/]"
        $a.TopGroups | Format-IaTable -Color $Accent
    }
}

# ─── graph activity log ───────────────────────────────────────────────────────

function Invoke-IaTuiGraphCalls {
    param([string]$Accent)
    # Prepare ALL data BEFORE rendering anything. A processing delay between the
    # header and the first table row lets the host drop the just-drawn header, so
    # the clear → header → table sequence must run with no gap in between.
    # (Assign first: the , @(...) return makes direct assignment the correct array;
    # wrapping the CALL in @() would collapse it to one nested element.)
    $entries = Get-IaCallLogEntries
    $entries = @($entries)
    $hasEntries = $entries.Count -gt 0
    if ($hasEntries) {
        $show = @($entries | Select-Object -Last 24)
        $rows = foreach ($e in $show) {
            $sc = if ($e.Status -ge 400 -or $e.Status -eq 0 -or $e.Error) { 'coral' } else { $Accent }
            [pscustomobject]@{
                Time   = $e.Time.ToString('HH:mm:ss')
                Method = $e.Method
                Uri    = $e.Uri
                Status = "[$sc]$($e.Status)[/]"
                Ms     = $e.Ms
                Items  = $e.Count
            }
        }
        $errs = @($entries | Where-Object { $_.Status -ge 400 -or $_.Status -eq 0 -or $_.Error }).Count
        $shownNote = if ($entries.Count -gt $show.Count) { " (showing last $($show.Count))" } else { '' }
        $footer = "[grey]$($entries.Count) call(s) in the live log$shownNote · [/][$Accent]$($entries.Count - $errs) ok[/][grey] · [/][coral]$errs error(s)[/]"
    }
    # ---- render (no data work past this point) ----
    Write-IaTuiHeader -Screen 'Graph activity log' -Sub 'recent Microsoft Graph calls (newest last)' -Accent $Accent
    if (-not $hasEntries) { Write-IaHost '[yellow]No Graph calls recorded yet.[/]'; return }
    $rows | Format-IaTable -Color $Accent
    Write-IaHost $footer
}

# ─── bulk assign ──────────────────────────────────────────────────────────────

function Invoke-IaTuiBulkAssign {
    param([string]$Accent)
    $g     = Select-IaGroup -Accent $Accent -Title 'Group to assign'
    $areas = @('All areas') + (@(Get-IaResourceRegistry | ForEach-Object Area | Select-Object -Unique | Sort-Object))
    $area  = Read-IaSelection -Title 'Which area?' -Choices $areas -Color $Accent

    $items  = Get-IaTuiInventory
    $scoped = if ($area -eq 'All areas') { $items } else { @($items | Where-Object Area -eq $area) }
    if (-not $scoped) { Write-IaHost "[yellow]No resources in $area.[/]"; return }

    $intent = $null
    if ($area -eq 'Apps' -or ($scoped | Where-Object { (Find-IaResourceType -Key $_.ResourceType).HasIntent })) {
        $intent = Read-IaMenu -Title 'Install intent (apps)' -Color $Accent `
            -Choices @('required', 'available', 'uninstall', 'availableWithoutEnrollment', '(none / non-app)')
        if ($intent -eq '(none / non-app)') { $intent = $null }
    }
    $modeChoice = Read-IaMenu -Title 'Assignment mode' -Choices @('include', 'exclude (block)') -Color $Accent
    $exclude    = $modeChoice -like 'exclude*'

    $filterId = $null; $filterType = 'include'
    $filters  = Get-IaFilterList
    if ($filters) {
        $fchoice = Read-IaSelection -Title 'Assignment filter' -Color $Accent `
            -Choices (@('(no filter)') + @($filters | ForEach-Object Name))
        if ($fchoice -ne '(no filter)') {
            $filterId   = ($filters | Where-Object Name -eq $fchoice | Select-Object -First 1).Id
            $filterType = Read-IaMenu -Title "Filter mode for '$fchoice'" -Choices @('include', 'exclude') -Color $Accent
        }
    }

    $map  = @{}; $i = 0
    $labels = foreach ($it in ($scoped | Sort-Object Area, Name)) {
        $i++; $lbl = "$i. ($($it.Area)) $($it.Name)"; $map[$lbl] = $it; $lbl
    }

    $subTitle = if ($intent) { "group: $($g.DisplayName)  ·  area: $area  ·  intent: $intent" } `
                else          { "group: $($g.DisplayName)  ·  area: $area" }
    Write-IaTuiHeader -Screen 'Assign a group to many' -Sub $subTitle -Accent $Accent

    $picked = Read-IaMultiMenu -Title "Select resources to assign [$Accent]$($g.DisplayName)[/]" `
        -Choices $labels -Color $Accent -PageSize 18
    if (-not $picked) { Write-IaHost '[yellow]Nothing selected.[/]'; return }
    $sel = @($picked | ForEach-Object { $map[$_] })

    $verb    = if ($exclude) { 'EXCLUDE' } else { 'assign' }
    $confirm = Read-IaMenu -Color $Accent `
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
    else { Write-IaHost "[grey]Preview only — choose 'Apply now' to write.[/]" }
}

# ─── templates ────────────────────────────────────────────────────────────────

function Invoke-IaTuiTemplates {
    param([string]$Accent)
    $action = Read-IaMenu -Title 'Templates' -Color $Accent -Choices @(
        'Capture a group as a template (save to file)',
        'Apply a template file to a group'
    )
    if ($action -like 'Capture*') {
        $g    = Select-IaGroup -Accent $Accent -Title 'Group to capture'
        $name = Read-IaText -Question 'Template name' -DefaultAnswer 'baseline'
        $path = Read-IaText -Question 'Save to path' -DefaultAnswer "$name.json"
        Write-IaTuiHeader -Screen 'Templates · capture' -Sub "group: $($g.DisplayName)" -Accent $Accent
        $tmpl = New-IaTemplateFromGroup -Items (Get-IaTuiInventory) -GroupId $g.Id -Name $name
        $tmpl | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding utf8
        Write-IaHost "[$Accent]Saved[/] template '$name' with [$Accent]$($tmpl.resources.Count)[/] resource(s) → $path"
    } else {
        $path = Read-IaText -Question 'Template file path'
        if (-not (Test-Path $path)) { Write-IaHost "[red]Not found:[/] $path"; return }
        $tmpl = Get-Content $path -Raw | ConvertFrom-Json
        $g    = Select-IaGroup -Accent $Accent -Title 'Device group to stamp on'
        Write-IaTuiHeader -Screen 'Templates · apply' -Sub "template: $($tmpl.name)  ·  target: $($g.DisplayName)" -Accent $Accent
        $keys  = @($tmpl.resources | ForEach-Object resource_type | Select-Object -Unique)
        $items = Get-IaInventory -Type $keys
        $confirm = Read-IaMenu -Color $Accent `
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
        Write-IaHost '[yellow]You have no PIM-eligible roles to activate (or this is an app-only sign-in).[/]'
        $active = Get-IntuneActiveRole
        if ($active) { Write-IaHost 'Currently active:'; $active | Format-IaTable -Color $Accent }
        return
    }
    $role    = Read-IaSelection -Title 'Activate which eligible role?' -Color $Accent `
        -Choices @($eligible | ForEach-Object Role)
    $just    = Read-IaText -Question 'Justification'
    $dur     = Read-IaText -Question 'Duration (e.g. 2h, 30m, 8h)' -DefaultAnswer '2h'
    $confirm = Read-IaMenu -Title "Activate [$Accent]$role[/] for $dur?" `
        -Choices @('Yes, activate now', 'Cancel') -Color $Accent
    if ($confirm -notlike 'Yes*') { Write-IaHost '[grey]Cancelled.[/]'; return }

    $res = Enable-IntuneAdminRole -Role $role -Justification $just -Duration $dur -Confirm:$false
    Write-IaHost "[$Accent]$($res.Role)[/] → status [$Accent]$($res.Status)[/] (expires after $($res.Duration))"
    if ($res.Status -in 'PendingApproval', 'PendingProvisioning') {
        Write-IaHost '[yellow]Activation needs approval / is provisioning — re-check with Get-IntuneActiveRole.[/]'
    }
    Get-IntuneActiveRole | Format-IaTable -Color $Accent
}

# ─── apps submenu ─────────────────────────────────────────────────────────────
function Invoke-IaTuiApps {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Apps' -Sub 'list · assign · Win32 details' -Accent $Accent

    while ($true) {
        $pick = Read-IaMenu -Title 'Apps' -Color $Accent -PageSize 10 -Choices @(
            'List all apps',
            'Filter by type (Win32 / Store / iOS / Android / macOS)',
            'Win32 app details (detection · requirements · return codes)',
            'Assign app to groups',
            'Back'
        )
        switch -Wildcard ($pick) {
            'List all*' {
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading apps…' -Color $Accent -ScriptBlock {
                    $script:_apps = @(Get-IntuneApp)
                }
                if (-not $script:_apps) { Write-IaHost "[yellow]No apps found.[/]"; Read-IaPause | Out-Null; break }
                $rows = @($script:_apps | ForEach-Object {
                    [pscustomobject][ordered]@{ Name = $_.Name; Type = $_.AppType; Publisher = $_.Publisher; Version = $_.Version }
                })
                Write-IaTuiHeader -Screen 'Apps' -Sub "all apps ($($rows.Count))" -Accent $Accent
                $rows | Format-IaTable -Color $Accent -Title "All Apps ($($rows.Count))"
                Read-IaTablePause -Data $script:_apps -Stem 'apps-all' -Color $Accent
            }
            'Filter by type*' {
                $type = Read-IaMenu -Title 'App type' -Color $Accent -Choices @('Win32','Store','iOS','Android','macOS','WebApp','LOB','VPP','Office365')
                Invoke-IaStatus -Spinner 'Dots2' -Title "Loading $type apps…" -Color $Accent -ScriptBlock {
                    $script:_apps = @(Get-IntuneApp -AppType $type)
                }
                $rows = @($script:_apps | ForEach-Object {
                    [pscustomobject][ordered]@{ Name = $_.Name; Publisher = $_.Publisher; Version = $_.Version; Modified = $_.Modified }
                })
                Write-IaTuiHeader -Screen 'Apps' -Sub "$type ($($rows.Count))" -Accent $Accent
                $rows | Format-IaTable -Color $Accent -Title "$type Apps ($($rows.Count))"
                Read-IaTablePause -Data $script:_apps -Stem "apps-$($type.ToLower())" -Color $Accent
            }
            'Win32 app details*' {
                $name = Read-IaText -Question 'App name or GUID'
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_w32 = Get-IntuneWin32App -Id $name
                }
                if ($script:_w32) {
                    Write-IaHost "[$Accent]$($script:_w32.Name)[/]  v$($script:_w32.Version)  ($($script:_w32.Publisher))"
                    Write-IaHost "Install:   $($script:_w32.InstallCommandLine)"
                    Write-IaHost "Uninstall: $($script:_w32.UninstallCommandLine)"
                    Write-IaHost "Run as:    $($script:_w32.InstallExperience?.runAsAccount)"
                    Write-IaHost "Min OS:    $($script:_w32.MinimumOS)"
                    Write-IaHost "Detection rules: $($script:_w32.DetectionRules.Count)"
                    Write-IaHost "Requirement rules: $($script:_w32.RequirementRules.Count)"
                }
                Read-IaText -Question 'Press Enter to continue' | Out-Null
            }
            'Assign app*' {
                $appName = Read-IaText -Question 'App name or GUID'
                $mode    = Read-IaMenu -Title 'Assign to' -Color $Accent -Choices @('All Devices','All Users','Specific group','Clear all assignments')
                switch ($mode) {
                    'All Devices' {
                        Invoke-IaStatus -Spinner 'Dots2' -Title 'Assigning…' -Color $Accent -ScriptBlock {
                            Set-IntuneAppAssignment -AppId $appName -AllDevices -Confirm:$false
                        }
                    }
                    'All Users' {
                        Invoke-IaStatus -Spinner 'Dots2' -Title 'Assigning…' -Color $Accent -ScriptBlock {
                            Set-IntuneAppAssignment -AppId $appName -AllUsers -Confirm:$false
                        }
                    }
                    'Specific group' {
                        $grp = Read-IaText -Question 'Group name or GUID'
                        $excl = Read-IaMenu -Title 'Include or exclude?' -Color $Accent -Choices @('Include','Exclude')
                        Invoke-IaStatus -Spinner 'Dots2' -Title 'Assigning…' -Color $Accent -ScriptBlock {
                            if ($excl -eq 'Include') {
                                Set-IntuneAppAssignment -AppId $appName -Include @($grp) -Confirm:$false
                            } else {
                                Set-IntuneAppAssignment -AppId $appName -Exclude @($grp) -Confirm:$false
                            }
                        }
                    }
                    'Clear all assignments' {
                        $confirm = Read-IaMenu -Title "[red]Remove all assignments from '$appName'?[/]" -Color $Accent -Choices @('Yes','Cancel')
                        if ($confirm -eq 'Yes') {
                            Invoke-IaStatus -Spinner 'Dots2' -Title 'Clearing…' -Color $Accent -ScriptBlock {
                                Set-IntuneAppAssignment -AppId $appName -Clear -Confirm:$false
                            }
                        }
                    }
                }
                Write-IaHost "[$Accent]Done.[/]"
                Read-IaText -Question 'Press Enter to continue' | Out-Null
            }
            'Back' { return }
        }
    }
}

# ─── windows update submenu ───────────────────────────────────────────────────
function Invoke-IaTuiWindowsUpdate {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Windows Update' -Sub 'rings · feature updates · driver updates' -Accent $Accent

    while ($true) {
        $pick = Read-IaMenu -Title 'Windows Update' -Color $Accent -PageSize 10 -Choices @(
            'List update rings',
            'Create update ring',
            'Delete update ring',
            'List feature update profiles',
            'Create feature update profile',
            'List driver update profiles',
            'Back'
        )
        switch -Wildcard ($pick) {
            'List update rings' {
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_rings = @(Get-IntuneUpdateRing)
                }
                $rows = $script:_rings | ForEach-Object {
                    [ordered]@{ Name = $_.Name; QualityDeferral = $_.QualityUpdateDeferralDays; FeatureDeferral = $_.FeatureUpdateDeferralDays; AutoMode = $_.AutomaticUpdateMode; Modified = $_.Modified }
                }
                Format-IaTable -Data $rows -Accent $Accent -Title 'Windows Update Rings'
                Read-IaText -Question 'Press Enter to continue' | Out-Null
            }
            'Create update ring' {
                $name    = Read-IaText -Question 'Ring name'
                $qDefer  = [int](Read-IaText -Question 'Quality deferral days (0-30)')
                $fDefer  = [int](Read-IaText -Question 'Feature deferral days (0-365)')
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Creating…' -Color $Accent -ScriptBlock {
                    $script:_ring = New-IntuneUpdateRing -Name $name -QualityDeferralDays $qDefer -FeatureDeferralDays $fDefer -Confirm:$false
                }
                Write-IaHost "[$Accent]Created:[/] $($script:_ring.Name) ($($script:_ring.Id))"
                Read-IaText -Question 'Press Enter to continue' | Out-Null
            }
            'Delete update ring' {
                $name = Read-IaText -Question 'Ring name or GUID to delete'
                $confirm = Read-IaMenu -Title "[red]Delete '$name'?[/]" -Color $Accent -Choices @('Yes, delete','Cancel')
                if ($confirm -eq 'Yes, delete') {
                    Invoke-IaStatus -Spinner 'Dots2' -Title 'Deleting…' -Color $Accent -ScriptBlock {
                        Remove-IntuneUpdateRing -Id $name -Confirm:$false
                    }
                    Write-IaHost "[$Accent]Deleted.[/]"
                }
            }
            'List feature update*' {
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_fups = @(Get-IntuneFeatureUpdate)
                }
                $rows = $script:_fups | ForEach-Object { [ordered]@{ Name = $_.Name; Version = $_.FeatureUpdateVersion; RolloutStart = $_.RolloutSettings?.offerStartDateTimeInUTC; Modified = $_.Modified } }
                Format-IaTable -Data $rows -Accent $Accent -Title 'Feature Update Profiles'
                Read-IaText -Question 'Press Enter to continue' | Out-Null
            }
            'Create feature update*' {
                $name    = Read-IaText -Question 'Profile name'
                $version = Read-IaText -Question 'Feature update version (e.g. Windows 11, version 23H2)'
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Creating…' -Color $Accent -ScriptBlock {
                    $script:_fup = New-IntuneFeatureUpdate -Name $name -FeatureUpdateVersion $version -Confirm:$false
                }
                Write-IaHost "[$Accent]Created:[/] $($script:_fup.Name)"
                Read-IaText -Question 'Press Enter to continue' | Out-Null
            }
            'List driver update*' {
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_dups = @(Get-IntuneDriverUpdate)
                }
                $rows = $script:_dups | ForEach-Object { [ordered]@{ Name = $_.Name; ApprovalType = $_.ApprovalType; Deferral = $_.DeploymentDeferralInDays; Modified = $_.Modified } }
                Format-IaTable -Data $rows -Accent $Accent -Title 'Driver Update Profiles'
                Read-IaText -Question 'Press Enter to continue' | Out-Null
            }
            'Back' { return }
        }
    }
}

# ─── autopilot & enrollment submenu ──────────────────────────────────────────
function Invoke-IaTuiAutopilot {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Autopilot & Enrollment' -Sub 'devices · profiles · restrictions · ESP' -Accent $Accent

    while ($true) {
        $pick = Read-IaMenu -Title 'Autopilot & Enrollment' -Color $Accent -PageSize 10 -Choices @(
            'List Autopilot devices',
            'Search Autopilot device (by serial)',
            'Update Autopilot device (group tag)',
            'List Autopilot profiles',
            'Enrollment restrictions',
            'Enrollment Status Pages (ESP)',
            'Back'
        )
        switch -Wildcard ($pick) {
            'List Autopilot devices' {
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_apdevs = @(Get-IntuneAutopilotDevice)
                }
                $rows = $script:_apdevs | ForEach-Object { [ordered]@{ Serial = $_.SerialNumber; Model = $_.Model; Manufacturer = $_.Manufacturer; GroupTag = $_.GroupTag; EnrollState = $_.EnrollmentState } }
                Format-IaTable -Data $rows -Accent $Accent -Title "Autopilot Devices ($($script:_apdevs.Count))"
                Read-IaText -Question 'Press Enter to continue' | Out-Null
            }
            'Search Autopilot device*' {
                $serial = Read-IaText -Question 'Serial number'
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Searching…' -Color $Accent -ScriptBlock {
                    $script:_apdev = @(Get-IntuneAutopilotDevice -SerialNumber $serial)
                }
                if (-not $script:_apdev) { Write-IaHost "[yellow]No device found.[/]" }
                else {
                    $d = $script:_apdev[0]
                    Write-IaHost "[$Accent]$($d.SerialNumber)[/]  $($d.Model)  GroupTag: $($d.GroupTag)  State: $($d.EnrollmentState)"
                }
                Read-IaText -Question 'Press Enter to continue' | Out-Null
            }
            'Update Autopilot device*' {
                $serial   = Read-IaText -Question 'Serial number or GUID'
                $groupTag = Read-IaText -Question 'New group tag (leave blank to skip)'
                $dispName = Read-IaText -Question 'New display name (leave blank to skip)'
                $params   = @{ Id = $serial }
                if ($groupTag) { $params['GroupTag']    = $groupTag }
                if ($dispName) { $params['DisplayName'] = $dispName }
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Updating…' -Color $Accent -ScriptBlock {
                    Set-IntuneAutopilotDevice @using:params -Confirm:$false
                }
                Write-IaHost "[$Accent]Updated.[/]"
                Read-IaText -Question 'Press Enter to continue' | Out-Null
            }
            'List Autopilot profiles' {
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_appros = @(Get-IntuneAutopilotProfile)
                }
                $rows = $script:_appros | ForEach-Object { [ordered]@{ Name = $_.Name; Language = $_.Language; DeviceUsageType = $_.OobeSettings?.deviceUsageType; Modified = $_.Modified } }
                Format-IaTable -Data $rows -Accent $Accent -Title 'Autopilot Profiles'
                Read-IaText -Question 'Press Enter to continue' | Out-Null
            }
            'Enrollment restrictions' {
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_restr = @(Get-IntuneEnrollmentRestriction)
                }
                $rows = $script:_restr | ForEach-Object { [ordered]@{ Name = $_.Name; Type = $_.Type; Priority = $_.Priority; Modified = $_.Modified } }
                Format-IaTable -Data $rows -Accent $Accent -Title 'Enrollment Restrictions'
                Read-IaText -Question 'Press Enter to continue' | Out-Null
            }
            'Enrollment Status Pages*' {
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_esps = @(Get-IntuneESP)
                }
                $rows = $script:_esps | ForEach-Object { [ordered]@{ Name = $_.Name; Priority = $_.Priority; ShowProgress = $_.ShowInstallationProgress; TimeoutMin = $_.InstallProgressTimeoutInMinutes; TrackedApps = $_.TrackedAppCount } }
                Format-IaTable -Data $rows -Accent $Accent -Title 'Enrollment Status Pages'
                Read-IaText -Question 'Press Enter to continue' | Out-Null
            }
            'Back' { return }
        }
    }
}

# ─── security baselines submenu ───────────────────────────────────────────────
function Invoke-IaTuiSecurityBaselines {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Security Baselines' -Sub 'endpoint security · antivirus · firewall · disk encryption' -Accent $Accent

    while ($true) {
        $pick = Read-IaMenu -Title 'Security Baselines' -Color $Accent -PageSize 8 -Choices @(
            'List all security baselines',
            'Filter by category',
            'View baseline details',
            'Create from template',
            'Delete a baseline',
            'Back'
        )
        switch -Wildcard ($pick) {
            'List all*' {
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_baselines = @(Get-IntuneSecurityBaseline)
                }
                $rows = $script:_baselines | ForEach-Object { [ordered]@{ Name = $_.Name; Category = $_.Category; Platform = $_.Platform; Settings = $_.SettingCount; Modified = $_.Modified } }
                Format-IaTable -Data $rows -Accent $Accent -Title "Security Baselines ($($script:_baselines.Count))"
                Read-IaText -Question 'Press Enter to continue' | Out-Null
            }
            'Filter by category' {
                $cat = Read-IaMenu -Title 'Category' -Color $Accent -Choices @('Baseline','Antivirus','DiskEncryption','Firewall','EndpointDetectionResponse','AttackSurfaceReduction','AccountProtection')
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_baselines = @(Get-IntuneSecurityBaseline -Category $cat)
                }
                $rows = $script:_baselines | ForEach-Object { [ordered]@{ Name = $_.Name; Platform = $_.Platform; Settings = $_.SettingCount; Modified = $_.Modified } }
                Format-IaTable -Data $rows -Accent $Accent -Title "$cat Baselines"
                Read-IaText -Question 'Press Enter to continue' | Out-Null
            }
            'View baseline details' {
                $name = Read-IaText -Question 'Baseline name or GUID'
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_bl = Get-IntuneSecurityBaseline -Id $name
                }
                if ($script:_bl) {
                    Write-IaHost "[$Accent]$($script:_bl.Name)[/]  Category: $($script:_bl.Category)  Platform: $($script:_bl.Platform)"
                    Write-IaHost "Baseline type: $($script:_bl.BaselineType)"
                    Write-IaHost "Settings: $($script:_bl.SettingCount)  Created: $($script:_bl.Created)  Modified: $($script:_bl.Modified)"
                }
                Read-IaText -Question 'Press Enter to continue' | Out-Null
            }
            'Create from template' {
                $name  = Read-IaText -Question 'New baseline name'
                $tmplId = Read-IaText -Question 'Template ID (GUID from Get-IntuneSecurityTemplate)'
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Creating…' -Color $Accent -ScriptBlock {
                    $script:_newbl = New-IntuneSecurityBaseline -Name $name -TemplateId $tmplId -Confirm:$false
                }
                Write-IaHost "[$Accent]Created:[/] $($script:_newbl.Name) ($($script:_newbl.Id))"
                Read-IaText -Question 'Press Enter to continue' | Out-Null
            }
            'Delete a baseline' {
                $name = Read-IaText -Question 'Baseline name or GUID'
                $confirm = Read-IaMenu -Title "[red]Delete '$name'?[/]" -Color $Accent -Choices @('Yes, delete','Cancel')
                if ($confirm -eq 'Yes, delete') {
                    Invoke-IaStatus -Spinner 'Dots2' -Title 'Deleting…' -Color $Accent -ScriptBlock {
                        Remove-IntuneConfigurationPolicy -Id $name -Confirm:$false
                    }
                    Write-IaHost "[$Accent]Deleted.[/]"
                }
            }
            'Back' { return }
        }
    }
}

# ─── policies submenu ─────────────────────────────────────────────────────────

function Invoke-IaTuiPolicies {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Policies' -Sub 'configuration · compliance · scripts · remediations' -Accent $Accent

    while ($true) {
        $pick = Read-IaMenu -Title 'Policies' -Color $Accent -PageSize 14 -Choices @(
            'Configuration policies (Settings Catalog)',
            'Compliance policies',
            'Scripts (Windows PowerShell · macOS shell)',
            'Remediations (device health scripts)',
            'Back'
        )

        switch -Wildcard ($pick) {
            'Configuration*' { Invoke-IaTuiConfigPolicies  -Accent $Accent }
            'Compliance*'    { Invoke-IaTuiCompliancePol   -Accent $Accent }
            'Scripts*'       { Invoke-IaTuiScripts         -Accent $Accent }
            'Remediations*'  { Invoke-IaTuiRemediations    -Accent $Accent }
            'Back'           { return }
        }
    }
}

function Invoke-IaTuiConfigPolicies {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Configuration Policies' -Sub 'Settings Catalog' -Accent $Accent

    $action = Read-IaMenu -Title 'Action' -Color $Accent -Choices @(
        'List all',
        'Filter by platform',
        'View a policy (with settings)',
        'Copy a policy',
        'Delete a policy',
        'Back'
    )

    switch -Wildcard ($action) {
        'List all' {
            Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                $script:_pols = @(Get-IntuneConfigurationPolicy)
            }
            if (-not $script:_pols) { Write-IaHost "[yellow]No configuration policies found.[/]"; return }
            $rows = $script:_pols | ForEach-Object {
                [ordered]@{ Name = $_.Name; Platform = $_.Platform; Technologies = $_.Technologies; Settings = $_.SettingCount; Modified = $_.Modified }
            }
            Format-IaTable -Data $rows -Accent $Accent -Title 'Configuration Policies'
            Read-IaText -Question 'Press Enter to continue' | Out-Null
        }
        'Filter by platform' {
            $plat = Read-IaMenu -Title 'Platform' -Color $Accent -Choices @('windows10','macOS','iOS','android','linux')
            Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                $script:_pols = @(Get-IntuneConfigurationPolicy -Platform $plat)
            }
            if (-not $script:_pols) { Write-IaHost "[yellow]No $plat policies found.[/]"; return }
            $rows = $script:_pols | ForEach-Object {
                [ordered]@{ Name = $_.Name; Platform = $_.Platform; Settings = $_.SettingCount; Modified = $_.Modified }
            }
            Format-IaTable -Data $rows -Accent $Accent -Title "$plat Configuration Policies"
            Read-IaText -Question 'Press Enter to continue' | Out-Null
        }
        'View a policy*' {
            $name = Read-IaText -Question 'Policy name or GUID'
            Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                $script:_pol = Get-IntuneConfigurationPolicy -Id $name
            }
            if (-not $script:_pol) { return }
            Write-IaHost "[$Accent]$($script:_pol.Name)[/]  Platform: $($script:_pol.Platform)  Settings: $($script:_pol.SettingCount)"
            Write-IaHost "Description: $($script:_pol.Description)"
            Write-IaHost "Created: $($script:_pol.Created)  Modified: $($script:_pol.Modified)"
            $script:_pol.Settings | ForEach-Object { Write-IaHost "  - $($_.settingInstance.'@odata.type' -replace '.*\.', '')" }
            Read-IaText -Question 'Press Enter to continue' | Out-Null
        }
        'Copy a policy' {
            $src  = Read-IaText -Question 'Source policy name or GUID'
            $dest = Read-IaText -Question 'New policy name'
            Invoke-IaStatus -Spinner 'Dots2' -Title "Copying '$src'…" -Color $Accent -ScriptBlock {
                $script:_copy = Copy-IntuneConfigurationPolicy -SourceId $src -NewName $dest
            }
            Write-IaHost "[$Accent]Created:[/] $($script:_copy.Name) ($($script:_copy.Id))"
            Read-IaText -Question 'Press Enter to continue' | Out-Null
        }
        'Delete a policy' {
            $name = Read-IaText -Question 'Policy name or GUID to delete'
            $confirm = Read-IaMenu -Title "[red]Delete '$name'?[/]" -Color $Accent -Choices @('Yes, delete', 'Cancel')
            if ($confirm -eq 'Yes, delete') {
                Invoke-IaStatus -Spinner 'Dots2' -Title "Deleting…" -Color $Accent -ScriptBlock {
                    Remove-IntuneConfigurationPolicy -Id $name -Confirm:$false
                }
                Write-IaHost "[$Accent]Deleted.[/]"
            }
        }
        'Back' { return }
    }
}

function Invoke-IaTuiCompliancePol {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Compliance Policies' -Accent $Accent

    $action = Read-IaMenu -Title 'Action' -Color $Accent -Choices @(
        'List all',
        'Filter by platform',
        'Delete a policy',
        'Back'
    )

    switch -Wildcard ($action) {
        'List all' {
            Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                $script:_cpols = @(Get-IntuneCompliancePolicy)
            }
            if (-not $script:_cpols) { Write-IaHost "[yellow]No compliance policies found.[/]"; return }
            $rows = $script:_cpols | ForEach-Object {
                [ordered]@{ Name = $_.Name; Platform = $_.Platform; Modified = $_.Modified }
            }
            Format-IaTable -Data $rows -Accent $Accent -Title 'Compliance Policies'
            Read-IaText -Question 'Press Enter to continue' | Out-Null
        }
        'Filter by platform' {
            $plat = Read-IaMenu -Title 'Platform' -Color $Accent -Choices @('Windows','macOS','iOS','Android','AndroidWorkProfile')
            Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                $script:_cpols = @(Get-IntuneCompliancePolicy -Platform $plat)
            }
            $rows = $script:_cpols | ForEach-Object { [ordered]@{ Name = $_.Name; Platform = $_.Platform; Modified = $_.Modified } }
            Format-IaTable -Data $rows -Accent $Accent -Title "$plat Compliance Policies"
            Read-IaText -Question 'Press Enter to continue' | Out-Null
        }
        'Delete a policy' {
            $name = Read-IaText -Question 'Policy name or GUID to delete'
            $confirm = Read-IaMenu -Title "[red]Delete '$name'?[/]" -Color $Accent -Choices @('Yes, delete', 'Cancel')
            if ($confirm -eq 'Yes, delete') {
                Invoke-IaStatus -Spinner 'Dots2' -Title "Deleting…" -Color $Accent -ScriptBlock {
                    Remove-IntuneCompliancePolicy -Id $name -Confirm:$false
                }
                Write-IaHost "[$Accent]Deleted.[/]"
            }
        }
        'Back' { return }
    }
}

function Invoke-IaTuiScripts {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Scripts' -Sub 'Windows PowerShell · macOS shell' -Accent $Accent

    $action = Read-IaMenu -Title 'Action' -Color $Accent -Choices @(
        'List all',
        'List Windows scripts',
        'List macOS scripts',
        'View script content',
        'Delete a script',
        'Back'
    )

    switch -Wildcard ($action) {
        'List all' {
            Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                $script:_scripts = @(Get-IntuneScript -Platform Both)
            }
            $rows = $script:_scripts | ForEach-Object { [ordered]@{ Name = $_.Name; Platform = $_.Platform; RunAs = $_.RunAs; Modified = $_.Modified } }
            Format-IaTable -Data $rows -Accent $Accent -Title 'Scripts'
            Read-IaText -Question 'Press Enter to continue' | Out-Null
        }
        'List Windows*' {
            Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                $script:_scripts = @(Get-IntuneScript -Platform Windows)
            }
            $rows = $script:_scripts | ForEach-Object { [ordered]@{ Name = $_.Name; FileName = $_.FileName; RunAs = $_.RunAs; Modified = $_.Modified } }
            Format-IaTable -Data $rows -Accent $Accent -Title 'Windows Scripts'
            Read-IaText -Question 'Press Enter to continue' | Out-Null
        }
        'List macOS*' {
            Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                $script:_scripts = @(Get-IntuneScript -Platform macOS)
            }
            $rows = $script:_scripts | ForEach-Object { [ordered]@{ Name = $_.Name; FileName = $_.FileName; RetryCount = $_.RetryCount; Modified = $_.Modified } }
            Format-IaTable -Data $rows -Accent $Accent -Title 'macOS Scripts'
            Read-IaText -Question 'Press Enter to continue' | Out-Null
        }
        'View script content' {
            $name = Read-IaText -Question 'Script name or GUID'
            Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                $script:_scr = Get-IntuneScript -Id $name -IncludeContent
            }
            if ($script:_scr) {
                Write-IaHost "[$Accent]$($script:_scr.Name)[/]  Platform: $($script:_scr.Platform)  RunAs: $($script:_scr.RunAs)"
                Write-IaHost "---"
                Write-IaHost ($script:_scr.Content ?? '(no content)')
            }
            Read-IaText -Question 'Press Enter to continue' | Out-Null
        }
        'Delete a script' {
            $name = Read-IaText -Question 'Script name or GUID to delete'
            $confirm = Read-IaMenu -Title "[red]Delete '$name'?[/]" -Color $Accent -Choices @('Yes, delete', 'Cancel')
            if ($confirm -eq 'Yes, delete') {
                Invoke-IaStatus -Spinner 'Dots2' -Title "Deleting…" -Color $Accent -ScriptBlock {
                    Remove-IntuneScript -Id $name -Confirm:$false
                }
                Write-IaHost "[$Accent]Deleted.[/]"
            }
        }
        'Back' { return }
    }
}

function Invoke-IaTuiRemediations {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Remediations' -Sub 'device health scripts' -Accent $Accent

    $action = Read-IaMenu -Title 'Action' -Color $Accent -Choices @(
        'List all',
        'View remediation (with content)',
        'Run on-demand on a device',
        'Delete a remediation',
        'Back'
    )

    switch -Wildcard ($action) {
        'List all' {
            Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                $script:_rems = @(Get-IntuneRemediation)
            }
            $rows = $script:_rems | ForEach-Object { [ordered]@{ Name = $_.Name; Publisher = $_.Publisher; Version = $_.Version; RunAs = $_.RunAs; Modified = $_.Modified } }
            Format-IaTable -Data $rows -Accent $Accent -Title 'Remediations'
            Read-IaText -Question 'Press Enter to continue' | Out-Null
        }
        'View remediation*' {
            $name = Read-IaText -Question 'Remediation name or GUID'
            Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                $script:_rem = Get-IntuneRemediation -Id $name -IncludeContent
            }
            if ($script:_rem) {
                Write-IaHost "[$Accent]$($script:_rem.Name)[/]  Publisher: $($script:_rem.Publisher)  v$($script:_rem.Version)"
                Write-IaHost "--- Detection ---"
                Write-IaHost ($script:_rem.DetectionContent ?? '(none)')
                Write-IaHost "--- Remediation ---"
                Write-IaHost ($script:_rem.RemediationContent ?? '(none)')
            }
            Read-IaText -Question 'Press Enter to continue' | Out-Null
        }
        'Run on-demand*' {
            $remName = Read-IaText -Question 'Remediation name or GUID'
            $devName = Read-IaText -Question 'Device name or GUID'
            $confirm = Read-IaMenu -Title "Run '$remName' on '$devName'?" -Color $Accent -Choices @('Yes, run it', 'Cancel')
            if ($confirm -eq 'Yes, run it') {
                Invoke-IaStatus -Spinner 'Dots2' -Title "Submitting…" -Color $Accent -ScriptBlock {
                    Invoke-IntuneRemediation -RemediationId $remName -Device $devName -Confirm:$false
                }
                Write-IaHost "[$Accent]Submitted.[/]"
            }
        }
        'Delete a remediation' {
            $name = Read-IaText -Question 'Remediation name or GUID to delete'
            $confirm = Read-IaMenu -Title "[red]Delete '$name'?[/]" -Color $Accent -Choices @('Yes, delete', 'Cancel')
            if ($confirm -eq 'Yes, delete') {
                Invoke-IaStatus -Spinner 'Dots2' -Title "Deleting…" -Color $Accent -ScriptBlock {
                    Remove-IntuneRemediation -Id $name -Confirm:$false
                }
                Write-IaHost "[$Accent]Deleted.[/]"
            }
        }
        'Back' { return }
    }
}

# ─── reports submenu ──────────────────────────────────────────────────────────

function Invoke-IaTuiReports {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Reports' -Sub 'status · audit · approvals · any report' -Accent $Accent
    $pick = Read-IaMenu -Title 'Reports' -Color $Accent -PageSize 14 -Choices @(
        'Tenant dashboard (devices · compliance · posture)',
        'Device inventory (compliance · last check-in)',
        'User lookup (help desk · devices · groups · effective policy)',
        'App install status (device / user)',
        'Configuration profile status',
        'Compliance status',
        'Deployment summary (success / fail, by group)',
        'Custom report builder (select · where · sort · group · export)',
        'Audit log (who changed what)',
        'Multi Admin Approval requests',
        'PIM activations',
        'Run any Intune report',
        'Back'
    )
    switch -Wildcard ($pick) {
        'Tenant dashboard*' {
            $items = Get-IaTuiInventory
            $sum = Invoke-IaStatus -Spinner Dots -Title 'Reading device health…' -ScriptBlock {
                Get-IaDeviceSummary -StaleDays 30
            }
            Write-IaTuiHeader -Screen 'Tenant dashboard' -Sub 'device health · assignment posture' -Accent $Accent

            $pctColor = if ($sum.CompliancePercent -ge 90) { $Accent } elseif ($sum.CompliancePercent -ge 75) { 'yellow' } else { 'coral' }
            Write-IaHost (
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
            Write-IaHost (
                "[$Accent]Resources  $(@($items).Count)[/]    " +
                "Assigned  $assignedCount    " +
                "[grey]Unassigned  $(@($items).Count - $assignedCount)[/]"
            )

            if ($sum.ByPlatform) {
                Write-IaHost ""
                Write-IaHost "[$Accent]Compliance by platform[/]"
                foreach ($p in $sum.ByPlatform) {
                    $w   = [int][math]::Round(($p.CompliantPercent / 100) * 28)
                    $bar = '█' * [math]::Max($w, 0)
                    $bc  = if ($p.CompliantPercent -ge 90) { $Accent } elseif ($p.CompliantPercent -ge 75) { 'yellow' } else { 'coral' }
                    Write-IaHost ("[grey]{0,-10}[/] [$bc]{1,-28}[/] {2,3}%  [grey]({3})[/]" -f $p.Platform, $bar, $p.CompliantPercent, $p.Total)
                }
            }
            if ($byArea) {
                Write-IaHost ""
                Write-IaHost "[$Accent]Assigned by area[/]"
                $max = ($byArea | Measure-Object -Property Assigned -Maximum).Maximum
                foreach ($r in ($byArea | Sort-Object Assigned -Descending)) {
                    $w   = if ($max) { [int][math]::Round(($r.Assigned / $max) * 28) } else { 0 }
                    $bar = '█' * [math]::Max($w, 1)
                    Write-IaHost ("[grey]{0,-16}[/] [$Accent]{1}[/] {2}/{3}" -f $r.Area, $bar, $r.Assigned, $r.Total)
                }
            }
        }
        'Device inventory*' {
            # Filter submenu
            $filt = Read-IaMenu -Title 'Filter' -Color $Accent -PageSize 10 -Choices @(
                'All devices',
                'Non-compliant only',
                'Stale (no sync 30d+)',
                'Cloud PCs only',
                'Autopilot enrolled only',
                'By platform (Windows / iOS / Android / macOS)',
                'By manufacturer',
                'By compliance state',
                'Group by a column (count per value)'
            )
            $invParams = @{}
            $groupProp = $null
            $subTitle  = $filt.ToLower()
            switch -Wildcard ($filt) {
                'Non-compliant*'   { $invParams.ComplianceState = 'noncompliant' }
                'Stale*'           { $invParams.StaleDays = 30 }
                'Cloud PCs*'       { $invParams.Source = 'CloudPC' }
                'Autopilot*'       { $invParams.Source = 'Autopilot' }
                'By platform*'     {
                    $pl = Read-IaMenu -Title 'Platform' -Color $Accent -Choices @('Windows','iOS','Android','macOS','Linux')
                    $invParams.Platform = $pl; $subTitle = "platform: $pl"
                }
                'By manufacturer*' {
                    $mfr = Read-IaText -Question 'Manufacturer contains'
                    $invParams.Manufacturer = $mfr; $subTitle = "manufacturer: $mfr"
                }
                'By compliance*'   {
                    $cs = Read-IaMenu -Title 'Compliance state' -Color $Accent -Choices @(
                        'compliant','noncompliant','error','conflict','inGracePeriod','notApplicable','unknown'
                    )
                    $invParams.ComplianceState = $cs; $subTitle = "compliance: $cs"
                }
                'Group by*'        {
                    $groupProp = Read-IaMenu -Title 'Group devices by' -Color $Accent -PageSize 12 -Choices @(
                        'Model','Manufacturer','OS','OSVersion','Compliance','Owner','User','EnrollmentType','JoinType','Source','Encrypted'
                    )
                    if (-not $groupProp) { return }
                    $subTitle = "grouped by $groupProp"
                }
            }
            Write-IaTuiHeader -Screen 'Device inventory' -Sub $subTitle -Accent $Accent
            $rawDevices = @(Invoke-IaStatus -Spinner Dots -Title 'Reading managed devices…' -ScriptBlock {
                Get-IntuneDeviceInventory @invParams
            })
            if (-not $rawDevices) { Write-IaHost '[yellow]No devices match.[/]'; Read-IaPause | Out-Null; return }
            if ($groupProp) {
                # Group-by pivot — count of devices per value of the chosen column; pick a
                # value to drill into just those devices (then the normal grid + console).
                $groups = $rawDevices | Group-Object -Property $groupProp | Sort-Object Count -Descending
                $gmax   = [Math]::Max(1, ($groups | Measure-Object -Property Count -Maximum).Maximum)
                $pivot  = @($groups | ForEach-Object {
                    $o = [ordered]@{}
                    $o[$groupProp] = if ([string]::IsNullOrWhiteSpace([string]$_.Name)) { '(none)' } else { $_.Name }
                    $o['Count']    = $_.Count
                    $o['Share']    = "[$Accent]$('█' * [Math]::Max(1, [int](($_.Count / $gmax) * 22)))[/]"
                    [pscustomobject]$o
                })
                $gv = Read-IaTableInteractive -Data $pivot -Color $Accent -Title "Devices grouped by $groupProp ($($rawDevices.Count) total · pick a group)" -Stem "devices-by-$groupProp" -Selectable
                if (-not $gv) { return }
                $val        = [string]$gv.$groupProp
                $rawDevices = @($rawDevices | Where-Object {
                    $v = if ([string]::IsNullOrWhiteSpace([string]$_.$groupProp)) { '(none)' } else { [string]$_.$groupProp }
                    $v -eq $val
                })
                $subTitle = "$groupProp = $val"
                Write-IaTuiHeader -Screen 'Device inventory' -Sub $subTitle -Accent $Accent
            }
            Write-IaHost "[$Accent]$($rawDevices.Count)[/] device(s)"

            # Colour-coded display rows
            $displayDevices = @($rawDevices | Select-Object -First 300 | ForEach-Object {
                $cs   = "$($_.Compliance)"
                $cc   = switch ($cs) { 'compliant' { $Accent } 'noncompliant' { 'coral' } default { 'grey' } }
                $dsc  = if ($null -ne $_.DaysSinceSync -and $_.DaysSinceSync -ge 30) { 'coral' }
                        elseif ($null -ne $_.DaysSinceSync -and $_.DaysSinceSync -ge 7) { 'yellow' } else { 'grey' }
                $srcC = switch ($_.Source) { 'CloudPC' { 'deepskyblue1' } 'Autopilot' { 'orange1' } default { 'grey' } }
                [pscustomobject][ordered]@{
                    Device       = $_.Device
                    OS           = "[$Accent]$($_.OS)[/]"
                    Compliance   = "[$cc]$cs[/]"
                    Source       = "[$srcC]$($_.Source)[/]"
                    Manufacturer = $_.Manufacturer
                    Model        = $_.Model
                    User         = $_.User
                    'Sync(d)'    = if ($null -ne $_.DaysSinceSync) { "[$dsc]$($_.DaysSinceSync)[/]" } else { '[grey]—[/]' }
                }
            })
            # Scrollable / searchable grid — Enter or click a device to drill into its
            # detail; e exports, q goes back. (Was: dump every row + "type a name".)
            $capNote = if ($rawDevices.Count -gt 300) { '  ·  first 300 shown' } else { '' }
            while ($true) {
                $picked = Read-IaTableInteractive -Data $displayDevices -Color $Accent `
                    -Title "Device inventory ($($rawDevices.Count)$capNote)" -Stem 'device-inventory' -Selectable
                if (-not $picked) { break }   # q / Esc leaves the inventory
                $devName = "$($picked.Device)"
                Write-IaTuiHeader -Screen 'Device detail' -Sub $devName -Accent $Accent
                    $detail = Invoke-IaStatus -Spinner Dots -Title "Loading $devName…" -ScriptBlock {
                        Get-IntuneDeviceDetail -Device $devName
                    }
                    if ($detail) {
                        $fields = [ordered]@{
                            Device        = $detail.Device
                            OS            = "$($detail.OS) $($detail.OSVersion)"
                            Model         = "$($detail.Manufacturer) $($detail.Model)"
                            Serial        = $detail.SerialNumber
                            Compliance    = $detail.ComplianceState
                            EnrollmentType = $detail.EnrollmentType
                            JoinType      = $detail.JoinType
                            Encrypted     = $detail.Encrypted
                            User          = "$($detail.UserDisplayName)  $($detail.UserEmail)"
                            LastSync      = $detail.LastSyncAt
                            AzureADId     = $detail.AzureADDeviceId
                            StorageGB     = "Free $($detail.FreeStorageGB) / Total $($detail.TotalStorageGB)"
                        }
                        # Render the detail block into the menu's -Header so it stays on
                        # screen — Read-IaMenu repaints full-screen and would otherwise wipe it.
                        $hdr = [System.Collections.Generic.List[string]]::new()
                        $hdr.Add((ConvertFrom-IaMarkup "[$Accent]≈ TIDE[/]  [bold]· Device detail[/]"))
                        $hdr.Add((ConvertFrom-IaMarkup "[grey]$devName[/]"))
                        $hdr.Add('')
                        foreach ($kv in $fields.GetEnumerator()) {
                            $lc = if ([string]::IsNullOrWhiteSpace($kv.Value)) { 'grey' } else { 'white' }
                            $hdr.Add((ConvertFrom-IaMarkup ("[grey]{0,-15}[/] [$lc]{1}[/]" -f $kv.Key, $kv.Value)))
                        }
                        $hdr.Add('')

                        $devHeader = ($hdr -join "`n")
                        while ($true) {
                          $sub = Read-IaMenu -Title 'Help desk · drill further' -Color $Accent -Header $devHeader -PageSize 11 -Choices @(
                            'Compliance policy states',
                            'Compliance failures (which settings · why non-compliant)',
                            'Configuration profile states',
                            'Configuration conflicts (profiles that disagree)',
                            'Detected apps (discovered inventory)',
                            'Managed apps (Intune-deployed + install state)',
                            'Group memberships (why it gets its policies)',
                            'BitLocker recovery keys',
                            'LAPS local admin password',
                            'Device actions (sync · reboot · lock · …)',
                            'Back to device list'
                          )
                          if (-not $sub -or $sub -eq 'Back to device list') { break }
                          switch -Wildcard ($sub) {
                            'Compliance pol*' {
                                $cs = @(Invoke-IaStatus -Spinner Dots -Title 'Loading compliance states…' -ScriptBlock {
                                    (Get-IntuneDeviceDetail -Device $devName -IncludeComplianceState).ComplianceStates
                                })
                                $cs | ForEach-Object {
                                    $sc = if ($_.state -eq 'compliant') { $Accent } elseif ($_.state -in 'noncompliant','error') { 'coral' } else { 'grey' }
                                    [pscustomobject][ordered]@{ Policy = $_.displayName; State = "[$sc]$($_.state)[/]"; Platform = $_.platformType }
                                } | Format-IaTable -Color $Accent
                                Read-IaTablePause -Data $cs -Stem "device-$devName-compliance" -Color $Accent
                            }
                            'Compliance failures*' {
                                $cf = @(Invoke-IaStatus -Spinner Dots -Title 'Loading failing compliance settings…' -ScriptBlock {
                                    Get-IntuneDeviceComplianceDetail -Device $devName -FailingOnly
                                })
                                if (-not $cf) { Write-IaHost "[$Accent]✓ No failing settings — the device meets every assigned compliance policy.[/]"; Read-IaPause | Out-Null }
                                else {
                                    $rows = $cf | ForEach-Object {
                                        $sc = if ("$($_.State)" -in 'compliant') { $Accent } elseif ("$($_.State)" -in 'noncompliant','nonCompliant','error') { 'coral' } else { 'yellow' }
                                        [pscustomobject][ordered]@{
                                            Policy  = $_.Policy
                                            Setting = $_.Setting
                                            State   = "[$sc]$($_.State)[/]"
                                            Current = $_.CurrentValue
                                            Error   = $_.ErrorCode
                                        }
                                    }
                                    Read-IaTablePause -Data $rows -Stem "device-$devName-compfail" -Color $Accent -Title "Compliance failures · $devName ($($cf.Count))"
                                }
                            }
                            'Configuration profile*' {
                                $cfg = @(Invoke-IaStatus -Spinner Dots -Title 'Loading config states…' -ScriptBlock {
                                    (Get-IntuneDeviceDetail -Device $devName -IncludeConfigState).ConfigStates
                                })
                                $cfg | ForEach-Object {
                                    $sc = if ($_.state -eq 'compliant') { $Accent } elseif ($_.state -in 'error','conflict') { 'coral' } else { 'grey' }
                                    [pscustomobject][ordered]@{ Profile = $_.displayName; State = "[$sc]$($_.state)[/]"; Version = $_.version }
                                } | Format-IaTable -Color $Accent
                                Read-IaTablePause -Data $cfg -Stem "device-$devName-config" -Color $Accent
                            }
                            'Configuration conflict*' {
                                $cc = @(Invoke-IaStatus -Spinner Dots -Title 'Looking for configuration conflicts…' -ScriptBlock {
                                    Get-IntuneDeviceConfigConflict -Device $devName
                                })
                                if (-not $cc) { Write-IaHost "[$Accent]✓ No conflicts — no two profiles disagree on a setting for this device.[/]"; Read-IaPause | Out-Null }
                                else {
                                    $rows = $cc | ForEach-Object {
                                        [pscustomobject][ordered]@{
                                            Setting  = $_.Setting
                                            State    = "[coral]$($_.State)[/]"
                                            Profiles = "[yellow]$($_.Profiles)[/]"
                                            Value    = $_.CurrentValue
                                        }
                                    }
                                    Read-IaTablePause -Data $rows -Stem "device-$devName-conflicts" -Color $Accent -Title "Configuration conflicts · $devName ($($cc.Count))"
                                }
                            }
                            'Detected apps*' {
                                $apps = @(Invoke-IaStatus -Spinner Dots -Title 'Loading detected apps…' -ScriptBlock {
                                    (Get-IntuneDeviceDetail -Device $devName -IncludeApps).Apps
                                })
                                $apps | Format-IaTable -Color $Accent -Title "Apps on $devName ($($apps.Count))"
                                Read-IaTablePause -Data $apps -Stem "device-$devName-apps" -Color $Accent
                            }
                            'Managed apps*' {
                                $mapps = @(Invoke-IaStatus -Spinner Dots -Title 'Loading managed apps…' -ScriptBlock {
                                    Get-IntuneDeviceManagedApp -Device $devName
                                })
                                if (-not $mapps) { Write-IaHost '[yellow]No Intune-managed apps reported for this device (or no primary user).[/]'; Read-IaPause | Out-Null }
                                else {
                                    $rows = $mapps | ForEach-Object {
                                        $sc = switch ("$($_.State)") { 'installed' { $Accent } 'failed' { 'coral' } 'pending' { 'yellow' } default { 'grey' } }
                                        [pscustomobject][ordered]@{ App = $_.App; Intent = $_.Intent; State = "[$sc]$($_.State)[/]"; Version = $_.Version }
                                    }
                                    Read-IaTablePause -Data $rows -Stem "device-$devName-managedapps" -Color $Accent -Title "Managed apps · $devName ($($mapps.Count))"
                                }
                            }
                            'Group memberships*' {
                                $grps = @(Invoke-IaStatus -Spinner Dots -Title 'Loading group memberships…' -ScriptBlock {
                                    Get-IntuneDeviceGroupMembership -Device $devName
                                })
                                if (-not $grps) { Write-IaHost '[yellow]Device is not a member of any Entra group (or name did not resolve).[/]'; Read-IaPause | Out-Null }
                                else {
                                    $rows = $grps | ForEach-Object {
                                        [pscustomobject][ordered]@{
                                            Group = $_.GroupName
                                            Type  = if ($_.MembershipRule) { '[deepskyblue1]dynamic[/]' } else { '[grey]assigned[/]' }
                                            Rule  = $_.MembershipRule
                                        }
                                    }
                                    Read-IaTablePause -Data $rows -Stem "device-$devName-groups" -Color $Accent -Title "Group memberships · $devName ($($grps.Count))"
                                }
                            }
                            'BitLocker*' {
                                $bk = @(Invoke-IaStatus -Spinner Dots -Title 'Loading BitLocker recovery keys…' -ScriptBlock {
                                    Get-IntuneBitLockerKey -Device $devName
                                })
                                if (-not $bk) { Write-IaHost '[yellow]No BitLocker recovery keys escrowed for this device.[/]'; Read-IaPause | Out-Null }
                                else { Read-IaTablePause -Data $bk -Stem "device-$devName-bitlocker" -Color $Accent -Title "BitLocker recovery keys · $devName" }
                            }
                            'LAPS*' {
                                $laps = @(Invoke-IaStatus -Spinner Dots -Title 'Loading LAPS credential…' -ScriptBlock {
                                    Get-IntuneLapsCredential -Device $devName
                                })
                                if (-not $laps) { Write-IaHost '[yellow]No Windows LAPS credential backed up for this device.[/]'; Read-IaPause | Out-Null }
                                else { Read-IaTablePause -Data $laps -Stem "device-$devName-laps" -Color $Accent -Title "LAPS local admin · $devName" }
                            }
                            'Device actions*' {
                                $actLabels = [ordered]@{
                                    'Sync (check in now)'   = 'Sync'
                                    'Reboot'                = 'Reboot'
                                    'Remote lock'           = 'RemoteLock'
                                    'Rotate BitLocker keys' = 'RotateBitLockerKeys'
                                    'Collect diagnostics'   = 'CollectDiagnostics'
                                    'Defender quick scan'   = 'DefenderScan'
                                    'Cancel'                = $null
                                }
                                $actPick = Read-IaMenu -Title "Action on $devName" -Color $Accent -Choices @($actLabels.Keys)
                                $action  = if ($actPick) { $actLabels[$actPick] } else { $null }
                                if ($action) {
                                    if (Read-IaConfirm "Send '$actPick' to $devName?") {
                                        try {
                                            Invoke-IntuneDeviceAction -Device $devName -Action $action -Confirm:$false | Out-Null
                                            Write-IaHost "[$Accent]✓ $actPick sent to $devName.[/]"
                                        } catch { Write-IaHost "[red]Failed:[/] $($_.Exception.Message)" }
                                        Read-IaPause | Out-Null
                                    }
                                }
                            }
                          }
                        }
                    }
            }
        }
        'User lookup*' {
            $upn = Read-IaText -Question 'User principal name (UPN), e.g. jdoe@contoso.com'
            if ([string]::IsNullOrWhiteSpace($upn)) { return }
            $stemU = ($upn -replace '[^\w.-]', '_')
            Write-IaTuiHeader -Screen 'User lookup' -Sub $upn -Accent $Accent

            # Pull the full help-desk profile once — managed devices, Entra group
            # memberships and assigned licenses (groups + licenses come from the beta
            # /users endpoints). Cached so each drill-in renders instantly and the
            # "Overview" can show all three together.
            $prof = Invoke-IaStatus -Spinner Dots -Title "Building help-desk profile for $upn…" -ScriptBlock {
                [pscustomobject]@{
                    Devices  = @(Get-IntuneUserDevice          -User $upn)
                    Groups   = @(Get-IntuneUserGroupMembership -User $upn)
                    Licenses = @(Get-IntuneUserLicense         -User $upn)
                }
            }
            $uDevices  = @($prof.Devices)
            $uGroups   = @($prof.Groups)
            $uLicenses = @($prof.Licenses)
            $compliant = @($uDevices | Where-Object { "$($_.Compliance)" -eq 'compliant' }).Count

            $hdr = [System.Collections.Generic.List[string]]::new()
            $hdr.Add((ConvertFrom-IaMarkup "[$Accent]≈ TIDE[/]  [bold]· User lookup[/]"))
            $hdr.Add((ConvertFrom-IaMarkup "[grey]$upn[/]"))
            $hdr.Add('')
            $hdr.Add((ConvertFrom-IaMarkup ("[grey]{0,-10}[/] [white]{1}[/]  [grey]({2} compliant)[/]" -f 'Devices',  $uDevices.Count, $compliant)))
            $hdr.Add((ConvertFrom-IaMarkup ("[grey]{0,-10}[/] [white]{1}[/]" -f 'Groups',   $uGroups.Count)))
            $hdr.Add((ConvertFrom-IaMarkup ("[grey]{0,-10}[/] [white]{1}[/]" -f 'Licenses', $uLicenses.Count)))
            $hdr.Add('')
            $userHeader = ($hdr -join "`n")

            # Display projections (built once) — shared by Overview and the individual
            # scrollable views so colouring stays consistent.
            $devRows = @($uDevices | ForEach-Object {
                $cc = switch ("$($_.Compliance)") { 'compliant' { $Accent } 'noncompliant' { 'coral' } default { 'grey' } }
                [pscustomobject][ordered]@{
                    Device     = $_.Device
                    OS         = "[$Accent]$($_.OS)[/]"
                    Compliance = "[$cc]$($_.Compliance)[/]"
                    Owner      = $_.Owner
                    Model      = $_.Model
                    Serial     = $_.Serial
                    Encrypted  = if ($_.Encrypted) { "[$Accent]yes[/]" } else { '[coral]no[/]' }
                    LastSync   = $_.LastSync
                }
            })
            $grpRows = @($uGroups | ForEach-Object {
                [pscustomobject][ordered]@{
                    Group      = $_.GroupName
                    Kind       = $_.Kind
                    Membership = if ($_.Membership -eq 'dynamic') { '[deepskyblue1]dynamic[/]' } else { '[grey]assigned[/]' }
                    Rule       = $_.MembershipRule
                }
            })
            $licRows = @($uLicenses | ForEach-Object {
                [pscustomobject][ordered]@{
                    License       = "[$Accent]$($_.License)[/]"
                    SkuPartNumber = $_.SkuPartNumber
                    Services      = $_.Services
                    Disabled      = if ($_.DisabledPlans) { "[yellow]$($_.DisabledPlans)[/]" } else { '' }
                }
            })

            while ($true) {
                $sub = Read-IaMenu -Title 'Help desk · user' -Color $Accent -Header $userHeader -PageSize 7 -Choices @(
                    'Overview — devices · groups · licenses (everything)',
                    'Devices (managed by Intune)',
                    'Group memberships (Entra)',
                    'Licenses (assigned SKUs + service plans)',
                    'Sign-in & MFA diagnostics (why can''t they log in)',
                    'Back'
                )
                if (-not $sub -or $sub -eq 'Back') { break }
                switch -Wildcard ($sub) {
                    'Overview*' {
                        Write-IaTuiHeader -Screen 'User profile' -Sub $upn -Accent $Accent
                        Write-IaHost ("[$Accent]$($uDevices.Count)[/] device(s)  ·  [$Accent]$($uGroups.Count)[/] group(s)  ·  [$Accent]$($uLicenses.Count)[/] license(s)  [grey]for $upn[/]")
                        Write-IaRule -Title "Devices ($($uDevices.Count))" -Color $Accent
                        if ($devRows) { $devRows | Format-IaTable -Color $Accent } else { Write-IaHost '[grey]none[/]' }
                        Write-IaRule -Title "Group memberships ($($uGroups.Count))" -Color $Accent
                        if ($grpRows) { $grpRows | Format-IaTable -Color $Accent } else { Write-IaHost '[grey]none[/]' }
                        Write-IaRule -Title "Licenses ($($uLicenses.Count))" -Color $Accent
                        if ($licRows) { $licRows | Format-IaTable -Color $Accent } else { Write-IaHost '[grey]none[/]' }
                        Read-IaPause | Out-Null
                    }
                    'Devices*' {
                        if (-not $uDevices) { Write-IaHost '[yellow]No Intune-managed devices found for this user.[/]'; Read-IaPause | Out-Null }
                        else { Read-IaTablePause -Data $devRows -Stem "user-$stemU-devices" -Color $Accent -Title "Devices · $upn ($($uDevices.Count))" }
                    }
                    'Group memberships*' {
                        if (-not $uGroups) { Write-IaHost '[yellow]User is not a member of any Entra group.[/]'; Read-IaPause | Out-Null }
                        else { Read-IaTablePause -Data $grpRows -Stem "user-$stemU-groups" -Color $Accent -Title "Group memberships · $upn ($($uGroups.Count))" }
                    }
                    'Licenses*' {
                        if (-not $uLicenses) { Write-IaHost '[yellow]No licenses assigned to this user.[/]'; Read-IaPause | Out-Null }
                        else { Read-IaTablePause -Data $licRows -Stem "user-$stemU-licenses" -Color $Accent -Title "Licenses · $upn ($($uLicenses.Count))" }
                    }
                    'Sign-in*' {
                        $si = @(Invoke-IaStatus -Spinner Dots -Title "Loading recent sign-ins for $upn…" -ScriptBlock {
                            Get-IntuneUserSignIn -User $upn -Top 20
                        })
                        if (-not $si) { Write-IaHost '[yellow]No sign-in records returned (needs AuditLog.Read.All + Entra ID P1).[/]' }
                        else {
                            # Curated columns for the on-screen table; the cmdlet keeps CA / IP /
                            # client / device too — press `e` in the viewer to export the lot.
                            $rows = $si | ForEach-Object {
                                $sc = if ("$($_.Status)" -like 'success*') { $Accent } else { 'coral' }
                                [pscustomobject][ordered]@{
                                    When    = $_.When
                                    App     = $_.App
                                    Status  = "[$sc]$($_.Status)[/]"
                                    Reason  = $_.Reason
                                    Blocked = if ($_.BlockedBy) { "[coral]$($_.BlockedBy)[/]" } else { '' }
                                }
                            }
                            Read-IaTablePause -Data $rows -Stem "user-$stemU-signins" -Color $Accent -Title "Recent sign-ins · $upn ($($si.Count))"
                        }
                        # MFA methods are rendered AFTER the table viewer so its full-screen
                        # repaint can't wipe them.
                        $mfa = @(Invoke-IaStatus -Spinner Dots -Title 'Loading registered MFA methods…' -ScriptBlock {
                            Get-IntuneUserAuthMethod -User $upn
                        })
                        Write-IaRule -Title "Registered MFA methods ($($mfa.Count))" -Color $Accent
                        if (-not $mfa) { Write-IaHost '[coral]No methods registered — the user has no MFA method on file.[/]' }
                        else {
                            $mfa | ForEach-Object { [pscustomobject][ordered]@{ Method = "[$Accent]$($_.Method)[/]"; Detail = $_.Detail } } | Format-IaTable -Color $Accent
                        }
                        Read-IaPause | Out-Null
                    }
                }
            }
        }
        'App install*' {
            $app = Select-IaInventoryItem -Accent $Accent -Area 'Apps' -Title 'Which app?'
            if (-not $app) { return }
            $by  = Read-IaMenu -Title 'Pivot by' -Choices @('Device', 'User') -Color $Accent
            Write-IaTuiHeader -Screen 'App install status' -Sub "app: $($app.Name)  ·  by: $by" -Accent $Accent
            $name = $app.Name
            $rows = Invoke-IaStatus -Spinner Dots -Title "Querying $name…" -ScriptBlock {
                Get-IntuneAppInstallStatus -App $name -By $by
            }
            if ($by -eq 'Device') {
                $displayRows = @($rows | ForEach-Object {
                    $sc = switch ($_.Status) {
                        'installed' { $Accent } 'failed' { 'coral' } 'pending' { 'yellow' } default { 'grey' }
                    }
                    [pscustomobject][ordered]@{
                        Device = $_.Device; Status = "[$sc]$($_.Status)[/]"
                        Detail = $_.Detail; ErrorCode = $_.ErrorCode; User = $_.User
                    }
                })
                $displayRows | Format-IaTable -Color $Accent
            } else {
                $rows | Format-IaTable -Color $Accent
            }
            Read-IaTablePause -Data $rows -Stem "app-install-$($name -replace '\s+','-')" -Color $Accent
            # Remediation hints AFTER the table view so the viewer's repaint can't wipe them.
            if ($by -eq 'Device') {
                $failHints = @($rows | Where-Object { $_.Hint })
                if ($failHints) {
                    Write-IaRule -Title 'Remediation hints' -Color $Accent
                    foreach ($fh in $failHints | Select-Object -First 5) {
                        Write-IaHost "[$Accent]$($fh.ErrorCode)[/]  $($fh.ErrorReason)"
                        Write-IaHost "  [grey]→ $($fh.Hint)[/]"
                    }
                }
            }
        }
        'Configuration*' {
            $p = Select-IaInventoryItem -Accent $Accent -Area 'Configuration' -Title 'Which configuration profile?'
            if (-not $p) { return }
            Write-IaTuiHeader -Screen 'Configuration profile status' -Sub "profile: $($p.Name)" -Accent $Accent
            $rows = @(Invoke-IaStatus -Spinner Dots -Title 'Loading profile status…' -ScriptBlock {
                Get-IntuneConfigurationStatus -Profile $p.Name
            })
            $rows | Format-IaTable -Color $Accent
            Read-IaTablePause -Data $rows -Stem "config-$($p.Name -replace '\s+','-')" -Color $Accent
        }
        'Compliance*' {
            $mode = Read-IaMenu -Title 'Compliance by' -Choices @('Tenant summary', 'Policy', 'Device') -Color $Accent
            Write-IaTuiHeader -Screen 'Compliance status' -Sub $mode.ToLower() -Accent $Accent
            $rows = @(switch -Wildcard ($mode) {
                'Policy'  {
                    $pol = Select-IaInventoryItem -Accent $Accent -Area 'Compliance' -Title 'Which compliance policy?'
                    if ($pol) { Get-IntuneComplianceStatus -Policy $pol.Name }
                }
                'Device'  { Get-IntuneComplianceStatus -Device (Read-IaText -Question 'Device name') }
                default   { Get-IntuneComplianceStatus }
            })
            if ($mode -eq 'Policy' -or $mode -eq 'Device') {
                # Colour-grade the Status/State column
                $displayRows = @($rows | ForEach-Object {
                    $sc = if ($_.Status -eq 'compliant' -or $_.State -eq 'compliant') { $Accent }
                          elseif ($_.Status -in 'noncompliant','error' -or $_.State -in 'noncompliant','error') { 'coral' }
                          else { 'grey' }
                    $r = $_ | Select-Object *
                    if ($r.Status) { $r.Status = "[$sc]$($r.Status)[/]" }
                    if ($r.State)  { $r.State  = "[$sc]$($r.State)[/]"  }
                    $r
                })
                $displayRows | Format-IaTable -Color $Accent
            } else {
                $rows | Format-IaTable -Color $Accent
            }
            Read-IaTablePause -Data $rows -Stem "compliance-$mode" -Color $Accent
        }
        'Deployment*' {
            $scope = Read-IaMenu -Title 'Scope' -Color $Accent -Choices @('All resources', 'Scope to a group')
            $grp   = $null
            if ($scope -like 'Scope*') { $grp = (Select-IaGroup -Accent $Accent -Title 'Scope to group').DisplayName }
            Write-IaTuiHeader -Screen 'Deployment summary' `
                -Sub "for everything assigned to '$(if ($grp) { $grp } else { 'all resources' })'" -Accent $Accent
            $data = @(Invoke-IaStatus -Spinner Dots -Title 'Rolling up deployment health…' -ScriptBlock {
                if ($grp) { Get-IntuneDeploymentSummary -Group $grp }
                else       { Get-IntuneDeploymentSummary }
            })
            if (-not $data) { Write-IaHost '[yellow]No deployment data found.[/]'; Read-IaPause | Out-Null; return }

            # Show summary table
            $displayData = @($data | ForEach-Object {
                $fr      = [double]$_.FailRate
                $frColor = if ($fr -gt 15) { 'coral' } elseif ($fr -gt 5) { 'yellow' } else { $Accent }
                [pscustomobject][ordered]@{
                    Area     = "[$Accent]$($_.Area)[/]"
                    Resource = $_.Resource
                    OK       = $_.Success
                    FAIL     = if ($_.Failed -gt 0) { "[coral]$($_.Failed)[/]" } else { '0' }
                    PEND     = $_.Pending
                    TOTAL    = $_.Total
                    'FAIL%'  = "[$frColor]$($_.FailRate)[/]"
                }
            })
            # Selectable summary — scroll, / search, e export; Enter or click a row to
            # drill into its per-device status. FAIL% is colour-graded in-table
            # (coral >15% · amber >5%). Was: dump + a menu of abbreviated row strings.
            while ($true) {
                $picked = Read-IaTableInteractive -Data $displayData -Color $Accent `
                    -Title "Deployment summary ($($data.Count))" -Stem 'deployment-summary' -Selectable
                if (-not $picked) { break }
                $idx = [array]::IndexOf($displayData, $picked)
                if ($idx -ge 0 -and $idx -lt $data.Count) {
                    Invoke-IaTuiPolicyDeviceDrilldown -Accent $Accent -Row $data[$idx]
                }
            }
        }
        'Custom report*' {
            Invoke-IaTuiReportBuilder -Accent $Accent
        }
        'Audit*' {
            $since = Read-IaText -Question 'Since (e.g. 7d, 24h)' -DefaultAnswer '7d'
            $act   = Read-IaText -Question 'Activity contains (blank = any)' -DefaultAnswer ''
            Write-IaTuiHeader -Screen 'Audit log' -Sub "since $since$(if ($act) { "  ·  activity: $act" })" -Accent $Accent
            $p = @{ Since = $since }; if ($act) { $p.Activity = $act }
            $rows = @(Get-IntuneAuditLog @p | Select-Object -First 50)
            $rows | Format-IaTable -Color $Accent
            Read-IaTablePause -Data $rows -Stem 'audit-log' -Color $Accent
        }
        'Multi Admin*' {
            Write-IaTuiHeader -Screen 'Multi Admin Approval requests' -Accent $Accent
            $rows = @(Get-IntuneApprovalRequest)
            $rows | Format-IaTable -Color $Accent
            Read-IaTablePause -Data $rows -Stem 'approval-requests' -Color $Accent
        }
        'PIM*' {
            Write-IaTuiHeader -Screen 'PIM activations' -Accent $Accent
            $rows = @(Get-IntunePimActivation)
            $rows | Format-IaTable -Color $Accent
            Read-IaTablePause -Data $rows -Stem 'pim-activations' -Color $Accent
        }
        'Run any*' {
            $name = Read-IaSelection -Title 'Pick a report' -Color $Accent `
                -Choices (@(Get-IntuneReportCatalog | ForEach-Object Name) + 'Other (type a name)')
            if ($name -like 'Other*') { $name = Read-IaText -Question 'Report name' }
            Write-IaTuiHeader -Screen "Report: $name" -Accent $Accent
            $rows = @(Invoke-IaStatus -Spinner Dots -Title "Running $name…" -ScriptBlock {
                Export-IntuneReport -Name $name
            } | Select-Object -First 100)
            $rows | Format-IaTable -Color $Accent
            Read-IaTablePause -Data $rows -Stem "report-$($name -replace '\s+','-')" -Color $Accent
        }
        default { return }
    }
}

# ─── deployment summary drill-down ───────────────────────────────────────────
function Invoke-IaTuiPolicyDeviceDrilldown {
    param([string]$Accent, [pscustomobject]$Row)
    $area = $Row.Area
    $name = $Row.Resource
    Write-IaTuiHeader -Screen 'Device status' -Sub "$area · $name" -Accent $Accent
    $rows = @(Invoke-IaStatus -Spinner Dots -Title "Loading per-device status for $name…" -ScriptBlock {
        switch ($area) {
            'Compliance'    { Get-IntuneComplianceStatus -Policy $name }
            'Configuration' { Get-IntuneConfigurationStatus -Profile $name }
            'Apps'          { Get-IntuneAppInstallStatus -App $name -By Device }
            default {
                Write-IaHost "[yellow]Device-level drill-down is not yet available for '$area'.[/]"
                @()
            }
        }
    })
    if (-not $rows) { Write-IaHost "[yellow]No device data returned.[/]"; Read-IaPause | Out-Null; return }
    $displayRows = @($rows | ForEach-Object {
        $statusVal = $_.Status ?? $_.State ?? $_.status ?? $_.state ?? ''
        $sc = switch ($statusVal) {
            { $_ -in 'compliant','installed','success' } { $Accent }
            { $_ -in 'noncompliant','failed','error'   } { 'coral'  }
            { $_ -in 'pending','inGracePeriod'         } { 'yellow' }
            default { 'grey' }
        }
        $r = [ordered]@{}
        foreach ($p in $_.PSObject.Properties) {
            $v = "$($p.Value)"
            if ($p.Name -in 'Status','State','status','state' -and $v) {
                $r[$p.Name] = "[$sc]$v[/]"
            } else {
                $r[$p.Name] = $v
            }
        }
        [pscustomobject]$r
    })
    $displayRows | Format-IaTable -Color $Accent -Title "Devices ($($rows.Count))"
    Read-IaTablePause -Data $rows -Stem "$($area.ToLower())-$($name -replace '\s+','-')-devices" -Color $Accent
}

# ─── custom report builder ────────────────────────────────────────────────────

function Get-IaReportSources {
    # Named data sources for the custom report builder. Each: a loader scriptblock
    # plus the equivalent cmdlet text shown in "Show as PowerShell".
    [ordered]@{
        'Managed devices'        = @{ Cmd = 'Get-IntuneDeviceInventory'; Load = { Get-IntuneDeviceInventory } }
        'Apps (all)'             = @{ Cmd = 'Get-IntuneApp';             Load = { Get-IntuneApp } }
        'Win32 apps'             = @{ Cmd = 'Get-IntuneWin32App';        Load = { Get-IntuneWin32App } }
        'Assignments (inventory)'= @{ Cmd = 'Get-IntuneAssignment';      Load = {
            @(Get-IaTuiInventory | ForEach-Object {
                $assigns = @($_.Assignments)
                [pscustomobject][ordered]@{
                    Area          = $_.Area
                    ResourceType  = $_.ResourceType
                    Name          = $_.Name
                    Platform      = $_.Platform
                    AssignedCount = $assigns.Count
                    AssignedTo    = (@($assigns | ForEach-Object { Get-IaTargetDisplay -Target $_.Target }) -join '; ')
                    Id            = $_.Id
                }
            })
        } }
        'Deployment summary'     = @{ Cmd = 'Get-IntuneDeploymentSummary'; Load = { Get-IntuneDeploymentSummary } }
        'Cloud PCs'              = @{ Cmd = 'Get-IntuneCloudPC';           Load = { Get-IntuneCloudPC } }
        'Configuration policies' = @{ Cmd = 'Get-IntuneConfigurationPolicy'; Load = { Get-IntuneConfigurationPolicy } }
        'Compliance policies'    = @{ Cmd = 'Get-IntuneCompliancePolicy';  Load = { Get-IntuneCompliancePolicy } }
        'Audit log (7d)'         = @{ Cmd = 'Get-IntuneAuditLog -Since 7d'; Load = { Get-IntuneAuditLog -Since 7d } }
    }
}

function Get-IaReportCommandText {
    # Render a recipe as the equivalent PowerShell pipeline (display only).
    param([string]$Cmd, $Recipe)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append($Cmd)
    $wheres = @($Recipe.Where | Where-Object { $_ -and $_.Prop })
    if ($wheres.Count -gt 0) {
        $clauses = foreach ($f in $wheres) {
            $p = "`$_.$($f.Prop)"
            switch ($f.Op) {
                'eq'          { "$p -eq '$($f.Val)'" }
                'ne'          { "$p -ne '$($f.Val)'" }
                'contains'    { "$p -like '*$($f.Val)*'" }
                'notcontains' { "$p -notlike '*$($f.Val)*'" }
                'startswith'  { "$p -like '$($f.Val)*'" }
                'endswith'    { "$p -like '*$($f.Val)'" }
                'like'        { "$p -like '$($f.Val)'" }
                'match'       { "$p -match '$($f.Val)'" }
                'gt'          { "$p -gt '$($f.Val)'" }
                'ge'          { "$p -ge '$($f.Val)'" }
                'lt'          { "$p -lt '$($f.Val)'" }
                'le'          { "$p -le '$($f.Val)'" }
                'isempty'     { "[string]::IsNullOrWhiteSpace($p)" }
                'notempty'    { "-not [string]::IsNullOrWhiteSpace($p)" }
                'istrue'      { "$p -eq `$true" }
                'isfalse'     { "$p -ne `$true" }
                default       { $p }
            }
        }
        [void]$sb.Append(" |`n  Where-Object { " + ($clauses -join ' -and ') + ' }')
    }
    if ($Recipe.GroupBy) {
        [void]$sb.Append(" |`n  Group-Object $($Recipe.GroupBy)")
        if ($Recipe.Agg -and $Recipe.Agg.Func -and $Recipe.Agg.Func -ne 'Count' -and $Recipe.Agg.Prop) {
            $a = $Recipe.Agg
            [void]$sb.Append(" |`n  Select-Object Name, Count, @{n='$($a.Func)($($a.Prop))';e={(`$_.Group | Measure-Object $($a.Prop) -$($a.Func)).$($a.Func)}}")
        } else {
            [void]$sb.Append(" |`n  Select-Object Name, Count")
        }
    }
    $sorts = @($Recipe.Sort | Where-Object { $_ -and $_.Prop })
    if ($sorts.Count -gt 0) {
        $sortStr = (@($sorts | ForEach-Object { $_.Prop }) -join ', ')
        $desc = if ($sorts[0].Desc) { ' -Descending' } else { '' }
        [void]$sb.Append(" |`n  Sort-Object $sortStr$desc")
    }
    if (-not $Recipe.GroupBy -and @($Recipe.Select).Count -gt 0) {
        [void]$sb.Append(" |`n  Select-Object " + (@($Recipe.Select) -join ', '))
    }
    if ([int]$Recipe.Top -gt 0) { [void]$sb.Append(" |`n  Select-Object -First $($Recipe.Top)") }
    $sb.ToString()
}

function Get-IaReportPanel {
    # Build the recipe-summary header repainted above the builder menu each frame.
    param([string]$Accent, [string]$SourceName, [int]$RowCount, $Recipe)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add((ConvertFrom-IaMarkup "[$Accent]≈ TIDE[/]  [bold]· Custom report builder[/]"))
    $lines.Add((ConvertFrom-IaMarkup "[grey]build a report: select · where · sort · group · export[/]"))
    $lines.Add((ConvertFrom-IaMarkup ("[darkslategray1]" + ('─' * [Math]::Min(96, [Math]::Max(40, (Get-IaInnerWidth)))) + '[/]')))

    $cols = if (@($Recipe.Select).Count -gt 0) { (@($Recipe.Select) -join ', ') } else { '(all)' }
    $filt = if (@($Recipe.Where | Where-Object { $_ -and $_.Prop }).Count -gt 0) {
        (@($Recipe.Where | Where-Object { $_ -and $_.Prop } | ForEach-Object {
            $v = if ($_.Op -in 'isempty','notempty','istrue','isfalse') { '' } else { " $($_.Val)" }
            "$($_.Prop) $($_.Op)$v"
        }) -join '  ·  ')
    } else { '(none)' }
    $sort = if (@($Recipe.Sort | Where-Object { $_ -and $_.Prop }).Count -gt 0) {
        (@($Recipe.Sort | Where-Object { $_ -and $_.Prop } | ForEach-Object {
            "$($_.Prop) $(if ($_.Desc) { '↓' } else { '↑' })"
        }) -join ', ')
    } else { '(none)' }
    $grp = if ($Recipe.GroupBy) {
        $g = $Recipe.GroupBy
        if ($Recipe.Agg -and $Recipe.Agg.Func -and $Recipe.Agg.Func -ne 'Count' -and $Recipe.Agg.Prop) {
            "$g  +  $($Recipe.Agg.Func)($($Recipe.Agg.Prop))"
        } else { "$g  (count)" }
    } else { '(none)' }
    $top = if ([int]$Recipe.Top -gt 0) { "$($Recipe.Top)" } else { 'all' }

    $lines.Add((ConvertFrom-IaMarkup ("[grey]{0,-9}[/] [$Accent]{1}[/]  [grey]({2} rows)[/]" -f 'Source', $SourceName, $RowCount)))
    $lines.Add((ConvertFrom-IaMarkup ("[grey]{0,-9}[/] {1}" -f 'Columns', $cols)))
    $lines.Add((ConvertFrom-IaMarkup ("[grey]{0,-9}[/] {1}" -f 'Filter',  $filt)))
    $lines.Add((ConvertFrom-IaMarkup ("[grey]{0,-9}[/] {1}" -f 'Sort',    $sort)))
    $lines.Add((ConvertFrom-IaMarkup ("[grey]{0,-9}[/] {1}" -f 'Group',   $grp)))
    $lines.Add((ConvertFrom-IaMarkup ("[grey]{0,-9}[/] {1}" -f 'Top',     $top)))
    $lines.Add('')
    return ($lines -join "`n")
}

function Invoke-IaTuiReportBuilder {
    param([string]$Accent)

    $sources   = Get-IaReportSources
    $srcName   = @($sources.Keys)[0]
    $recipe    = @{ Select = @(); Where = @(); Sort = @(); GroupBy = $null; Agg = $null; Top = 0 }
    $raw       = $null
    $props     = @()

    $loadSource = {
        param($Name)
        Write-IaTuiHeader -Screen 'Custom report builder' -Sub "loading '$Name'…" -Accent $Accent
        $script:_rptRaw = @(Invoke-IaStatus -Spinner Dots -Title "Loading $Name…" -ScriptBlock {
            & $sources[$Name].Load
        })
        $script:_rptRaw
    }

    # Initial load
    $raw   = & $loadSource $srcName
    $props = @(Get-IaReportProperties -Data $raw)

    while ($true) {
        $panel = Get-IaReportPanel -Accent $Accent -SourceName $srcName -RowCount @($raw).Count -Recipe $recipe
        $pick  = Read-IaMenu -Title 'Action' -Color $Accent -PageSize 16 -Header $panel -Choices @(
            'Data source',
            'Select columns',
            'Add filter',
            'Clear filters',
            'Sort by',
            'Clear sort',
            'Group / aggregate',
            'Top N rows',
            'Run / preview',
            'Export',
            'Show as PowerShell command',
            'Save report definition',
            'Load report definition',
            'Reset recipe',
            'Back'
        )
        switch -Wildcard ($pick) {
            'Data source' {
                $newSrc = Read-IaMenu -Title 'Data source' -Color $Accent -PageSize 12 -Choices @($sources.Keys)
                if ($newSrc -and $newSrc -ne $srcName) {
                    $srcName = $newSrc
                    $raw     = & $loadSource $srcName
                    $props   = @(Get-IaReportProperties -Data $raw)
                    # Reset projection bits that reference old columns.
                    $recipe.Select = @(); $recipe.Where = @(); $recipe.Sort = @()
                    $recipe.GroupBy = $null; $recipe.Agg = $null
                }
            }
            'Select columns' {
                if (-not $props) { Write-IaHost '[yellow]No columns — load data first.[/]'; Read-IaPause; break }
                $chosen = @(Read-IaMultiMenu -Title 'Columns (none = all)' -Color $Accent -PageSize 20 -Choices $props)
                $recipe.Select = $chosen
            }
            'Add filter' {
                if (-not $props) { Write-IaHost '[yellow]No columns to filter.[/]'; Read-IaPause; break }
                $fProp = Read-IaMenu -Title 'Filter which property?' -Color $Accent -PageSize 20 -Choices $props
                if (-not $fProp) { break }
                $opMap = [ordered]@{}
                $opChoices = foreach ($kv in $script:IaReportOperators.GetEnumerator()) {
                    $label = "$($kv.Value)"; $opMap[$label] = $kv.Key; $label
                }
                $opPick = Read-IaMenu -Title "How should '$fProp' compare?" -Color $Accent -PageSize 18 -Choices @($opChoices)
                if (-not $opPick) { break }
                $op = $opMap[$opPick]
                $val = ''
                if ($op -notin 'isempty','notempty','istrue','isfalse') {
                    $val = Read-IaText -Question "Value for $fProp $op"
                }
                $recipe.Where += @{ Prop = $fProp; Op = $op; Val = $val }
            }
            'Clear filters' { $recipe.Where = @() }
            'Sort by' {
                if (-not $props) { Write-IaHost '[yellow]No columns to sort.[/]'; Read-IaPause; break }
                $sProp = Read-IaMenu -Title 'Sort which property?' -Color $Accent -PageSize 20 -Choices $props
                if (-not $sProp) { break }
                $dir = Read-IaMenu -Title 'Direction' -Color $Accent -Choices @('Ascending ↑', 'Descending ↓')
                $recipe.Sort += @{ Prop = $sProp; Desc = ($dir -like 'Desc*') }
            }
            'Clear sort' { $recipe.Sort = @() }
            'Group / aggregate' {
                if (-not $props) { Write-IaHost '[yellow]No columns to group.[/]'; Read-IaPause; break }
                $gProp = Read-IaMenu -Title 'Group by (Back = no grouping)' -Color $Accent -PageSize 20 -Choices (@('(no grouping)') + $props)
                if (-not $gProp -or $gProp -eq '(no grouping)') { $recipe.GroupBy = $null; $recipe.Agg = $null; break }
                $recipe.GroupBy = $gProp
                $func = Read-IaMenu -Title 'Aggregate' -Color $Accent -Choices @('Count only', 'Sum', 'Average', 'Min', 'Max')
                if ($func -eq 'Count only' -or -not $func) {
                    $recipe.Agg = @{ Func = 'Count'; Prop = $null }
                } else {
                    $mProp = Read-IaMenu -Title "Which numeric property to $func?" -Color $Accent -PageSize 20 -Choices $props
                    $fmap = @{ 'Sum'='Sum'; 'Average'='Avg'; 'Min'='Min'; 'Max'='Max' }
                    $recipe.Agg = @{ Func = $fmap[$func]; Prop = $mProp }
                }
            }
            'Top N rows' {
                $n = Read-IaText -Question 'Top N (0 = all)' -DefaultAnswer "$($recipe.Top)"
                $parsed = 0; if ([int]::TryParse($n, [ref]$parsed)) { $recipe.Top = [Math]::Max(0, $parsed) }
            }
            'Run / preview' {
                $result = @(Invoke-IaReportPipeline -Data $raw -Recipe $recipe)
                Write-IaTuiHeader -Screen 'Custom report — preview' -Sub "$srcName  ·  $($result.Count) row(s)" -Accent $Accent
                if (-not $result) {
                    Write-IaHost '[yellow]No rows match the current recipe.[/]'
                } else {
                    @($result | Select-Object -First 200) | Format-IaTable -Color $Accent
                    if ($result.Count -gt 200) {
                        Write-IaHost "[grey]Showing first 200 of $($result.Count) — export for the full set.[/]"
                    }
                    # Wide table → suggest narrowing columns for readability.
                    if (-not $recipe.GroupBy -and @($recipe.Select).Count -eq 0 -and @($props).Count -gt 8) {
                        Write-IaHost "[grey]Tip: $(@($props).Count) columns shown — use [/][$Accent]Select columns[/][grey] to narrow for readability, or [/][$Accent]e[/][grey] to export the full width.[/]"
                    }
                }
                Read-IaTablePause -Data $result -Stem "custom-$($srcName -replace '\W+','-')" -Color $Accent -Title 'Custom report — preview'
            }
            'Export' {
                $result = @(Invoke-IaReportPipeline -Data $raw -Recipe $recipe)
                if (-not $result) { Write-IaHost '[yellow]Nothing to export — recipe returns no rows.[/]'; Read-IaPause; break }
                Invoke-IaExport -Data $result -Stem "custom-$($srcName -replace '\W+','-')" -Color $Accent
                Read-IaPause
            }
            'Show as PowerShell*' {
                Write-IaTuiHeader -Screen 'Custom report — PowerShell' -Sub $srcName -Accent $Accent
                $cmd = Get-IaReportCommandText -Cmd $sources[$srcName].Cmd -Recipe $recipe
                Write-IaHost '[grey]Equivalent command (copy into a script or console):[/]'
                Write-IaHost ''
                # Render raw (no markup parse) so [ ] and | in the command survive intact.
                $reset = Get-IaReset; $fg = Get-IaAnsi $Accent
                Write-IaRaw ($fg + $cmd + $reset)
                Write-IaHost ''
                Read-IaPause
            }
            'Save report definition' {
                $name = Read-IaText -Question 'Report name' -DefaultAnswer 'my-report'
                $safe = ($name -replace '[^\w-]', '-')
                $path = Join-Path ([Environment]::GetFolderPath('UserProfile')) "tide-report-$safe.json"
                $def  = [pscustomobject]@{ Source = $srcName; Recipe = $recipe; SavedBy = 'IntuneTide'; Version = 1 }
                try {
                    $def | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding UTF8
                    Write-IaHost "[$Accent]✓ Saved → $path[/]"
                } catch { Write-IaHost "[coral]Save failed: $($_.Exception.Message)[/]" }
                Read-IaPause
            }
            'Load report definition' {
                $userHome = [Environment]::GetFolderPath('UserProfile')
                $defs = @(Get-ChildItem -Path $userHome -Filter 'tide-report-*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
                $path = $null
                if ($defs) {
                    $choice = Read-IaMenu -Title 'Load which report?' -Color $Accent -PageSize 15 -Choices (@($defs | ForEach-Object { $_.Name }) + 'Type a path…')
                    if ($choice -eq 'Type a path…') { $path = Read-IaText -Question 'Path to .json' }
                    elseif ($choice) { $path = (Join-Path $userHome $choice) }
                } else {
                    $path = Read-IaText -Question 'Path to report .json'
                }
                if ($path -and (Test-Path $path)) {
                    try {
                        $loaded = Get-Content -Path $path -Raw | ConvertFrom-Json
                        if ($loaded.Source -and @($sources.Keys) -contains $loaded.Source) {
                            $srcName = $loaded.Source
                            $raw     = & $loadSource $srcName
                            $props   = @(Get-IaReportProperties -Data $raw)
                        }
                        $r = $loaded.Recipe
                        $recipe = @{
                            Select  = @($r.Select)
                            Where   = @($r.Where  | Where-Object { $_ } | ForEach-Object { @{ Prop = $_.Prop; Op = $_.Op; Val = $_.Val } })
                            Sort    = @($r.Sort   | Where-Object { $_ } | ForEach-Object { @{ Prop = $_.Prop; Desc = [bool]$_.Desc } })
                            GroupBy = $r.GroupBy
                            Agg     = if ($r.Agg -and $r.Agg.Func) { @{ Func = $r.Agg.Func; Prop = $r.Agg.Prop } } else { $null }
                            Top     = [int]$r.Top
                        }
                        Write-IaHost "[$Accent]✓ Loaded $([IO.Path]::GetFileName($path))[/]"
                    } catch { Write-IaHost "[coral]Load failed: $($_.Exception.Message)[/]" }
                } elseif ($path) {
                    Write-IaHost "[coral]Not found: $path[/]"
                }
                Read-IaPause
            }
            'Reset recipe' {
                $recipe = @{ Select = @(); Where = @(); Sort = @(); GroupBy = $null; Agg = $null; Top = 0 }
            }
            'Back' { return }
        }
    }
}

# ─── backup / restore / drift ─────────────────────────────────────────────────

function Invoke-IaTuiBackup {
    param([string]$Accent)
    $pick = Read-IaMenu -Title 'Backup / Restore / Drift' -Color $Accent -PageSize 8 -Choices @(
        'Backup assignments to a file',
        'Backup full config (one file per config)',
        'Restore assignments from a snapshot',
        'Restore full config (from a folder)',
        'Drift — compare current vs a snapshot',
        'Back'
    )
    switch -Wildcard ($pick) {
        'Backup assignments*' {
            $p    = Read-IaSavePath -Prompt 'Save assignment snapshot as' -DefaultName (Get-IaBackupName)
            if (-not $p) { return }   # cancelled
            Write-IaTuiHeader -Screen 'Backup' -Sub "→ $p" -Accent $Accent
            $snap = Backup-IntuneAssignment -Path $p
            Write-IaHost "[$Accent]Backed up[/] $($snap.count) resource(s) → $p"
        }
        'Backup full config*' {
            $p = Read-IaText -Question 'Backup folder' -DefaultAnswer (Get-IaBackupName -Prefix 'intunetide-config' -Extension '')
            Write-IaTuiHeader -Screen 'Full config backup' -Sub "→ $p (one file per config)" -Accent $Accent
            $res = Invoke-IaStatus -Spinner Dots -Title 'Exporting every config…' -ScriptBlock {
                $ProgressPreference = 'SilentlyContinue'
                Backup-IntuneConfig -Path $p
            }
            Write-IaHost "[$Accent]Backed up[/] $($res.Count) config(s) across $(@($res.Areas).Count) area(s) → $($res.Path)"
            Write-IaHost "[grey]Each config is its own JSON, grouped by area, with a manifest.json index.[/]"
        }
        'Drift*' {
            $latest = Find-IaLatestBackup
            $p = if ($latest) { Read-IaText -Question 'Snapshot file to compare against' -DefaultAnswer $latest }
                 else { Read-IaText -Question 'Snapshot file to compare against' }
            Write-IaTuiHeader -Screen 'Drift' -Sub "snapshot: $p" -Accent $Accent
            $d = @(Get-IntuneAssignmentDrift -Path $p)
            if (-not $d) { Write-IaHost "[$Accent]No drift — current state matches the snapshot.[/]"; return }
            Write-IaHost "[$Accent]$($d.Count)[/] drifted assignment target(s):"
            $d | ForEach-Object {
                $changeColor = switch ($_.Change) { 'Added' { $Accent } 'Removed' { 'coral' } default { 'yellow' } }
                [pscustomobject]@{
                    Change   = "[$changeColor]$($_.Change)[/]"
                    Area     = "[$Accent]$($_.Area)[/]"
                    Resource = $_.Resource
                    Target   = $_.Target
                }
            } | Format-IaTable -Color $Accent
            Write-IaHost "[grey]Added = [$Accent]sea-green[/]  ·  Removed = [coral]coral[/]  ·  use Restore to revert[/]"
        }
        'Restore assignments*' {
            $latest = Find-IaLatestBackup
            $p    = if ($latest) { Read-IaText -Question 'Snapshot file to restore' -DefaultAnswer $latest }
                    else { Read-IaText -Question 'Snapshot file to restore' }
            $mode = Read-IaMenu -Title 'Restore mode' -Color $Accent -Choices @('Preview only (no changes)', 'Apply now')
            Write-IaTuiHeader -Screen 'Restore' -Sub "snapshot: $p" -Accent $Accent
            $plans = if ($mode -like 'Apply*') { Restore-IntuneAssignment -Path $p -Confirm:$false }
                     else { Restore-IntuneAssignment -Path $p -WhatIf }
            Show-IaRestorePlan -Plans $plans -Accent $Accent
            if ($mode -like 'Apply*') { $script:IaTuiInventory = $null }
        }
        'Restore full config*' {
            $dir = Find-IaLatestConfigBackup
            $p   = if ($dir) { Read-IaText -Question 'Backup folder to restore' -DefaultAnswer $dir }
                   else { Read-IaText -Question 'Backup folder to restore' }
            $mode = Read-IaMenu -Title 'Restore mode' -Color $Accent -Choices @('Preview only (no changes)', 'Apply now')
            $create = Read-IaMenu -Title 'Re-create configs that were deleted?' -Color $Accent `
                -Choices @('Update existing only', 'Also create missing (where supported)')
            $createMissing = $create -like 'Also create*'
            Write-IaTuiHeader -Screen 'Full config restore' -Sub "folder: $p" -Accent $Accent
            $apply = $mode -like 'Apply*'
            $plans = Invoke-IaStatus -Spinner Dots -Title 'Restoring configs…' -ScriptBlock {
                if ($apply) { Restore-IntuneConfig -Path $p -CreateMissing:$createMissing -Confirm:$false }
                else { Restore-IntuneConfig -Path $p -CreateMissing:$createMissing -WhatIf }
            }
            Show-IaRestorePlan -Plans $plans -Accent $Accent
            if (-not $apply) { Write-IaHost "[grey]Preview only — re-run and choose 'Apply now' to write.[/]" }
            if ($apply) { $script:IaTuiInventory = $null }
        }
        default { return }
    }
}

# ─── export report ────────────────────────────────────────────────────────────

function Invoke-IaTuiExport {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Export report' -Sub 'HTML · Excel · Rich HTML' -Accent $Accent
    $fmt = Read-IaMenu -Title 'Export format' -Color $Accent -Choices @(
        'Built-in HTML (themed, no dependencies)',
        'Excel workbook (ImportExcel)',
        'Rich interactive HTML (PSWriteHTML)'
    )
    switch -Wildcard ($fmt) {
        'Built-in*' {
            $p = Read-IaSavePath -Prompt 'Save HTML report as' -DefaultName 'intune-assignments.html'
            if (-not $p) { return }   # cancelled in the native dialog
            New-IaHtmlReport -Items (Get-IaTuiInventory) | Set-Content -Path $p -Encoding utf8
            Write-IaHost "[$Accent]Wrote[/] $p"
        }
        'Excel*' {
            if (-not (Get-Command Export-Excel -ErrorAction SilentlyContinue)) {
                Write-IaHost "[yellow]ImportExcel not installed.[/] Install-Module ImportExcel -Scope CurrentUser"; return
            }
            $p = Read-IaSavePath -Prompt 'Save Excel workbook as' -DefaultName 'intune-assignments.xlsx'
            if (-not $p) { return }
            Get-IntuneAssignment -Flat | Export-IntuneExcel -Path $p -WorksheetName Assignments -Title 'Intune assignments'
            Write-IaHost "[$Accent]Wrote[/] $p"
        }
        'Rich*' {
            if (-not (Get-Command New-HTML -ErrorAction SilentlyContinue)) {
                Write-IaHost "[yellow]PSWriteHTML not installed.[/] Install-Module PSWriteHTML -Scope CurrentUser"; return
            }
            $p = Read-IaSavePath -Prompt 'Save rich HTML report as' -DefaultName 'intune-assignments-rich.html'
            if (-not $p) { return }
            Export-IntuneHtmlReport -Path $p
            Write-IaHost "[$Accent]Wrote[/] $p"
        }
    }
}

# ─── Windows 365 / Cloud PC ───────────────────────────────────────────────────

function Invoke-IaTuiCloudPC {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Windows 365 Cloud PCs' -Sub 'browse · actions · policies · connections' -Accent $Accent
    $pick = Read-IaMenu -Title 'Windows 365' -Color $Accent -PageSize 12 -Choices @(
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
            $pcs = Invoke-IaStatus -Spinner Dots -Title 'Loading Cloud PCs…' -ScriptBlock {
                Get-IntuneCloudPC
            }
            if (-not $pcs) { Write-IaHost '[grey]No Cloud PCs found.[/]'; return }
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
            $pcs = Invoke-IaStatus -Spinner Dots -Title 'Loading Cloud PCs…' -ScriptBlock { Get-IntuneCloudPC }
            if (-not $pcs) { Write-IaHost '[grey]No Cloud PCs found.[/]'; return }
            $pcNames = @($pcs | ForEach-Object { $_.CloudPC })
            $pcName = Read-IaMenu -Title 'Select Cloud PC' -Choices $pcNames -Color $Accent
            $action = Read-IaMenu -Title 'Select action' -Color $Accent -Choices @(
                'Restart', 'Reprovision', 'Troubleshoot', 'EndGracePeriod',
                'CreateSnapshot', 'Resize', 'Rename', 'Restore', 'PowerOn', 'PowerOff'
            )
            $extraParams = @{}
            switch ($action) {
                'Resize' {
                    $plans = Invoke-IaStatus -Spinner Dots -Title 'Loading service plans…' -ScriptBlock { Get-IntuneCloudPCServicePlan }
                    $planChoice = Read-IaMenu -Title 'Target service plan' -Color $Accent `
                        -Choices @($plans | ForEach-Object { "$($_.vCPU)vCPU / $($_.RAM)GB RAM / $($_.Storage)GB  —  $($_.Name)" })
                    $planIndex  = @($plans | ForEach-Object { "$($_.vCPU)vCPU / $($_.RAM)GB RAM / $($_.Storage)GB  —  $($_.Name)" }).IndexOf($planChoice)
                    $extraParams.ServicePlanId = $plans[$planIndex].Id
                }
                'Rename' {
                    $extraParams.NewName = Read-IaText -Question 'New display name'
                }
                'Restore' {
                    $snaps = Invoke-IaStatus -Spinner Dots -Title 'Loading snapshots…' -ScriptBlock {
                        Get-IntuneCloudPCSnapshot -CloudPC $pcName
                    }
                    if (-not $snaps) { Write-IaHost '[yellow]No snapshots found for this Cloud PC.[/]'; return }
                    $snapChoice = Read-IaMenu -Title 'Restore from snapshot' -Color $Accent `
                        -Choices @($snaps | ForEach-Object { "$($_.CreatedAt)  ($($_.SnapshotType))" })
                    $snapIndex  = @($snaps | ForEach-Object { "$($_.CreatedAt)  ($($_.SnapshotType))" }).IndexOf($snapChoice)
                    $extraParams.SnapshotId = $snaps[$snapIndex].Id
                }
            }
            Write-IaTuiHeader -Screen "Cloud PC action: $action" -Sub $pcName -Accent $Accent
            $result = Invoke-IntuneCloudPCAction -CloudPC $pcName -Action $action @extraParams -Confirm:$false
            if ($result.Submitted) {
                Write-IaHost "[$Accent]Submitted.[/] Action '$action' is queued for [$Accent]$pcName[/]."
            }
        }
        'Provisioning policies*' {
            Write-IaTuiHeader -Screen 'Provisioning Policies' -Accent $Accent
            $sub = Read-IaMenu -Title 'Provisioning policies' -Color $Accent -Choices @(
                'List all', 'Create new', 'Delete', 'Back'
            )
            switch -Wildcard ($sub) {
                'List*' {
                    $pols = Invoke-IaStatus -Spinner Dots -Title 'Loading…' -ScriptBlock {
                        Get-IntuneCloudPCProvisioningPolicy -IncludeAssignments
                    }
                    $pols | Select-Object Name, JoinType, ImageType, ImageName, Region, Id | Format-IaTable -Color $Accent
                }
                'Create*' {
                    $name  = Read-IaText -Question 'Policy name'
                    $imgs  = Invoke-IaStatus -Spinner Dots -Title 'Loading images…' -ScriptBlock { Get-IntuneCloudPCImage }
                    $imgC  = Read-IaMenu -Title 'OS image' -Color $Accent `
                        -Choices @($imgs | ForEach-Object { "$($_.Type): $($_.Name)  [$($_.OS)]" })
                    $imgIdx= @($imgs | ForEach-Object { "$($_.Type): $($_.Name)  [$($_.OS)]" }).IndexOf($imgC)
                    $img   = $imgs[$imgIdx]
                    $join  = Read-IaMenu -Title 'Azure AD join type' -Color $Accent `
                        -Choices @('azureADJoin', 'hybridAzureADJoin')
                    Write-IaTuiHeader -Screen 'Create provisioning policy' -Sub $name -Accent $Accent
                    New-IntuneCloudPCProvisioningPolicy -Name $name -ImageId $img.Id `
                        -ImageType ($img.Type.ToLower()) -DomainJoinType $join -WhatIf
                    if ((Read-IaMenu -Title 'Apply?' -Choices @('Yes','No') -Color $Accent) -eq 'Yes') {
                        New-IntuneCloudPCProvisioningPolicy -Name $name -ImageId $img.Id `
                            -ImageType ($img.Type.ToLower()) -DomainJoinType $join -Confirm:$false
                        Write-IaHost "[$Accent]Policy created.[/]"
                    }
                }
                'Delete*' {
                    $pols = Invoke-IaStatus -Spinner Dots -Title 'Loading…' -ScriptBlock { Get-IntuneCloudPCProvisioningPolicy }
                    $polC = Read-IaMenu -Title 'Policy to delete' -Color $Accent `
                        -Choices @($pols | ForEach-Object { $_.Name })
                    Remove-IntuneCloudPCProvisioningPolicy -Policy $polC -Confirm:$false
                    Write-IaHost "[$Accent]Deleted[/] $polC"
                }
            }
        }
        'Network connections*' {
            Write-IaTuiHeader -Screen 'Network Connections' -Accent $Accent
            $sub = Read-IaMenu -Title 'Network connections' -Color $Accent -Choices @(
                'List all', 'Run health check', 'Back'
            )
            switch -Wildcard ($sub) {
                'List*' {
                    $conns = Invoke-IaStatus -Spinner Dots -Title 'Loading…' -ScriptBlock { Get-IntuneCloudPCConnection }
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
                    $conns = Invoke-IaStatus -Spinner Dots -Title 'Loading…' -ScriptBlock { Get-IntuneCloudPCConnection }
                    $connC = Read-IaMenu -Title 'Select connection' -Color $Accent `
                        -Choices @($conns | ForEach-Object { $_.Name })
                    Test-IntuneCloudPCConnection -Connection $connC
                    Write-IaHost "[$Accent]Health check triggered.[/] Check connection status in a few minutes."
                }
            }
        }
        'User settings*' {
            Write-IaTuiHeader -Screen 'Cloud PC User Settings' -Accent $Accent
            Invoke-IaStatus -Spinner Dots -Title 'Loading…' -ScriptBlock {
                Get-IntuneCloudPCUserSetting
            } | Format-IaTable -Color $Accent
        }
        'Images*' {
            Write-IaTuiHeader -Screen 'Cloud PC Images' -Sub 'gallery · custom' -Accent $Accent
            $type = Read-IaMenu -Title 'Image type' -Choices @('All','Gallery','Custom') -Color $Accent
            Invoke-IaStatus -Spinner Dots -Title 'Loading images…' -ScriptBlock {
                Get-IntuneCloudPCImage -Type $type
            } | Format-IaTable -Color $Accent
        }
        'Service plans*' {
            Write-IaTuiHeader -Screen 'Cloud PC Service Plans' -Accent $Accent
            Invoke-IaStatus -Spinner Dots -Title 'Loading…' -ScriptBlock {
                Get-IntuneCloudPCServicePlan
            } | Sort-Object vCPU, RAM | Format-IaTable -Color $Accent
        }
        'Snapshots*' {
            Write-IaTuiHeader -Screen 'Cloud PC Snapshots' -Accent $Accent
            $pcs   = Invoke-IaStatus -Spinner Dots -Title 'Loading Cloud PCs…' -ScriptBlock { Get-IntuneCloudPC }
            $scope = Read-IaMenu -Title 'Scope' -Color $Accent -Choices (@('All Cloud PCs') + @($pcs | ForEach-Object { $_.CloudPC }))
            $snaps = Invoke-IaStatus -Spinner Dots -Title 'Loading snapshots…' -ScriptBlock {
                if ($scope -eq 'All Cloud PCs') { Get-IntuneCloudPCSnapshot }
                else { Get-IntuneCloudPCSnapshot -CloudPC $scope }
            }
            $snaps | Format-IaTable -Color $Accent
        }
        'Reports*' {
            Write-IaTuiHeader -Screen 'Cloud PC Reports' -Accent $Accent
            $rpt = Read-IaMenu -Title 'Report' -Color $Accent -PageSize 7 -Choices @(
                'Total usage (active hours · connections)', 'Daily aggregate', 'Remote connections',
                'Connection quality', 'Frontline (shared) utilization', 'Inaccessible Cloud PCs'
            )
            $rptName = switch -Wildcard ($rpt) {
                'Total*'        { 'TotalUsage' }
                'Daily*'        { 'DailyAggregate' }
                'Remote*'       { 'RemoteConnection' }
                'Connection*'   { 'ConnectionQuality' }
                'Frontline*'    { 'Frontline' }
                'Inaccessible*' { 'Inaccessible' }
            }
            Invoke-IaStatus -Spinner Dots -Title "Running $rpt report…" -ScriptBlock {
                Get-IntuneCloudPCReport -Report $rptName
            } | Select-Object -First 100 | Format-IaTable -Color $Accent
        }
        default { return }
    }
}
