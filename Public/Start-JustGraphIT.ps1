function Start-JustGraphIT {
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
        Connect-JustGraphIT; Start-JustGraphIT
    #>
    [CmdletBinding()]
    param([ValidateSet('green', 'amber', 'lego', 'deepsea', 'sunset', 'ocean', 'forest', 'mono')][string]$Theme = 'deepsea')

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw "The JustGraphIT TUI requires PowerShell 7+ (you are on $($PSVersionTable.PSVersion))."
    }
    if (-not (Get-Command Get-MgContext -ErrorAction SilentlyContinue)) {
        throw "JustGraphIT needs the Microsoft Graph authentication module. Install it once:`n    Install-Module Microsoft.Graph.Authentication -Scope CurrentUser"
    }
    if (-not (Get-MgContext)) {
        Write-IaHost "[yellow]Not connected.[/] Signing in…"
        Connect-JustGraphIT | Out-Null
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
            # @() so an EMPTY tenant caches as @() — a bare $null result would fail the
            # cache check above and re-run the full inventory sweep on every action.
            $script:IaTuiInventory = @(Invoke-IaStatus -Spinner Dots -Title 'Reading Intune assignments…' -ScriptBlock {
                Get-IaInventory
            })
        }
        $script:IaTuiInventory
    }

    $ctx  = Get-MgContext
    $elev = try { if (Test-IaPrivileged) { "[green]ELEVATED[/]" } else { "[yellow]NOT ELEVATED[/]" } } catch { '' }
    $script:IaTuiAccount = $ctx.Account
    $script:IaTuiElev    = $elev

    # The main menu is a full-screen redraw, so its banner is passed as a -Header that
    # is repainted with every frame (rather than printed above it, where the redraw
    # would erase it).
    $splashHeader = @(
        (Get-IaFigletString -Text 'JUSTGRAPHIT' -Color $accent)
        (ConvertFrom-IaMarkup "[dim][[[$accent]SYS[/]]][/] [white]$($ctx.Account)[/]  [dim]│[/]  [grey]tenant $(Format-IaMaskedId $ctx.TenantId)[/]  [dim]│[/]  $elev")
        (ConvertFrom-IaMarkup "[dim][[[$accent]GRF[/]]][/] [$accent]Microsoft Intune & Entra[/] [dim]─[/] [grey]direct graph access[/]")
        ''
    ) -join "`n"

    function Show-IaTuiSplash {
        Clear-IaHost
        Write-IaFiglet -Text 'JUSTGRAPHIT' -Color $accent
        Write-IaHost "[dim][[[$accent]SYS[/]]][/] [white]$($ctx.Account)[/]  [dim]│[/]  [grey]tenant $(Format-IaMaskedId $ctx.TenantId)[/]  [dim]│[/]  $elev"
        Write-IaRule -Color $accent
    }

    Show-IaTuiSplash
    # One-time inventory load: stream the live Graph calls as they happen (JustGraphIT logs
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
        # Actions are listed alphabetically (utility items pinned at the bottom).
        $choice = Read-IaMenu -Title "Choose an action" -Header $splashHeader -Color $accent -PageSize 17 -ShowGraphFooter -Choices @(
            'Apps (list · assign · Win32 details)',
            'Assign a group to many (pick which)',
            'Audit',
            'Autopilot & enrollment (devices · profiles · restrictions)',
            'Backup / Restore / Drift',
            'Build a group from a query (stale devices · users → group)',
            'Compare two groups',
            'Dashboard (tenant overview · devices · identity · health)',
            'Elevate (PIM) — activate an eligible role',
            'Export report (HTML · Excel · Rich HTML)',
            'Graph calls (live activity log)',
            'Group lookup (what is a group assigned to)',
            'Help desk (user · device lookup · hardware · actions)',
            'Identity · Entra (users · groups · access · apps · roles · security)',
            'Mirror assignments (copy A -> B, pick which)',
            'Policies (configuration · compliance · scripts · remediations)',
            'Reports (status · audit · approvals)',
            'Security baselines',
            'Templates (capture / apply)',
            'View all assignments',
            'What-if (user / device effective assignments)',
            'Windows 365 (Cloud PCs · provisioning · connections)',
            'Windows Update (rings · feature · driver)',
            'Refresh data',
            'Quit'
        )
        if (-not $choice) { return }
        try {
            switch -Wildcard ($choice) {
                'View all*'       { Invoke-IaTuiViewAll     -Accent $accent }
                'Dashboard*'      { Invoke-IaTuiDashboard   -Accent $accent }
                'Help desk*'      { Invoke-IaTuiHelpDesk    -Accent $accent }
                'Identity*'       { Invoke-IaTuiEntra       -Accent $accent }
                'Group lookup*'   { Invoke-IaTuiGroupLookup -Accent $accent }
                'Build a group*'  { Invoke-IaTuiBuildGroupFromQuery -Accent $accent }
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
        if ($choice -ne 'Quit' -and $choice -notlike 'View all*' -and $choice -notlike 'Dashboard*') {
            # 'View all' and 'Dashboard' are self-paced by their interactive tables
            # (own q/Esc exit), so they skip the trailing redundant "press any key".
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
    #   -Area          one or more inventory areas (Apps, Compliance, Scripts…)
    #   -ResourceType  narrow to specific registry keys (e.g. windowsUpdateRings)
    #                  when an Area lumps several types together
    #   -AllowType     append a "✎ Type a name or GUID…" escape hatch so a freshly
    #                  created resource (not yet in the cached inventory) or a raw
    #                  GUID is never a dead end. Returns {Id;Name;Typed=$true}.
    # Returns the inventory item ({Id;Name;Area;…}) or $null when cancelled.
    param([string]$Accent, [string[]]$Area, [string[]]$ResourceType, [string]$Title, [switch]$AllowType)
    $items = @(Get-IaTuiInventory)
    if ($Area)         { $items = @($items | Where-Object { $_.Area -in $Area }) }
    if ($ResourceType) { $items = @($items | Where-Object { $_.ResourceType -in $ResourceType }) }
    $items = @($items | Sort-Object Name)
    $label = if ($Area) { ($Area -join ' / ') } else { 'resource' }
    $typeTag = '✎ Type a name or GUID…'
    if (-not $items) {
        if (-not $AllowType) { Write-IaHost "[yellow]No $label resources found.[/]"; return $null }
        $typed = Read-IaText -Question "No $label loaded — type a name or GUID"
        if ([string]::IsNullOrWhiteSpace($typed)) { return $null }
        return [pscustomobject]@{ Id = $typed; Name = $typed; Typed = $true }
    }
    $choices = @($items | ForEach-Object Name)
    if ($AllowType) { $choices = @($choices) + $typeTag }
    $pick = Read-IaSelection -Title $Title -Choices $choices -Color $Accent
    if (-not $pick) { return $null }
    if ($AllowType -and $pick -eq $typeTag) {
        $typed = Read-IaText -Question 'Type a name or GUID'
        if ([string]::IsNullOrWhiteSpace($typed)) { return $null }
        return [pscustomobject]@{ Id = $typed; Name = $typed; Typed = $true }
    }
    $items | Where-Object Name -eq $pick | Select-Object -First 1
}

function Select-IaManagedDevice {
    # Pick a managed device from the live device inventory. Returns the device
    # name (every -Device cmdlet resolves name-or-GUID) or $null when cancelled.
    # Falls back to typing only when the inventory can't be read.
    param([string]$Accent, [string]$Title = 'Which device?')
    $devs = $null
    try {
        $devs = Invoke-IaStatus -Spinner Dots -Title 'Loading devices…' -ScriptBlock {
            Get-IntuneDeviceInventory -Top 2000
        }
    } catch { $devs = $null }
    $devs = @($devs | Where-Object Device)
    if (-not $devs) {
        $typed = Read-IaText -Question 'Device name or GUID'
        return $(if ([string]::IsNullOrWhiteSpace($typed)) { $null } else { $typed })
    }
    $disp = @($devs | ForEach-Object {
        [pscustomobject][ordered]@{ Device = $_.Device; User = $_.User; OS = $_.OS; Compliance = $_.Compliance; LastSync = $_.LastSync }
    })
    $picked = Read-IaTableInteractive -Data $disp -Color $Accent -Selectable -Title "$Title ($($disp.Count))  ·  / to search" -Stem 'device-pick'
    if (-not $picked) { return $null }
    $picked.Device
}

function Select-IaAutopilotDevice {
    # Pick an Autopilot device by serial. Returns the serial string or $null.
    param([string]$Accent, [string]$Title = 'Which Autopilot device?')
    $devs = $null
    try {
        $devs = Invoke-IaStatus -Spinner Dots -Title 'Loading Autopilot devices…' -ScriptBlock {
            Get-IntuneAutopilotDevice
        }
    } catch { $devs = $null }
    $devs = @($devs | Where-Object SerialNumber)
    if (-not $devs) {
        $typed = Read-IaText -Question 'Serial number'
        return $(if ([string]::IsNullOrWhiteSpace($typed)) { $null } else { $typed })
    }
    $disp = @($devs | ForEach-Object {
        [pscustomobject][ordered]@{ Serial = $_.SerialNumber; Model = $_.Model; Manufacturer = $_.Manufacturer; GroupTag = $_.GroupTag; State = $_.EnrollmentState }
    })
    $picked = Read-IaTableInteractive -Data $disp -Color $Accent -Selectable -Title "$Title ($($disp.Count))  ·  / to search" -Stem 'autopilot-pick'
    if (-not $picked) { return $null }
    $picked.Serial
}

function Select-IaUser {
    # Pick a user (UPN) from the directory. Returns the UPN string or $null.
    # Falls back to typing when Directory read is blocked or empty.
    param([string]$Accent, [string]$Title = 'Which user?')
    if ($script:IaDirectoryBlocked) {
        $typed = Read-IaText -Question 'User principal name (UPN)'
        return $(if ([string]::IsNullOrWhiteSpace($typed)) { $null } else { $typed })
    }
    $users = $null
    try {
        $users = Invoke-IaStatus -Spinner Dots -Title 'Loading users…' -ScriptBlock {
            Get-IaCollection -V1 -Path "users?`$select=id,displayName,userPrincipalName&`$top=999"
        }
    } catch { $users = $null }
    $users = @($users | Where-Object userPrincipalName)
    if (-not $users) {
        $typed = Read-IaText -Question 'User principal name (UPN)'
        return $(if ([string]::IsNullOrWhiteSpace($typed)) { $null } else { $typed })
    }
    $disp = @($users | ForEach-Object {
        [pscustomobject][ordered]@{ User = $_.displayName; UPN = $_.userPrincipalName }
    } | Sort-Object User)
    $picked = Read-IaTableInteractive -Data $disp -Color $Accent -Selectable -Title "$Title ($($disp.Count))  ·  / to search" -Stem 'user-pick'
    if (-not $picked) { return $null }
    $picked.UPN
}

function Select-IaReportValue {
    # For a report/inventory filter: present the DISTINCT values of $Prop drawn
    # from the loaded rows as a pick-list (+ a "type a value" escape hatch for
    # free-form operators). Returns the chosen string, a typed string, or $null.
    param([string]$Accent, [object[]]$Data, [string]$Prop, [string]$Op = '')
    $q = if ($Op) { "Value for $Prop $Op" } else { "Value for $Prop" }
    $typeTag = '✎ Type a value…'
    $vals = @($Data | ForEach-Object { $_.$Prop } |
        Where-Object { $null -ne $_ -and "$_" -ne '' } |
        ForEach-Object { "$_" } | Select-Object -Unique | Sort-Object)
    if (-not $vals) { return (Read-IaText -Question $q) }
    # Cap the distinct list so a high-cardinality column stays usable.
    $capped  = @($vals | Select-Object -First 200)
    $choices = @($capped) + $typeTag
    $pick = Read-IaSelection -Title $q -Choices $choices -Color $Accent -PageSize 20
    if (-not $pick) { return $null }
    if ($pick -eq $typeTag) { return (Read-IaText -Question $q) }
    $pick
}

function Select-IaLoadedItem {
    # Generic picker over a freshly-loaded object list (for resources that aren't
    # cleanly in the cached TUI inventory, e.g. security baselines). Runs $Loader,
    # shows a searchable selectable table of $Columns, and returns the chosen
    # object (matched on $KeyProp) or $null when cancelled / nothing to pick.
    param([string]$Accent, [scriptblock]$Loader, [string]$KeyProp = 'Name',
          [string[]]$Columns, [string]$Title = 'Select', [string]$Stem = 'pick')
    $items = $null
    try { $items = Invoke-IaStatus -Spinner Dots -Title 'Loading…' -Color $Accent -ScriptBlock $Loader } catch { $items = $null }
    $items = @($items | Where-Object { $null -ne $_.$KeyProp -and "$($_.$KeyProp)" -ne '' })
    if (-not $items) { Write-IaHost '[yellow]Nothing to select.[/]'; return $null }
    $cols = if ($Columns) { $Columns } else { @($KeyProp) }
    $disp = @($items | ForEach-Object {
        $src = $_; $o = [ordered]@{}; foreach ($c in $cols) { $o[$c] = $src.$c }; [pscustomobject]$o
    })
    $picked = Read-IaTableInteractive -Data $disp -Color $Accent -Selectable -Title "$Title ($($disp.Count))  ·  / to search" -Stem $Stem
    if (-not $picked) { return $null }
    $items | Where-Object { "$($_.$KeyProp)" -eq "$($picked.$KeyProp)" } | Select-Object -First 1
}

function Select-IaBackupPath {
    # Pick an existing backup snapshot (file or -Directory folder) from the working
    # directory, newest first, with a "✎ Type a path…" escape hatch. Returns the
    # full path, a typed path, or $null when cancelled.
    param([string]$Accent, [string]$Title = 'Which snapshot?',
          [string]$Prefix = 'justgraphit-assignments', [string]$Extension = 'json',
          [string]$Glob, [switch]$Directory)
    $filter = if ($Glob) { $Glob } else { "$Prefix-*.$Extension" }
    $items = if ($Directory) {
        @(Get-ChildItem -Path '.' -Directory -Filter $filter -ErrorAction SilentlyContinue)
    } else {
        @(Get-ChildItem -Path '.' -Filter $filter -File -ErrorAction SilentlyContinue)
    }
    $items   = @($items | Sort-Object LastWriteTime -Descending)
    $typeTag = '✎ Type a path…'
    if (-not $items) { return (Read-IaText -Question $Title) }
    $map = [ordered]@{}
    foreach ($f in $items) { $map[$f.Name] = $f.FullName }
    $pick = Read-IaSelection -Title $Title -Choices (@($map.Keys) + $typeTag) -Color $Accent -PageSize 15
    if (-not $pick) { return $null }
    if ($pick -eq $typeTag) { return (Read-IaText -Question $Title) }
    $map[$pick]
}

# ─── shared header ────────────────────────────────────────────────────────────

function Write-IaTuiHeader {
    param([string]$Screen, [string]$Sub = '', [string]$Accent)
    Clear-IaHost
    try { $host.UI.RawUI.WindowTitle = "JustGraphIT — $Screen" } catch { }
    Write-IaHost "[dim][[[$Accent]JGI[/]]][/] [bold]$Screen[/]"
    if ($Sub) {
        Write-IaHost "[grey]$Sub[/]"
    } elseif ($script:IaTuiAccount) {
        Write-IaHost "[dim][[[grey]USR[/]]][/] [grey]$($script:IaTuiAccount)[/]  [dim]│[/]  $script:IaTuiElev"
    }
    Write-IaRule -Color $Accent
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
    if (-not $g) { return }
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
    if (-not $a) { return }
    $b = Select-IaGroup -Accent $Accent -Title 'Group B'
    if (-not $b) { return }
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
    if (-not $kind) { return }   # Esc → cancel (else the device picker loads unbidden)
    $val  = if ($kind -eq 'user') { Select-IaUser -Accent $Accent -Title 'Which user?' }
            else { Select-IaManagedDevice -Accent $Accent -Title 'Which device?' }
    if ([string]::IsNullOrWhiteSpace($val)) { return }
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
    if (-not $src) { return }
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
    if (-not $dst) { return }
    Write-IaTuiHeader -Screen 'Mirror assignments' -Sub "from $($src.DisplayName)  →  $($dst.DisplayName)" -Accent $Accent
    $confirm = Read-IaMenu `
        -Title "Apply $($ids.Count) assignment(s) to [$Accent]$($dst.DisplayName)[/]?" `
        -Choices @('Preview first (no changes yet)', 'Apply now') -Color $Accent
    $commit  = $confirm -eq 'Apply now'

    # Shared renderer so the preview and the post-preview apply look identical.
    $renderPlans = {
        param($Plans, $Committed)
        $Plans | ForEach-Object {
            $status = if ($Committed) { if ($_.Applied) { "[$Accent]OK[/]" } else { '[coral]FAILED[/]' } } else { '[grey]PREVIEW[/]' }
            [pscustomobject]@{
                Status   = $status
                Area     = "[$Accent]$($_.Area)[/]"
                Resource = $_.ResourceName
                Added    = ($_.Added -join '; ')
                Error    = $_.Error
            }
        } | Format-IaTable -Color $Accent
    }

    $plans = Invoke-IaCopy -Items $items -SrcId $src.Id -DstId $dst.Id -DstName $dst.DisplayName `
        -IncludeIds $ids -Commit:$commit
    if (-not $plans) { Write-IaHost '[yellow]Nothing to change (already assigned?).[/]'; return }
    & $renderPlans $plans $commit
    if ($commit) { $script:IaTuiInventory = $null; return }   # applied — drop cached inventory

    # Previewed only — offer to apply right here, no need to re-run the picker.
    $after = Read-IaMenu -Color $Accent `
        -Title "Apply these $(@($plans).Count) change(s) to [$Accent]$($dst.DisplayName)[/] now?" `
        -Choices @('Apply now', 'Cancel (leave unchanged)')
    if ($after -ne 'Apply now') { Write-IaHost '[grey]No changes made.[/]'; return }
    Write-IaTuiHeader -Screen 'Mirror assignments' -Sub "applying → $($dst.DisplayName)" -Accent $Accent
    $applied = Invoke-IaCopy -Items $items -SrcId $src.Id -DstId $dst.Id -DstName $dst.DisplayName `
        -IncludeIds $ids -Commit
    & $renderPlans $applied $true
    $script:IaTuiInventory = $null   # assignments changed — refresh on next read
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
    if (-not $g) { return }
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
        if ($fchoice -and $fchoice -ne '(no filter)') {   # $null -ne '(no filter)' is TRUE — guard Esc
            $filterId = ($filters | Where-Object Name -eq $fchoice | Select-Object -First 1).Id
            $ftPick   = Read-IaMenu -Title "Filter mode for '$fchoice'" -Choices @('include', 'exclude') -Color $Accent
            if ($ftPick) { $filterType = $ftPick }   # keep the 'include' default if cancelled
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
        if (-not $g) { return }
        $name = Read-IaText -Question 'Template name' -DefaultAnswer 'baseline'
        $path = Read-IaText -Question 'Save to path' -DefaultAnswer "$name.json"
        Write-IaTuiHeader -Screen 'Templates · capture' -Sub "group: $($g.DisplayName)" -Accent $Accent
        $tmpl = New-IaTemplateFromGroup -Items (Get-IaTuiInventory) -GroupId $g.Id -Name $name
        $tmpl | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding utf8
        Write-IaHost "[$Accent]Saved[/] template '$name' with [$Accent]$($tmpl.resources.Count)[/] resource(s) → $path"
    } else {
        $path = Select-IaBackupPath -Accent $Accent -Title 'Template file to apply' -Glob '*.json'
        if ([string]::IsNullOrWhiteSpace($path)) { return }
        if (-not (Test-Path $path)) { Write-IaHost "[red]Not found:[/] $path"; return }
        $tmpl = Get-Content $path -Raw | ConvertFrom-Json
        $g    = Select-IaGroup -Accent $Accent -Title 'Device group to stamp on'
        if (-not $g) { return }
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
    if (-not $role) { return }
    $just    = Read-IaText -Question 'Justification'
    $durPick = Read-IaMenu -Title 'Duration' -Color $Accent -Choices @('30m','1h','2h','4h','8h','✎ Custom…')
    $dur     = if ($durPick -eq '✎ Custom…') { Read-IaText -Question 'Duration (e.g. 2h, 30m, 8h)' -DefaultAnswer '2h' } else { $durPick }
    if ([string]::IsNullOrWhiteSpace($dur)) { $dur = '2h' }
    $confirm = Read-IaMenu -Title "Activate [$Accent]$role[/] for ${dur}?" `
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
    Write-IaTuiHeader -Screen 'Apps' -Sub 'list · assign · details' -Accent $Accent

    while ($true) {
        $pick = Read-IaMenu -Title 'Apps' -Color $Accent -PageSize 10 -Choices @(
            'List all apps',
            'Filter by type (Win32 / Store / iOS / Android / macOS)',
            'App details (any type · all fields)',
            'Assign app to groups',
            'Delete an app',
            'Back'
        )
        try { switch -Wildcard ($pick) {
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
                if (-not $type) { break }
                try {
                    Invoke-IaStatus -Spinner 'Dots2' -Title "Loading $type apps…" -Color $Accent -ScriptBlock {
                        $script:_apps = @(Get-IntuneApp -AppType $type)
                    }
                } catch { $script:_apps = @() }
                if (-not $script:_apps) { Write-IaHost "[yellow]No $type apps found.[/]"; Read-IaPause | Out-Null; break }
                $rows = @($script:_apps | ForEach-Object {
                    [pscustomobject][ordered]@{ Name = $_.Name; Publisher = $_.Publisher; Version = $_.Version; Modified = $_.Modified }
                })
                Write-IaTuiHeader -Screen 'Apps' -Sub "$type ($($rows.Count))" -Accent $Accent
                $rows | Format-IaTable -Color $Accent -Title "$type Apps ($($rows.Count))"
                Read-IaTablePause -Data $script:_apps -Stem "apps-$($type.ToLower())" -Color $Accent
            }
            'App details*' {
                $app = Select-IaInventoryItem -Accent $Accent -Area 'Apps' -Title 'Which app?'
                if (-not $app) { break }
                $name = $app.Id
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading app…' -Color $Accent -ScriptBlock {
                    $script:_appRaw = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceAppManagement/mobileApps/$name")
                }
                $raw = $script:_appRaw
                if (-not $raw) { Write-IaHost '[yellow]Could not load that app.[/]'; Read-IaPause | Out-Null; break }
                $type = "$($raw.'@odata.type')" -replace '#microsoft\.graph\.', ''
                Write-IaTuiHeader -Screen 'App details' -Sub "$($raw.displayName)  ·  $type" -Accent $Accent
                Write-IaHost "[$Accent]$($raw.displayName)[/]  $(if ($raw.version) { "v$($raw.version)  " })$(if ($raw.publisher) { "($($raw.publisher))" })"
                Write-IaHost "[grey]Type:[/] $type"
                if ($raw.description) { Write-IaHost "[grey]Description:[/] $($raw.description)" }
                Write-IaHost ''
                # Every populated field as a Property / Value table — works for ANY app
                # type (Win32, macOS PKG/DMG, store, LOB, VPP, web link…), so non-Win32
                # apps show their real detail instead of empty Win32 fields.
                $skip = @('@odata.type', 'displayName', 'publisher', 'description', 'largeIcon', 'id')
                $keys = if ($raw -is [System.Collections.IDictionary]) { @($raw.Keys) } else { @($raw.PSObject.Properties.Name) }
                $kv = foreach ($k in ($keys | Sort-Object)) {
                    if ($k -in $skip) { continue }
                    $v = $raw.$k
                    if ($null -eq $v -or "$v" -eq '') { continue }
                    $isComplex = ($v -is [System.Collections.IDictionary]) -or (($v -is [System.Collections.IEnumerable]) -and ($v -isnot [string]))
                    $sv = if ($isComplex) { ConvertTo-Json $v -Depth 5 -Compress } else { "$v" }
                    if ($sv.Length -gt 400) { $sv = $sv.Substring(0, 400) + '…' }
                    [pscustomobject][ordered]@{ Property = $k; Value = $sv }
                }
                Read-IaTablePause -Data @($kv) -Stem "app-$name" -Color $Accent -Title "App details · $($raw.displayName)"
            }
            'Assign app*' {
                $app = Select-IaInventoryItem -Accent $Accent -Area 'Apps' -Title 'Which app?'
                if (-not $app) { break }
                $appName = $app.Id
                Write-IaHost "[yellow]Note:[/] this [bold]replaces[/] every current assignment on [$Accent]$($app.Name)[/] with your choice below."
                $mode    = Read-IaMenu -Title 'Assign to' -Color $Accent -Choices @('All Devices','All Users','Specific group','Clear all assignments')
                if (-not $mode) { break }
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
                        $grpObj = $null
                        try { $grpObj = Select-IaGroup -Accent $Accent -Title 'Which group?' } catch { }
                        $grp = if ($grpObj -and $grpObj.Id) { $grpObj.Id } else { Read-IaText -Question 'Group name or GUID' }
                        if ([string]::IsNullOrWhiteSpace($grp)) { break }   # cancel → stay in Apps menu, not exit it
                        $excl = Read-IaMenu -Title 'Include or exclude?' -Color $Accent -Choices @('Include','Exclude')
                        if (-not $excl) { break }   # Esc must NOT fall through to the 'exclude' branch
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
                Read-IaPause | Out-Null
            }
            'Delete an app' {
                $app = Select-IaInventoryItem -Accent $Accent -Area 'Apps' -Title 'Which app to delete?' -AllowType
                if (-not $app) { break }
                $appName = $app.Id
                Write-IaHost '[grey]Deleting an app also removes all of its group assignments (irreversible).[/]'
                if (Read-IaConfirm "[red]Delete app '$($app.Name)'?[/]") {
                    Invoke-IaStatus -Spinner 'Dots2' -Title 'Deleting…' -Color $Accent -ScriptBlock {
                        Remove-IntuneApp -Id $appName -Confirm:$false
                    }
                    Write-IaHost "[$Accent]✓ Deleted.[/]"; Read-IaPause | Out-Null
                }
            }
            'Back' { return }
        } } catch { Write-IaHost "[coral]Error:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
    }
}

# ─── windows update submenu ───────────────────────────────────────────────────
function Invoke-IaTuiPatchReport {
    # Windows patch status (quality + feature updates) pulled from the Intune
    # report export API via Get-IntunePatchReport.
    param([string]$Accent)
    $mode = Read-IaMenu -Title 'Patch report (from Intune update reports)' -Color $Accent -PageSize 8 -Choices @(
        'Summary (quality + feature roll-up)',
        'Quality updates — per device',
        'Feature updates — per device',
        'Failures only (quality + feature)',
        'Back'
    )
    if (-not $mode -or $mode -eq 'Back') { return }
    Write-IaTuiHeader -Screen 'Patch report' -Sub 'pulled from Intune update reports (async export)' -Accent $Accent
    Write-IaHost '[grey]Async Intune export jobs (quality + feature update status) — large tenants can take 1–3 min.[/]'

    $colorState = {
        param($s)
        switch -Regex ("$s") {
            '^(Success|Compliant|UpToDate|Installed)$' { $Accent }
            '^(Error|Failed|Cancelled)$'               { 'coral' }
            '^(InProgress|Pending|Scheduled|Offer)'    { 'yellow' }
            default                                    { 'grey' }
        }
    }

    if ($mode -like 'Summary*') {
        $rows = @(Invoke-IaStatus -Spinner Dots -Title 'Running quality + feature update reports…' -ScriptBlock {
            Get-IntunePatchReport -Summary
        })
        if (-not $rows) { Write-IaHost '[yellow]No update-status rows (no update policies, or the reports are empty).[/]'; Read-IaPause | Out-Null; return }
        $disp = @($rows | ForEach-Object {
            $sc = & $colorState $_.State
            [pscustomobject][ordered]@{ UpdateType = $_.UpdateType; State = "[$sc]$($_.State)[/]"; Devices = $_.Devices }
        })
        $total = (@($rows | Measure-Object -Property Devices -Sum).Sum)
        Read-IaTablePause -Data $disp -Stem 'patch-summary' -Color $Accent -Title "Patch status summary ($total device-states)"
        return
    }

    # Per-device views (Quality / Feature / Failures-only)
    $rows = @(Invoke-IaStatus -Spinner Dots -Title 'Running update report(s)…' -ScriptBlock {
        if     ($mode -like 'Quality*')  { Get-IntunePatchReport -Type Quality }
        elseif ($mode -like 'Feature*')  { Get-IntunePatchReport -Type Feature }
        else                             { Get-IntunePatchReport -State Error }
    })
    if (-not $rows) { Write-IaHost '[yellow]No matching update-status rows.[/]'; Read-IaPause | Out-Null; return }
    $disp = @($rows | ForEach-Object {
        $sc = & $colorState $_.State
        [pscustomobject][ordered]@{
            Type      = $_.UpdateType
            Device    = $_.Device
            User      = $_.User
            State     = "[$sc]$($_.State)[/]"
            Detail    = $_.Detail
            LastEvent = $_.LastEvent
        }
    })
    $label = ($mode -replace '\s+—.*', '' -replace '\s*\(.*', '')
    Read-IaTablePause -Data $disp -Stem 'patch-report' -Color $Accent -Title "Patch report · $label ($($rows.Count))"
}

function Invoke-IaTuiWindowsUpdate {
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Windows Update' -Sub 'rings · feature updates · driver updates · patch report' -Accent $Accent

    while ($true) {
        $pick = Read-IaMenu -Title 'Windows Update' -Color $Accent -PageSize 10 -Choices @(
            'Patch report (quality · feature update status)',
            'List update rings',
            'Create update ring',
            'Edit update ring',
            'Delete update ring',
            'List feature update profiles',
            'Create feature update profile',
            'Delete feature update profile',
            'List driver update profiles',
            'Delete driver update profile',
            'Back'
        )
        try { switch -Wildcard ($pick) {
            'Patch report*' { Invoke-IaTuiPatchReport -Accent $Accent }
            'List update rings' {
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_rings = @(Get-IntuneUpdateRing)
                }
                $rows = $script:_rings | ForEach-Object {
                    [ordered]@{ Name = $_.Name; QualityDeferral = $_.QualityUpdateDeferralDays; FeatureDeferral = $_.FeatureUpdateDeferralDays; AutoMode = $_.AutomaticUpdateMode; Modified = $_.Modified }
                }
                Format-IaTable -Data $rows -Accent $Accent -Title 'Windows Update Rings'
                Read-IaPause | Out-Null
            }
            'Create update ring' {
                $name    = Read-IaText -Question 'Ring name'
                $qDefer  = ConvertTo-IaSafeInt (Read-IaText -Question 'Quality deferral days (0-30)') 0
                $fDefer  = ConvertTo-IaSafeInt (Read-IaText -Question 'Feature deferral days (0-365)') 0
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Creating…' -Color $Accent -ScriptBlock {
                    $script:_ring = New-IntuneUpdateRing -Name $name -QualityDeferralDays $qDefer -FeatureDeferralDays $fDefer -Confirm:$false
                }
                Write-IaHost "[$Accent]Created:[/] $($script:_ring.Name) ($($script:_ring.Id))"
                Read-IaPause | Out-Null
            }
            'Edit update ring' {
                $ring = Select-IaInventoryItem -Accent $Accent -ResourceType 'windowsUpdateRings' -Title 'Which update ring to edit?' -AllowType
                if (-not $ring) { break }
                $rid = $ring.Id
                $nn  = Read-IaText -Question 'New name (blank = keep)'
                $qd  = Read-IaText -Question 'Quality deferral days 0-30 (blank = keep)'
                $fd  = Read-IaText -Question 'Feature deferral days 0-365 (blank = keep)'
                $pause = Read-IaMenu -Title 'Pause updates?' -Color $Accent -Choices @('No change', 'Pause quality + feature', 'Resume quality + feature')
                $p = @{ Id = $rid; Confirm = $false }
                if ($nn) { $p.NewName = $nn }
                if ($qd -match '^\d+$') { $p.QualityDeferralDays = [int]$qd }
                if ($fd -match '^\d+$') { $p.FeatureDeferralDays = [int]$fd }
                if ($pause -like 'Pause*')  { $p.PauseQualityUpdates = $true;  $p.PauseFeatureUpdates = $true }
                if ($pause -like 'Resume*') { $p.PauseQualityUpdates = $false; $p.PauseFeatureUpdates = $false }
                if ($p.Count -le 2) { Write-IaHost '[yellow]Nothing to change.[/]'; Read-IaPause | Out-Null; break }
                if (Read-IaConfirm "Update ring '$($ring.Name)'?") {
                    Invoke-IaStatus -Spinner 'Dots2' -Title 'Updating…' -Color $Accent -ScriptBlock { Set-IntuneUpdateRing @p }
                    Write-IaHost "[$Accent]✓ Updated.[/]"; Read-IaPause | Out-Null
                }
            }
            'Delete update ring' {
                $ring = Select-IaInventoryItem -Accent $Accent -ResourceType 'windowsUpdateRings' -Title 'Which update ring to delete?' -AllowType
                if (-not $ring) { break }
                $name = $ring.Id
                $confirm = Read-IaMenu -Title "[red]Delete '$($ring.Name)'?[/]" -Color $Accent -Choices @('Yes, delete','Cancel')
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
                Read-IaPause | Out-Null
            }
            'Create feature update*' {
                $name    = Read-IaText -Question 'Profile name'
                $version = Read-IaMenu -Title 'Feature update version' -Color $Accent -Choices @(
                    'Windows 11, version 24H2','Windows 11, version 23H2','Windows 11, version 22H2','Windows 10, version 22H2','✎ Custom…')
                if ($version -eq '✎ Custom…') { $version = Read-IaText -Question 'Feature update version (e.g. Windows 11, version 23H2)' }
                if ([string]::IsNullOrWhiteSpace($version)) { break }
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Creating…' -Color $Accent -ScriptBlock {
                    $script:_fup = New-IntuneFeatureUpdate -Name $name -FeatureUpdateVersion $version -Confirm:$false
                }
                Write-IaHost "[$Accent]Created:[/] $($script:_fup.Name)"
                Read-IaPause | Out-Null
            }
            'Delete feature update*' {
                $fup = Select-IaInventoryItem -Accent $Accent -ResourceType 'windowsFeatureUpdateProfiles' -Title 'Which feature update profile to delete?' -AllowType
                if (-not $fup) { break }
                $name = $fup.Id
                if ((Read-IaMenu -Title "[red]Delete '$($fup.Name)'?[/]" -Color $Accent -Choices @('Yes, delete','Cancel')) -eq 'Yes, delete') {
                    Invoke-IaStatus -Spinner 'Dots2' -Title 'Deleting…' -Color $Accent -ScriptBlock { Remove-IntuneFeatureUpdate -Id $name -Confirm:$false }
                    Write-IaHost "[$Accent]Deleted.[/]"
                }
            }
            'List driver update*' {
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_dups = @(Get-IntuneDriverUpdate)
                }
                $rows = $script:_dups | ForEach-Object { [ordered]@{ Name = $_.Name; ApprovalType = $_.ApprovalType; Deferral = $_.DeploymentDeferralInDays; Modified = $_.Modified } }
                Format-IaTable -Data $rows -Accent $Accent -Title 'Driver Update Profiles'
                Read-IaPause | Out-Null
            }
            'Delete driver update*' {
                $dup = Select-IaInventoryItem -Accent $Accent -ResourceType 'windowsDriverUpdateProfiles' -Title 'Which driver update profile to delete?' -AllowType
                if (-not $dup) { break }
                $name = $dup.Id
                if ((Read-IaMenu -Title "[red]Delete '$($dup.Name)'?[/]" -Color $Accent -Choices @('Yes, delete','Cancel')) -eq 'Yes, delete') {
                    Invoke-IaStatus -Spinner 'Dots2' -Title 'Deleting…' -Color $Accent -ScriptBlock { Remove-IntuneDriverUpdate -Id $name -Confirm:$false }
                    Write-IaHost "[$Accent]Deleted.[/]"
                }
            }
            'Back' { return }
        } } catch { Write-IaHost "[coral]Error:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
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
        try { switch -Wildcard ($pick) {
            'List Autopilot devices' {
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_apdevs = @(Get-IntuneAutopilotDevice)
                }
                $rows = $script:_apdevs | ForEach-Object { [ordered]@{ Serial = $_.SerialNumber; Model = $_.Model; Manufacturer = $_.Manufacturer; GroupTag = $_.GroupTag; EnrollState = $_.EnrollmentState } }
                Format-IaTable -Data $rows -Accent $Accent -Title "Autopilot Devices ($($script:_apdevs.Count))"
                Read-IaPause | Out-Null
            }
            'Search Autopilot device*' {
                $serial = Select-IaAutopilotDevice -Accent $Accent -Title 'Which Autopilot device?'
                if ([string]::IsNullOrWhiteSpace($serial)) { break }
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Searching…' -Color $Accent -ScriptBlock {
                    $script:_apdev = @(Get-IntuneAutopilotDevice -SerialNumber $serial)
                }
                if (-not $script:_apdev) { Write-IaHost "[yellow]No device found.[/]" }
                else {
                    $d = $script:_apdev[0]
                    Write-IaHost "[$Accent]$($d.SerialNumber)[/]  $($d.Model)  GroupTag: $($d.GroupTag)  State: $($d.EnrollmentState)"
                }
                Read-IaPause | Out-Null
            }
            'Update Autopilot device*' {
                $serial   = Select-IaAutopilotDevice -Accent $Accent -Title 'Which Autopilot device to update?'
                if ([string]::IsNullOrWhiteSpace($serial)) { break }
                $groupTag = Read-IaText -Question 'New group tag (leave blank to skip)'
                $dispName = Read-IaText -Question 'New display name (leave blank to skip)'
                $params   = @{ Id = $serial }
                if ($groupTag) { $params['GroupTag']    = $groupTag }
                if ($dispName) { $params['DisplayName'] = $dispName }
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Updating…' -Color $Accent -ScriptBlock {
                    Set-IntuneAutopilotDevice @params -Confirm:$false
                }
                Write-IaHost "[$Accent]Updated.[/]"
                Read-IaPause | Out-Null
            }
            'List Autopilot profiles' {
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_appros = @(Get-IntuneAutopilotProfile)
                }
                $rows = $script:_appros | ForEach-Object { [ordered]@{ Name = $_.Name; Language = $_.Language; DeviceUsageType = $_.OobeSettings?.deviceUsageType; Modified = $_.Modified } }
                Format-IaTable -Data $rows -Accent $Accent -Title 'Autopilot Profiles'
                Read-IaPause | Out-Null
            }
            'Enrollment restrictions' {
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_restr = @(Get-IntuneEnrollmentRestriction)
                }
                $rows = $script:_restr | ForEach-Object { [ordered]@{ Name = $_.Name; Type = $_.Type; Priority = $_.Priority; Modified = $_.Modified } }
                Format-IaTable -Data $rows -Accent $Accent -Title 'Enrollment Restrictions'
                Read-IaPause | Out-Null
            }
            'Enrollment Status Pages*' {
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_esps = @(Get-IntuneESP)
                }
                $rows = $script:_esps | ForEach-Object { [ordered]@{ Name = $_.Name; Priority = $_.Priority; ShowProgress = $_.ShowInstallationProgress; TimeoutMin = $_.InstallProgressTimeoutInMinutes; TrackedApps = $_.TrackedAppCount } }
                Format-IaTable -Data $rows -Accent $Accent -Title 'Enrollment Status Pages'
                Read-IaPause | Out-Null
            }
            'Back' { return }
        } } catch { Write-IaHost "[coral]Error:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
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
        try { switch -Wildcard ($pick) {
            'List all*' {
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_baselines = @(Get-IntuneSecurityBaseline)
                }
                $rows = $script:_baselines | ForEach-Object { [ordered]@{ Name = $_.Name; Category = $_.Category; Platform = $_.Platform; Settings = $_.SettingCount; Modified = $_.Modified } }
                Format-IaTable -Data $rows -Accent $Accent -Title "Security Baselines ($($script:_baselines.Count))"
                Read-IaPause | Out-Null
            }
            'Filter by category' {
                $cat = Read-IaMenu -Title 'Category' -Color $Accent -Choices @('Baseline','Antivirus','DiskEncryption','Firewall','EndpointDetectionResponse','AttackSurfaceReduction','AccountProtection')
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_baselines = @(Get-IntuneSecurityBaseline -Category $cat)
                }
                $rows = $script:_baselines | ForEach-Object { [ordered]@{ Name = $_.Name; Platform = $_.Platform; Settings = $_.SettingCount; Modified = $_.Modified } }
                Format-IaTable -Data $rows -Accent $Accent -Title "$cat Baselines"
                Read-IaPause | Out-Null
            }
            'View baseline details' {
                $bl = Select-IaLoadedItem -Accent $Accent -Title 'Which baseline?' -Stem 'baseline-pick' -KeyProp 'Id' -Columns @('Name','Category','Platform') -Loader { Get-IntuneSecurityBaseline }
                if (-not $bl) { break }
                $name = $bl.Id
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                    $script:_bl = Get-IntuneSecurityBaseline -Id $name
                }
                if ($script:_bl) {
                    Write-IaHost "[$Accent]$($script:_bl.Name)[/]  Category: $($script:_bl.Category)  Platform: $($script:_bl.Platform)"
                    Write-IaHost "Baseline type: $($script:_bl.BaselineType)"
                    Write-IaHost "Settings: $($script:_bl.SettingCount)  Created: $($script:_bl.Created)  Modified: $($script:_bl.Modified)"
                }
                Read-IaPause | Out-Null
            }
            'Create from template' {
                $name  = Read-IaText -Question 'New baseline name'
                if ([string]::IsNullOrWhiteSpace($name)) { break }
                $tmpl = Select-IaLoadedItem -Accent $Accent -Title 'Which template?' -Stem 'sec-template-pick' -KeyProp 'Id' -Columns @('Name','Category','Platform') -Loader { Get-IntuneSecurityTemplate }
                if (-not $tmpl) { break }
                $tmplId = $tmpl.Id
                Invoke-IaStatus -Spinner 'Dots2' -Title 'Creating…' -Color $Accent -ScriptBlock {
                    $script:_newbl = New-IntuneSecurityBaseline -Name $name -TemplateId $tmplId -Confirm:$false
                }
                Write-IaHost "[$Accent]Created:[/] $($script:_newbl.Name) ($($script:_newbl.Id))"
                Read-IaPause | Out-Null
            }
            'Delete a baseline' {
                $bl = Select-IaLoadedItem -Accent $Accent -Title 'Which baseline to delete?' -Stem 'baseline-pick' -KeyProp 'Id' -Columns @('Name','Category','Platform') -Loader { Get-IntuneSecurityBaseline }
                if (-not $bl) { break }
                $name = $bl.Id
                $confirm = Read-IaMenu -Title "[red]Delete '$($bl.Name)'?[/]" -Color $Accent -Choices @('Yes, delete','Cancel')
                if ($confirm -eq 'Yes, delete') {
                    Invoke-IaStatus -Spinner 'Dots2' -Title 'Deleting…' -Color $Accent -ScriptBlock {
                        Remove-IntuneConfigurationPolicy -Id $name -Confirm:$false
                    }
                    Write-IaHost "[$Accent]Deleted.[/]"
                }
            }
            'Back' { return }
        } } catch { Write-IaHost "[coral]Error:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
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
            'Assignment filters (browse · create · delete)',
            'Other profiles (legacy device configs · ADMX templates)',
            'Back'
        )

        try { switch -Wildcard ($pick) {
            'Configuration*'      { Invoke-IaTuiConfigPolicies  -Accent $Accent }
            'Compliance*'         { Invoke-IaTuiCompliancePol   -Accent $Accent }
            'Scripts*'            { Invoke-IaTuiScripts         -Accent $Accent }
            'Remediations*'       { Invoke-IaTuiRemediations    -Accent $Accent }
            'Assignment filters*' { Invoke-IaTuiAssignmentFilters -Accent $Accent }
            'Other profiles*'     { Invoke-IaTuiLegacyConfig    -Accent $Accent }
            'Back'                { return }
        } } catch { Write-IaHost "[coral]Error:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
    }
}

function Invoke-IaTuiLegacyConfig {
    # Legacy/sibling configuration profile types that aren't Settings Catalog:
    # classic device configuration profiles and ADMX (administrative templates).
    # Authoring these needs structured bodies (CLI cmdlets); the TUI browses & deletes.
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Other config profiles' -Sub 'legacy device configs · ADMX templates' -Accent $Accent
    while ($true) {
        $action = Read-IaMenu -Title 'Other config profiles' -Color $Accent -Choices @(
            'List legacy device config profiles', 'Delete a legacy device config profile',
            'List admin templates (ADMX)', 'Delete an admin template (ADMX)', 'Back')
        if (-not $action -or $action -eq 'Back') { return }
        try {
            switch -Wildcard ($action) {
                'List legacy*' {
                    $dc = @(Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock { Get-IntuneDeviceConfiguration })
                    if (-not $dc) { Write-IaHost '[yellow]No legacy device configuration profiles.[/]'; Read-IaPause | Out-Null; continue }
                    $rows = @($dc | ForEach-Object { [pscustomobject][ordered]@{ Name = $_.Name; Type = $_.Type; Platform = $_.Platform; Modified = $_.Modified } })
                    Read-IaTablePause -Data $rows -Color $Accent -Title "Legacy device configs ($($rows.Count))" -Stem 'intune-legacy-dc' | Out-Null
                }
                'Delete a legacy*' {
                    $dc = Select-IaInventoryItem -Accent $Accent -ResourceType 'deviceConfigurations' -Title 'Which legacy device config to delete?' -AllowType
                    if (-not $dc) { continue }
                    $name = $dc.Id
                    if ((Read-IaMenu -Title "[red]Delete '$($dc.Name)'?[/]" -Color $Accent -Choices @('Yes, delete', 'Cancel')) -eq 'Yes, delete') {
                        Invoke-IaStatus -Spinner 'Dots2' -Title 'Deleting…' -Color $Accent -ScriptBlock { Remove-IntuneDeviceConfiguration -Id $name -Confirm:$false }
                        Write-IaHost "[$Accent]Deleted.[/]"
                    }
                }
                'List admin templates*' {
                    $at = @(Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock { Get-IntuneAdminTemplate })
                    if (-not $at) { Write-IaHost '[yellow]No admin templates.[/]'; Read-IaPause | Out-Null; continue }
                    $rows = @($at | ForEach-Object { [pscustomobject][ordered]@{ Name = $_.Name; Description = $_.Description; Modified = $_.Modified } })
                    Read-IaTablePause -Data $rows -Color $Accent -Title "Admin templates / ADMX ($($rows.Count))" -Stem 'intune-admx' | Out-Null
                }
                'Delete an admin template*' {
                    $at = Select-IaInventoryItem -Accent $Accent -ResourceType 'groupPolicyConfigurations' -Title 'Which admin template to delete?' -AllowType
                    if (-not $at) { continue }
                    $name = $at.Id
                    if ((Read-IaMenu -Title "[red]Delete '$($at.Name)'?[/]" -Color $Accent -Choices @('Yes, delete', 'Cancel')) -eq 'Yes, delete') {
                        Invoke-IaStatus -Spinner 'Dots2' -Title 'Deleting…' -Color $Accent -ScriptBlock { Remove-IntuneAdminTemplate -Id $name -Confirm:$false }
                        Write-IaHost "[$Accent]Deleted.[/]"
                    }
                }
            }
        } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
    }
}

function Invoke-IaTuiAssignmentFilters {
    # Assignment filters — browse, create (name · platform · rule), delete. The rule is
    # a filter expression, e.g. (device.deviceOwnership -eq "Corporate").
    param([string]$Accent)
    Write-IaTuiHeader -Screen 'Assignment Filters' -Sub 'device & app assignment scoping' -Accent $Accent
    while ($true) {
        $action = Read-IaMenu -Title 'Assignment filters' -Color $Accent -Choices @('List all', 'Create a filter', 'Delete a filter', 'Back')
        if (-not $action -or $action -eq 'Back') { return }
        try {
            switch -Wildcard ($action) {
                'List all' {
                    $fl = @(Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading filters…' -Color $Accent -ScriptBlock { Get-IntuneAssignmentFilter })
                    if (-not $fl) { Write-IaHost '[yellow]No assignment filters.[/]'; Read-IaPause | Out-Null; continue }
                    $rows = @($fl | ForEach-Object { [pscustomobject][ordered]@{ Name = $_.Name; Platform = $_.Platform; Rule = $_.Rule; Modified = $_.Modified } })
                    Read-IaTablePause -Data $rows -Color $Accent -Title "Assignment filters ($($rows.Count))" -Stem 'intune-filters' | Out-Null
                }
                'Create a filter' {
                    $nm = Read-IaText -Question 'Filter name'
                    if ([string]::IsNullOrWhiteSpace($nm)) { continue }
                    $plat = Read-IaMenu -Title 'Platform' -Color $Accent -Choices @('windows10AndLater', 'iOS', 'macOS', 'androidForWork', 'android', 'linux')
                    if (-not $plat) { continue }
                    $rule = Read-IaText -Question 'Rule (e.g. (device.deviceOwnership -eq "Corporate"))'
                    if ([string]::IsNullOrWhiteSpace($rule)) { Write-IaHost '[yellow]A rule is required.[/]'; Read-IaPause | Out-Null; continue }
                    if (Read-IaConfirm "Create $plat filter '$nm'?") {
                        $r = New-IntuneAssignmentFilter -Name $nm -Platform $plat -Rule $rule -Confirm:$false
                        Write-IaHost "[$Accent]✓ Created[/] '$($r.Name)' ($($r.Id))"; Read-IaPause | Out-Null
                    }
                }
                'Delete a filter' {
                    $fl = @(Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading filters…' -Color $Accent -ScriptBlock { Get-IntuneAssignmentFilter })
                    if (-not $fl) { Write-IaHost '[yellow]No assignment filters.[/]'; Read-IaPause | Out-Null; continue }
                    $fd = @($fl | ForEach-Object { [pscustomobject][ordered]@{ Name = $_.Name; Platform = $_.Platform; Rule = $_.Rule; Id = $_.Id } })
                    $fp = Read-IaTableInteractive -Data $fd -Color $Accent -Selectable -Title "Assignment filters ($($fd.Count)) · Enter = delete" -Stem 'intune-filter-rm'
                    if ($fp -and (Read-IaConfirm "[red]Delete filter '$($fp.Name)'? Any assignment using it will be affected.[/]")) {
                        Remove-IntuneAssignmentFilter -Id $fp.Id -Confirm:$false | Out-Null
                        Write-IaHost "[$Accent]✓ Deleted.[/]"; Read-IaPause | Out-Null
                    }
                }
            }
        } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
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
            Read-IaPause | Out-Null
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
            Read-IaPause | Out-Null
        }
        'View a policy*' {
            $pol = Select-IaInventoryItem -Accent $Accent -ResourceType 'configurationPolicies' -Title 'Which policy?' -AllowType
            if (-not $pol) { break }
            $name = $pol.Id
            Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                $script:_pol = Get-IntuneConfigurationPolicy -Id $name
            }
            if (-not $script:_pol) { return }
            Write-IaHost "[$Accent]$($script:_pol.Name)[/]  Platform: $($script:_pol.Platform)  Settings: $($script:_pol.SettingCount)"
            Write-IaHost "Description: $($script:_pol.Description)"
            Write-IaHost "Created: $($script:_pol.Created)  Modified: $($script:_pol.Modified)"
            $script:_pol.Settings | ForEach-Object { Write-IaHost "  - $($_.settingInstance.'@odata.type' -replace '.*\.', '')" }
            Read-IaPause | Out-Null
        }
        'Copy a policy' {
            $srcPol = Select-IaInventoryItem -Accent $Accent -ResourceType 'configurationPolicies' -Title 'Which policy to copy?' -AllowType
            if (-not $srcPol) { break }
            $src  = $srcPol.Id
            $dest = Read-IaText -Question 'New policy name'
            if ([string]::IsNullOrWhiteSpace($dest)) { break }
            Invoke-IaStatus -Spinner 'Dots2' -Title "Copying '$($srcPol.Name)'…" -Color $Accent -ScriptBlock {
                $script:_copy = Copy-IntuneConfigurationPolicy -SourceId $src -NewName $dest
            }
            Write-IaHost "[$Accent]Created:[/] $($script:_copy.Name) ($($script:_copy.Id))"
            Read-IaPause | Out-Null
        }
        'Delete a policy' {
            $pol = Select-IaInventoryItem -Accent $Accent -ResourceType 'configurationPolicies' -Title 'Which policy to delete?' -AllowType
            if (-not $pol) { break }
            $name = $pol.Id
            $confirm = Read-IaMenu -Title "[red]Delete '$($pol.Name)'?[/]" -Color $Accent -Choices @('Yes, delete', 'Cancel')
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
            Invoke-IaTuiPolicyStatusPicker -Accent $Accent -Items $script:_cpols -Area 'Compliance' -Title 'Compliance Policies'
        }
        'Filter by platform' {
            $plat = Read-IaMenu -Title 'Platform' -Color $Accent -Choices @('Windows','macOS','iOS','Android','AndroidWorkProfile')
            Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                $script:_cpols = @(Get-IntuneCompliancePolicy -Platform $plat)
            }
            Invoke-IaTuiPolicyStatusPicker -Accent $Accent -Items $script:_cpols -Area 'Compliance' -Title "$plat Compliance Policies"
        }
        'Delete a policy' {
            $cpol = Select-IaInventoryItem -Accent $Accent -ResourceType 'deviceCompliancePolicies' -Title 'Which compliance policy to delete?' -AllowType
            if (-not $cpol) { break }
            $name = $cpol.Id
            $confirm = Read-IaMenu -Title "[red]Delete '$($cpol.Name)'?[/]" -Color $Accent -Choices @('Yes, delete', 'Cancel')
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
            Read-IaPause | Out-Null
        }
        'List Windows*' {
            Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                $script:_scripts = @(Get-IntuneScript -Platform Windows)
            }
            $rows = $script:_scripts | ForEach-Object { [ordered]@{ Name = $_.Name; FileName = $_.FileName; RunAs = $_.RunAs; Modified = $_.Modified } }
            Format-IaTable -Data $rows -Accent $Accent -Title 'Windows Scripts'
            Read-IaPause | Out-Null
        }
        'List macOS*' {
            Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                $script:_scripts = @(Get-IntuneScript -Platform macOS)
            }
            $rows = $script:_scripts | ForEach-Object { [ordered]@{ Name = $_.Name; FileName = $_.FileName; RetryCount = $_.RetryCount; Modified = $_.Modified } }
            Format-IaTable -Data $rows -Accent $Accent -Title 'macOS Scripts'
            Read-IaPause | Out-Null
        }
        'View script content' {
            $scr = Select-IaInventoryItem -Accent $Accent -Area 'Scripts' -Title 'Which script?' -AllowType
            if (-not $scr) { break }
            $name = $scr.Id
            Invoke-IaStatus -Spinner 'Dots2' -Title 'Loading…' -Color $Accent -ScriptBlock {
                $script:_scr = Get-IntuneScript -Id $name -IncludeContent
            }
            if ($script:_scr) {
                Write-IaHost "[$Accent]$($script:_scr.Name)[/]  Platform: $($script:_scr.Platform)  RunAs: $($script:_scr.RunAs)"
                Write-IaHost "---"
                Write-IaHost ($script:_scr.Content ?? '(no content)')
            }
            Read-IaPause | Out-Null
        }
        'Delete a script' {
            $scr = Select-IaInventoryItem -Accent $Accent -Area 'Scripts' -Title 'Which script to delete?' -AllowType
            if (-not $scr) { break }
            $name = $scr.Id
            $confirm = Read-IaMenu -Title "[red]Delete '$($scr.Name)'?[/]" -Color $Accent -Choices @('Yes, delete', 'Cancel')
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
            Read-IaPause | Out-Null
        }
        'View remediation*' {
            $rem = Select-IaInventoryItem -Accent $Accent -ResourceType 'deviceHealthScripts' -Title 'Which remediation?' -AllowType
            if (-not $rem) { break }
            $name = $rem.Id
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
            Read-IaPause | Out-Null
        }
        'Run on-demand*' {
            $rem = Select-IaInventoryItem -Accent $Accent -ResourceType 'deviceHealthScripts' -Title 'Which remediation to run?' -AllowType
            if (-not $rem) { break }
            $remName = $rem.Id
            $devName = Select-IaManagedDevice -Accent $Accent -Title 'Run on which device?'
            if ([string]::IsNullOrWhiteSpace($devName)) { break }
            $confirm = Read-IaMenu -Title "Run '$($rem.Name)' on '$devName'?" -Color $Accent -Choices @('Yes, run it', 'Cancel')
            if ($confirm -eq 'Yes, run it') {
                Invoke-IaStatus -Spinner 'Dots2' -Title "Submitting…" -Color $Accent -ScriptBlock {
                    Invoke-IntuneRemediation -RemediationId $remName -Device $devName -Confirm:$false
                }
                Write-IaHost "[$Accent]Submitted.[/]"
            }
        }
        'Delete a remediation' {
            $rem = Select-IaInventoryItem -Accent $Accent -ResourceType 'deviceHealthScripts' -Title 'Which remediation to delete?' -AllowType
            if (-not $rem) { break }
            $name = $rem.Id
            $confirm = Read-IaMenu -Title "[red]Delete '$($rem.Name)'?[/]" -Color $Accent -Choices @('Yes, delete', 'Cancel')
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

function Invoke-IaTuiDeviceAct {
    # Confirm + send a single managedDevice action, with feedback.
    param([string]$Accent, [string]$Device, [string]$Action)
    $extra = @{}
    if ($Action -eq 'Rename') {
        $nn = Read-IaText -Question 'New device name'
        if ([string]::IsNullOrWhiteSpace($nn)) { return }
        $extra.NewName = $nn
    }
    if (-not (Read-IaConfirm "Send '$Action' to ${Device}?")) { return }
    try {
        Invoke-IaStatus -Spinner Dots -Title "Sending $Action…" -Color $Accent -ScriptBlock {
            Invoke-IntuneDeviceAction -Device $Device -Action $Action @extra -Confirm:$false
        } | Out-Null
        Write-IaHost "[$Accent]✓ $Action sent to $Device.[/]"
    } catch { Write-IaHost "[coral]Failed: $($_.Exception.Message)[/]" }
    Read-IaPause | Out-Null
}

function Invoke-IaTuiDeviceCard {
    # Reusable, ACTIONABLE device view: every field + the full hardwareInformation,
    # the compliance/config/app states, and device actions (sync / restart / locate /
    # lock / …). Reached from the dashboard device list and from Help desk.
    param([string]$Accent, [string]$Device)
    if ([string]::IsNullOrWhiteSpace($Device)) { return }
    while ($true) {
        $detail = Invoke-IaStatus -Spinner Dots -Title "Loading $Device…" -ScriptBlock { Get-IntuneDeviceDetail -Device $Device }
        if (-not $detail) { Write-IaHost "[yellow]No detail found for '$Device'.[/]"; Read-IaPause | Out-Null; return }
        $cs = "$($detail.ComplianceState)"
        $cc = if ($cs -eq 'compliant') { $Accent } elseif ($cs -in 'noncompliant', 'error') { 'coral' } else { 'grey' }
        $hdr = [System.Collections.Generic.List[string]]::new()
        $hdr.Add((ConvertFrom-IaMarkup "[dim][[[$Accent]JGI[/]]][/] [bold]Device card[/]"))
        $hdr.Add((ConvertFrom-IaMarkup "[grey]$($detail.Device)[/]  [dim]│[/]  [$cc]$cs[/]"))
        $hdr.Add('')
        $hdr.Add((ConvertFrom-IaMarkup ("[grey]{0,-12}[/] [white]{1}[/]" -f 'OS',      "$($detail.OS) $($detail.OSVersion)")))
        $hdr.Add((ConvertFrom-IaMarkup ("[grey]{0,-12}[/] [white]{1}[/]" -f 'Model',   "$($detail.Manufacturer) $($detail.Model)")))
        $hdr.Add((ConvertFrom-IaMarkup ("[grey]{0,-12}[/] [white]{1}[/]" -f 'Serial',  $detail.SerialNumber)))
        $hdr.Add((ConvertFrom-IaMarkup ("[grey]{0,-12}[/] [white]{1}[/]" -f 'User',    "$($detail.UserDisplayName)  $($detail.UserPrincipalName)")))
        $hdr.Add((ConvertFrom-IaMarkup ("[grey]{0,-12}[/] [white]{1}[/]" -f 'Storage', "Free $($detail.FreeStorageGB) / $($detail.TotalStorageGB) GB")))
        $hdr.Add((ConvertFrom-IaMarkup ("[grey]{0,-12}[/] [white]{1}[/]" -f 'Last sync', $detail.LastSyncAt)))
        $hdr.Add('')
        $cardHeader = ($hdr -join "`n")

        $sub = Read-IaMenu -Title "Device · $Device" -Color $Accent -Header $cardHeader -PageSize 12 -Choices @(
            'All fields & hardware (everything)',
            'Compliance policy states',
            'Configuration profile states',
            'Detected apps (inventory)',
            'Action: Sync now',
            'Action: Restart',
            'Action: Locate device',
            'Action: Set primary user',
            'Action: Set device category',
            'Action: more…',
            'Back'
        )
        if (-not $sub -or $sub -eq 'Back') { return }
        try { switch -Wildcard ($sub) {
            'All fields*' {
                $rows = [System.Collections.Generic.List[object]]::new()
                foreach ($p in $detail.PSObject.Properties) {
                    if ($p.Name -in 'Hardware', 'Apps', 'ConfigStates', 'ComplianceStates') { continue }
                    if ($null -eq $p.Value -or "$($p.Value)" -eq '') { continue }
                    $rows.Add([pscustomobject][ordered]@{ Property = $p.Name; Value = "$($p.Value)" })
                }
                if ($detail.Hardware) {
                    $hw = $detail.Hardware
                    $keys = if ($hw -is [System.Collections.IDictionary]) { @($hw.Keys) } else { @($hw.PSObject.Properties.Name) }
                    foreach ($k in ($keys | Sort-Object)) {
                        $v = $hw.$k
                        if ($null -eq $v -or "$v" -eq '') { continue }
                        $isC = ($v -is [System.Collections.IDictionary]) -or (($v -is [System.Collections.IEnumerable]) -and ($v -isnot [string]))
                        $sv = if ($isC) { ConvertTo-Json $v -Depth 4 -Compress } else { "$v" }
                        if ($sv.Length -gt 300) { $sv = $sv.Substring(0, 300) + '…' }
                        $rows.Add([pscustomobject][ordered]@{ Property = "hw.$k"; Value = $sv })
                    }
                }
                Read-IaTablePause -Data $rows.ToArray() -Stem "devcard-$Device" -Color $Accent -Title "All fields & hardware · $Device ($($rows.Count))"
            }
            'Compliance policy*' {
                $detail = Invoke-IaStatus -Spinner Dots -Title 'Loading…' -ScriptBlock { Get-IntuneDeviceDetail -Device $Device -IncludeComplianceState }
                if (-not $detail) { Write-IaHost '[yellow]Could not reload device detail — try again.[/]'; Read-IaPause | Out-Null; break }
                $rows = @($detail.ComplianceStates | ForEach-Object {
                    $c = if ($_.state -eq 'compliant') { $Accent } elseif ($_.state -in 'noncompliant', 'error') { 'coral' } else { 'grey' }
                    [pscustomobject][ordered]@{ Policy = $_.displayName; State = "[$c]$($_.state)[/]"; Platform = $_.platformType }
                })
                Read-IaTablePause -Data $rows -Stem "devcard-$Device-comp" -Color $Accent -Title "Compliance states · $Device ($($rows.Count))"
            }
            'Configuration profile*' {
                $detail = Invoke-IaStatus -Spinner Dots -Title 'Loading…' -ScriptBlock { Get-IntuneDeviceDetail -Device $Device -IncludeConfigState }
                if (-not $detail) { Write-IaHost '[yellow]Could not reload device detail — try again.[/]'; Read-IaPause | Out-Null; break }
                $rows = @($detail.ConfigStates | ForEach-Object {
                    $c = if ($_.state -eq 'compliant') { $Accent } elseif ($_.state -in 'error', 'conflict') { 'coral' } else { 'grey' }
                    [pscustomobject][ordered]@{ Profile = $_.displayName; State = "[$c]$($_.state)[/]"; Version = $_.version }
                })
                Read-IaTablePause -Data $rows -Stem "devcard-$Device-cfg" -Color $Accent -Title "Configuration states · $Device ($($rows.Count))"
            }
            'Detected apps*' {
                $detail = Invoke-IaStatus -Spinner Dots -Title 'Loading…' -ScriptBlock { Get-IntuneDeviceDetail -Device $Device -IncludeApps }
                if (-not $detail) { Write-IaHost '[yellow]Could not reload device detail — try again.[/]'; Read-IaPause | Out-Null; break }
                $rows = @($detail.Apps | ForEach-Object { [pscustomobject][ordered]@{ App = $_.App; Version = $_.Version } })
                Read-IaTablePause -Data $rows -Stem "devcard-$Device-apps" -Color $Accent -Title "Detected apps · $Device ($($rows.Count))"
            }
            'Action: Sync*'    { Invoke-IaTuiDeviceAct -Accent $Accent -Device $Device -Action 'Sync' }
            'Action: Restart*' { Invoke-IaTuiDeviceAct -Accent $Accent -Device $Device -Action 'Reboot' }
            'Action: Locate*'  { Invoke-IaTuiDeviceAct -Accent $Accent -Device $Device -Action 'LocateDevice' }
            'Action: Set primary user*' {
                $u = Select-IaUser -Accent $Accent -Title 'New primary user?'
                if ($u -and (Read-IaConfirm "Set $u as primary user of ${Device}?")) {
                    try { Set-IntuneDevicePrimaryUser -Device $Device -User $u -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Primary user set.[/]" }
                    catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)" }
                    Read-IaPause | Out-Null
                }
            }
            'Action: Set device category*' {
                $cats = @(Invoke-IaStatus -Spinner Dots -Title 'Loading categories…' -ScriptBlock { Get-IntuneDeviceCategory })
                if (-not $cats) { Write-IaHost '[yellow]No device categories defined.[/]'; Read-IaPause | Out-Null }
                else {
                    $cd = @($cats | ForEach-Object { [pscustomobject][ordered]@{ Category = $_.Category; Description = $_.Description } })
                    $cp = Read-IaTableInteractive -Data $cd -Color $Accent -Selectable -Title "Device categories ($($cd.Count)) · Enter = assign" -Stem 'dev-cat-pick'
                    if ($cp -and (Read-IaConfirm "Set ${Device}'s category to '$($cp.Category)'?")) {
                        try { Set-IntuneDeviceCategory -Device $Device -Category $cp.Category -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Category set.[/]" }
                        catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)" }
                        Read-IaPause | Out-Null
                    }
                }
            }
            'Action: more*'    {
                $a = Read-IaMenu -Title 'Device action' -Color $Accent -PageSize 14 -Choices @(
                    'Sync', 'Reboot', 'RemoteLock', 'LocateDevice', 'RotateBitLockerKeys', 'DefenderScan',
                    'DefenderUpdateSignatures', 'ResetPasscode', 'Rename', 'CollectDiagnostics',
                    'EnableLostMode', 'DisableLostMode', 'Cancel')
                if ($a -and $a -ne 'Cancel') { Invoke-IaTuiDeviceAct -Accent $Accent -Device $Device -Action $a }
            }
        } } catch { Write-IaHost "[coral]Error:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
    }
}

function Invoke-IaTuiHelpDesk {
    # Help desk hub: user lookup or device lookup.
    param([string]$Accent)
    while ($true) {
        $pick = Read-IaMenu -Title 'Help desk' -Color $Accent -Choices @(
            'User lookup (devices · groups · licenses · sign-in)',
            'Device lookup (hardware · compliance · apps · actions)',
            'Back'
        )
        if (-not $pick -or $pick -eq 'Back') { return }
        if ($pick -like 'User*') {
            Invoke-IaTuiUserLookup -Accent $Accent
        } else {
            $dev = Select-IaManagedDevice -Accent $Accent -Title 'Which device?'
            if (-not [string]::IsNullOrWhiteSpace($dev)) { Invoke-IaTuiDeviceCard -Accent $Accent -Device $dev }
        }
    }
}

function Invoke-IaTuiDashboard {
    # Live device-management overview for the first-page menu: KPI tiles plus
    # colour-graded bar charts, all computed from a single managedDevices read.
    param([string]$Accent)
    $devs = try { @(Invoke-IaStatus -Spinner Dots -Title 'Building device management dashboard…' -ScriptBlock {
        Get-IntuneDeviceInventory -Top 5000
    }) } catch { @() }
    Write-IaTuiHeader -Screen 'Tenant overview' -Sub 'devices · identity · health — live' -Accent $Accent
    if (-not $devs) { Write-IaHost '[yellow]No managed devices found.[/]'; Read-IaPause | Out-Null; return }

    $total   = @($devs).Count
    $comp    = @($devs | Where-Object { "$($_.Compliance)" -eq 'compliant' }).Count
    $noncomp = @($devs | Where-Object { "$($_.Compliance)" -eq 'noncompliant' }).Count
    $enc     = @($devs | Where-Object { $_.Encrypted }).Count
    $stale   = @($devs | Where-Object { $null -ne $_.DaysSinceSync -and $_.DaysSinceSync -ge 30 }).Count
    $compPct = if ($total) { [int][math]::Round($comp / $total * 100) } else { 0 }
    $ncPct   = if ($total) { [int][math]::Round($noncomp / $total * 100) } else { 0 }
    $encPct  = if ($total) { [int][math]::Round($enc / $total * 100) } else { 0 }

    $health  = { param($p) if ($p -ge 90) { $Accent } elseif ($p -ge 75) { 'yellow' } else { 'coral' } }
    $cClr = & $health $compPct
    $eClr = & $health $encPct
    $rClr = if ($noncomp -eq 0) { $Accent } else { 'coral' }
    $sClr = if ($stale -eq 0) { $Accent } elseif ($stale -le [math]::Ceiling($total * 0.1)) { 'yellow' } else { 'coral' }

    # Gauge bar from a percentage (filled vs track).
    $gauge = {
        param([int]$pct, [int]$width, [string]$color)
        $w = [int][math]::Round($pct / 100 * $width)
        $f = '█' * [Math]::Max(0, [Math]::Min($width, $w))
        $t = '░' * [Math]::Max(0, $width - $w)
        "[$color]$f[/][grey]$t[/]"
    }
    # Category breakdown bars (count vs the largest in the set).
    $drawBars = {
        param($pairs, [int]$width, [string]$color)
        $max = (@($pairs) | Measure-Object -Property Count -Maximum).Maximum
        foreach ($p in @($pairs)) {
            $w = if ($max) { [int][math]::Round($p.Count / $max * $width) } else { 0 }
            $bar = '█' * [Math]::Max($w, 1)
            $extra = if ($p.PSObject.Properties['Extra'] -and $p.Extra) { "  [grey]$($p.Extra)[/]" } else { '' }
            Write-IaHost ("  [grey]{0,-16}[/] [$color]{1}[/] [white]{2}[/]{3}" -f $p.Label, $bar, $p.Count, $extra)
        }
    }
    $groupBars = {
        param([string]$Prop, [string]$Fallback, [int]$Top, [string]$color)
        $g = @($devs | Group-Object $Prop | Sort-Object Count -Descending)
        if ($Top -gt 0) { $g = @($g | Select-Object -First $Top) }
        $pairs = foreach ($x in $g) {
            $lbl = if ("$($x.Name)") { "$($x.Name)" } else { $Fallback }
            [pscustomobject]@{ Label = $lbl; Count = $x.Count }
        }
        & $drawBars $pairs 30 $color
    }

    # ── KPI tiles ──────────────────────────────────────────────────────────
    $tile = { param($text, $color, $w = 16) $s = "$text"; "[$color]$s[/]" + (' ' * [Math]::Max(1, $w - $s.Length)) }
    Write-IaHost ''
    Write-IaHost (' ' + (& $tile '▎ DEVICES' $Accent) + (& $tile '▎ COMPLIANT' $cClr) + (& $tile '▎ AT RISK' $rClr) + (& $tile '▎ STALE 30d+' $sClr) + (& $tile '▎ ENCRYPTED' $eClr))
    Write-IaHost ('   ' + (& $tile $total 'white') + (& $tile "$compPct%" $cClr) + (& $tile $noncomp $rClr) + (& $tile $stale $sClr) + (& $tile "$encPct%" $eClr))

    # ── Identity & security KPIs (one guarded sweep — the deep view lives in Identity·Entra) ──
    $idn = try { Invoke-IaStatus -Spinner Dots -Title 'Reading identity KPIs…' -ScriptBlock {
        $enc       = { param($f) [uri]::EscapeDataString($f) }
        # Keep the lists, not just counts — the health check below reuses them.
        # Assign INSIDE try ($x = try { @(...) } would unroll an empty @() to
        # AutomationNull, making a healthy-but-empty tenant look like a failed probe).
        $riskyList = $null; $caList = $null; $credList = $null
        try { $riskyList = @(Get-EntraRiskyUser -AtRiskOnly) } catch { }
        try { $caList    = @(Get-EntraConditionalAccessPolicy) } catch { }
        try { $credList  = @(Get-EntraExpiringSecret -Days 30 -IncludeExpired) } catch { }
        [ordered]@{
            users     = Get-IaCount -Path 'users/$count'
            guests    = Get-IaCount -Path ('users/$count?$filter=' + (& $enc "userType eq 'Guest'"))
            risky     = ($null -eq $riskyList) ? $null : $riskyList.Count
            expiring  = ($null -eq $credList)  ? $null : $credList.Count
            caOn      = ($null -eq $caList)    ? $null : @($caList | Where-Object { $_.State -eq 'enabled' }).Count
            riskyList = $riskyList; credList = $credList; caList = $caList
        }
    } } catch { $null }
    if ($idn) {
        $fc = { param($n) if ($null -eq $n -or ($n -is [int] -and $n -lt 0)) { '—' } else { "$n" } }
        $riskClr = if ($null -eq $idn.risky) { 'grey' } elseif ($idn.risky -eq 0) { $Accent } else { 'coral' }
        $expClr  = if ($null -eq $idn.expiring) { 'grey' } elseif ($idn.expiring -eq 0) { $Accent } else { 'coral' }
        Write-IaHost ''
        Write-IaHost (' ' + (& $tile '▎ USERS' $Accent) + (& $tile '▎ GUESTS' $Accent) + (& $tile '▎ RISKY' $riskClr) + (& $tile '▎ EXPIRING' $expClr) + (& $tile '▎ CA ON' $Accent))
        Write-IaHost ('   ' + (& $tile (& $fc $idn.users) 'white') + (& $tile (& $fc $idn.guests) 'white') + (& $tile (& $fc $idn.risky) $riskClr) + (& $tile (& $fc $idn.expiring) $expClr) + (& $tile (& $fc $idn.caOn) 'white'))
    }

    # ── Compliance gauge ───────────────────────────────────────────────────
    Write-IaHost ''
    Write-IaRule -Title 'Compliance' -Color $Accent
    Write-IaHost ("  [grey]Compliant [/] $(& $gauge $compPct 40 $cClr) [white]$compPct%[/]  [grey]($comp/$total)[/]")
    Write-IaHost ("  [grey]At risk   [/] $(& $gauge $ncPct 40 'coral') [white]$noncomp[/]")
    Write-IaHost ("  [grey]Encrypted [/] $(& $gauge $encPct 40 $eClr) [white]$encPct%[/]  [grey]($enc/$total)[/]")

    # ── Breakdowns ─────────────────────────────────────────────────────────
    Write-IaHost ''
    Write-IaRule -Title 'By platform (compliance)' -Color $Accent
    $byPlat = foreach ($x in @($devs | Group-Object OS | Sort-Object Count -Descending)) {
        $c = @($x.Group | Where-Object { "$($_.Compliance)" -eq 'compliant' }).Count
        $pct = if ($x.Count) { [int][math]::Round($c / $x.Count * 100) } else { 0 }
        $lbl = if ("$($x.Name)") { "$($x.Name)" } else { 'Unknown' }
        [pscustomobject]@{ Label = $lbl; Count = $x.Count; Extra = "$pct% compliant" }
    }
    & $drawBars $byPlat 30 $Accent

    Write-IaRule -Title 'By enrollment source' -Color $Accent
    & $groupBars 'Source' 'Standard' 0 'deepskyblue1'

    Write-IaRule -Title 'By ownership' -Color $Accent
    & $groupBars 'Owner' 'unknown' 0 $Accent

    Write-IaRule -Title 'Top manufacturers' -Color $Accent
    & $groupBars 'Manufacturer' 'Unknown' 6 $Accent

    # ── Tenant health (the scheduled morning sweep, inline — reuses the loaded fleet) ──
    Write-IaHost ''
    Write-IaRule -Title 'Tenant health' -Color $Accent
    $hc = try { @(Invoke-IaStatus -Spinner Dots -Title 'Running health checks…' -ScriptBlock {
        $hcp = @{ DeviceInventory = $devs }   # reuse the identity sweep where it succeeded
        if ($idn) {
            if ($null -ne $idn.credList)  { $hcp.CredentialInventory = @($idn.credList) }
            if ($null -ne $idn.riskyList) { $hcp.RiskyUserInventory  = @($idn.riskyList) }
            if ($null -ne $idn.caList)    { $hcp.CaPolicyInventory   = @($idn.caList) }
        }
        Invoke-IntuneHealthCheck @hcp
    }) } catch { @() }
    if (-not $hc) { Write-IaHost '  [grey](health checks unavailable)[/]' }
    foreach ($h in $hc) {
        $clr  = switch ("$($h.Status)") { 'Pass' { $Accent } 'Warn' { 'yellow' } 'Fail' { 'coral' } default { 'grey' } }
        $mark = switch ("$($h.Status)") { 'Pass' { '●' } 'Warn' { '▲' } 'Fail' { '✖' } default { '·' } }
        $detail = "$($h.Detail)"; if ($detail.Length -gt 82) { $detail = $detail.Substring(0, 81) + '…' }
        Write-IaHost ("  [$clr]{0} {1,-5}[/] [white]{2,-36}[/] [grey]{3}[/]" -f $mark, $h.Status, $h.Check, (Protect-IaMarkup $detail))
    }

    Write-IaHost ''
    Write-IaHost '[grey]Live from Microsoft Graph · press any key for the per-device list…[/]'
    Read-IaPause | Out-Null

    # Per-device detail: OS, OS version, user (UPN), last sync — scrollable / searchable / exportable.
    $devRows = @($devs | ForEach-Object {
        $cc = switch ("$($_.Compliance)") { 'compliant' { $Accent } 'noncompliant' { 'coral' } default { 'grey' } }
        [pscustomobject][ordered]@{
            Device            = $_.Device
            OS                = $_.OS
            OSVersion         = $_.OSVersion
            UserPrincipalName = $_.UPN
            LastSync          = $_.LastSync
            Compliance        = "[$cc]$($_.Compliance)[/]"
        }
    })
    while ($true) {
        $picked = Read-IaTableInteractive -Data $devRows -Color $Accent -Selectable `
            -Title "Devices · OS · version · user · last sync ($total)  ·  Enter = open device" -Stem 'dashboard-devices'
        if (-not $picked) { break }   # q / Esc leaves the dashboard
        Invoke-IaTuiDeviceCard -Accent $Accent -Device "$($picked.Device)"
    }
}

function Show-IaAllFields {
    # Render every populated property of an object (incl. nested hashtables/arrays as
    # compact JSON) as a scrollable Property / Value table. The "all properties" view.
    param([string]$Accent, [object]$Object, [string]$Title = 'All fields', [string]$Stem = 'allfields', [switch]$NoExport)
    if ($null -eq $Object) { return }
    $keys = if ($Object -is [System.Collections.IDictionary]) { @($Object.Keys) } else { @($Object.PSObject.Properties.Name) }
    $rows = foreach ($k in ($keys | Sort-Object)) {
        if ("$k" -eq '@odata.type') { continue }
        $v = $Object.$k
        if ($null -eq $v -or "$v" -eq '') { continue }
        $isC = ($v -is [System.Collections.IDictionary]) -or (($v -is [System.Collections.IEnumerable]) -and ($v -isnot [string]))
        $sv = if ($isC) { try { ConvertTo-Json $v -Depth 5 -Compress } catch { "$v" } } else { "$v" }
        if ($sv.Length -gt 400) { $sv = $sv.Substring(0, 400) + '…' }
        [pscustomobject][ordered]@{ Property = $k; Value = $sv }
    }
    Read-IaTablePause -Data @($rows) -Stem $Stem -Color $Accent -Title "$Title ($(@($rows).Count) fields)" -NoExport:$NoExport
}

function Invoke-IaTuiReportView {
    # Run a loader (with spinner) and show the result in a scrollable/exportable table.
    # The table is selectable: Enter on any row opens its full property set ("all
    # properties for every category"). q/Esc backs out.
    param([string]$Accent, [string]$Title, [scriptblock]$Loader, [string]$Stem = 'entra', [switch]$NoExport)
    $rows = try { @(Invoke-IaStatus -Spinner Dots -Title "Loading $Title…" -ScriptBlock $Loader) } catch { @() }
    Write-IaTuiHeader -Screen $Title -Accent $Accent
    if (-not $rows) { Write-IaHost '[yellow]No data (or the scope/license for this report is missing).[/]'; Read-IaPause | Out-Null; return }
    $hint = if ($NoExport) { 'Enter = all fields' } else { 'Enter = all fields · e export' }
    while ($true) {
        $picked = Read-IaTableInteractive -Data $rows -Color $Accent -Selectable -NoExport:$NoExport -Title "$Title ($($rows.Count))  ·  $hint" -Stem $Stem
        if (-not $picked) { break }
        Show-IaAllFields -Accent $Accent -Object $picked -Title "$Title — all fields" -Stem "$Stem-fields" -NoExport:$NoExport
    }
}

function Invoke-IaTuiEntraDeletedItems {
    # Directory recycle bin — pick a type, then restore or permanently purge a
    # soft-deleted user / group / app registration (recoverable for 30 days).
    param([string]$Accent)
    while ($true) {
        $type = Read-IaMenu -Title 'Deleted items — which type?' -Color $Accent -Choices @('Users', 'Groups', 'Applications', 'Back')
        if (-not $type -or $type -eq 'Back') { return }
        $t = switch ($type) { 'Users' { 'User' } 'Groups' { 'Group' } 'Applications' { 'Application' } }
        $items = try { @(Invoke-IaStatus -Spinner Dots -Title "Loading deleted $type…" -ScriptBlock { Get-EntraDeletedItem -Type $t }) } catch { @() }
        if (-not $items) { Write-IaHost "[$Accent]✓ Nothing recoverable in the $type recycle bin.[/]"; Read-IaPause | Out-Null; continue }
        while ($true) {
            $disp = @($items | ForEach-Object { [pscustomobject][ordered]@{ DisplayName = $_.DisplayName; Identifier = $_.Identifier; Deleted = $_.Deleted; DaysLeft = $_.DaysLeft; Id = $_.Id } })
            $pk = Read-IaTableInteractive -Data $disp -Color $Accent -Selectable -Title "Deleted $type ($($disp.Count)) · Enter = manage" -Stem 'entra-deleted'
            if (-not $pk) { break }
            $act = Read-IaMenu -Title "$($pk.DisplayName)" -Color $Accent -Choices @('Restore', 'Purge permanently', 'Cancel')
            $changed = $false
            try {
                if ($act -eq 'Restore' -and (Read-IaConfirm "Restore '$($pk.DisplayName)'?")) { Restore-EntraDeletedItem -Id $pk.Id -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Restored.[/]"; Read-IaPause | Out-Null; $changed = $true }
                elseif ($act -eq 'Purge permanently' -and (Read-IaConfirm "[red]Permanently purge '$($pk.DisplayName)'? This cannot be undone.[/]")) { Remove-EntraDeletedItem -Id $pk.Id -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Purged.[/]"; Read-IaPause | Out-Null; $changed = $true }
            } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
            if ($changed) {
                $items = try { @(Invoke-IaStatus -Spinner Dots -Title 'Reloading…' -ScriptBlock { Get-EntraDeletedItem -Type $t }) } catch { @() }
                if (-not $items) { break }
            }
        }
    }
}

function Invoke-IaTuiEntraTenantSettings {
    # Tenant "Settings" toggles — what the default user role can do, guest-invite policy,
    # and the Security Defaults switch. Enter on a row flips / changes it.
    param([string]$Accent)
    while ($true) {
        $ap = $null; $sd = $null
        try { $ap = Invoke-IaStatus -Spinner Dots -Title 'Loading tenant settings…' -ScriptBlock { Get-EntraAuthorizationPolicy } } catch { }
        try { $sd = Get-EntraSecurityDefault } catch { }
        $rows = @()
        if ($ap) {
            $rows += [pscustomobject]@{ Setting = 'Users can register applications';   Raw = $ap.UsersCanCreateApps;           Key = 'apps' }
            $rows += [pscustomobject]@{ Setting = 'Users can create security groups';   Raw = $ap.UsersCanCreateSecurityGroups; Key = 'secgrp' }
            $rows += [pscustomobject]@{ Setting = 'Users can create tenants';           Raw = $ap.UsersCanCreateTenants;        Key = 'tenants' }
            $rows += [pscustomobject]@{ Setting = 'Users can read other users';         Raw = $ap.UsersCanReadOtherUsers;       Key = 'readusers' }
            $rows += [pscustomobject]@{ Setting = 'Users can use SSPR';                 Raw = $ap.AllowedToUseSSPR;             Key = 'sspr' }
            $rows += [pscustomobject]@{ Setting = 'Guest invites allowed from';         Raw = $ap.AllowInvitesFrom;             Key = 'invites' }
        }
        if ($sd) { $rows += [pscustomobject]@{ Setting = 'Security Defaults enabled'; Raw = $sd.Enabled; Key = 'secdef' } }
        if (-not $rows) { Write-IaHost '[yellow]Could not read tenant settings (needs Policy.Read.All).[/]'; Read-IaPause | Out-Null; return }
        $disp = @($rows | ForEach-Object {
            $vc = if ($_.Raw -is [bool]) { if ($_.Raw) { $Accent } else { 'grey' } } else { 'white' }
            [pscustomobject][ordered]@{ Setting = $_.Setting; Value = "[$vc]$($_.Raw)[/]"; _Key = $_.Key; _Raw = $_.Raw }
        })
        $picked = Read-IaTableInteractive -Data $disp -Color $Accent -Selectable -HideColumns '_Key', '_Raw' -Title 'Tenant settings · Enter = change' -Stem 'entra-tenant-settings'
        if (-not $picked) { return }
        $changed = $false
        try {
            if ($picked._Key -eq 'invites') {
                $v = Read-IaMenu -Title 'Allow guest invites from' -Color $Accent -Choices @('everyone', 'adminsGuestInvitersAndAllMembers', 'adminsAndGuestInviters', 'none', 'Cancel')
                if ($v -and $v -ne 'Cancel' -and (Read-IaConfirm "Set guest invites → '$v'?")) { Set-EntraAuthorizationPolicy -AllowInvitesFrom $v -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Updated.[/]"; Read-IaPause | Out-Null; $changed = $true }
            } elseif ($picked._Key -eq 'secdef') {
                $new = -not [bool]$picked._Raw
                if (Read-IaConfirm "[red]Set Security Defaults → ${new}? (turning off removes baseline MFA)[/]") { Set-EntraSecurityDefault -Enabled $new -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Updated.[/]"; Read-IaPause | Out-Null; $changed = $true }
            } else {
                $new   = -not [bool]$picked._Raw
                $param = switch ($picked._Key) { 'apps' { 'UsersCanCreateApps' } 'secgrp' { 'UsersCanCreateSecurityGroups' } 'tenants' { 'UsersCanCreateTenants' } 'readusers' { 'UsersCanReadOtherUsers' } 'sspr' { 'AllowedToUseSSPR' } }
                if (Read-IaConfirm "Set '$($picked.Setting)' → ${new}?") { $sp = @{ $param = $new; Confirm = $false }; Set-EntraAuthorizationPolicy @sp | Out-Null; Write-IaHost "[$Accent]✓ Updated.[/]"; Read-IaPause | Out-Null; $changed = $true }
            }
        } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
        if (-not $changed) { } # loop re-reads current state on next pass
    }
}

function Invoke-IaTuiEntraDevices {
    # Entra device objects (registered / joined) — filter, then enable / disable / delete
    # or view registered owners. Distinct from Intune managedDevices.
    param([string]$Accent)
    $scope = Read-IaMenu -Title 'Which devices?' -Color $Accent -Choices @('All', 'Disabled only', 'Stale (no sign-in 90d+)', 'Back')
    if (-not $scope -or $scope -eq 'Back') { return }
    $loader = switch -Wildcard ($scope) {
        'Disabled*' { { Get-EntraDevice -Disabled -Top 1000 } }
        'Stale*'    { { Get-EntraDevice -StaleDays 90 -Top 1000 } }
        default     { { Get-EntraDevice -Top 1000 } }
    }
    $project = { param($list, $ac) @($list | ForEach-Object { $ec = if ($_.Enabled) { $ac } else { 'grey' }; [pscustomobject][ordered]@{ DisplayName = $_.DisplayName; Enabled = "[$ec]$($_.Enabled)[/]"; _Enabled = [bool]$_.Enabled; OS = $_.OS; Trust = $_.Trust; Compliant = $_.Compliant; DaysStale = $_.DaysStale; _DeviceId = $_.DeviceId; Id = $_.Id } }) }
    $devs = try { @(Invoke-IaStatus -Spinner Dots -Title 'Loading Entra devices…' -ScriptBlock $loader) } catch { @() }
    if (-not $devs) { Write-IaHost '[yellow]No matching devices.[/]'; Read-IaPause | Out-Null; return }
    $disp = @(& $project $devs $Accent)
    while ($true) {
        $picked = Read-IaTableInteractive -Data $disp -Color $Accent -Selectable -HideColumns '_Enabled', '_DeviceId' -Title "Entra devices ($($disp.Count)) · Enter = manage" -Stem 'entra-devices'
        if (-not $picked) { return }
        $devId = $picked.Id; $devName = $picked.DisplayName; $aadDevId = $picked._DeviceId
        $toggle = if ($picked._Enabled) { 'Disable device' } else { 'Enable device' }
        $act = Read-IaMenu -Title "Device · $devName" -Color $Accent -PageSize 8 -Choices @($toggle, 'View registered owners', 'BitLocker recovery keys', 'LAPS local-admin password', 'Delete device object', 'Back')
        if (-not $act -or $act -eq 'Back') { continue }
        $changed = $false
        try {
            switch -Wildcard ($act) {
                'Disable*' { if (Read-IaConfirm "[red]Disable '$devName'? It can't authenticate until re-enabled.[/]") { Set-EntraDevice -Device $devId -AccountEnabled $false -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Disabled.[/]"; Read-IaPause | Out-Null; $changed = $true } }
                'Enable*'  { if (Read-IaConfirm "Enable '$devName'?") { Set-EntraDevice -Device $devId -AccountEnabled $true -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Enabled.[/]"; Read-IaPause | Out-Null; $changed = $true } }
                'View*'      { Invoke-IaTuiReportView -Accent $Accent -Title "Owners · $devName" -Stem 'entra-dev-owners' -Loader { Get-EntraDeviceRegisteredOwner -Device $devId } }
                'BitLocker*' { if (Read-IaConfirm "[red]Reveal BitLocker recovery key(s) for '$devName'? This is audited.[/]") { Invoke-IaTuiReportView -Accent $Accent -Title "BitLocker keys · $devName" -Stem 'entra-bitlocker' -NoExport -Loader { Get-EntraBitLockerKey -DeviceId $aadDevId -Reveal } } }
                'LAPS*'      { if (Read-IaConfirm "[red]Reveal the Windows LAPS local-admin password for '$devName'? This is audited.[/]") { Invoke-IaTuiReportView -Accent $Accent -Title "LAPS · $devName" -Stem 'entra-laps' -NoExport -Loader { Get-EntraLapsCredential -DeviceId $aadDevId } } }
                'Delete*'    { if (Read-IaConfirm "[red]Delete the Entra device object '$devName'? It must re-register to return.[/]") { Remove-EntraDevice -Device $devId -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Deleted.[/]"; Read-IaPause | Out-Null; $changed = $true } }
            }
        } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
        if ($changed) {
            $devs = try { @(Invoke-IaStatus -Spinner Dots -Title 'Reloading…' -ScriptBlock $loader) } catch { @() }
            if (-not $devs) { return }
            $disp = @(& $project $devs $Accent)
        }
    }
}

function Invoke-IaTuiEntraDashboard {
    # Live identity overview — KPI tiles, a secure-score gauge and breakdown bars, built
    # from cheap $count calls plus a few guarded report reads. Any metric whose
    # permission/license is missing renders as '—' rather than failing the whole view.
    param([string]$Accent, [hashtable]$Data)
    Write-IaTuiHeader -Screen 'Identity dashboard' -Sub 'live overview · Entra ID' -Accent $Accent
    $d = if ($Data) { $Data } else { try { Invoke-IaStatus -Spinner Dots -Title 'Building identity dashboard…' -ScriptBlock {
        $enc = { param($f) [uri]::EscapeDataString($f) }
        # Hoisted: a try/catch is a statement, not a hashtable-value expression. risky is the
        # COUNT (not the array) because an empty array stored as a dict value reads back as
        # $null — so a failed read must stay $null (renders '—') while zero-at-risk is 0
        # (renders '0'); the two must not collapse.
        $risky = try { @(Get-EntraRiskyUser -AtRiskOnly).Count } catch { $null }
        $score = try { @(Get-EntraSecureScore) }                catch { $null }
        [ordered]@{
            users    = Get-IaCount -Path 'users/$count'
            disabled = Get-IaCount -Path ('users/$count?$filter=' + (& $enc "accountEnabled eq false"))
            guests   = Get-IaCount -Path ('users/$count?$filter=' + (& $enc "userType eq 'Guest'"))
            groups   = Get-IaCount -Path 'groups/$count'
            m365     = Get-IaCount -Path ('groups/$count?$filter=' + (& $enc "groupTypes/any(c:c eq 'Unified')"))
            dynamic  = Get-IaCount -Path ('groups/$count?$filter=' + (& $enc "groupTypes/any(c:c eq 'DynamicMembership')"))
            apps     = Get-IaCount -Path 'applications/$count'
            sps      = Get-IaCount -Path 'servicePrincipals/$count'
            devices  = Get-IaCount -Path 'devices/$count'
            expiring = @(try { Get-EntraExpiringSecret -Days 30 -IncludeExpired } catch { @() }).Count
            risky    = $risky
            score    = $score
            ca       = @(try { Get-EntraConditionalAccessPolicy } catch { @() })
        }
    } } catch { [ordered]@{} } }
    if (-not $d -or $d.Count -eq 0) { Write-IaHost '[yellow]Could not load identity dashboard data.[/]'; Read-IaPause | Out-Null; return }

    # formatters: '—' when a count is unknown (-1) or a guarded read returned null
    $fc = { param($n) if ($null -eq $n -or ($n -is [int] -and $n -lt 0)) { '—' } else { "$n" } }
    $gauge = {
        param([int]$pct, [int]$width, [string]$color)
        $w = [int][math]::Round($pct / 100 * $width)
        "[$color]$('█' * [Math]::Max(0, [Math]::Min($width, $w)))[/][grey]$('░' * [Math]::Max(0, $width - $w))[/]"
    }
    $drawBars = {
        param($pairs, [int]$width, [string]$color)
        $max = (@($pairs) | Measure-Object -Property Count -Maximum).Maximum
        foreach ($p in @($pairs)) {
            $w = if ($max) { [int][math]::Round($p.Count / $max * $width) } else { 0 }
            Write-IaHost ("  [grey]{0,-18}[/] [$color]{1}[/] [white]{2}[/]" -f $p.Label, ('█' * [Math]::Max($w, 1)), $p.Count)
        }
    }
    $tile = { param($text, $color, $w = 14) $s = "$text"; "[$color]$s[/]" + (' ' * [Math]::Max(1, $w - $s.Length)) }

    $riskyN = if ($null -eq $d.risky) { $null } elseif ($d.risky -is [int]) { $d.risky } else { @($d.risky).Count }
    $scoreRow = if ($d.score) { @($d.score)[0] } else { $null }
    $scorePct = if ($scoreRow) { ConvertTo-IaSafeInt $scoreRow.Percent } else { $null }
    $caEnabled = @($d.ca | Where-Object { $_.State -eq 'enabled' }).Count
    $caReport  = @($d.ca | Where-Object { $_.State -eq 'enabledForReportingButNotEnforced' }).Count
    $caOff     = @($d.ca | Where-Object { $_.State -eq 'disabled' }).Count

    # ── KPI tiles ──────────────────────────────────────────────────────────
    $riskClr = if ($null -eq $riskyN) { 'grey' } elseif ($riskyN -eq 0) { $Accent } else { 'coral' }
    $expClr  = if ($d.expiring -eq 0) { $Accent } else { 'coral' }
    Write-IaHost ''
    Write-IaHost (' ' + (& $tile '▎ USERS' $Accent) + (& $tile '▎ GUESTS' $Accent) + (& $tile '▎ GROUPS' $Accent) + (& $tile '▎ APP REGS' $Accent) + (& $tile '▎ ENT APPS' $Accent))
    Write-IaHost ('   ' + (& $tile (& $fc $d.users) 'white') + (& $tile (& $fc $d.guests) 'white') + (& $tile (& $fc $d.groups) 'white') + (& $tile (& $fc $d.apps) 'white') + (& $tile (& $fc $d.sps) 'white'))
    Write-IaHost ''
    Write-IaHost (' ' + (& $tile '▎ DISABLED' 'grey') + (& $tile '▎ DEVICES' $Accent) + (& $tile '▎ RISKY' $riskClr) + (& $tile '▎ EXPIRING' $expClr) + (& $tile '▎ CA ON' $Accent))
    Write-IaHost ('   ' + (& $tile (& $fc $d.disabled) 'grey') + (& $tile (& $fc $d.devices) 'white') + (& $tile (& $fc $riskyN) $riskClr) + (& $tile (& $fc $d.expiring) $expClr) + (& $tile (& $fc $caEnabled) 'white'))

    # ── Secure score gauge ─────────────────────────────────────────────────
    Write-IaHost ''
    Write-IaRule -Title 'Microsoft Secure Score' -Color $Accent
    if ($null -ne $scorePct) {
        $scClr = if ($scorePct -ge 70) { $Accent } elseif ($scorePct -ge 45) { 'yellow' } else { 'coral' }
        Write-IaHost ("  [grey]Secure score[/] $(& $gauge $scorePct 40 $scClr) [white]$scorePct%[/]  [grey]($($scoreRow.Current)/$($scoreRow.Max))[/]")
    } else {
        Write-IaHost '  [grey]Secure score unavailable (needs SecurityEvents.Read.All).[/]'
    }

    # ── Breakdowns ─────────────────────────────────────────────────────────
    Write-IaHost ''
    Write-IaRule -Title 'Users' -Color $Accent
    $uMembers = if (($d.users -ge 0) -and ($d.guests -ge 0)) { [Math]::Max(0, $d.users - $d.guests) } else { 0 }
    & $drawBars @(
        [pscustomobject]@{ Label = 'Members'; Count = $uMembers }
        [pscustomobject]@{ Label = 'Guests'; Count = $(if ($d.guests -ge 0) { $d.guests } else { 0 }) }
        [pscustomobject]@{ Label = 'Disabled'; Count = $(if ($d.disabled -ge 0) { $d.disabled } else { 0 }) }
    ) 30 $Accent

    Write-IaRule -Title 'Groups' -Color $Accent
    $secGroups = if (($d.groups -ge 0) -and ($d.m365 -ge 0)) { [Math]::Max(0, $d.groups - $d.m365) } else { 0 }
    & $drawBars @(
        [pscustomobject]@{ Label = 'Security'; Count = $secGroups }
        [pscustomobject]@{ Label = 'Microsoft 365'; Count = $(if ($d.m365 -ge 0) { $d.m365 } else { 0 }) }
        [pscustomobject]@{ Label = 'Dynamic'; Count = $(if ($d.dynamic -ge 0) { $d.dynamic } else { 0 }) }
    ) 30 'deepskyblue1'

    Write-IaRule -Title 'Conditional Access' -Color $Accent
    if (@($d.ca).Count) {
        & $drawBars @(
            [pscustomobject]@{ Label = 'Enabled'; Count = $caEnabled }
            [pscustomobject]@{ Label = 'Report-only'; Count = $caReport }
            [pscustomobject]@{ Label = 'Disabled'; Count = $caOff }
        ) 30 $Accent
    } else { Write-IaHost '  [grey]No Conditional Access policies (or Policy.Read.All not consented).[/]' }

    Write-IaHost ''
    Write-IaHost '[grey]Live from Microsoft Graph beta · press any key to return…[/]'
    Read-IaPause | Out-Null
}

function Invoke-IaTuiEntra {
    # Identity (Entra) hub — first-page category that fans out to every Entra surface.
    param([string]$Accent)
    while ($true) {
        $pick = Read-IaMenu -Title 'Identity · Entra' -Color $Accent -PageSize 16 -Choices @(
            'Dashboard — live identity overview',
            'Users — lookup & manage',
            'Groups — list / create / manage',
            'Licenses — tenant SKUs',
            'Sign-ins',
            'Conditional Access — policies · create · named locations',
            'Risky users (Identity Protection)',
            'Applications — registrations (secret/cert expiry)',
            'Enterprise apps (service principals)',
            'Managed identities',
            'Devices — registered / joined (enable · disable · delete)',
            'Lifecycle — inactive users · guests',
            'Directory roles & assignments',
            'PIM — eligible & active',
            'Security / XDR — score · alerts · incidents',
            'Usage & quota — mailbox · OneDrive · SharePoint · Teams',
            'Tenant settings — user defaults · security defaults',
            'Deleted items — restore / purge users · groups · apps',
            'Back'
        )
        if (-not $pick -or $pick -eq 'Back') { return }
        try {
            switch -Wildcard ($pick) {
                'Dashboard*'          { Invoke-IaTuiEntraDashboard -Accent $Accent }
                'Users*'              { Invoke-IaTuiUserLookup -Accent $Accent }
                'Groups*'             { Invoke-IaTuiEntraGroups -Accent $Accent }
                'Licenses*'           { Invoke-IaTuiReportView -Accent $Accent -Title 'Licenses' -Stem 'entra-licenses' -Loader { Get-EntraLicense } }
                'Sign-ins*'           { Invoke-IaTuiReportView -Accent $Accent -Title 'Sign-ins (recent)' -Stem 'entra-signins' -Loader { Get-EntraSignIn -Top 200 } }
                'Conditional Access*' { Invoke-IaTuiEntraCA -Accent $Accent }
                'Risky users*'        { Invoke-IaTuiEntraRisky -Accent $Accent }
                'Applications*'       { Invoke-IaTuiEntraApps -Accent $Accent }
                'Enterprise apps*'    { Invoke-IaTuiEntraEnterpriseApp -Accent $Accent }
                'Managed identities*' { Invoke-IaTuiReportView -Accent $Accent -Title 'Managed identities' -Stem 'entra-mi' -Loader { Get-EntraManagedIdentity } }
                'Devices*'            { Invoke-IaTuiEntraDevices -Accent $Accent }
                'Tenant settings*'    { Invoke-IaTuiEntraTenantSettings -Accent $Accent }
                'Deleted items*'      { Invoke-IaTuiEntraDeletedItems -Accent $Accent }
                'Lifecycle*' {
                    $m = Read-IaMenu -Title 'Lifecycle & hygiene' -Color $Accent -Choices @('Inactive users (90+ days)', 'Inactive users (30+ days)', 'Guest accounts', 'Invite a guest user', 'Back')
                    switch -Wildcard ($m) {
                        'Inactive users (90*' { Invoke-IaTuiReportView -Accent $Accent -Title 'Inactive users (90+ days)' -Stem 'entra-inactive90' -Loader { Get-EntraInactiveUser -Days 90 } }
                        'Inactive users (30*' { Invoke-IaTuiReportView -Accent $Accent -Title 'Inactive users (30+ days)' -Stem 'entra-inactive30' -Loader { Get-EntraInactiveUser -Days 30 } }
                        'Guest accounts*'      { Invoke-IaTuiReportView -Accent $Accent -Title 'Guest accounts' -Stem 'entra-guests' -Loader { Get-EntraGuestUser } }
                        'Invite a guest*'      { Invoke-IaTuiEntraInviteGuest -Accent $Accent }
                    }
                }
                'Directory roles*'    { Invoke-IaTuiEntraRoles -Accent $Accent }
                'PIM*'                { Invoke-IaTuiEntraPim -Accent $Accent }
                'Security*' {
                    $m = Read-IaMenu -Title 'Security / XDR' -Color $Accent -Choices @('Secure score', 'Alerts', 'Incidents', 'Back')
                    switch ($m) {
                        'Secure score' { Invoke-IaTuiReportView -Accent $Accent -Title 'Secure score' -Stem 'secscore' -Loader { Get-EntraSecureScore } }
                        'Alerts'       { Invoke-IaTuiReportView -Accent $Accent -Title 'Security alerts' -Stem 'secalerts' -Loader { Get-EntraSecurityAlert } }
                        'Incidents'    { Invoke-IaTuiReportView -Accent $Accent -Title 'Security incidents' -Stem 'secinc' -Loader { Get-EntraSecurityIncident } }
                    }
                }
                'Usage*' {
                    $m = Read-IaMenu -Title 'Usage & quota' -Color $Accent -Choices @('Mailbox usage & quota', 'OneDrive usage', 'SharePoint sites', 'Teams activity', 'Microsoft 365 Apps', 'Back')
                    switch -Wildcard ($m) {
                        'Mailbox*'    { Invoke-IaTuiReportView -Accent $Accent -Title 'Mailbox usage & quota' -Stem 'mbx-usage' -Loader { Get-EntraMailboxUsage } }
                        'OneDrive*'   { Invoke-IaTuiReportView -Accent $Accent -Title 'OneDrive usage' -Stem 'od-usage' -Loader { Get-EntraOneDriveUsage } }
                        'SharePoint*' { Invoke-IaTuiReportView -Accent $Accent -Title 'SharePoint sites' -Stem 'sp-usage' -Loader { Get-EntraSharePointUsage } }
                        'Teams*'      { Invoke-IaTuiReportView -Accent $Accent -Title 'Teams activity' -Stem 'teams-usage' -Loader { Get-EntraTeamsUsage } }
                        'Microsoft 365*' { Invoke-IaTuiReportView -Accent $Accent -Title 'Microsoft 365 Apps usage' -Stem 'm365-usage' -Loader { Get-EntraM365AppUsage } }
                    }
                }
            }
        } catch { Write-IaHost "[coral]Error:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
    }
}

function Invoke-IaTuiEntraApps {
    # App registration / enterprise-app governance reports.
    param([string]$Accent)
    while ($true) {
        $m = Read-IaMenu -Title 'App registrations & governance' -Color $Accent -PageSize 13 -Choices @(
            'Create a new app registration',
            'Manage an app registration (permissions · consent)',
            'All app registrations (secret/cert expiry)',
            'Expiring secrets & certs (next 30 days)',
            'Expiring incl. enterprise apps (90 days, incl. expired)',
            'App registrations WITHOUT an owner',
            'Enterprise apps WITHOUT an owner',
            'Credential hygiene summary (status per app)',
            'App permissions & consent (pick an app)',
            'Tenant consent audit (risky Graph app permissions)',
            'Back'
        )
        if (-not $m -or $m -eq 'Back') { return }
        try { switch -Wildcard ($m) {
            'Create a new app*'          { Invoke-IaTuiEntraCreateApp -Accent $Accent }
            'Manage an app*'             { Invoke-IaTuiEntraAppManage -Accent $Accent }
            'All app*'                   { Invoke-IaTuiReportView -Accent $Accent -Title 'App registrations' -Stem 'entra-appregs' -Loader { Get-EntraAppRegistration } }
            'Expiring secrets*'          { Invoke-IaTuiReportView -Accent $Accent -Title 'Expiring secrets/certs (30d)' -Stem 'entra-expiring' -Loader { Get-EntraExpiringSecret -Days 30 } }
            'Expiring incl*'             { Invoke-IaTuiReportView -Accent $Accent -Title 'Expiring incl. enterprise apps (90d)' -Stem 'entra-expiring90' -Loader { Get-EntraExpiringSecret -Days 90 -IncludeExpired -IncludeServicePrincipals } }
            'App registrations WITHOUT*' { Invoke-IaTuiReportView -Accent $Accent -Title 'App regs without owner' -Stem 'entra-noowner' -Loader { Get-EntraAppWithoutOwner } }
            'Enterprise apps WITHOUT*'   { Invoke-IaTuiReportView -Accent $Accent -Title 'Enterprise apps without owner' -Stem 'entra-spnoowner' -Loader { Get-EntraAppWithoutOwner -EnterpriseApps } }
            'Credential hygiene*'        { Invoke-IaTuiReportView -Accent $Accent -Title 'App credential hygiene' -Stem 'entra-credhygiene' -Loader { Get-EntraAppCredentialSummary } }
            'App permissions*'           { Invoke-IaTuiEntraAppPerms -Accent $Accent }
            'Tenant consent audit*'      { Invoke-IaTuiEntraConsentAudit -Accent $Accent }
        } } catch { Write-IaHost "[coral]Error:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
    }
}

function Invoke-IaTuiEntraAppPerms {
    # Pick an enterprise app (service principal), then drill into every API permission
    # it actually holds — delegated consent grants plus granted application roles.
    param([string]$Accent)
    $apps = try { @(Invoke-IaStatus -Spinner Dots -Title 'Loading enterprise apps…' -ScriptBlock { Get-EntraEnterpriseApp -Top 500 }) } catch { @() }
    if (-not $apps) { Write-IaHost '[yellow]No enterprise apps.[/]'; Read-IaPause | Out-Null; return }
    $disp = @($apps | ForEach-Object { [pscustomobject][ordered]@{ DisplayName = $_.DisplayName; Type = $_.Type; Enabled = $_.Enabled; AppId = $_.AppId; Id = $_.Id } })
    while ($true) {
        $picked = Read-IaTableInteractive -Data $disp -Color $Accent -Selectable -Title "Enterprise apps ($($disp.Count)) · Enter = permissions" -Stem 'entra-sp-pick'
        if (-not $picked) { return }
        $spId = $picked.Id
        Invoke-IaTuiReportView -Accent $Accent -Title "Permissions · $($picked.DisplayName)" -Stem 'entra-sp-perms' -Loader { Get-EntraAppPermission -App $spId }
    }
}

function Invoke-IaTuiEntraConsentAudit {
    # Tenant consent audit — apps holding high-risk Graph application permissions.
    # Selectable: Enter on a row offers to revoke that permission from the app.
    param([string]$Accent)
    while ($true) {
        $rows = try { @(Invoke-IaStatus -Spinner Dots -Title 'Auditing Graph app consents…' -ScriptBlock { Get-EntraRiskyAppPermission }) } catch { @() }
        if (-not $rows) { Write-IaHost "[$Accent]✓ No high-risk or unresolved Graph application permissions found.[/]"; Read-IaPause | Out-Null; return }
        # pass the markup string (not pre-rendered ANSI) so `e` export stays clean
        # grant id is masked in the table (and exports); the real id rides along in the
        # hidden _GrantId column so the revoke still targets the right assignment.
        $disp = @($rows | ForEach-Object { $rc = if ($_.Risk -eq 'Unknown') { 'yellow' } else { 'coral' }; [pscustomobject][ordered]@{ App = $_.App; Permission = $_.Permission; Risk = "[$rc]$($_.Risk)[/]"; PrincipalType = $_.PrincipalType; AppId = $_.AppPrincipalId; GrantId = '•••'; _GrantId = $_.GrantId } })
        $picked = Read-IaTableInteractive -Data $disp -Color $Accent -Selectable -HideColumns '_GrantId' -Title "Risky Graph consents ($($disp.Count)) · Enter = revoke" -Stem 'entra-consent'
        if (-not $picked) { return }
        $act = Read-IaMenu -Title "$($picked.App) — $($picked.Permission)" -Color $Accent -Choices @('Revoke this permission', 'Cancel')
        if ($act -eq 'Revoke this permission' -and (Read-IaConfirm "[red]Revoke '$($picked.Permission)' from $($picked.App)?[/]")) {
            try {
                Remove-EntraAppRoleAssignment -ServicePrincipal $picked.AppId -AssignmentId $picked._GrantId -Confirm:$false | Out-Null
                Write-IaHost "[$Accent]✓ Revoked.[/]"; Read-IaPause | Out-Null
            } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
        }
    }
}

function Invoke-IaTuiEntraEnterpriseApp {
    # Enterprise apps (service principals) — browse, see exactly what each app can do
    # (delegated + application permissions), and revoke a grant. The portal's
    # "Enterprise applications → Permissions" blade, from the CLI.
    param([string]$Accent)
    $sps = try { @(Invoke-IaStatus -Spinner Dots -Title 'Loading enterprise apps…' -ScriptBlock { Get-EntraEnterpriseApp }) } catch { @() }
    if (-not $sps) { Write-IaHost '[yellow]No enterprise apps (service principals).[/]'; Read-IaPause | Out-Null; return }
    $disp = @($sps | ForEach-Object { [pscustomobject][ordered]@{ DisplayName = $_.DisplayName; AppId = $_.AppId; Id = $_.Id } })
    while ($true) {
        $picked = Read-IaTableInteractive -Data $disp -Color $Accent -Selectable -Title "Enterprise apps ($($disp.Count)) · Enter = manage" -Stem 'entra-entapp-pick'
        if (-not $picked) { return }
        $spId = $picked.Id; $spName = $picked.DisplayName
        while ($true) {
            $act = Read-IaMenu -Title "Enterprise app · $spName" -Color $Accent -Choices @(
                'View permissions (what it can do)', 'Revoke a delegated grant', 'Revoke an application permission', 'Back')
            if (-not $act -or $act -eq 'Back') { break }
            try {
                switch -Wildcard ($act) {
                    'View permissions*' {
                        Invoke-IaTuiReportView -Accent $Accent -Title "Permissions · $spName" -Stem 'entapp-perms' -Loader { Get-EntraAppPermission -App $spId }
                    }
                    'Revoke a delegated*' {
                        $raw = Invoke-IaStatus -Spinner Dots -Title 'Loading delegated grants…' -ScriptBlock { Get-EntraAppPermission -App $spId -Raw }
                        $grants = @($raw.Delegated)
                        if (-not $grants) { Write-IaHost '[yellow]No delegated grants.[/]'; Read-IaPause | Out-Null; continue }
                        $gd = @($grants | ForEach-Object { [pscustomobject][ordered]@{ Consent = $(if ($_.consentType -eq 'AllPrincipals') { 'Admin (all users)' } else { 'User' }); Scopes = ("$($_.scope)").Trim(); GrantId = '•••'; _GrantId = $_.id } })
                        $gp = Read-IaTableInteractive -Data $gd -Color $Accent -Selectable -HideColumns '_GrantId' -Title "Delegated grants ($($gd.Count)) · Enter = revoke" -Stem 'entapp-grant-rm'
                        if ($gp -and (Read-IaConfirm "[red]Revoke this delegated grant ($($gp.Scopes)) from ${spName}?[/]")) {
                            Remove-EntraOAuth2Grant -GrantId $gp._GrantId -Confirm:$false | Out-Null
                            Write-IaHost "[$Accent]✓ Revoked.[/]"; Read-IaPause | Out-Null
                        }
                    }
                    'Revoke an application*' {
                        $raw = Invoke-IaStatus -Spinner Dots -Title 'Loading application permissions…' -ScriptBlock { Get-EntraAppPermission -App $spId -Raw }
                        $assigns = @($raw.Application)
                        if (-not $assigns) { Write-IaHost '[yellow]No application permissions.[/]'; Read-IaPause | Out-Null; continue }
                        $ad = @($assigns | ForEach-Object { [pscustomobject][ordered]@{ Resource = $_.resourceDisplayName; AppRoleId = $_.appRoleId; AssignmentId = '•••'; _AssignmentId = $_.id } })
                        $ap = Read-IaTableInteractive -Data $ad -Color $Accent -Selectable -HideColumns '_AssignmentId' -Title "Application permissions ($($ad.Count)) · Enter = revoke" -Stem 'entapp-approle-rm'
                        if ($ap -and (Read-IaConfirm "[red]Revoke this application permission ($($ap.Resource)) from ${spName}?[/]")) {
                            Remove-EntraAppRoleAssignment -ServicePrincipal $spId -AssignmentId $ap._AssignmentId -Confirm:$false | Out-Null
                            Write-IaHost "[$Accent]✓ Revoked.[/]"; Read-IaPause | Out-Null
                        }
                    }
                }
            } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
        }
    }
}

function Select-IaApiPermission {
    # Searchable, selectable list of a resource API's published permissions. Returns
    # the chosen permission value (e.g. User.Read.All) or $null.
    param([string]$Accent, [string]$Resource, [ValidateSet('Application', 'Delegated')][string]$Type)
    $sp = Invoke-IaStatus -Spinner Dots -Title "Loading $Resource permissions…" -ScriptBlock { Resolve-EntraResourceApi -Resource $Resource }
    if (-not $sp) { Write-IaHost "[yellow]Couldn't resolve '$Resource'.[/]"; Read-IaPause | Out-Null; return $null }
    # Flag tenant-takeover-class permissions so the operator sees the risk before
    # requesting one (it pairs with the pre-consent warning in Grant-EntraAdminConsent).
    $perms = if ($Type -eq 'Application') {
        @($sp.appRoles | Where-Object { $_.isEnabled } | ForEach-Object { [pscustomobject][ordered]@{ Permission = $_.value; Risk = $(if (Test-EntraHighRiskPermission $_.value) { '[coral]High[/]' } else { '' }); Description = $_.displayName } })
    } else {
        @($sp.oauth2PermissionScopes | ForEach-Object { [pscustomobject][ordered]@{ Permission = $_.value; Risk = $(if (Test-EntraHighRiskPermission $_.value) { '[coral]High[/]' } else { '' }); Description = $_.adminConsentDisplayName } })
    }
    $perms = @($perms | Where-Object { $_.Permission } | Sort-Object Permission)
    if (-not $perms) { Write-IaHost "[yellow]No $Type permissions published by $Resource.[/]"; Read-IaPause | Out-Null; return $null }
    $picked = Read-IaTableInteractive -Data $perms -Color $Accent -Selectable -Title "$Resource · $Type ($($perms.Count)) · / search · Enter = pick" -Stem 'api-perm-pick'
    if ($picked) { $picked.Permission } else { $null }
}

function Invoke-IaTuiEntraAppManage {
    # Pick an app registration, then add/remove API permissions, grant admin consent
    # or create its enterprise app — the portal's "API permissions" blade, from the CLI.
    param([string]$Accent)
    $apps = try { @(Invoke-IaStatus -Spinner Dots -Title 'Loading app registrations…' -ScriptBlock { Get-EntraAppRegistration -Top 500 }) } catch { @() }
    if (-not $apps) { Write-IaHost '[yellow]No app registrations.[/]'; Read-IaPause | Out-Null; return }
    $disp = @($apps | ForEach-Object { [pscustomobject][ordered]@{ DisplayName = $_.DisplayName; AppId = $_.AppId; Audience = $_.SignInAudience; Id = $_.Id } })
    while ($true) {
        $picked = Read-IaTableInteractive -Data $disp -Color $Accent -Selectable -Title "App registrations ($($disp.Count)) · Enter = manage" -Stem 'appreg-pick'
        if (-not $picked) { return }
        $appId = $picked.Id; $appName = $picked.DisplayName
        while ($true) {
            $act = Read-IaMenu -Title "App registration · $appName" -Color $Accent -PageSize 13 -Choices @(
                'View current API permissions', 'Add an API permission', 'Remove an API permission',
                'Grant admin consent (tenant-wide)', 'Add a client secret', 'Manage redirect URIs',
                'Owners (view / add / remove)', 'Update (name / sign-in audience)',
                'Create enterprise app (service principal)', 'Delete this app registration', 'Back')
            if (-not $act -or $act -eq 'Back') { break }
            try {
                switch -Wildcard ($act) {
                    'View current*' {
                        Invoke-IaTuiReportView -Accent $Accent -Title "Requested permissions · $appName" -Stem 'appreg-perms' -Loader { Get-EntraAppRequestedPermission -App $appId }
                    }
                    'Add an API*' {
                        $rc = Read-IaMenu -Title 'Which API?' -Color $Accent -Choices @('Microsoft Graph', 'SharePoint', 'Exchange', 'Intune', 'Other (type a name / appId)')
                        if (-not $rc) { continue }
                        $resource = if ($rc -like 'Other*') { Read-IaText -Question 'Resource API name or appId' } else { $rc }
                        if ([string]::IsNullOrWhiteSpace($resource)) { continue }
                        $tc = Read-IaMenu -Title 'Permission type' -Color $Accent -Choices @('Application (app-only)', 'Delegated (on behalf of a user)')
                        $t  = if ($tc -like 'Delegated*') { 'Delegated' } else { 'Application' }
                        $perm = Select-IaApiPermission -Accent $Accent -Resource $resource -Type $t
                        if ($perm -and (Read-IaConfirm "Add $t permission '$perm' ($resource) to ${appName}?")) {
                            Add-EntraAppPermission -App $appId -Resource $resource -Permission $perm -Type $t -Confirm:$false | Out-Null
                            Write-IaHost "[$Accent]✓ Added.[/] Run 'Grant admin consent' to activate it."; Read-IaPause | Out-Null
                        }
                    }
                    'Remove an API*' {
                        $cur = @(Invoke-IaStatus -Spinner Dots -Title 'Loading requested permissions…' -ScriptBlock { Get-EntraAppRequestedPermission -App $appId })
                        if (-not $cur) { Write-IaHost '[yellow]This app requests no permissions.[/]'; Read-IaPause | Out-Null; continue }
                        $rdisp = @($cur | ForEach-Object { [pscustomobject][ordered]@{ Resource = $_.Resource; Permission = $_.Permission; Type = $_.Type } })
                        $pick2 = Read-IaTableInteractive -Data $rdisp -Color $Accent -Selectable -Title "Requested permissions ($($rdisp.Count)) · Enter = remove" -Stem 'appreg-perm-rm'
                        if ($pick2 -and (Read-IaConfirm "[red]Remove $($pick2.Type) permission '$($pick2.Permission)' ($($pick2.Resource)) from ${appName}?[/]")) {
                            Remove-EntraAppPermission -App $appId -Resource $pick2.Resource -Permission $pick2.Permission -Type $pick2.Type -Confirm:$false | Out-Null
                            Write-IaHost "[$Accent]✓ Removed.[/]"; Read-IaPause | Out-Null
                        }
                    }
                    'Grant admin*' {
                        # Name the dangerous scopes BEFORE the confirm — the cmdlet's own warning
                        # fires mid-spinner, after the decision, and can be overwritten on screen.
                        $req  = @(Invoke-IaStatus -Spinner Dots -Title 'Checking requested permissions…' -ScriptBlock { Get-EntraAppRequestedPermission -App $appId })
                        $high = @($req | Where-Object { Test-EntraHighRiskPermission -Name $_.Permission } | ForEach-Object { $_.Permission } | Sort-Object -Unique)
                        $warn = if ($high.Count) { "[red]⚠ Includes tenant-takeover-class scope(s): $($high -join ', ').[/] " } else { '' }
                        if (Read-IaConfirm "$warn[red]Grant tenant-wide admin consent for everything '$appName' requests?[/]") {
                            $res = @(Invoke-IaStatus -Spinner Dots -Title 'Granting admin consent…' -ScriptBlock { Grant-EntraAdminConsent -App $appId -Confirm:$false })
                            if ($res) { Read-IaTablePause -Data $res -Color $Accent -Title "Consent results · $appName" -Stem 'appreg-consent' | Out-Null }
                            else { Write-IaHost '[yellow]Nothing to consent.[/]'; Read-IaPause | Out-Null }
                        }
                    }
                    'Create enterprise*' {
                        if (Read-IaConfirm "Create the enterprise app (service principal) for '$appName'?") {
                            New-EntraServicePrincipal -App $appId -Confirm:$false | Out-Null
                            Write-IaHost "[$Accent]✓ Done.[/]"; Read-IaPause | Out-Null
                        }
                    }
                    'Add a client secret' {
                        $life = Read-IaMenu -Title 'Secret lifetime' -Color $Accent -Choices @('6 months', '12 months', '24 months')
                        if (-not $life) { continue }
                        $mo  = [int]($life -replace '\D')
                        $nm  = Read-IaText -Question 'Secret description (blank = default)'
                        if (Read-IaConfirm "[red]Add a $mo-month client secret to '$appName'? It is a credential shown once.[/]") {
                            $p = @{ App = $appId; Months = $mo; Confirm = $false }; if ($nm) { $p.DisplayName = $nm }
                            $sec = New-EntraAppSecret @p
                            Write-IaHost "[$Accent]✓ Secret created — copy it NOW (Graph won't show it again):[/]"
                            Write-IaHost "  [yellow]$($sec.Secret)[/]"
                            Write-IaHost "  [grey]id $($sec.SecretId) · expires $($sec.Expires)[/]"
                            Read-IaPause | Out-Null
                        }
                    }
                    'Manage redirect*' {
                        $plat = Read-IaMenu -Title 'Platform' -Color $Accent -Choices @('Web', 'Spa', 'PublicClient')
                        if (-not $plat) { continue }
                        $op = Read-IaMenu -Title "Redirect URIs · $plat" -Color $Accent -Choices @('Add a URI', 'Remove a URI', 'Back')
                        if ($op -eq 'Add a URI') {
                            $uri = Read-IaText -Question "New $plat redirect URI"
                            if ($uri -and (Read-IaConfirm "Add '$uri' ($plat) to ${appName}?")) {
                                Add-EntraAppRedirectUri -App $appId -Uri $uri -Platform $plat -Confirm:$false | Out-Null
                                Write-IaHost "[$Accent]✓ Added.[/]"; Read-IaPause | Out-Null
                            }
                        } elseif ($op -eq 'Remove a URI') {
                            $prop = $plat.ToLower()
                            $cur  = Invoke-IaStatus -Spinner Dots -Title 'Loading redirect URIs…' -ScriptBlock { Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "applications/${appId}?`$select=$prop") }
                            $uris = @($cur.$prop.redirectUris | ForEach-Object { [pscustomobject]@{ RedirectUri = $_ } })
                            if (-not $uris) { Write-IaHost "[yellow]No $plat redirect URIs.[/]"; Read-IaPause | Out-Null; continue }
                            $pk = Read-IaTableInteractive -Data $uris -Color $Accent -Selectable -Title "$plat redirect URIs ($($uris.Count)) · Enter = remove" -Stem 'appreg-uri-rm'
                            if ($pk -and (Read-IaConfirm "[red]Remove '$($pk.RedirectUri)'?[/]")) {
                                Remove-EntraAppRedirectUri -App $appId -Uri $pk.RedirectUri -Platform $plat -Confirm:$false | Out-Null
                                Write-IaHost "[$Accent]✓ Removed.[/]"; Read-IaPause | Out-Null
                            }
                        }
                    }
                    'Owners*' {
                        $op = Read-IaMenu -Title "Owners · $appName" -Color $Accent -Choices @('View owners', 'Add an owner', 'Remove an owner', 'Back')
                        switch -Wildcard ($op) {
                            'View*' { Invoke-IaTuiReportView -Accent $Accent -Title "Owners · $appName" -Stem 'appreg-owners' -Loader { Get-EntraAppOwner -App $appId } }
                            'Add*'  {
                                $u = Select-IaUser -Accent $Accent -Title 'Add which owner?'
                                if ($u -and (Read-IaConfirm "Make $u an owner of ${appName}?")) { Add-EntraAppOwner -App $appId -Owner $u -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Added.[/]"; Read-IaPause | Out-Null }
                            }
                            'Remove*' {
                                $owners = @(Invoke-IaStatus -Spinner Dots -Title 'Loading owners…' -ScriptBlock { Get-EntraAppOwner -App $appId })
                                if (-not $owners) { Write-IaHost '[yellow]No owners.[/]'; Read-IaPause | Out-Null; continue }
                                $od = @($owners | ForEach-Object { [pscustomobject][ordered]@{ Name = $_.Name; UPN = $_.UPN; Id = $_.Id } })
                                $po = Read-IaTableInteractive -Data $od -Color $Accent -Selectable -Title "Owners ($($od.Count)) · Enter = remove" -Stem 'appreg-owner-rm'
                                if ($po -and (Read-IaConfirm "[red]Remove owner $($po.Name) from ${appName}?[/]")) { Remove-EntraAppOwner -App $appId -Owner $po.Id -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Removed.[/]"; Read-IaPause | Out-Null }
                            }
                        }
                    }
                    'Update*' {
                        $nn = Read-IaText -Question 'New display name (blank = keep)'
                        if ($nn -and (Read-IaConfirm "Rename '$appName' to '$nn'?")) {
                            Set-EntraAppRegistration -App $appId -DisplayName $nn -Confirm:$false | Out-Null
                            $appName = $nn; Write-IaHost "[$Accent]✓ Renamed.[/]"; Read-IaPause | Out-Null
                        }
                    }
                    'Delete this app*' {
                        if (Read-IaConfirm "[red]Delete app registration '$appName'? This cannot be undone.[/]") {
                            Remove-EntraAppRegistration -App $appId -Confirm:$false | Out-Null
                            Write-IaHost "[$Accent]✓ Deleted.[/]"; Read-IaPause | Out-Null; break
                        }
                    }
                }
            } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
        }
    }
}

function Invoke-IaTuiEntraCreateApp {
    # Create a new app registration from the CLI.
    param([string]$Accent)
    $name = Read-IaText -Question 'App registration name'
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    $aud = Read-IaMenu -Title 'Who can sign in?' -Color $Accent -Choices @(
        'This tenant only', 'Any Entra tenant (multi-tenant)', 'Entra + personal Microsoft accounts', 'Personal Microsoft accounts only')
    $audience = switch -Wildcard ($aud) {
        'Any Entra*'   { 'AzureADMultipleOrgs' }
        'Entra +*'     { 'AzureADandPersonalMicrosoftAccount' }
        'Personal*'    { 'PersonalMicrosoftAccount' }
        default        { 'AzureADMyOrg' }
    }
    $uri = Read-IaText -Question 'Web redirect URI (blank = none)'
    if (-not (Read-IaConfirm "Create app registration '$name'?")) { return }
    try {
        $p = @{ Name = $name; SignInAudience = $audience; Confirm = $false }
        if ($uri) { $p.RedirectUri = $uri; $p.Platform = 'Web' }
        $a = New-EntraAppRegistration @p
        Write-IaHost "[$Accent]✓ Created[/] '$($a.DisplayName)'  ·  appId $($a.AppId)"
        Write-IaHost "[grey]Add a secret + API permissions via 'Manage an app registration'.[/]"
    } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)" }
    Read-IaPause | Out-Null
}

function Select-IaDirectoryRole {
    # Searchable, selectable list of directory role definitions. Returns the role name.
    param([string]$Accent)
    $roles = try { @(Invoke-IaStatus -Spinner Dots -Title 'Loading directory roles…' -ScriptBlock { Get-EntraDirectoryRole }) } catch { @() }
    if (-not $roles) { Write-IaHost '[yellow]No directory roles.[/]'; Read-IaPause | Out-Null; return $null }
    $disp = @($roles | ForEach-Object { [pscustomobject][ordered]@{ Role = $_.Role; Description = $_.Description; BuiltIn = $_.BuiltIn } })
    $pick = Read-IaTableInteractive -Data $disp -Color $Accent -Selectable -Title "Directory roles ($($disp.Count)) · / search · Enter = pick" -Stem 'dirrole-pick'
    if ($pick) { $pick.Role } else { $null }
}

function Invoke-IaTuiEntraCustomRoles {
    # Custom directory roles — list every role definition, browse the action catalogue,
    # and create / edit / delete custom (non-built-in) roles.
    param([string]$Accent)
    while ($true) {
        $op = Read-IaMenu -Title 'Custom roles' -Color $Accent -Choices @('List all role definitions', 'Browse available actions', 'Create a custom role', 'Edit / delete a custom role', 'Back')
        if (-not $op -or $op -eq 'Back') { return }
        try {
            switch -Wildcard ($op) {
                'List all*' { Invoke-IaTuiReportView -Accent $Accent -Title 'Role definitions' -Stem 'entra-roledefs' -Loader { Get-EntraRoleDefinition } }
                'Browse available*' {
                    $like = Read-IaText -Question 'Filter actions by text (blank = all)'
                    if ($like) { Invoke-IaTuiReportView -Accent $Accent -Title "Resource actions · '$like'" -Stem 'entra-roleactions' -Loader { Get-EntraRoleAction -Like $like } }
                    else       { Invoke-IaTuiReportView -Accent $Accent -Title 'Directory resource actions' -Stem 'entra-roleactions' -Loader { Get-EntraRoleAction } }
                }
                'Create a custom*' {
                    $nm = Read-IaText -Question 'Custom role name'
                    if ([string]::IsNullOrWhiteSpace($nm)) { continue }
                    $desc = Read-IaText -Question 'Description (blank = none)'
                    $acts = @(Invoke-IaStatus -Spinner Dots -Title 'Loading available actions…' -ScriptBlock { Get-EntraRoleAction })
                    if (-not $acts) { Write-IaHost '[yellow]Could not load the action catalogue.[/]'; Read-IaPause | Out-Null; continue }
                    $picked = Read-IaMultiMenu -Title "Allowed actions for '$nm'" -Choices (@($acts | ForEach-Object Action)) -Color $Accent -PageSize 18
                    if (-not $picked) { Write-IaHost '[yellow]No actions selected — a custom role needs at least one.[/]'; Read-IaPause | Out-Null; continue }
                    $privPicked = @($acts | Where-Object { $_.Action -in $picked -and $_.Privileged })
                    $warn = if ($privPicked.Count) { "[red]⚠ $($privPicked.Count) of the selected action(s) are PRIVILEGED (can elevate access).[/] " } else { '' }
                    if (Read-IaConfirm "${warn}Create custom role '$nm' with $($picked.Count) action(s)?") {
                        $p = @{ Name = $nm; AllowedResourceAction = @($picked); Confirm = $false }; if ($desc) { $p.Description = $desc }
                        $r = New-EntraRoleDefinition @p
                        Write-IaHost "[$Accent]✓ Created[/] '$($r.Name)' ($($r.Id))"; Read-IaPause | Out-Null
                    }
                }
                'Edit / delete*' {
                    $defs = @(Invoke-IaStatus -Spinner Dots -Title 'Loading custom roles…' -ScriptBlock { Get-EntraRoleDefinition -CustomOnly })
                    if (-not $defs) { Write-IaHost '[yellow]No custom roles in this tenant.[/]'; Read-IaPause | Out-Null; continue }
                    $dd = @($defs | ForEach-Object { [pscustomobject][ordered]@{ DisplayName = $_.DisplayName; Enabled = $_.Enabled; Actions = $_.Actions; Id = $_.Id } })
                    $pk = Read-IaTableInteractive -Data $dd -Color $Accent -Selectable -Title "Custom roles ($($dd.Count)) · Enter = manage" -Stem 'entra-customrole-pick'
                    if (-not $pk) { continue }
                    $act = Read-IaMenu -Title "$($pk.DisplayName)" -Color $Accent -Choices @('Rename', 'Enable', 'Disable', 'Delete', 'Cancel')
                    switch ($act) {
                        'Rename'  { $nn = Read-IaText -Question 'New name'; if ($nn -and (Read-IaConfirm "Rename to '$nn'?")) { Set-EntraRoleDefinition -Role $pk.Id -DisplayName $nn -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Renamed.[/]"; Read-IaPause | Out-Null } }
                        'Enable'  { if (Read-IaConfirm "Enable '$($pk.DisplayName)'?")  { Set-EntraRoleDefinition -Role $pk.Id -Enabled $true  -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Enabled.[/]";  Read-IaPause | Out-Null } }
                        'Disable' { if (Read-IaConfirm "Disable '$($pk.DisplayName)'?") { Set-EntraRoleDefinition -Role $pk.Id -Enabled $false -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Disabled.[/]"; Read-IaPause | Out-Null } }
                        'Delete'  { if (Read-IaConfirm "[red]Delete custom role '$($pk.DisplayName)'?[/]") { Remove-EntraRoleDefinition -Role $pk.Id -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Deleted.[/]"; Read-IaPause | Out-Null } }
                    }
                }
            }
        } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
    }
}

function Invoke-IaTuiEntraRoles {
    # Directory role assignments — view / assign (permanent) / remove.
    param([string]$Accent)
    while ($true) {
        $m = Read-IaMenu -Title 'Directory roles' -Color $Accent -Choices @('View role assignments', 'Assign a role to a user', 'Remove a role assignment', 'Custom roles (create / edit / delete)', 'Back')
        if (-not $m -or $m -eq 'Back') { return }
        try {
            switch -Wildcard ($m) {
                'Custom roles*' { Invoke-IaTuiEntraCustomRoles -Accent $Accent }
                'View*' { Invoke-IaTuiReportView -Accent $Accent -Title 'Role assignments' -Stem 'entra-roles' -Loader { Get-EntraRoleAssignment } }
                'Assign*' {
                    $u = Select-IaUser -Accent $Accent -Title 'Assign a role to which user?'
                    if (-not $u) { continue }
                    $role = Select-IaDirectoryRole -Accent $Accent
                    if ($role -and (Read-IaConfirm "[red]Assign '$role' to $u (permanent / active)?[/]")) {
                        New-EntraRoleAssignment -User $u -Role $role -Confirm:$false | Out-Null
                        Write-IaHost "[$Accent]✓ Assigned.[/]"; Read-IaPause | Out-Null
                    }
                }
                'Remove*' {
                    $as = @(Invoke-IaStatus -Spinner Dots -Title 'Loading role assignments…' -ScriptBlock { Get-EntraRoleAssignment })
                    if (-not $as) { Write-IaHost '[yellow]No role assignments.[/]'; Read-IaPause | Out-Null; continue }
                    $ad = @($as | ForEach-Object { [pscustomobject][ordered]@{ Role = $_.Role; Principal = $_.Principal; Type = $_.PrincipalType; Id = $_.Id } })
                    $p  = Read-IaTableInteractive -Data $ad -Color $Accent -Selectable -Title "Role assignments ($($ad.Count)) · Enter = remove" -Stem 'entra-role-rm'
                    if ($p -and (Read-IaConfirm "[red]Remove '$($p.Role)' from $($p.Principal)?[/]")) {
                        Remove-EntraRoleAssignment -AssignmentId $p.Id -Confirm:$false | Out-Null
                        Write-IaHost "[$Accent]✓ Removed.[/]"; Read-IaPause | Out-Null
                    }
                }
            }
        } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
    }
}

function Invoke-IaTuiEntraPim {
    # PIM — view eligible/active, activate one of YOUR eligible roles, or make a user eligible.
    param([string]$Accent)
    while ($true) {
        $m = Read-IaMenu -Title 'PIM (Privileged Identity Management)' -Color $Accent -PageSize 8 -Choices @(
            'Eligible roles (tenant)', 'Active roles (tenant)', 'Activate one of MY eligible roles',
            'Make a user eligible for a role', "Remove a user's eligibility", 'Back')
        if (-not $m -or $m -eq 'Back') { return }
        try {
            switch -Wildcard ($m) {
                'Eligible roles*' { Invoke-IaTuiReportView -Accent $Accent -Title 'PIM eligible' -Stem 'pim-elig' -Loader { Get-EntraPimEligibility } }
                'Active roles*'   { Invoke-IaTuiReportView -Accent $Accent -Title 'PIM active' -Stem 'pim-active' -Loader { Get-EntraPimActive } }
                'Activate one*' {
                    $mine = try { @(Invoke-IaStatus -Spinner Dots -Title 'Loading your eligible roles…' -ScriptBlock { Get-IaEligibleRoles }) } catch { @() }
                    if (-not $mine) { Write-IaHost '[yellow]You have no eligible roles (or this is an app-only sign-in).[/]'; Read-IaPause | Out-Null; continue }
                    $rd = @($mine | ForEach-Object { [pscustomobject][ordered]@{ Role = $_.roleDefinition.displayName; Scope = $_.directoryScopeId } })
                    $pk = Read-IaTableInteractive -Data $rd -Color $Accent -Selectable -Title "Your eligible roles ($($rd.Count)) · Enter = activate" -Stem 'pim-my-elig'
                    if (-not $pk) { continue }
                    $just = Read-IaText -Question 'Justification (required)'
                    if ([string]::IsNullOrWhiteSpace($just)) { Write-IaHost '[yellow]A justification is required.[/]'; Read-IaPause | Out-Null; continue }
                    $durC = Read-IaMenu -Title 'Activate for' -Color $Accent -Choices @('1 hour', '4 hours', '8 hours', '1 day')
                    $dur  = switch -Wildcard ($durC) { '1 hour*' { 'PT1H' } '4 hours*' { 'PT4H' } '1 day*' { 'P1D' } default { 'PT8H' } }
                    Enable-EntraPimRole -Role $pk.Role -Duration $dur -Justification $just -Confirm:$false | Out-Null
                    Write-IaHost "[$Accent]✓ Activation requested for '$($pk.Role)'.[/]"; Read-IaPause | Out-Null
                }
                'Make a user*' {
                    $u = Select-IaUser -Accent $Accent -Title 'Make which user eligible?'
                    if (-not $u) { continue }
                    $role = Select-IaDirectoryRole -Accent $Accent
                    if (-not $role) { continue }
                    $durC = Read-IaMenu -Title 'Eligibility window' -Color $Accent -Choices @('Permanent', '30 days', '90 days', '180 days')
                    $p = @{ User = $u; Role = $role; Confirm = $false }
                    switch -Wildcard ($durC) { '30 days*' { $p.Duration = '30d' } '90 days*' { $p.Duration = '90d' } '180 days*' { $p.Duration = '180d' } }
                    if (Read-IaConfirm "[red]Make $u eligible for '$role' ($durC)?[/]") {
                        New-EntraPimEligibility @p | Out-Null
                        Write-IaHost "[$Accent]✓ Eligibility granted.[/]"; Read-IaPause | Out-Null
                    }
                }
                "Remove a user's*" {
                    $elig = try { @(Invoke-IaStatus -Spinner Dots -Title 'Loading eligibilities…' -ScriptBlock { Get-EntraPimEligibility -Raw }) } catch { @() }
                    if (-not $elig) { Write-IaHost '[yellow]No PIM eligibilities.[/]'; Read-IaPause | Out-Null; continue }
                    $ed = @($elig | ForEach-Object { [pscustomobject][ordered]@{
                        Role        = if ($_.roleDefinition) { $_.roleDefinition.displayName } else { $_.roleDefinitionId }
                        Principal   = if ($_.principal) { ($_.principal.displayName ?? $_.principal.userPrincipalName) } else { $_.principalId }
                        Type        = if ($_.principal) { ($_.principal.'@odata.type' -replace '#microsoft\.graph\.', '') } else { $null }
                        PrincipalId = if ($_.principal) { $_.principal.id } else { $_.principalId }
                    } })
                    $ep = Read-IaTableInteractive -Data $ed -Color $Accent -Selectable -Title "PIM eligibilities ($($ed.Count)) · Enter = remove" -Stem 'pim-elig-rm'
                    if ($ep -and (Read-IaConfirm "[red]Remove $($ep.Principal)'s eligibility for '$($ep.Role)'?[/]")) {
                        Remove-EntraPimEligibility -User $ep.PrincipalId -Role $ep.Role -Confirm:$false | Out-Null
                        Write-IaHost "[$Accent]✓ Removed.[/]"; Read-IaPause | Out-Null
                    }
                }
            }
        } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
    }
}

function Invoke-IaTuiEntraTeamManage {
    # Pick a Team (Microsoft 365 group) → manage its channels and members.
    param([string]$Accent)
    $groups = try { @(Invoke-IaStatus -Spinner Dots -Title 'Loading Teams / Microsoft 365 groups…' -ScriptBlock { Get-EntraGroup -Top 500 | Where-Object { $_.Type -eq 'Microsoft 365' } }) } catch { @() }
    if (-not $groups) { Write-IaHost '[yellow]No Microsoft 365 groups / teams.[/]'; Read-IaPause | Out-Null; return }
    $disp = @($groups | ForEach-Object { [pscustomobject][ordered]@{ DisplayName = $_.DisplayName; Mail = $_.Mail; Id = $_.Id } })
    while ($true) {
        $picked = Read-IaTableInteractive -Data $disp -Color $Accent -Selectable -Title "Teams ($($disp.Count)) · Enter = manage" -Stem 'team-pick'
        if (-not $picked) { return }
        $teamId = $picked.Id; $teamName = $picked.DisplayName
        while ($true) {
            $act = Read-IaMenu -Title "Team · $teamName" -Color $Accent -Choices @('Channels (view / add / remove)', 'Members (view / add / remove)', 'Back')
            if (-not $act -or $act -eq 'Back') { break }
            try {
                switch -Wildcard ($act) {
                    'Channels*' {
                        $op = Read-IaMenu -Title "Channels · $teamName" -Color $Accent -Choices @('View channels', 'Add a channel', 'Remove a channel', 'Back')
                        switch -Wildcard ($op) {
                            'View*' { Invoke-IaTuiReportView -Accent $Accent -Title "Channels · $teamName" -Stem 'team-chan' -Loader { Get-EntraTeamChannel -Team $teamId } }
                            'Add*'  {
                                $cn = Read-IaText -Question 'Channel name'
                                if ([string]::IsNullOrWhiteSpace($cn)) { continue }
                                $priv = Read-IaConfirm 'Make it a private channel?'
                                if (Read-IaConfirm "Add channel '$cn' to ${teamName}?") { New-EntraTeamChannel -Team $teamId -Name $cn -Private:$priv -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Added.[/]"; Read-IaPause | Out-Null }
                            }
                            'Remove*' {
                                $chans = @(Invoke-IaStatus -Spinner Dots -Title 'Loading channels…' -ScriptBlock { Get-EntraTeamChannel -Team $teamId })
                                $cd = @($chans | Where-Object { $_.Name -ne 'General' } | ForEach-Object { [pscustomobject][ordered]@{ Name = $_.Name; Type = $_.Type; Id = $_.Id } })
                                if (-not $cd) { Write-IaHost '[yellow]No removable channels.[/]'; Read-IaPause | Out-Null; continue }
                                $cp = Read-IaTableInteractive -Data $cd -Color $Accent -Selectable -Title "Channels ($($cd.Count)) · Enter = remove" -Stem 'team-chan-rm'
                                if ($cp -and (Read-IaConfirm "[red]Delete channel '$($cp.Name)'?[/]")) { Remove-EntraTeamChannel -Team $teamId -Channel $cp.Id -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Deleted.[/]"; Read-IaPause | Out-Null }
                            }
                        }
                    }
                    'Members*' {
                        $op = Read-IaMenu -Title "Members · $teamName" -Color $Accent -Choices @('View members', 'Add a member', 'Add an owner', 'Remove a member', 'Back')
                        switch -Wildcard ($op) {
                            'View*' { Invoke-IaTuiReportView -Accent $Accent -Title "Members · $teamName" -Stem 'team-mem' -Loader { Get-EntraTeamMember -Team $teamId } }
                            'Add a member*' { $u = Select-IaUser -Accent $Accent -Title 'Add which user?'; if ($u -and (Read-IaConfirm "Add $u to ${teamName}?")) { Add-EntraTeamMember -Team $teamId -User $u -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Added.[/]"; Read-IaPause | Out-Null } }
                            'Add an owner*' { $u = Select-IaUser -Accent $Accent -Title 'Add which owner?'; if ($u -and (Read-IaConfirm "Make $u an owner of ${teamName}?")) { Add-EntraTeamMember -Team $teamId -User $u -Owner -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Added.[/]"; Read-IaPause | Out-Null } }
                            'Remove a member*' {
                                $mem = @(Invoke-IaStatus -Spinner Dots -Title 'Loading members…' -ScriptBlock { Get-EntraTeamMember -Team $teamId })
                                if (-not $mem) { Write-IaHost '[yellow]No members.[/]'; Read-IaPause | Out-Null; continue }
                                $md = @($mem | ForEach-Object { [pscustomobject][ordered]@{ Name = $_.Name; Email = $_.Email; Roles = $_.Roles; UserId = $_.UserId } })
                                $mp = Read-IaTableInteractive -Data $md -Color $Accent -Selectable -Title "Members ($($md.Count)) · Enter = remove" -Stem 'team-mem-rm'
                                if ($mp -and (Read-IaConfirm "[red]Remove $($mp.Name) from ${teamName}?[/]")) { Remove-EntraTeamMember -Team $teamId -User $mp.UserId -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Removed.[/]"; Read-IaPause | Out-Null }
                            }
                        }
                    }
                }
            } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
        }
    }
}

function Invoke-IaTuiBuildGroupFromQuery {
    # Query → push to group. Filter a population (stale devices / users by name /
    # inactive users), review it, then add the whole set to a new or existing group.
    param([string]$Accent)
    $src = Read-IaMenu -Title 'Build a group from…' -Color $Accent -PageSize 6 -Choices @(
        'Devices not synced in N days', 'Devices with a discovered app (Zscaler · Chrome < 126)',
        'Users by display-name prefix', 'Inactive users (no sign-in in N days)', 'Back')
    if (-not $src -or $src -eq 'Back') { return }

    $objIds = @(); $what = ''
    try {
        switch -Wildcard ($src) {
            'Devices not synced*' {
                $dC = Read-IaMenu -Title 'Not synced in…' -Color $Accent -Choices @('7 days', '14 days', '30 days', '60 days', '90 days')
                if (-not $dC) { return }
                $days = [int]($dC -replace '\D')
                $devs = @(Invoke-IaStatus -Spinner Dots -Title "Finding devices stale > $days days…" -ScriptBlock { Get-IntuneStaleDevice -Days $days })
                if (-not $devs) { Write-IaHost "[$Accent]✓ No devices stale beyond $days days.[/]"; Read-IaPause | Out-Null; return }
                $disp = @($devs | ForEach-Object { [pscustomobject][ordered]@{ DeviceName = $_.DeviceName; OS = $_.OS; LastSync = $_.LastSync; DaysStale = $_.DaysStale; User = $_.User } })
                Read-IaTablePause -Data $disp -Color $Accent -Title "Stale devices ($($devs.Count)) · not synced > $days days" -Stem 'q2g-dev' | Out-Null
                $what = "$($devs.Count) device(s) not synced > $days days"
                if (-not (Read-IaConfirm "Add these $($devs.Count) device(s) to a group?")) { return }
                $objIds = @(Invoke-IaStatus -Spinner Dots -Title 'Resolving device objects…' -ScriptBlock { $devs | ForEach-Object { Resolve-EntraDeviceObjectId -AzureAdDeviceId $_.AzureAdDeviceId } | Where-Object { $_ } })
            }
            'Devices with a discovered*' {
                $q = Read-IaText -Question 'App name contains (e.g. zscaler)'
                if ([string]::IsNullOrWhiteSpace($q)) { return }
                $bv = Read-IaText -Question 'Only versions below (blank = any version)' -DefaultAnswer ''
                $ap = @{ Name = $q; Devices = $true }
                if ($bv) { $ap.BelowVersion = $bv }
                $qSafe = Protect-IaMarkup $(if ($bv) { "'$q' below $bv" } else { "'$q'" })
                $rows = @(Invoke-IaStatus -Spinner Dots -Title "Finding devices with $qSafe…" -ScriptBlock { Get-IntuneDiscoveredApp @ap })
                if (-not $rows) { Write-IaHost "[$Accent]✓ No devices carry $qSafe.[/]"; Read-IaPause | Out-Null; return }
                $disp = @($rows | ForEach-Object { [pscustomobject][ordered]@{ App = $_.App; Version = $_.Version; Device = $_.Device; User = $_.User; OS = $_.OS } })
                Read-IaTablePause -Data $disp -Color $Accent -Title "Devices with $qSafe ($($rows.Count))" -Stem 'q2g-app' | Out-Null
                $what = "$($rows.Count) device row(s) with $qSafe"
                if (-not (Read-IaConfirm 'Add these devices to a group?')) { return }
                $objIds = @(Invoke-IaStatus -Spinner Dots -Title 'Resolving device objects…' -ScriptBlock {
                    $rows | ForEach-Object AzureAdDeviceId | Where-Object { $_ } | Select-Object -Unique |
                        ForEach-Object { try { Resolve-EntraDeviceObjectId -AzureAdDeviceId $_ } catch { $null } } | Where-Object { $_ }
                })
            }
            'Users by display-name*' {
                $prefix = Read-IaText -Question 'Display name starts with'
                if ([string]::IsNullOrWhiteSpace($prefix)) { return }
                $f = "startswith(displayName,'$($prefix.Replace("'", "''"))')"
                $users = @(Invoke-IaStatus -Spinner Dots -Title "Finding users starting '$prefix'…" -ScriptBlock { Get-EntraUser -Filter $f -Top 999 })
                if (-not $users) { Write-IaHost "[$Accent]No users match '$prefix'.[/]"; Read-IaPause | Out-Null; return }
                $disp = @($users | ForEach-Object { [pscustomobject][ordered]@{ DisplayName = $_.DisplayName; UPN = $_.UPN; Department = $_.Department } })
                Read-IaTablePause -Data $disp -Color $Accent -Title "Users starting '$prefix' ($($users.Count))" -Stem 'q2g-usr' | Out-Null
                $what = "$($users.Count) user(s) starting '$prefix'"
                if (-not (Read-IaConfirm "Add these $($users.Count) user(s) to a group?")) { return }
                $objIds = @($users | ForEach-Object { $_.Id } | Where-Object { $_ })
            }
            'Inactive users*' {
                $dC = Read-IaMenu -Title 'No sign-in in…' -Color $Accent -Choices @('30 days', '60 days', '90 days', '180 days')
                if (-not $dC) { return }
                $days = [int]($dC -replace '\D')
                $users = @(Invoke-IaStatus -Spinner Dots -Title "Finding users inactive > $days days…" -ScriptBlock { Get-EntraInactiveUser -Days $days })
                if (-not $users) { Write-IaHost "[$Accent]✓ No inactive users.[/]"; Read-IaPause | Out-Null; return }
                $disp = @($users | ForEach-Object { [pscustomobject][ordered]@{ User = $_.User; LastSignIn = $_.LastSignIn; DaysInactive = $_.DaysInactive } })
                Read-IaTablePause -Data $disp -Color $Accent -Title "Inactive users ($($users.Count))" -Stem 'q2g-inact' | Out-Null
                $what = "$($users.Count) user(s) inactive > $days days"
                if (-not (Read-IaConfirm "Add these $($users.Count) user(s) to a group?")) { return }
                $objIds = @($users | ForEach-Object { $_.Id } | Where-Object { $_ })
            }
        }
        if (-not $objIds) { Write-IaHost '[coral]Could not resolve any of those to directory objects.[/]'; Read-IaPause | Out-Null; return }

        $gMode = Read-IaMenu -Title "Target group for $what" -Color $Accent -Choices @('Create a new security group', 'Pick an existing group')
        if (-not $gMode) { return }
        $groupRef = $null; $groupName = $null
        if ($gMode -like 'Create*') {
            $gn = Read-IaText -Question 'New security-group name'
            if ([string]::IsNullOrWhiteSpace($gn)) { return }
            $g = New-EntraGroup -Name $gn -Type Security -Confirm:$false
            $groupRef = $g.Id; $groupName = $g.DisplayName
        } else {
            $groups = @(Invoke-IaStatus -Spinner Dots -Title 'Loading groups…' -ScriptBlock { Get-EntraGroup -Top 500 })
            if (-not $groups) { Write-IaHost '[yellow]No groups.[/]'; Read-IaPause | Out-Null; return }
            $gd = @($groups | ForEach-Object { [pscustomobject][ordered]@{ DisplayName = $_.DisplayName; Type = $_.Type; Membership = $_.Membership; Id = $_.Id } })
            $gp = Read-IaTableInteractive -Data $gd -Color $Accent -Selectable -Title 'Pick the target group · Enter = select' -Stem 'q2g-grp'
            if (-not $gp) { return }
            if ($gp.Membership -eq 'Dynamic') { Write-IaHost '[yellow]That group is dynamic — its members are rule-driven and cannot be set manually.[/]'; Read-IaPause | Out-Null; return }
            $groupRef = $gp.Id; $groupName = $gp.DisplayName
        }

        $res = Add-EntraGroupMemberBulk -Group $groupRef -MemberId $objIds -Confirm:$false
        $msg = "[$Accent]✓ Added $($res.Added) of $($res.Requested) → '$groupName'.[/]"
        if ($res.Failed) { $msg += " [coral]$($res.Failed) failed.[/]" }
        Write-IaHost $msg
    } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)" }
    Read-IaPause | Out-Null
}

function Invoke-IaTuiEntraInviteGuest {
    # Invite an external (B2B guest) user from the CLI.
    param([string]$Accent)
    $email = Read-IaText -Question 'External email address to invite'
    if ([string]::IsNullOrWhiteSpace($email)) { return }
    $name  = Read-IaText -Question 'Display name (blank = let Entra derive it)'
    $send  = Read-IaConfirm 'Email the invitation to them now?'
    if (-not (Read-IaConfirm "Invite $email as a guest?")) { return }
    try {
        $p = @{ EmailAddress = $email; Confirm = $false }
        if ($name) { $p.DisplayName = $name }
        if ($send) { $p.SendInvitationMessage = $true }
        $r = New-EntraGuestInvitation @p
        Write-IaHost "[$Accent]✓ Invited[/] $email  (user id $($r.UserId), status $($r.Status))"
        if ($r.RedeemUrl) { Write-IaHost "[grey]Redeem URL:[/] $($r.RedeemUrl)" }
    } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)" }
    Read-IaPause | Out-Null
}

function Invoke-IaTuiEntraCreateTeam {
    # Create a Microsoft 365 Team from the CLI.
    param([string]$Accent)
    $name = Read-IaText -Question 'Team name'
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    $owner = Select-IaUser -Accent $Accent -Title 'Who owns the team?'
    if (-not $owner) { return }
    $desc = Read-IaText -Question 'Description (blank = none)'
    $vis  = Read-IaMenu -Title 'Visibility' -Color $Accent -Choices @('Private', 'Public')
    if (-not $vis) { return }
    if (-not (Read-IaConfirm "Create $vis Team '$name' owned by ${owner}?")) { return }
    try {
        $p = @{ Name = $name; Owner = $owner; Visibility = $vis; Confirm = $false }
        if ($desc) { $p.Description = $desc }
        $r = New-EntraTeam @p
        if ($r.Teamified) { Write-IaHost "[$Accent]✓ Team created[/] '$name' (group $($r.GroupId))" }
        else { Write-IaHost "[yellow]Group created ($($r.GroupId)); Teams enablement is still finishing — check in a minute.[/]" }
    } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)" }
    Read-IaPause | Out-Null
}

function Invoke-IaTuiEntraGroups {
    param([string]$Accent)
    while ($true) {
        $action = Read-IaMenu -Title 'Groups & Teams' -Color $Accent -Choices @('Browse / manage groups', 'Create a group', 'Create a Microsoft 365 Team', 'Manage a Team (channels · members)', 'Back')
        if (-not $action -or $action -eq 'Back') { return }
        if ($action -like 'Manage a Team*') { Invoke-IaTuiEntraTeamManage -Accent $Accent; continue }
        if ($action -like 'Create a Microsoft 365 Team*') { Invoke-IaTuiEntraCreateTeam -Accent $Accent; continue }
        if ($action -like 'Create a group*') { Invoke-IaTuiEntraCreateGroup -Accent $Accent; continue }
        $groups = try { @(Invoke-IaStatus -Spinner Dots -Title 'Loading groups…' -ScriptBlock { Get-EntraGroup -Top 500 }) } catch { @() }
        if (-not $groups) { Write-IaHost '[yellow]No groups.[/]'; Read-IaPause | Out-Null; continue }
        $disp = @($groups | ForEach-Object { [pscustomobject][ordered]@{ DisplayName = $_.DisplayName; Type = $_.Type; Membership = $_.Membership; Mail = $_.Mail; Id = $_.Id } })
        while ($true) {
            $picked = Read-IaTableInteractive -Data $disp -Color $Accent -Selectable -Title "Groups ($($disp.Count)) · Enter = manage" -Stem 'entra-groups'
            if (-not $picked) { break }
            Invoke-IaTuiEntraGroupCard -Accent $Accent -Group $picked.Id -Name $picked.DisplayName
        }
    }
}

function Invoke-IaTuiEntraGroupCard {
    param([string]$Accent, [string]$Group, [string]$Name)
    while ($true) {
        $a = Read-IaMenu -Title "Group · $Name" -Color $Accent -PageSize 12 -Choices @(
            'Members', 'Owners', 'Add member', 'Remove member', 'Add owner', 'Remove owner', 'License (group-based)', 'Update (name/description/rule)', 'Delete group', 'Back')
        if (-not $a -or $a -eq 'Back') { return }
        try {
            switch -Wildcard ($a) {
                'License*' {
                    $op = Read-IaMenu -Title "Group licensing · $Name" -Color $Accent -Choices @('Assign a license', 'Remove a license', 'Back')
                    if ($op -in 'Assign a license', 'Remove a license') {
                        $skus = @(Invoke-IaStatus -Spinner Dots -Title 'Loading tenant SKUs…' -ScriptBlock { Get-EntraLicense })
                        $sd = @($skus | ForEach-Object { [pscustomobject][ordered]@{ DisplayName = $_.DisplayName; SkuPartNumber = $_.SkuPartNumber; Available = $_.Available } })
                        $sp = Read-IaTableInteractive -Data $sd -Color $Accent -Selectable -Title "Tenant SKUs ($($sd.Count)) · / search · Enter = pick" -Stem 'grp-lic-pick'
                        if ($sp) {
                            $verb = if ($op -like 'Assign*') { 'Assign' } else { 'Remove' }
                            if (Read-IaConfirm "$verb '$($sp.SkuPartNumber)' on group ${Name}?") {
                                $lp = @{ Group = $Group; Confirm = $false }; if ($op -like 'Assign*') { $lp.AddSku = $sp.SkuPartNumber } else { $lp.RemoveSku = $sp.SkuPartNumber }
                                Set-EntraGroupLicense @lp | Out-Null; Write-IaHost "[$Accent]✓ Done — members will be (de)licensed by Entra.[/]"; Read-IaPause | Out-Null
                            }
                        }
                    }
                }
                'Members'  { Invoke-IaTuiReportView -Accent $Accent -Title "Members · $Name" -Stem 'grp-members' -Loader { Get-EntraGroupMember -Group $Group } }
                'Owners'   { Invoke-IaTuiReportView -Accent $Accent -Title "Owners · $Name" -Stem 'grp-owners' -Loader { Get-EntraGroupOwner -Group $Group } }
                'Add member'    { $u = Select-IaUser -Accent $Accent -Title 'Add which user?'; if ($u -and (Read-IaConfirm "Add $u to ${Name}?")) { Add-EntraGroupMember -Group $Group -Member $u -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Added.[/]"; Read-IaPause | Out-Null } }
                'Remove member' { $u = Select-IaUser -Accent $Accent -Title 'Remove which user?'; if ($u -and (Read-IaConfirm "[red]Remove $u from ${Name}?[/]")) { Remove-EntraGroupMember -Group $Group -Member $u -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Removed.[/]"; Read-IaPause | Out-Null } }
                'Add owner'     { $u = Select-IaUser -Accent $Accent -Title 'Add which owner?'; if ($u -and (Read-IaConfirm "Make $u an owner of ${Name}?")) { Add-EntraGroupOwner -Group $Group -Owner $u -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Added.[/]"; Read-IaPause | Out-Null } }
                'Remove owner'  {
                    $owners = @(Invoke-IaStatus -Spinner Dots -Title 'Loading owners…' -ScriptBlock { Get-EntraGroupOwner -Group $Group })
                    if (-not $owners) { Write-IaHost '[yellow]No owners.[/]'; Read-IaPause | Out-Null; continue }
                    $od = @($owners | ForEach-Object { [pscustomobject][ordered]@{ Name = $_.Name; UPN = $_.UPN; Id = $_.Id } })
                    $po = Read-IaTableInteractive -Data $od -Color $Accent -Selectable -Title "Owners ($($od.Count)) · Enter = remove" -Stem 'grp-owner-rm'
                    if ($po -and (Read-IaConfirm "[red]Remove owner $($po.Name) from ${Name}?[/]")) { Remove-EntraGroupOwner -Group $Group -Owner $po.Id -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Removed.[/]"; Read-IaPause | Out-Null }
                }
                'Update*' {
                    $nn = Read-IaText -Question 'New display name (blank = keep)'
                    $dd = Read-IaText -Question 'New description (blank = keep)'
                    $p = @{ Group = $Group; Confirm = $false }
                    if ($nn) { $p.DisplayName = $nn }; if ($dd) { $p.Description = $dd }
                    if ($p.Count -gt 2) { Set-EntraGroup @p | Out-Null; Write-IaHost "[$Accent]✓ Updated.[/]"; Read-IaPause | Out-Null }
                }
                'Delete group' { if (Read-IaConfirm "[red]Delete group '$Name'? This cannot be undone.[/]") { Remove-EntraGroup -Group $Group -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Deleted.[/]"; Read-IaPause | Out-Null; return } }
            }
        } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
    }
}

function Invoke-IaTuiEntraCreateGroup {
    param([string]$Accent)
    $name = Read-IaText -Question 'Group name'
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    $type = Read-IaMenu -Title 'Group type' -Color $Accent -Choices @('Security', 'Microsoft365')
    $desc = Read-IaText -Question 'Description (blank = none)'
    $dyn  = Read-IaMenu -Title 'Membership' -Color $Accent -Choices @('Assigned (manual)', 'Dynamic (rule)')
    $rule = if ($dyn -like 'Dynamic*') { Read-IaText -Question 'Membership rule (e.g. user.department -eq "Sales")' } else { $null }
    if (-not (Read-IaConfirm "Create $type group '$name'?")) { return }
    $p = @{ Name = $name; Type = $type; Confirm = $false }
    if ($desc) { $p.Description = $desc }
    if ($rule) { $p.MembershipRule = $rule }
    try { $g = New-EntraGroup @p; Write-IaHost "[$Accent]✓ Created:[/] $($g.DisplayName) ($($g.Id))" }
    catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)" }
    Read-IaPause | Out-Null
}

function Invoke-IaTuiEntraCA {
    # Conditional Access hub — manage existing policies, author a new one, or manage
    # named locations. Authoring defaults to report-only so nothing locks the tenant.
    param([string]$Accent)
    while ($true) {
        $m = Read-IaMenu -Title 'Conditional Access' -Color $Accent -Choices @(
            'Policies — view / change state / delete', 'Create a policy', 'Named locations', 'Back')
        if (-not $m -or $m -eq 'Back') { return }
        switch -Wildcard ($m) {
            'Policies*'  { Invoke-IaTuiEntraCAPolicies -Accent $Accent }
            'Create*'    { Invoke-IaTuiEntraCACreate -Accent $Accent }
            'Named*'     { Invoke-IaTuiEntraNamedLocation -Accent $Accent }
        }
    }
}

function Invoke-IaTuiEntraCAPolicies {
    # List CA policies → change state or delete the picked one.
    param([string]$Accent)
    $pols = try { @(Invoke-IaStatus -Spinner Dots -Title 'Loading CA policies…' -ScriptBlock { Get-EntraConditionalAccessPolicy }) } catch { @() }
    if (-not $pols) { Write-IaHost '[yellow]No Conditional Access policies (or Policy.Read.All not consented).[/]'; Read-IaPause | Out-Null; return }
    while ($true) {
        $disp = @($pols | ForEach-Object { $sc = switch ($_.State) { 'enabled' { $Accent } 'disabled' { 'grey' } default { 'yellow' } }; [pscustomobject][ordered]@{ Name = $_.Name; State = "[$sc]$($_.State)[/]"; Controls = $_.Controls; Id = $_.Id } })
        $picked = Read-IaTableInteractive -Data $disp -Color $Accent -Selectable -Title "Conditional Access ($($disp.Count)) · Enter = act" -Stem 'entra-ca'
        if (-not $picked) { return }
        $act = Read-IaMenu -Title "$($picked.Name)" -Color $Accent -Choices @('Change state', 'Rename policy', 'Delete policy', 'Cancel')
        try {
            if ($act -eq 'Change state') {
                $st = Read-IaMenu -Title "Set '$($picked.Name)' to" -Color $Accent -Choices @('enabled', 'disabled', 'reportOnly', 'Cancel')
                if ($st -in 'enabled', 'disabled', 'reportOnly' -and (Read-IaConfirm "Set '$($picked.Name)' → ${st}?")) {
                    Set-EntraConditionalAccessState -Id $picked.Id -State $st -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Done.[/]"; Read-IaPause | Out-Null
                    $pols = @(Invoke-IaStatus -Spinner Dots -Title 'Reloading…' -ScriptBlock { Get-EntraConditionalAccessPolicy })
                }
            } elseif ($act -eq 'Rename policy') {
                $nn = Read-IaText -Question 'New policy name'
                if ($nn -and (Read-IaConfirm "Rename '$($picked.Name)' to '$nn'?")) {
                    Set-EntraConditionalAccessPolicy -Policy $picked.Id -DisplayName $nn -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Renamed.[/]"; Read-IaPause | Out-Null
                    $pols = @(Invoke-IaStatus -Spinner Dots -Title 'Reloading…' -ScriptBlock { Get-EntraConditionalAccessPolicy })
                }
            } elseif ($act -eq 'Delete policy') {
                if (Read-IaConfirm "[red]Delete CA policy '$($picked.Name)'? This cannot be undone.[/]") {
                    Remove-EntraConditionalAccessPolicy -Policy $picked.Id -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Deleted.[/]"; Read-IaPause | Out-Null
                    $pols = @(Invoke-IaStatus -Spinner Dots -Title 'Reloading…' -ScriptBlock { Get-EntraConditionalAccessPolicy })
                    if (-not $pols) { return }
                }
            }
        } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
    }
}

function Invoke-IaTuiEntraCACreate {
    # Author a CA policy from the common knobs. Report-only is the default state so a
    # new policy never enforces (or locks anyone out) until you deliberately enable it.
    param([string]$Accent)
    $name = Read-IaText -Question 'Policy display name'
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    $p = @{ Name = $name; Confirm = $false }
    try {
        $scope = Read-IaMenu -Title 'Who does it apply to?' -Color $Accent -Choices @('All users', 'A specific group', 'Guests / external users', 'Cancel')
        if (-not $scope -or $scope -eq 'Cancel') { return }
        switch -Wildcard ($scope) {
            'All users'  { $p.IncludeUsers = @('All') }
            'A specific*' {
                $g = Select-IaGroup -Accent $Accent -Title 'Apply to which group?'
                if (-not $g) { return }
                $p.IncludeGroups = @($g.Id)   # leaving IncludeUsers unset → includeUsers='None' (no tenant-wide union)
            }
            'Guests*'    { $p.IncludeUsers = @('GuestsOrExternalUsers') }
        }
        # Optional break-glass exclusion — strongly encouraged for an enforced policy.
        if (Read-IaConfirm 'Exclude a break-glass / emergency-access group?') {
            $exg = Select-IaGroup -Accent $Accent -Title 'Exclude which group?'
            if ($exg) { $p.ExcludeGroups = @($exg.Id) }
        }
        $grant = Read-IaMenu -Title 'Grant control' -Color $Accent -Choices @('Require MFA', 'Require compliant device', 'Block access', 'Cancel')
        if (-not $grant -or $grant -eq 'Cancel') { return }
        switch -Wildcard ($grant) {
            'Require MFA'       { $p.RequireMfa = $true }
            'Require compliant*' { $p.RequireCompliantDevice = $true }
            'Block access'      { $p.BlockAccess = $true }
        }
        $stC = Read-IaMenu -Title 'Initial state' -Color $Accent -Choices @('Report-only (recommended)', 'Enabled (enforce now)', 'Disabled', 'Cancel')
        if (-not $stC -or $stC -eq 'Cancel') { return }
        $p.State = switch -Wildcard ($stC) { 'Enabled*' { 'enabled' } 'Disabled' { 'disabled' } default { 'enabledForReportingButNotEnforced' } }

        $summary = "Create CA policy '$name' · $scope · $grant · state=$($p.State)?"
        if ($p.State -eq 'enabled' -and $grant -eq 'Block access') { $summary = "[red]$summary[/]" }
        if (-not (Read-IaConfirm $summary)) { return }
        $r = New-EntraConditionalAccessPolicy @p
        Write-IaHost "[$Accent]✓ Created[/] '$($r.Name)'  (state $($r.State), id $($r.Id))"
    } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)" }
    Read-IaPause | Out-Null
}

function Invoke-IaTuiEntraNamedLocation {
    # Named locations — view / add an IP-range or country location / remove one.
    param([string]$Accent)
    while ($true) {
        $m = Read-IaMenu -Title 'Named locations' -Color $Accent -Choices @(
            'View named locations', 'Add an IP-range location', 'Add a country location', 'Remove a named location', 'Back')
        if (-not $m -or $m -eq 'Back') { return }
        try {
            switch -Wildcard ($m) {
                'View*' { Invoke-IaTuiReportView -Accent $Accent -Title 'Named locations' -Stem 'entra-namedloc' -Loader { Get-EntraNamedLocation } }
                'Add an IP*' {
                    $nm = Read-IaText -Question 'Location name'
                    if ([string]::IsNullOrWhiteSpace($nm)) { continue }
                    $cidr = Read-IaText -Question 'CIDR range(s), comma- or space-separated (e.g. 203.0.113.0/24)'
                    $ranges = @($cidr -split '[,\s]+' | Where-Object { $_ })
                    if (-not $ranges) { Write-IaHost '[yellow]No CIDR range given.[/]'; Read-IaPause | Out-Null; continue }
                    $trusted = Read-IaConfirm 'Mark as a trusted location?'
                    if (Read-IaConfirm "Create IP location '$nm' with $($ranges.Count) range(s)?") {
                        $r = New-EntraNamedLocation -Name $nm -IpRange $ranges -Trusted:$trusted -Confirm:$false
                        Write-IaHost "[$Accent]✓ Created[/] '$($r.Name)' (id $($r.Id))"; Read-IaPause | Out-Null
                    }
                }
                'Add a country*' {
                    $nm = Read-IaText -Question 'Location name'
                    if ([string]::IsNullOrWhiteSpace($nm)) { continue }
                    $cc = Read-IaText -Question 'ISO country codes, comma- or space-separated (e.g. US, CA, GB)'
                    $codes = @($cc -split '[,\s]+' | Where-Object { $_ } | ForEach-Object { $_.ToUpper() })
                    if (-not $codes) { Write-IaHost '[yellow]No country codes given.[/]'; Read-IaPause | Out-Null; continue }
                    if (Read-IaConfirm "Create country location '$nm' with $($codes.Count) country/ies?") {
                        $r = New-EntraNamedLocation -Name $nm -Country $codes -Confirm:$false
                        Write-IaHost "[$Accent]✓ Created[/] '$($r.Name)' (id $($r.Id))"; Read-IaPause | Out-Null
                    }
                }
                'Remove*' {
                    $locs = @(Invoke-IaStatus -Spinner Dots -Title 'Loading named locations…' -ScriptBlock { Get-EntraNamedLocation })
                    if (-not $locs) { Write-IaHost '[yellow]No named locations.[/]'; Read-IaPause | Out-Null; continue }
                    $ld = @($locs | ForEach-Object { [pscustomobject][ordered]@{ Name = $_.Name; Kind = $_.Kind; Detail = $_.Detail; Id = $_.Id } })
                    $lp = Read-IaTableInteractive -Data $ld -Color $Accent -Selectable -Title "Named locations ($($ld.Count)) · Enter = remove" -Stem 'entra-namedloc-rm'
                    if ($lp -and (Read-IaConfirm "[red]Delete named location '$($lp.Name)'?[/]")) {
                        Remove-EntraNamedLocation -Location $lp.Id -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Deleted.[/]"; Read-IaPause | Out-Null
                    }
                }
            }
        } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
    }
}

function Invoke-IaTuiEntraRisky {
    param([string]$Accent)
    $users = try { @(Invoke-IaStatus -Spinner Dots -Title 'Loading risky users…' -ScriptBlock { Get-EntraRiskyUser }) } catch { @() }
    if (-not $users) { Write-IaHost '[yellow]No risky users (needs IdentityRiskyUser.ReadWrite.All scope + Entra ID P2 license).[/]'; Read-IaPause | Out-Null; return }
    while ($true) {
        $disp = @($users | ForEach-Object { $sc = switch ($_.RiskState) { 'atRisk' { 'coral' } 'confirmedCompromised' { 'red' } default { 'grey' } }; [pscustomobject][ordered]@{ User = $_.User; RiskLevel = $_.RiskLevel; RiskState = "[$sc]$($_.RiskState)[/]"; Updated = $_.Updated; Id = $_.Id } })
        $picked = Read-IaTableInteractive -Data $disp -Color $Accent -Selectable -Title "Risky users ($($disp.Count)) · Enter = act" -Stem 'entra-risky'
        if (-not $picked) { return }
        $act = Read-IaMenu -Title "$($picked.User)" -Color $Accent -Choices @('Dismiss risk', 'Confirm compromised', 'Cancel')
        try {
            if ($act -eq 'Dismiss risk' -and (Read-IaConfirm "Dismiss risk for $($picked.User)?")) { Set-EntraRiskyUser -UserId $picked.Id -Action Dismiss -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Dismissed.[/]"; Read-IaPause | Out-Null }
            elseif ($act -eq 'Confirm compromised' -and (Read-IaConfirm "[red]Confirm $($picked.User) as compromised?[/]")) { Set-EntraRiskyUser -UserId $picked.Id -Action Compromise -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Confirmed.[/]"; Read-IaPause | Out-Null }
        } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)"; Read-IaPause | Out-Null }
        $users = try { @(Invoke-IaStatus -Spinner Dots -Title 'Reloading…' -ScriptBlock { Get-EntraRiskyUser }) } catch { @() }
        if (-not $users) { Write-IaHost '[yellow]No risky users remain.[/]'; Read-IaPause | Out-Null; return }
    }
}

function Invoke-IaTuiUserActions {
    # Actionable Entra user management from the help desk: enable/disable, reset
    # password, revoke sessions, reset MFA, issue a TAP (passkey), group membership,
    # licensing, property updates. Every write confirms first.
    param([string]$Accent, [string]$Upn)
    while ($true) {
        $enabled = $null
        try { $enabled = (Get-EntraUser -User $Upn).Enabled } catch { }
        $toggle = if ($enabled -eq $false) { 'Enable account' } else { 'Disable account' }
        $act = Read-IaMenu -Title "Manage $Upn" -Color $Accent -PageSize 12 -Choices @(
            $toggle,
            'Reset password (temp + force change)',
            'Revoke all sign-in sessions',
            'Reset MFA (delete strong methods)',
            'Set per-user MFA state',
            'Add a phone (MFA) method',
            'Issue Temporary Access Pass (passkey enrollment)',
            'Add to a group',
            'Remove from a group',
            'Assign / remove a license',
            'Set / clear manager',
            'Update properties (job title · department · office)',
            'Back'
        )
        if (-not $act -or $act -eq 'Back') { return }
        try {
            switch -Wildcard ($act) {
                'Enable account'  { if (Read-IaConfirm "Enable ${Upn}?")          { Set-EntraUser -User $Upn -AccountEnabled $true  -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Enabled.[/]" } }
                'Disable account' { if (Read-IaConfirm "[red]Disable ${Upn}?[/]")  { Set-EntraUser -User $Upn -AccountEnabled $false -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Disabled.[/]" } }
                'Reset password*' {
                    if (Read-IaConfirm "[red]Reset password for '$Upn'? Their current password stops working immediately.[/]") {
                        $r = Reset-EntraUserPassword -User $Upn -Confirm:$false
                        Write-IaHost "[$Accent]✓ Temporary password:[/] [white]$($r.TempPassword)[/]  [grey](must change at next sign-in)[/]"
                    }
                }
                'Revoke all*' { if (Read-IaConfirm "[red]Sign $Upn out of every session?[/]") { Revoke-EntraUserSession -User $Upn -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Sessions revoked.[/]" } }
                'Reset MFA*'  { if (Read-IaConfirm "[red]Delete $Upn's strong MFA methods (forces re-register)?[/]") { $r = Reset-EntraUserMfa -User $Upn -Confirm:$false; Write-IaHost "[$Accent]✓ Removed $($r.MethodsRemoved) method(s).[/]" } }
                'Set per-user MFA*' {
                    $cur = $null; try { $cur = (Get-EntraUserMfaState -User $Upn).PerUserMfaState } catch { }
                    $st = Read-IaMenu -Title "Per-user MFA state ($(if ($cur) { "now: $cur" } else { 'unknown' }))" -Color $Accent -Choices @('disabled', 'enabled', 'enforced', 'Cancel')
                    if ($st -in 'disabled', 'enabled', 'enforced' -and (Read-IaConfirm "[red]Set $Upn per-user MFA → ${st}?[/]")) { Set-EntraUserMfaState -User $Upn -State $st -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Set to $st.[/]" }
                }
                'Add a phone*' {
                    $num = Read-IaText -Question 'Phone number (e.g. +1 2065551234)'
                    if (-not [string]::IsNullOrWhiteSpace($num)) {
                        $pt = Read-IaMenu -Title 'Phone type' -Color $Accent -Choices @('mobile', 'alternateMobile', 'office')
                        if ($pt -and (Read-IaConfirm "Add $pt phone '$num' for ${Upn}?")) { Add-EntraUserPhoneMethod -User $Upn -PhoneNumber $num -PhoneType $pt -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Added.[/]" }
                    }
                }
                'Issue Temporary*' {
                    # A TAP is a redeemable credential that lets the holder enroll an MFA
                    # method / passkey — i.e. it can bootstrap account takeover. Gate it
                    # like the other sensitive actions in this menu (it was unguarded).
                    if (Read-IaConfirm "[red]Issue a Temporary Access Pass for ${Upn}? It can be redeemed to enroll a passkey and bypass existing MFA.[/]") {
                        $r = New-EntraUserTempAccessPass -User $Upn -Confirm:$false
                        Write-IaHost "[$Accent]✓ Temporary Access Pass:[/] [white]$($r.TemporaryAccessPass)[/]  [grey](valid $($r.LifetimeMinutes) min — the user redeems it to enroll a passkey)[/]"
                    }
                }
                'Add to a group' {
                    $g = $null; try { $g = Select-IaGroup -Accent $Accent -Title 'Add to which group?' } catch { }
                    $gn = if ($g -and $g.Id) { $g.Id } else { Read-IaText -Question 'Group name or GUID' }
                    if (-not [string]::IsNullOrWhiteSpace($gn) -and (Read-IaConfirm "Add $Upn to $(if ($g) { $g.DisplayName } else { $gn })?")) {
                        Add-EntraUserToGroup -User $Upn -Group $gn -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Added.[/]"
                    }
                }
                'Remove from a group' {
                    $g = $null; try { $g = Select-IaGroup -Accent $Accent -Title 'Remove from which group?' } catch { }
                    $gn = if ($g -and $g.Id) { $g.Id } else { Read-IaText -Question 'Group name or GUID' }
                    if (-not [string]::IsNullOrWhiteSpace($gn) -and (Read-IaConfirm "[red]Remove $Upn from $(if ($g) { $g.DisplayName } else { $gn })?[/]")) {
                        Remove-EntraUserFromGroup -User $Upn -Group $gn -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Removed.[/]"
                    }
                }
                'Assign / remove*' {
                    $skus = @(Invoke-IaStatus -Spinner Dots -Title 'Loading tenant SKUs…' -ScriptBlock { Get-EntraLicense })
                    if (-not $skus) { Write-IaHost '[yellow]No SKUs found.[/]' }
                    else {
                        $mode = Read-IaMenu -Title 'License' -Color $Accent -Choices @('Assign', 'Remove', 'Cancel')
                        if ($mode -in 'Assign', 'Remove') {
                            $pick = Read-IaSelection -Title "$mode which SKU?" -Color $Accent -Choices (@($skus | ForEach-Object { "$($_.SkuPartNumber)  ($($_.Available) free)" }))
                            if ($pick) {
                                $sku = ($pick -split '  ')[0]
                                if ($mode -eq 'Assign') { Set-EntraUserLicense -User $Upn -AddSku $sku -Confirm:$false | Out-Null }
                                else { Set-EntraUserLicense -User $Upn -RemoveSku $sku -Confirm:$false | Out-Null }
                                Write-IaHost "[$Accent]✓ $mode $sku done.[/]"
                            }
                        }
                    }
                }
                'Set / clear manager' {
                    $cur = Invoke-IaStatus -Spinner Dots -Title 'Reading manager…' -ScriptBlock { Get-EntraUserManager -User $Upn }
                    if ($cur) { Write-IaHost "[grey]Current manager:[/] $($cur.Manager) ($($cur.ManagerUPN))" }
                    $op = Read-IaMenu -Title "Manager · $Upn" -Color $Accent -Choices @('Set a manager', 'Clear the manager', 'Cancel')
                    if ($op -eq 'Set a manager') {
                        $mgr = Select-IaUser -Accent $Accent -Title 'Who is the manager?'
                        if ($mgr -and (Read-IaConfirm "Set $mgr as manager of ${Upn}?")) { Set-EntraUser -User $Upn -ManagerUser $mgr -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Manager set.[/]" }
                    } elseif ($op -eq 'Clear the manager') {
                        if (Read-IaConfirm "[red]Clear ${Upn}'s manager?[/]") { Remove-EntraUserManager -User $Upn -Confirm:$false | Out-Null; Write-IaHost "[$Accent]✓ Manager cleared.[/]" }
                    }
                }
                'Update properties*' {
                    $jt  = Read-IaText -Question 'Job title (blank = skip)'
                    $dep = Read-IaText -Question 'Department (blank = skip)'
                    $off = Read-IaText -Question 'Office location (blank = skip)'
                    $p = @{ User = $Upn; Confirm = $false }
                    if ($jt)  { $p.JobTitle = $jt }
                    if ($dep) { $p.Department = $dep }
                    if ($off) { $p.OfficeLocation = $off }
                    if ($p.Count -gt 2) { Set-EntraUser @p | Out-Null; Write-IaHost "[$Accent]✓ Updated.[/]" } else { Write-IaHost '[grey]Nothing to update.[/]' }
                }
            }
        } catch { Write-IaHost "[coral]Failed:[/] $($_.Exception.Message)" }
        Read-IaPause | Out-Null
    }
}

function Invoke-IaTuiUserLookup {
    # Help-desk user report (devices, groups, licenses, sign-in/MFA). Reachable
    # from the first-page menu and from Reports.
    param([string]$Accent)
            $upn = Select-IaUser -Accent $Accent -Title 'Which user to look up?'
            if ([string]::IsNullOrWhiteSpace($upn)) { return }
            $stemU = ($upn -replace '[^\w.-]', '_')
            Write-IaTuiHeader -Screen 'User lookup' -Sub $upn -Accent $Accent

            # Pull the full help-desk profile once — managed devices, Entra group
            # memberships and assigned licenses (groups + licenses come from the beta
            # /users endpoints). Cached so each drill-in renders instantly and the
            # "Overview" can show all three together.
            $prof = Invoke-IaStatus -Spinner Dots -Title "Building help-desk profile for $upn…" -ScriptBlock {
                [pscustomobject]@{
                    Devices  = @(try { Get-IntuneUserDevice          -User $upn } catch { @() })
                    Groups   = @(try { Get-IntuneUserGroupMembership -User $upn } catch { @() })
                    Licenses = @(try { Get-IntuneUserLicense         -User $upn } catch { @() })
                }
            }
            $uDevices  = @($prof.Devices)
            $uGroups   = @($prof.Groups)
            $uLicenses = @($prof.Licenses)
            $compliant = @($uDevices | Where-Object { "$($_.Compliance)" -eq 'compliant' }).Count

            $hdr = [System.Collections.Generic.List[string]]::new()
            $hdr.Add((ConvertFrom-IaMarkup "[dim][[[$Accent]JGI[/]]][/] [bold]User lookup[/]"))
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
                    'Manage user — actions (enable · reset · MFA · groups · license)',
                    'Back'
                )
                if (-not $sub -or $sub -eq 'Back') { break }
                switch -Wildcard ($sub) {
                    'Manage user*' { Invoke-IaTuiUserActions -Accent $Accent -Upn $upn }
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
                        $si = try { @(Invoke-IaStatus -Spinner Dots -Title "Loading recent sign-ins for $upn…" -ScriptBlock {
                            Get-IntuneUserSignIn -User $upn -Top 20
                        }) } catch { @() }
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
                        $mfa = try { @(Invoke-IaStatus -Spinner Dots -Title 'Loading registered MFA methods…' -ScriptBlock {
                            Get-IntuneUserAuthMethod -User $upn
                        }) } catch { @() }
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
        'Discovered apps (which devices have X installed)',
        'Connector & token health (Apple push · VPP · DEP · NDES)',
        'MFA registration gaps (not capable · admins first)',
        'BitLocker escrow gaps (encrypted · no key in Entra)',
        'Config drift (Microsoft 365 baselines · what changed)',
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
            if (-not $filt) { break }
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
                    $mfrPick = Read-IaMenu -Title 'Manufacturer contains' -Color $Accent -PageSize 14 -Choices @(
                        'Dell','HP','Lenovo','Microsoft','Apple','ASUS','Acer','Samsung','Toshiba','VMware','Parallels','✎ Custom…')
                    $mfr = if ($mfrPick -eq '✎ Custom…') { Read-IaText -Question 'Manufacturer contains' } else { $mfrPick }
                    if (-not [string]::IsNullOrWhiteSpace($mfr)) { $invParams.Manufacturer = $mfr; $subTitle = "manufacturer: $mfr" }
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
                        $hdr.Add((ConvertFrom-IaMarkup "[dim][[[$Accent]JGI[/]]][/] [bold]Device detail[/]"))
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
                                $detail = Invoke-IaStatus -Spinner Dots -Title 'Loading compliance states…' -ScriptBlock {
                                    Get-IntuneDeviceDetail -Device $devName -IncludeComplianceState
                                }
                                if (-not $detail) { Write-IaHost '[yellow]Could not load compliance states — try again.[/]'; Read-IaPause | Out-Null; break }
                                # Project to a narrow, readable table — the raw Graph state
                                # objects carry id/userId/settingStates GUID columns that wrap.
                                $rows = @($detail.ComplianceStates | ForEach-Object {
                                    $sc = if ($_.state -eq 'compliant') { $Accent } elseif ($_.state -in 'noncompliant','error') { 'coral' } else { 'grey' }
                                    [pscustomobject][ordered]@{ Policy = $_.displayName; State = "[$sc]$($_.state)[/]"; Platform = $_.platformType }
                                })
                                Read-IaTablePause -Data $rows -Stem "device-$devName-compliance" -Color $Accent -Title "Compliance policy states · $devName ($($rows.Count))"
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
                                $detail = Invoke-IaStatus -Spinner Dots -Title 'Loading config states…' -ScriptBlock {
                                    Get-IntuneDeviceDetail -Device $devName -IncludeConfigState
                                }
                                if (-not $detail) { Write-IaHost '[yellow]Could not load configuration states — try again.[/]'; Read-IaPause | Out-Null; break }
                                $rows = @($detail.ConfigStates | ForEach-Object {
                                    $sc = if ($_.state -eq 'compliant') { $Accent } elseif ($_.state -in 'error','conflict') { 'coral' } else { 'grey' }
                                    [pscustomobject][ordered]@{ Profile = $_.displayName; State = "[$sc]$($_.state)[/]"; Version = $_.version }
                                })
                                Read-IaTablePause -Data $rows -Stem "device-$devName-config" -Color $Accent -Title "Configuration profile states · $devName ($($rows.Count))"
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
                                $detail = Invoke-IaStatus -Spinner Dots -Title 'Loading detected apps…' -ScriptBlock {
                                    Get-IntuneDeviceDetail -Device $devName -IncludeApps
                                }
                                if (-not $detail) { Write-IaHost '[yellow]Could not load detected apps — try again.[/]'; Read-IaPause | Out-Null; break }
                                $rows = @($detail.Apps | ForEach-Object { [pscustomobject][ordered]@{ App = $_.App; Version = $_.Version } })
                                Read-IaTablePause -Data $rows -Stem "device-$devName-apps" -Color $Accent -Title "Detected apps · $devName ($($rows.Count))"
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
                                else { Read-IaTablePause -Data $bk -Stem "device-$devName-bitlocker" -Color $Accent -Title "BitLocker recovery keys · $devName" -NoExport }
                            }
                            'LAPS*' {
                                $laps = @(Invoke-IaStatus -Spinner Dots -Title 'Loading LAPS credential…' -ScriptBlock {
                                    Get-IntuneLapsCredential -Device $devName
                                })
                                if (-not $laps) { Write-IaHost '[yellow]No Windows LAPS credential backed up for this device.[/]'; Read-IaPause | Out-Null }
                                else { Read-IaTablePause -Data $laps -Stem "device-$devName-laps" -Color $Accent -Title "LAPS local admin · $devName" -NoExport }
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
                                    if (Read-IaConfirm "Send '$actPick' to ${devName}?") {
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
        'User lookup*' { Invoke-IaTuiUserLookup -Accent $Accent }
        'App install*' {
            $app = Select-IaInventoryItem -Accent $Accent -Area 'Apps' -Title 'Which app?'
            if (-not $app) { return }
            $by  = Read-IaMenu -Title 'Pivot by' -Choices @('Device', 'User') -Color $Accent
            if (-not $by) { return }   # Esc → cancel (else -By $null fails the ValidateSet)
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
            if (-not $mode) { break }
            Write-IaTuiHeader -Screen 'Compliance status' -Sub $mode.ToLower() -Accent $Accent
            $rows = @(switch -Wildcard ($mode) {
                'Policy'  {
                    $pol = Select-IaInventoryItem -Accent $Accent -Area 'Compliance' -Title 'Which compliance policy?'
                    if ($pol) { Get-IntuneComplianceStatus -Policy $pol.Name }
                }
                'Device'  {
                    $dev = Select-IaManagedDevice -Accent $Accent -Title 'Which device?'
                    if ($dev) { Get-IntuneComplianceStatus -Device $dev }
                }
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
            if (-not $scope) { break }   # Esc → cancel (else silently runs the all-resources summary)
            $grp   = $null
            if ($scope -like 'Scope*') {
                $grpObj = Select-IaGroup -Accent $Accent -Title 'Scope to group'
                if (-not $grpObj) { break }
                $grp = $grpObj.DisplayName
            }
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
        'Discovered apps*' {
            $q = Read-IaText -Question "App name contains (e.g. zscaler)"
            if ([string]::IsNullOrWhiteSpace($q)) { return }
            $bv = Read-IaText -Question 'Only versions below (blank = all versions)' -DefaultAnswer ''
            $title = if ($bv) { "Devices with '$q' below $bv" } else { "Devices with '$q' installed" }
            Invoke-IaTuiReportView -Accent $Accent -Title $title `
                -Stem "discovered-$($q -replace '\W+','-')" -Loader {
                    $p = @{ Name = $q; Devices = $true }
                    if ($bv) { $p.BelowVersion = $bv }
                    Get-IntuneDiscoveredApp @p
                }
        }
        'Connector & token*' {
            Invoke-IaTuiReportView -Accent $Accent -Title 'Connector & token health' `
                -Stem 'connector-health' -Loader { Get-IntuneConnectorHealth }
        }
        'MFA registration*' {
            Invoke-IaTuiReportView -Accent $Accent -Title 'MFA registration gaps (not MFA-capable)' `
                -Stem 'mfa-gaps' -Loader { Get-EntraMfaRegistration -GapsOnly }
        }
        'BitLocker escrow*' {
            Invoke-IaTuiReportView -Accent $Accent -Title 'BitLocker escrow gaps (encrypted, no key in Entra)' `
                -Stem 'bitlocker-escrow-gap' -Loader { Get-IntuneBitLockerEscrowGap }
        }
        'Config drift*' {
            $view = Read-IaMenu -Title 'Config drift' -Color $Accent -Choices @(
                'Active drifts (property detail — desired vs current)',
                'Active drifts (summary by resource)',
                'Monitors & last runs'
            )
            if (-not $view) { return }
            switch -Wildcard ($view) {
                'Active drifts (property*' {
                    Invoke-IaTuiReportView -Accent $Accent -Title 'Config drift — desired vs current' `
                        -Stem 'config-drift-detail' -Loader { Get-TenantConfigDrift -Detail }
                }
                'Active drifts (summary*' {
                    Invoke-IaTuiReportView -Accent $Accent -Title 'Config drift — active by resource' `
                        -Stem 'config-drift' -Loader { Get-TenantConfigDrift }
                }
                'Monitors*' {
                    Invoke-IaTuiReportView -Accent $Accent -Title 'Configuration monitors & last runs' `
                        -Stem 'config-monitors' -Loader { Get-TenantConfigMonitor }
                }
            }
        }
        'Audit*' {
            $sincePick = Read-IaMenu -Title 'Since' -Color $Accent -Choices @('24h','7d','30d','90d','✎ Custom…')
            $since = if ($sincePick -eq '✎ Custom…') { Read-IaText -Question 'Since (e.g. 7d, 24h)' -DefaultAnswer '7d' } else { $sincePick }
            if ([string]::IsNullOrWhiteSpace($since)) { $since = '7d' }
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
            Write-IaHost "[grey]This is an async Intune export job (Graph queues it server-side). Large reports like Devices can take 1–3 min; 5-min timeout.[/]"
            $rows = @(Invoke-IaStatus -Spinner Dots -Title "Running $name… (export job — can take a few minutes)" -ScriptBlock {
                Export-IntuneReport -Name $name
            } | Select-Object -First 100)
            $rows | Format-IaTable -Color $Accent
            Read-IaTablePause -Data $rows -Stem "report-$($name -replace '\s+','-')" -Color $Accent
        }
        default { return }
    }
}

# ─── deployment summary drill-down ───────────────────────────────────────────
function Invoke-IaTuiPolicyStatusPicker {
    # A selectable policy/profile list. Enter (or click) a row to drill into its
    # per-device success/failure report. Loops until the user backs out.
    param([string]$Accent, [object[]]$Items, [string]$Area, [string]$Title)
    $items = @($Items)
    if (-not $items.Count) { Write-IaHost '[yellow]Nothing to show.[/]'; Read-IaPause | Out-Null; return }
    $disp = @($items | ForEach-Object {
        [pscustomobject][ordered]@{ Name = $_.Name; Platform = $_.Platform; Modified = $_.Modified }
    })
    while ($true) {
        $picked = Read-IaTableInteractive -Data $disp -Color $Accent -Selectable `
            -Title "$Title ($($disp.Count))  ·  Enter = per-device pass / fail" -Stem ("$Area-policies".ToLower())
        if (-not $picked) { break }
        Invoke-IaTuiPolicyDeviceDrilldown -Accent $Accent -Row ([pscustomobject]@{ Area = $Area; Resource = $picked.Name })
    }
}

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
        'Quality update status'  = @{ Cmd = 'Get-IntunePatchReport -Type Quality'; Load = { Get-IntunePatchReport -Type Quality } }
        'Feature update status'  = @{ Cmd = 'Get-IntunePatchReport -Type Feature'; Load = { Get-IntunePatchReport -Type Feature } }
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
    $lines.Add((ConvertFrom-IaMarkup "[dim][[[$Accent]JGI[/]]][/] [bold]Custom report builder[/]"))
    $lines.Add((ConvertFrom-IaMarkup "[grey]select │ where │ sort │ group │ export[/]"))
    $lines.Add((ConvertFrom-IaMarkup ("[$Accent]" + ([string][char]0x2550 * [Math]::Min(96, [Math]::Max(40, (Get-IaInnerWidth)))) + '[/]')))

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
                    # Pick from the distinct values present in the loaded data (with a
                    # "type a value" escape hatch for free-form operators).
                    $val = Select-IaReportValue -Accent $Accent -Data $raw -Prop $fProp -Op $op
                    if ($null -eq $val) { break }
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
                    $mProp = Read-IaMenu -Title "Which numeric property to ${func}?" -Color $Accent -PageSize 20 -Choices $props
                    $fmap = @{ 'Sum'='Sum'; 'Average'='Avg'; 'Min'='Min'; 'Max'='Max' }
                    $recipe.Agg = @{ Func = $fmap[$func]; Prop = $mProp }
                }
            }
            'Top N rows' {
                $nPick = Read-IaMenu -Title 'Top N rows' -Color $Accent -Choices @('All (0)','10','25','50','100','250','500','1000','✎ Custom…')
                if (-not $nPick) { break }
                $n = if ($nPick -eq '✎ Custom…') { Read-IaText -Question 'Top N (0 = all)' -DefaultAnswer "$($recipe.Top)" }
                     elseif ($nPick -eq 'All (0)') { '0' } else { $nPick }
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
                $path = Join-Path ([Environment]::GetFolderPath('UserProfile')) "JustGraphIT-report-$safe.json"
                $def  = [pscustomobject]@{ Source = $srcName; Recipe = $recipe; SavedBy = 'JustGraphIT'; Version = 1 }
                try {
                    $def | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding UTF8
                    Write-IaHost "[$Accent]✓ Saved → $path[/]"
                } catch { Write-IaHost "[coral]Save failed: $($_.Exception.Message)[/]" }
                Read-IaPause
            }
            'Load report definition' {
                $userHome = [Environment]::GetFolderPath('UserProfile')
                $defs = @(Get-ChildItem -Path $userHome -Filter 'JustGraphIT-report-*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
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
            $p = Read-IaText -Question 'Backup folder' -DefaultAnswer (Get-IaBackupName -Prefix 'justgraphit-config' -Extension '')
            Write-IaTuiHeader -Screen 'Full config backup' -Sub "→ $p (one file per config)" -Accent $Accent
            $res = Invoke-IaStatus -Spinner Dots -Title 'Exporting every config…' -ScriptBlock {
                $ProgressPreference = 'SilentlyContinue'
                Backup-IntuneConfig -Path $p
            }
            Write-IaHost "[$Accent]Backed up[/] $($res.Count) config(s) across $(@($res.Areas).Count) area(s) → $($res.Path)"
            Write-IaHost "[grey]Each config is its own JSON, grouped by area, with a manifest.json index.[/]"
        }
        'Drift*' {
            $p = Select-IaBackupPath -Accent $Accent -Title 'Snapshot file to compare against'
            if ([string]::IsNullOrWhiteSpace($p)) { return }
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
            $p = Select-IaBackupPath -Accent $Accent -Title 'Snapshot file to restore'
            if ([string]::IsNullOrWhiteSpace($p)) { return }
            $mode = Read-IaMenu -Title 'Restore mode' -Color $Accent -Choices @('Preview only (no changes)', 'Apply now')
            Write-IaTuiHeader -Screen 'Restore' -Sub "snapshot: $p" -Accent $Accent
            $plans = if ($mode -like 'Apply*') { Restore-IntuneAssignment -Path $p -Confirm:$false }
                     else { Restore-IntuneAssignment -Path $p -WhatIf }
            Show-IaRestorePlan -Plans $plans -Accent $Accent
            if ($mode -like 'Apply*') { $script:IaTuiInventory = $null }
        }
        'Restore full config*' {
            $p = Select-IaBackupPath -Accent $Accent -Title 'Backup folder to restore' -Prefix 'justgraphit-config' -Directory
            if ([string]::IsNullOrWhiteSpace($p)) { return }
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
                    LastLogin    = & { $dt = ConvertTo-IaSafeDateTime $_.LastLogin; if ($dt) { $dt.ToString('yyyy-MM-dd HH:mm') } else { '—' } }
                    GracePeriod  = & { $dt = ConvertTo-IaSafeDateTime $_.GracePeriodEnd; if ($dt) { $dt.ToString('yyyy-MM-dd') } else { '—' } }
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
            if (-not $pcName -or -not $action) { return }   # Esc → cancel (else empty-subject confirm + Mandatory binding error)
            $extraParams = @{}
            switch ($action) {
                'Resize' {
                    $plans = Invoke-IaStatus -Spinner Dots -Title 'Loading service plans…' -ScriptBlock { Get-IntuneCloudPCServicePlan }
                    $planChoice = Read-IaMenu -Title 'Target service plan' -Color $Accent `
                        -Choices @($plans | ForEach-Object { "$($_.vCPU)vCPU / $($_.RAM)GB RAM / $($_.Storage)GB  —  $($_.Name)" })
                    if (-not $planChoice) { return }   # Esc → cancel (IndexOf($null) would pick the last plan)
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
                    if (-not $snapChoice) { return }   # Esc → cancel (else IndexOf($null) rolls back to the LAST snapshot)
                    $snapIndex  = @($snaps | ForEach-Object { "$($_.CreatedAt)  ($($_.SnapshotType))" }).IndexOf($snapChoice)
                    $extraParams.SnapshotId = $snaps[$snapIndex].Id
                }
            }
            # -Confirm:$false suppresses the cmdlet's own prompt, so gate here. Reprovision /
            # Restore / EndGracePeriod rebuild or roll back the Cloud PC and destroy data.
            $irrev = $action -in @('Reprovision', 'Restore', 'EndGracePeriod')
            $cmsg  = if ($irrev) { "[red]$action '$pcName'? This is IRREVERSIBLE — it rebuilds or rolls back the Cloud PC and DESTROYS current data.[/]" } else { "Run '$action' on '$pcName'?" }
            if (-not (Read-IaConfirm $cmsg)) { Write-IaHost '[grey]Cancelled.[/]'; return }
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
                    if ([string]::IsNullOrWhiteSpace($name)) { return }   # no name → cancel
                    $imgs  = Invoke-IaStatus -Spinner Dots -Title 'Loading images…' -ScriptBlock { Get-IntuneCloudPCImage }
                    $imgC  = Read-IaMenu -Title 'OS image' -Color $Accent `
                        -Choices @($imgs | ForEach-Object { "$($_.Type): $($_.Name)  [$($_.OS)]" })
                    if (-not $imgC) { return }   # Esc → cancel (else IndexOf($null) picks the last image)
                    $imgIdx= @($imgs | ForEach-Object { "$($_.Type): $($_.Name)  [$($_.OS)]" }).IndexOf($imgC)
                    $img   = $imgs[$imgIdx]
                    $join  = Read-IaMenu -Title 'Azure AD join type' -Color $Accent `
                        -Choices @('azureADJoin', 'hybridAzureADJoin')
                    if (-not $join) { return }   # Esc → cancel (else -DomainJoinType $null fails binding)
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
                    if (-not $polC) { return }
                    if (-not (Read-IaConfirm "[red]Delete provisioning policy '$polC'? New Cloud PC provisioning will stop using it.[/]")) { return }
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
                    if (-not $connC) { return }   # Esc → cancel (else -Connection $null binding error + false success message)
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
            if (-not $type) { return }   # Esc → cancel (else -Type $null fails the ValidateSet)
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
            if (-not $scope) { return }   # Esc → cancel
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
            if (-not $rptName) { return }
            $rows = @(Invoke-IaStatus -Spinner Dots -Title "Running $rpt report…" -ScriptBlock {
                Get-IntuneCloudPCReport -Report $rptName
            } | Select-Object -First 100)
            if (-not $rows) { Write-IaHost '[yellow]No data returned for this report.[/]'; Read-IaPause | Out-Null }
            else { Read-IaTablePause -Data $rows -Stem "cloudpc-report-$rptName" -Color $Accent -Title "Cloud PC · $rpt ($($rows.Count))" }
        }
        default { return }
    }
}
