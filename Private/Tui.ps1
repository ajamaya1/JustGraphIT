# ════════════════════════════════════════════════════════════════════════════
#  IntuneTide self-contained terminal-UI engine  (no external TUI dependency)
# ────────────────────────────────────────────────────────────────────────────
#  WHY THIS EXISTS
#    The TUI was originally built on PwshSpectreConsole. Two properties of that
#    library made it fragile against live Intune data:
#      1. Its markup parser THROWS on any "[token]" it doesn't recognise as a
#         colour — e.g. a group literally named "[Test]", or an area label that
#         reached a colour parameter as "[Apps]" ("Could not find color 'Apps'").
#      2. Its parameter surface varies by version (the "-Data not found" crash).
#
#    This engine — modelled on the approach used by jorgeasaurus/InTUI — replaces
#    Spectre entirely:
#      • a markup parser WE control that DEGRADES GRACEFULLY: an unknown tag is
#        emitted as literal text, never an exception;
#      • 24-bit ANSI colour with a comprehensive colour-name map;
#      • arrow-key single/multi menus with a non-interactive numbered fallback so
#        the same code runs under Pester / redirected I/O without throwing;
#      • render helpers that return / emit strings, so they are unit-testable
#        head-lessly.
#
#    Public TUI code calls the Ia* primitives below; there is no PwshSpectreConsole
#    requirement anywhere in the module.
# ════════════════════════════════════════════════════════════════════════════

$script:IaEsc = [char]0x1B

# Colour-name → 24-bit RGB. Covers every name the TUI uses as markup or -Color
# (accents: green/orange1/yellow/turquoise2; coral/grey/red/… ) plus common
# Spectre names so themes stay faithful. Unknown names degrade to no colour.
$script:IaColorRgb = @{
    'black'          = @(0, 0, 0)
    'white'          = @(220, 223, 228)
    'grey'           = @(146, 153, 166)
    'gray'           = @(146, 153, 166)
    'silver'         = @(192, 192, 192)
    'red'            = @(231, 72, 86)
    'green'          = @(35, 209, 139)
    'lime'           = @(120, 220, 80)
    'yellow'         = @(245, 213, 108)
    'gold1'          = @(255, 215, 0)
    'blue'           = @(59, 142, 234)
    'cyan'           = @(41, 184, 219)
    'cyan1'          = @(0, 215, 215)
    'magenta'        = @(214, 112, 214)
    'purple'         = @(160, 110, 220)
    'mediumpurple'   = @(135, 135, 255)
    'teal'           = @(64, 196, 196)
    'coral'          = @(255, 127, 80)
    'orange'         = @(255, 135, 0)
    'orange1'        = @(255, 175, 0)
    'darkorange'     = @(255, 135, 0)
    'turquoise2'     = @(0, 215, 215)
    'deepskyblue1'   = @(0, 175, 255)
    'steelblue1'     = @(95, 175, 255)
    'steelblue1_1'   = @(95, 175, 255)
    'darkslategray1' = @(135, 255, 255)
}
$script:IaStyleCode = @{ 'bold' = '1'; 'dim' = '2'; 'italic' = '3'; 'underline' = '4' }

function Get-IaSeq {
    # Build an ANSI CSI sequence: ESC + "[" + body  (e.g. body "0m" → reset).
    param([Parameter(Mandatory)][string]$Body)
    "$($script:IaEsc)[$Body"
}

function Get-IaReset { Get-IaSeq '0m' }

function Get-IaAnsi {
    # ANSI escape for a single colour/style name, or '' if unknown.
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    $key = $Name.Trim().ToLower()
    if ($script:IaColorRgb.ContainsKey($key)) {
        $rgb = $script:IaColorRgb[$key]
        return (Get-IaSeq "38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m")
    }
    if ($script:IaStyleCode.ContainsKey($key)) {
        return (Get-IaSeq "$($script:IaStyleCode[$key])m")
    }
    return ''
}

function ConvertFrom-IaMarkup {
    <#
    .SYNOPSIS
        Convert [colour]text[/] markup to ANSI escapes. Never throws.
    .DESCRIPTION
        Stack-based parser with correct nesting. Known tags (single or compound,
        e.g. [bold white]) push a style and [/] pops it. Crucially, an UNKNOWN tag
        such as [Apps] is emitted as the literal text "[Apps]" rather than raising
        an error — this is the property the previous Spectre layer lacked.
        Escaped brackets: [[ → literal [ , ]] → literal ].
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    $reset = Get-IaReset
    $stack = [System.Collections.Generic.Stack[string]]::new()
    $buf = [System.Text.StringBuilder]::new($Text.Length * 2)
    $len = $Text.Length
    $pos = 0

    while ($pos -lt $len) {
        $ch = $Text[$pos]

        if ($ch -eq '[' -and ($pos + 1) -lt $len -and $Text[$pos + 1] -eq '[') {
            [void]$buf.Append('['); $pos += 2; continue
        }
        if ($ch -eq ']' -and ($pos + 1) -lt $len -and $Text[$pos + 1] -eq ']') {
            [void]$buf.Append(']'); $pos += 2; continue
        }

        if ($ch -eq '[') {
            $close = $Text.IndexOf(']', $pos + 1)
            if ($close -eq -1) { [void]$buf.Append($ch); $pos++; continue }
            $tag = $Text.Substring($pos + 1, $close - $pos - 1)

            if ($tag -eq '/') {
                if ($stack.Count -gt 0) {
                    [void]$stack.Pop()
                    [void]$buf.Append($reset)
                    if ($stack.Count -gt 0) { [void]$buf.Append($stack.Peek()) }
                }
                # stray [/] with empty stack: emit nothing
            }
            else {
                $ansi = ''
                foreach ($part in ($tag.Trim() -split '\s+')) {
                    $ansi += (Get-IaAnsi $part)
                }
                if ($ansi) {
                    [void]$stack.Push($ansi)
                    [void]$buf.Append($ansi)
                }
                else {
                    # Unknown tag → render literally, never throw.
                    [void]$buf.Append('[').Append($tag).Append(']')
                }
            }
            $pos = $close + 1
            continue
        }

        [void]$buf.Append($ch)
        $pos++
    }

    if ($stack.Count -gt 0) { [void]$buf.Append($reset) }
    return $buf.ToString()
}

function Strip-IaMarkup {
    <#
    .SYNOPSIS
        Remove markup tags, returning the plain text that will be displayed.
        Mirrors ConvertFrom-IaMarkup exactly: known tags vanish, unknown tags
        survive as literal "[tag]" text, escaped brackets collapse.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    $stack = 0
    $buf = [System.Text.StringBuilder]::new($Text.Length)
    $len = $Text.Length
    $pos = 0

    while ($pos -lt $len) {
        $ch = $Text[$pos]
        if ($ch -eq '[' -and ($pos + 1) -lt $len -and $Text[$pos + 1] -eq '[') {
            [void]$buf.Append('['); $pos += 2; continue
        }
        if ($ch -eq ']' -and ($pos + 1) -lt $len -and $Text[$pos + 1] -eq ']') {
            [void]$buf.Append(']'); $pos += 2; continue
        }
        if ($ch -eq '[') {
            $close = $Text.IndexOf(']', $pos + 1)
            if ($close -eq -1) { [void]$buf.Append($ch); $pos++; continue }
            $tag = $Text.Substring($pos + 1, $close - $pos - 1)
            if ($tag -eq '/') {
                if ($stack -gt 0) { $stack-- }
            }
            else {
                $known = $false
                foreach ($part in ($tag.Trim() -split '\s+')) {
                    if (Get-IaAnsi $part) { $known = $true } else { $known = $false; break }
                }
                if ($known) { $stack++ }
                else { [void]$buf.Append('[').Append($tag).Append(']') }
            }
            $pos = $close + 1
            continue
        }
        [void]$buf.Append($ch)
        $pos++
    }
    return $buf.ToString()
}

function Protect-IaMarkup {
    <#
    .SYNOPSIS
        Escape brackets in arbitrary data so it renders literally instead of being
        interpreted as markup. Use when interpolating untrusted strings (group
        names, app names) into a markup string.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $Text -replace '\[', '[[' -replace '\]', ']]'
}

function Measure-IaWidth {
    <#
    .SYNOPSIS
        Visual column width of a string, counting East-Asian-wide / emoji as 2 and
        control characters as 0. Used for box / table alignment.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    $width = 0
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $cp = [int]$Text[$i]
        if ($cp -ge 0xD800 -and $cp -le 0xDBFF -and ($i + 1) -lt $Text.Length) {
            $low = [int]$Text[$i + 1]
            if ($low -ge 0xDC00 -and $low -le 0xDFFF) {
                $cp = 0x10000 + (($cp - 0xD800) -shl 10) + ($low - 0xDC00); $i++
            }
        }
        if ($cp -lt 0x20 -or ($cp -ge 0x7F -and $cp -lt 0xA0)) { continue }
        if (($cp -ge 0x1100 -and $cp -le 0x115F) -or
            ($cp -ge 0x2E80 -and $cp -le 0x303E) -or
            ($cp -ge 0x3041 -and $cp -le 0x33BF) -or
            ($cp -ge 0x3400 -and $cp -le 0x4DBF) -or
            ($cp -ge 0x4E00 -and $cp -le 0x9FFF) -or
            ($cp -ge 0xAC00 -and $cp -le 0xD7AF) -or
            ($cp -ge 0xF900 -and $cp -le 0xFAFF) -or
            ($cp -ge 0xFE30 -and $cp -le 0xFE6F) -or
            ($cp -ge 0xFF01 -and $cp -le 0xFF60) -or
            ($cp -ge 0xFFE0 -and $cp -le 0xFFE6) -or
            ($cp -ge 0x1F000 -and $cp -le 0x1FAFF)) { $width += 2 }
        else { $width += 1 }
    }
    return $width
}

function Get-IaInnerWidth {
    # Usable content width (clamped 48..160).
    $w = 100
    try { $w = [Console]::WindowWidth - 4 } catch { $w = 100 }
    if ($w -lt 1) { $w = 100 }
    return [Math]::Min(160, [Math]::Max(48, $w))
}

function Test-IaArrowSupport {
    <#
    .SYNOPSIS
        $true when the host can drive raw arrow-key menus. $false under Pester,
        redirected I/O, ISE, or PS < 7 — callers then use the numbered fallback.
    #>
    [CmdletBinding()] param()
    if ($PSVersionTable.PSVersion.Major -lt 7) { return $false }
    if (-not [Environment]::UserInteractive) { return $false }
    if ($Host.Name -eq 'Windows PowerShell ISE Host') { return $false }
    if ([Console]::IsInputRedirected) { return $false }
    try { $null = [Console]::KeyAvailable; return $true } catch { return $false }
}

# ─── output primitives ───────────────────────────────────────────────────────

function Write-IaRaw {
    # Write a PRE-RENDERED string SYNCHRONOUSLY ([Console]::Out + Flush). The menus
    # render via [Console]::Out too; if screens used buffered Write-Host instead, any
    # delay between a clear and the first row (e.g. a data load) lets the buffer flush
    # out of order and repaint the previous menu (the "menu bleed"). Routing ALL TUI
    # output through this one synchronous path keeps ordering deterministic. Falls
    # back to Write-Host where [Console]::Out is unavailable (redirected / Pester).
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowEmptyString()][string]$Text = '', [switch]$NoNewline)
    if ($NoNewline) { Write-Host $Text -NoNewline } else { Write-Host $Text }
}

function Write-IaHost {
    # Markup → ANSI to the host. Replaces Write-SpectreHost. Never throws on data.
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowEmptyString()][string]$Message = '', [switch]$NoNewline)
    Write-IaRaw (ConvertFrom-IaMarkup -Text $Message) -NoNewline:$NoNewline
}

function Clear-IaHost {
    # Forcefully clear the screen + scrollback and home the cursor. After in-place
    # (cursor-addressed) menu rendering, a plain Clear-Host can leave the menu
    # visible behind the next screen on some terminals; ESC[2J wipes the whole
    # screen unconditionally, which is reliable across xterm / Windows Terminal /
    # VS Code / tmux.
    # Scroll the previous screen OFF with newlines, THEN clear + home. After the
    # menus' cursor-addressed rendering some terminals drop a bare ESC[H/ESC[2J (a
    # control sequence with no flowing content), so the menu bleeds behind the next
    # screen. Newlines are real content flow and always advance, pushing the old
    # frame into scrollback; the trailing ESC[2J/ESC[H then lands cleanly. Written
    # synchronously via [Console]::Out to match the menus/tables.
    Write-IaRaw "$($script:IaEsc)[2J$($script:IaEsc)[3J$($script:IaEsc)[H" -NoNewline
}

function Write-IaRule {
    # Horizontal rule with an optional inline title. Replaces Write-SpectreRule.
    [CmdletBinding()]
    param([string]$Title, [string]$Color = 'grey')
    $w = Get-IaInnerWidth
    $reset = Get-IaReset
    $fg = Get-IaAnsi $Color
    $h = [string][char]0x2500
    if ($Title) {
        $plain = Strip-IaMarkup -Text $Title
        $tw = Measure-IaWidth -Text $plain
        $left = 2
        $right = [Math]::Max(2, $w - $left - $tw - 2)
        Write-IaRaw ("{0}{1}{2} {3} {0}{4}{5}" -f $fg, ($h * $left), $reset, (ConvertFrom-IaMarkup $Title), ($h * $right), $reset)
    }
    else {
        Write-IaRaw ("{0}{1}{2}" -f $fg, ($h * $w), $reset)
    }
}

# 5-row block glyphs for the TIDE banner; anything else falls back to a bold rule.
$script:IaFiglet = @{
    'T' = @('█████', '  █  ', '  █  ', '  █  ', '  █  ')
    'I' = @('█████', '  █  ', '  █  ', '  █  ', '█████')
    'D' = @('████ ', '█   █', '█   █', '█   █', '████ ')
    'E' = @('█████', '█    ', '███  ', '█    ', '█████')
    ' ' = @('   ', '   ', '   ', '   ', '   ')
}

function Write-IaFiglet {
    # Big block-letter banner. Replaces Write-SpectreFigletText.
    [CmdletBinding()]
    param([Parameter(Position = 0)][string]$Text = '', [string]$Color = 'green')
    Write-IaRaw (Get-IaFigletString -Text $Text -Color $Color)
}

function Get-IaFigletString {
    # Return the block-letter banner as a (multi-line, ANSI-coloured) string instead
    # of writing it — used to embed the banner in a menu frame's header.
    [CmdletBinding()]
    param([Parameter(Position = 0)][string]$Text = '', [string]$Color = 'green')
    $reset = Get-IaReset
    $fg = Get-IaAnsi $Color
    $chars = $Text.ToUpper().ToCharArray()
    $supported = $chars.Count -gt 0
    foreach ($c in $chars) { if (-not $script:IaFiglet.ContainsKey([string]$c)) { $supported = $false; break } }
    if (-not $supported) { return (ConvertFrom-IaMarkup "[$Color][bold]$Text[/][/]") }
    $rows = for ($row = 0; $row -lt 5; $row++) {
        $line = ''
        foreach ($c in $chars) { $line += $script:IaFiglet[[string]$c][$row] + ' ' }
        "$fg$line$reset"
    }
    return ($rows -join "`n")
}

# ─── input primitives ────────────────────────────────────────────────────────

function Read-IaText {
    # Text prompt with optional default. Replaces Read-SpectreText.
    [CmdletBinding()]
    param([Parameter(Position = 0)][Alias('Question')][string]$Message = '', [string]$DefaultAnswer = '')
    $reset = Get-IaReset
    $dim = Get-IaAnsi 'dim'
    $msg = ConvertFrom-IaMarkup -Text $Message
    $hint = if ($DefaultAnswer) { " $dim($DefaultAnswer)$reset" } else { '' }
    Write-IaRaw "$msg$hint`: " -NoNewline
    $in = Read-Host
    if ([string]::IsNullOrWhiteSpace($in) -and $DefaultAnswer) { return $DefaultAnswer }
    return $in
}

function Read-IaConfirm {
    # Y/N prompt. Returns [bool].
    [CmdletBinding()]
    param([Parameter(Position = 0)][string]$Message, [bool]$DefaultAnswer = $false)
    $reset = Get-IaReset
    $dim = Get-IaAnsi 'dim'
    $hint = if ($DefaultAnswer) { '[Y/n]' } else { '[y/N]' }
    Write-IaRaw "$(ConvertFrom-IaMarkup $Message) $dim$hint$reset " -NoNewline
    $in = Read-Host
    if ([string]::IsNullOrWhiteSpace($in)) { return $DefaultAnswer }
    return ($in.Trim().ToLower() -eq 'y')
}

function Read-IaPause {
    # "Press any key" pause. Replaces Read-SpectrePause.
    [CmdletBinding()] param()
    Write-IaHost '[grey]Press any key to continue…[/]'
    try {
        if (-not [Console]::IsInputRedirected) { $null = [Console]::ReadKey($true); return }
    } catch { }
    try { Read-Host | Out-Null } catch { }
}

# ─── status / spinner ────────────────────────────────────────────────────────

function Invoke-IaStatus {
    <#
    .SYNOPSIS
        Run a script block while showing a one-line status, then clear it.
        Replaces Invoke-SpectreCommandWithStatus. Runs on the calling thread, so
        the block sees its defining scope (TUI scriptblocks reference plain $vars,
        NOT $using:). Returns the block's output.
    #>
    [CmdletBinding()]
    param(
        [string]$Spinner,
        [string]$Title,
        [string]$Color = 'grey',
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )
    $reset = Get-IaReset
    $fg = Get-IaAnsi ([string]::IsNullOrWhiteSpace($Color) ? 'grey' : $Color)
    $plain = if ($Title) { Strip-IaMarkup -Text $Title } else { 'Working' }
    Write-IaRaw "`r$fg»$reset $plain… " -NoNewline
    try {
        return (& $ScriptBlock)
    }
    finally {
        $w = 80
        try { $w = [Console]::WindowWidth - 1 } catch { $w = 80 }
        if ($w -lt 1) { $w = 80 }
        Write-IaRaw ("`r" + (' ' * $w) + "`r") -NoNewline
    }
}

# ─── tables ──────────────────────────────────────────────────────────────────

function Show-IaTableObjects {
    <#
    .SYNOPSIS
        Render an array of objects as a bordered, markup-aware table. Columns are
        taken from the first object's properties. Replaces Format-SpectreTable.
    #>
    [CmdletBinding()]
    param([object[]]$Rows, [string]$Color = 'grey', [string]$Title)

    $data = @($Rows | Where-Object { $null -ne $_ })
    if ($data.Count -eq 0) { return }

    # Support both PSCustomObject and Hashtable/OrderedDictionary rows.
    $isDictionary = $data[0] -is [System.Collections.IDictionary]
    $cols = if ($isDictionary) { @($data[0].Keys) } else { @($data[0].PSObject.Properties.Name) }
    if ($cols.Count -eq 0) { return }

    # Cell matrix (raw markup strings). Use a List to keep each row an intact array.
    $matrix = [System.Collections.Generic.List[object[]]]::new()
    foreach ($r in $data) {
        $isDict = $r -is [System.Collections.IDictionary]
        $cells = foreach ($c in $cols) {
            $cv = if ($isDict) { $r[$c] } else { $r.PSObject.Properties[$c].Value }
            if ($null -eq $cv) { '' } else { [string]$cv }
        }
        $matrix.Add(@($cells))
    }

    $reset = Get-IaReset
    $border = Get-IaAnsi $Color
    $bold = Get-IaAnsi 'bold'
    $dim = Get-IaAnsi 'dim'
    $white = Get-IaAnsi 'white'
    $v = [string][char]0x2502
    $h = [string][char]0x2500

    # Column widths from display width of header + cells.
    $widths = foreach ($c in $cols) { Measure-IaWidth -Text (Strip-IaMarkup -Text $c) }
    $widths = @($widths)
    for ($ri = 0; $ri -lt $matrix.Count; $ri++) {
        for ($ci = 0; $ci -lt $cols.Count; $ci++) {
            $cw = Measure-IaWidth -Text (Strip-IaMarkup -Text $matrix[$ri][$ci])
            if ($cw -gt $widths[$ci]) { $widths[$ci] = $cw }
        }
    }

    # Clamp to inner width, shrinking proportionally if needed.
    $inner = Get-IaInnerWidth
    $sep = ($cols.Count - 1) * 3
    $pad = 4
    $sum = ($widths | Measure-Object -Sum).Sum
    if (($sum + $sep + $pad) -gt $inner) {
        $avail = $inner - $sep - $pad
        if ($avail -lt ($cols.Count * 4)) { $avail = $cols.Count * 4 }
        $total = if ($sum -lt 1) { 1 } else { $sum }
        for ($ci = 0; $ci -lt $cols.Count; $ci++) {
            $widths[$ci] = [Math]::Max(4, [int]($widths[$ci] * $avail / $total))
        }
    }
    $tableWidth = (($widths | Measure-Object -Sum).Sum) + $sep + $pad

    $padCell = {
        param($Raw, $Width)
        $plain = Strip-IaMarkup -Text $Raw
        $dispW = Measure-IaWidth -Text $plain
        if ($dispW -gt $Width) {
            $cut = 0; $acc = 0; $max = [Math]::Max(1, $Width - 1)
            for ($k = 0; $k -lt $plain.Length; $k++) {
                $chW = Measure-IaWidth -Text ([string]$plain[$k])
                if (($acc + $chW) -gt $max) { break }
                $acc += $chW; $cut++
            }
            $plain = $plain.Substring(0, [Math]::Max(1, $cut)) + '…'
            return ($plain + (' ' * [Math]::Max(0, $Width - (Measure-IaWidth -Text $plain))))
        }
        return ((ConvertFrom-IaMarkup -Text $Raw) + $reset + (' ' * [Math]::Max(0, $Width - $dispW)))
    }

    # Title row.
    if ($Title) {
        $pt = Strip-IaMarkup -Text $Title
        $tw = Measure-IaWidth -Text $pt
        $lineLen = $tableWidth - 4 - $tw
        $l = [Math]::Max(1, [int][Math]::Floor($lineLen / 2))
        $rgt = [Math]::Max(1, $lineLen - $l)
        Write-IaRaw ("{0}{1}{2} {3} {0}{4}{2}" -f $border, (([char]0x256D) + ($h * $l)), $reset, (ConvertFrom-IaMarkup $Title), (($h * $rgt) + ([char]0x256E)))
    }

    # Header.
    $hdr = @()
    for ($ci = 0; $ci -lt $cols.Count; $ci++) {
        $plain = Strip-IaMarkup -Text $cols[$ci]
        $w = Measure-IaWidth -Text $plain
        $hdr += ($bold + $white + $plain + $reset + (' ' * [Math]::Max(0, $widths[$ci] - $w)))
    }
    Write-IaRaw ("{0}{1}{2} {3} {0}{1}{2}" -f $border, $v, $reset, ($hdr -join " $dim$v$reset "))

    # Underline (column rules joined by ┼, framed to match the header width).
    $under = @(); for ($ci = 0; $ci -lt $cols.Count; $ci++) { $under += ($h * $widths[$ci]) }
    $underJoined = $under -join "$h$([char]0x253C)$h"
    Write-IaRaw "$border$v$reset$h$underJoined$h$border$v$reset"

    # Rows.
    foreach ($row in $matrix) {
        $cells = @()
        for ($ci = 0; $ci -lt $cols.Count; $ci++) {
            $raw = if ($ci -lt $row.Count) { $row[$ci] } else { '' }
            $cells += (& $padCell $raw $widths[$ci])
        }
        Write-IaRaw ("{0}{1}{2} {3} {0}{1}{2}" -f $border, $v, $reset, ($cells -join " $dim$v$reset "))
    }

    # Bottom.
    Write-IaRaw ("{0}{1}{2}" -f $border, (([char]0x2570) + ($h * [Math]::Max(0, $tableWidth - 2)) + ([char]0x256F)), $reset)
}

# ─── menus ───────────────────────────────────────────────────────────────────

function Read-IaMenuClassic {
    # Numbered selection via Read-Host. Non-interactive fallback (testable).
    [CmdletBinding()]
    param([string]$Title, [Parameter(Mandatory)][string[]]$Choices)
    if ($Title) { Write-IaHost $Title }
    for ($i = 0; $i -lt $Choices.Count; $i++) {
        Write-IaHost ("  [grey]{0,2}[/]) {1}" -f ($i + 1), (Protect-IaMarkup $Choices[$i]))
    }
    while ($true) {
        $ans = Read-Host 'Select (number)'
        if ([string]::IsNullOrWhiteSpace($ans)) { return 0 }
        if ($ans -match '^\d+$') {
            $n = [int]$ans
            if ($n -ge 1 -and $n -le $Choices.Count) { return ($n - 1) }
        }
    }
}

function Read-IaMenuArrow {
    # Arrow-key single-select with viewport. Returns chosen index, or -1 on Escape.
    # -Header is a pre-rendered (ANSI) banner drawn at the top of every frame.
    [CmdletBinding()]
    param([string]$Title, [Parameter(Mandatory)][string[]]$Choices, [string]$Color = 'grey', [int]$PageSize = 15, [string]$Header = '')

    $reset = Get-IaReset
    $accent = Get-IaAnsi $Color
    $dim = Get-IaAnsi 'dim'
    $bold = Get-IaAnsi 'bold'
    $count = $Choices.Count
    $page = [Math]::Min([Math]::Max(1, $PageSize), $count)
    $sel = 0
    $headerLines = if ($Header) { @($Header -split "`n") } else { @() }
    $vp = @{ top = 0 }

    $render = {
        if ($sel -lt $vp.top) { $vp.top = $sel }
        elseif ($sel -ge ($vp.top + $page)) { $vp.top = $sel - $page + 1 }
        $lines = [System.Collections.Generic.List[string]]::new()
        foreach ($hl in $headerLines) { $lines.Add($hl) }
        if ($Title) { $lines.Add("$accent$bold$(Strip-IaMarkup $Title)$reset") }
        $lines.Add($(if ($vp.top -gt 0) { "$dim   ↑ more$reset" } else { '' }))
        for ($i = $vp.top; $i -lt ($vp.top + $page); $i++) {
            if ($i -lt $count) {
                $label = ConvertFrom-IaMarkup -Text $Choices[$i]
                if ($i -eq $sel) { $lines.Add("$accent ❯ $bold$label$reset") }
                else { $lines.Add("   $label$reset") }
            }
            else { $lines.Add('') }
        }
        $lines.Add($(if (($vp.top + $page) -lt $count) { "$dim   ↓ more$reset" } else { '' }))
        $lines.Add("$dim   ↑/↓ move · Enter select · Esc back$reset")

        # Full clear + redraw from home on every keypress through the one shared
        # output path (Write-IaRaw). Constant line count keeps the region stable; a
        # full clear each frame means there is no in-place state to drift.
        Write-IaRaw ("$($script:IaEsc)[2J$($script:IaEsc)[3J$($script:IaEsc)[H" + ($lines -join "`n") + "`n") -NoNewline
    }

    try {
        Write-IaRaw (Get-IaSeq '?25l') -NoNewline   # hide cursor
        & $render
        while ($true) {
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { $sel = ($sel - 1 + $count) % $count; & $render }
                'DownArrow' { $sel = ($sel + 1) % $count; & $render }
                'Home'      { $sel = 0; & $render }
                'End'       { $sel = $count - 1; & $render }
                'PageUp'    { $sel = [Math]::Max(0, $sel - $page); & $render }
                'PageDown'  { $sel = [Math]::Min($count - 1, $sel + $page); & $render }
                'Enter'     { return $sel }
                'Escape'    { return -1 }
            }
        }
    }
    finally {
        # Blank the whole screen HERE, inside the menu's own render context where full
        # repaints take effect (a clear issued after this function returns can be
        # dropped by the host, leaving the menu visible under the next screen). Clear
        # each line then home, all as flowing content so it always lands.
        $bh = 50; try { $bh = [Console]::WindowHeight } catch { }
        if ($bh -lt 1) { $bh = 50 }
        Write-IaRaw ("$($script:IaEsc)[H" + ("$($script:IaEsc)[2K`n" * $bh) + "$($script:IaEsc)[H") -NoNewline
        Write-IaRaw (Get-IaSeq '?25h') -NoNewline   # show cursor
    }
}

function Read-IaMenu {
    <#
    .SYNOPSIS
        Single-select menu. Returns the chosen STRING (or $null). Replaces
        Read-SpectreSelection. Arrow-key when interactive, numbered otherwise.
    #>
    [CmdletBinding()]
    param(
        [string]$Title,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Choices,
        [string]$Color = 'grey',
        [int]$PageSize = 15,
        [switch]$EnableSearch,
        [string]$Header = ''
    )
    $list = @($Choices)
    if ($list.Count -eq 0) { return $null }
    if (Test-IaArrowSupport) {
        $idx = Read-IaMenuArrow -Title $Title -Choices $list -Color $Color -PageSize $PageSize -Header $Header
    }
    else {
        $idx = Read-IaMenuClassic -Title $Title -Choices $list
    }
    if ($idx -is [int] -and $idx -ge 0 -and $idx -lt $list.Count) { return $list[$idx] }
    return $null
}

function Read-IaMultiMenuClassic {
    # Numbered multi-select via Read-Host (comma/space separated). Testable.
    [CmdletBinding()]
    param([string]$Title, [Parameter(Mandatory)][string[]]$Choices)
    if ($Title) { Write-IaHost $Title }
    for ($i = 0; $i -lt $Choices.Count; $i++) {
        Write-IaHost ("  [grey]{0,2}[/]) {1}" -f ($i + 1), (Protect-IaMarkup $Choices[$i]))
    }
    Write-IaHost "[grey]Enter numbers separated by space/comma (blank = none, 'all' = all):[/]"
    $ans = Read-Host 'Select'
    if ([string]::IsNullOrWhiteSpace($ans)) { return @() }
    if ($ans.Trim().ToLower() -eq 'all') { return @(0..($Choices.Count - 1)) }
    $idx = foreach ($tok in ($ans -split '[,\s]+' | Where-Object { $_ })) {
        if ($tok -match '^\d+$') { $n = [int]$tok; if ($n -ge 1 -and $n -le $Choices.Count) { $n - 1 } }
    }
    return @($idx | Sort-Object -Unique)
}

function Read-IaMultiMenuArrow {
    # Arrow-key multi-select. Space toggles, A toggles all, Enter confirms.
    [CmdletBinding()]
    param([string]$Title, [Parameter(Mandatory)][string[]]$Choices, [string]$Color = 'grey', [int]$PageSize = 15)

    $reset = Get-IaReset
    $accent = Get-IaAnsi $Color
    $dim = Get-IaAnsi 'dim'
    $bold = Get-IaAnsi 'bold'
    $green = Get-IaAnsi 'green'
    $count = $Choices.Count
    $page = [Math]::Min([Math]::Max(1, $PageSize), $count)
    $sel = 0
    $checked = [bool[]]::new($count)
    # Reference-type render state (see note in Read-IaMenuArrow).
    $vp = @{ top = 0; prev = 0 }

    $render = {
        if ($sel -lt $vp.top) { $vp.top = $sel }
        elseif ($sel -ge ($vp.top + $page)) { $vp.top = $sel - $page + 1 }
        $lines = [System.Collections.Generic.List[string]]::new()
        if ($Title) { $lines.Add("$accent$bold$(Strip-IaMarkup $Title)$reset") }
        # Constant line count across navigation (see note in Read-IaMenuArrow).
        $lines.Add($(if ($vp.top -gt 0) { "$dim     ↑ more$reset" } else { '' }))
        for ($i = $vp.top; $i -lt ($vp.top + $page); $i++) {
            if ($i -lt $count) {
                $box = if ($checked[$i]) { "$green[x]$reset" } else { "$dim[ ]$reset" }
                $label = ConvertFrom-IaMarkup -Text $Choices[$i]
                if ($i -eq $sel) { $lines.Add("$accent ❯ $box $bold$label$reset") }
                else { $lines.Add("   $box $label$reset") }
            }
            else { $lines.Add('') }
        }
        $lines.Add($(if (($vp.top + $page) -lt $count) { "$dim     ↓ more$reset" } else { '' }))
        $n = (@($checked | Where-Object { $_ })).Count
        $lines.Add("$dim   Space toggle · A all · Enter confirm ($n selected) · Esc cancel$reset")

        # Full clear + redraw from home each keypress through the shared output path.
        Write-IaRaw ("$($script:IaEsc)[2J$($script:IaEsc)[3J$($script:IaEsc)[H" + ($lines -join "`n") + "`n") -NoNewline
    }

    try {
        Write-IaRaw (Get-IaSeq '?25l') -NoNewline
        & $render
        while ($true) {
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { $sel = ($sel - 1 + $count) % $count; & $render }
                'DownArrow' { $sel = ($sel + 1) % $count; & $render }
                'Spacebar'  { $checked[$sel] = -not $checked[$sel]; & $render }
                'A'         { $all = (@($checked | Where-Object { $_ }).Count -eq $count); for ($i = 0; $i -lt $count; $i++) { $checked[$i] = -not $all }; & $render }
                'Enter'     { $out = @(); for ($i = 0; $i -lt $count; $i++) { if ($checked[$i]) { $out += $i } }; return $out }
                'Escape'    { return @() }
            }
        }
    }
    finally {
        # Blank the screen in the menu's own render context (see Read-IaMenuArrow).
        $bh = 50; try { $bh = [Console]::WindowHeight } catch { }
        if ($bh -lt 1) { $bh = 50 }
        Write-IaRaw ("$($script:IaEsc)[H" + ("$($script:IaEsc)[2K`n" * $bh) + "$($script:IaEsc)[H") -NoNewline
        Write-IaRaw (Get-IaSeq '?25h') -NoNewline
    }
}

function Read-IaMultiMenu {
    <#
    .SYNOPSIS
        Multi-select menu. Returns an array of chosen STRINGS (possibly empty).
        Replaces Read-SpectreMultiSelection.
    #>
    [CmdletBinding()]
    param(
        [string]$Title,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Choices,
        [string]$Color = 'grey',
        [int]$PageSize = 15
    )
    $list = @($Choices)
    if ($list.Count -eq 0) { return @() }
    if (Test-IaArrowSupport) {
        $idx = @(Read-IaMultiMenuArrow -Title $Title -Choices $list -Color $Color -PageSize $PageSize)
    }
    else {
        $idx = @(Read-IaMultiMenuClassic -Title $Title -Choices $list)
    }
    $out = foreach ($i in $idx) { if ($i -ge 0 -and $i -lt $list.Count) { $list[$i] } }
    return @($out)
}

# ─── export ──────────────────────────────────────────────────────────────────

function Invoke-IaExport {
    # Export an array of objects to CSV, Excel, or JSON.  Strips markup from
    # values so the file contains plain text.  Opens the containing folder on
    # Windows/macOS after writing.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Data,
        [string]$Stem  = 'tide-export',
        [string]$Color = 'turquoise2'
    )
    $clean = @($Data | ForEach-Object {
        $src = $_
        $isDict = $src -is [System.Collections.IDictionary]
        $o = [ordered]@{}
        if ($isDict) {
            foreach ($k in $src.Keys) {
                $o[$k] = Strip-IaMarkup ([string]($src[$k] ?? ''))
            }
        } else {
            foreach ($p in $src.PSObject.Properties) {
                $o[$p.Name] = Strip-IaMarkup ([string]($p.Value ?? ''))
            }
        }
        [pscustomobject]$o
    })

    $choices = [System.Collections.Generic.List[string]]@('CSV')
    if (Get-Module ImportExcel -ListAvailable -ErrorAction SilentlyContinue) { $choices.Add('Excel (.xlsx)') }
    $choices.Add('JSON'); $choices.Add('Cancel')

    $fmt = Read-IaMenu -Title 'Export format' -Color $Color -Choices $choices.ToArray()
    if (-not $fmt -or $fmt -eq 'Cancel') { return }

    $ts   = (Get-Date -Format 'yyyyMMdd-HHmm')
    $safe = ($Stem -replace '[^\w-]','-') + "-$ts"
    $tmp  = [IO.Path]::GetTempPath()
    $path = $null

    switch -Wildcard ($fmt) {
        'CSV' {
            $path = Join-Path $tmp "$safe.csv"
            $clean | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
            Write-IaHost "[$Color]✓ CSV → $path[/]"
        }
        'Excel*' {
            $path = Join-Path $tmp "$safe.xlsx"
            $clean | Export-Excel -Path $path -AutoSize -BoldTopRow -FreezeTopRow
            Write-IaHost "[$Color]✓ Excel → $path[/]"
        }
        'JSON' {
            $path = Join-Path $tmp "$safe.json"
            $clean | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding UTF8
            Write-IaHost "[$Color]✓ JSON → $path[/]"
        }
    }
    if ($path -and (Test-Path $path)) {
        try {
            if ($IsWindows) { Start-Process 'explorer.exe' "/select,`"$path`"" }
            elseif ($IsMacOS) { & open -R $path }
        } catch { }
    }
}

function Read-IaTableInteractive {
    <#
    .SYNOPSIS
        Scrollable, searchable, exportable interactive table viewer.
        ↑/↓/PgUp/PgDn scroll · / search · e export · ? help · q back.
        With -Selectable, Enter returns the chosen row for drill-down.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Data,
        [string]$Color     = 'grey',
        [string]$Title     = '',
        [string]$Stem      = 'tide-export',
        [switch]$Selectable
    )

    $rows = @($Data | Where-Object { $null -ne $_ })
    if ($rows.Count -eq 0) {
        Write-IaHost '[grey](no data)[/]'
        Read-IaPause
        return $null
    }

    # Non-interactive fallback (Pester / redirected I/O)
    if (-not (Test-IaArrowSupport)) {
        Show-IaTableObjects -Rows $rows -Color $Color -Title $Title
        Read-IaPause
        return $null
    }

    # ── Pre-compute columns and cell matrix (done once; not per-frame) ──────
    $isDictionary = $rows[0] -is [System.Collections.IDictionary]
    $cols = if ($isDictionary) { @($rows[0].Keys) } else { @($rows[0].PSObject.Properties.Name) }

    $allCells = [System.Collections.Generic.List[object[]]]::new()
    foreach ($r in $rows) {
        $isDict = $r -is [System.Collections.IDictionary]
        $cells = foreach ($c in $cols) {
            $cv = if ($isDict) { $r[$c] } else { $r.PSObject.Properties[$c].Value }
            if ($null -eq $cv) { '' } else { [string]$cv }
        }
        $allCells.Add(@($cells))
    }

    $widths = @(foreach ($c in $cols) { Measure-IaWidth (Strip-IaMarkup $c) })
    for ($ri = 0; $ri -lt $allCells.Count; $ri++) {
        for ($ci = 0; $ci -lt $cols.Count; $ci++) {
            $cw = Measure-IaWidth (Strip-IaMarkup $allCells[$ri][$ci])
            if ($cw -gt $widths[$ci]) { $widths[$ci] = $cw }
        }
    }
    $inner = Get-IaInnerWidth
    $csep  = ($cols.Count - 1) * 3
    $cpad  = 4
    $sum   = ($widths | Measure-Object -Sum).Sum
    if (($sum + $csep + $cpad) -gt $inner) {
        $avail = [Math]::Max($cols.Count * 4, $inner - $csep - $cpad)
        $tot   = if ($sum -lt 1) { 1 } else { $sum }
        for ($ci = 0; $ci -lt $cols.Count; $ci++) {
            $widths[$ci] = [Math]::Max(4, [int]($widths[$ci] * $avail / $tot))
        }
    }
    $tableWidth = (($widths | Measure-Object -Sum).Sum) + $csep + $cpad

    # ── ANSI codes ──────────────────────────────────────────────────────────
    $reset  = Get-IaReset
    $border = Get-IaAnsi $Color
    $bold   = Get-IaAnsi 'bold'
    $dim    = Get-IaAnsi 'dim'
    $white  = Get-IaAnsi 'white'
    $v      = [string][char]0x2502
    $h      = [string][char]0x2500

    # Page size: terminal height minus chrome (title + header + underline + bottom + status + margin)
    $pageSize = 20
    try { $pageSize = [Math]::Max(5, [Console]::WindowHeight - 10) } catch { }

    # ── Mutable state (hashtable so mutations inside scriptblocks propagate) ─
    $st = @{ sel = 0; top = 0; query = ''; searching = $false }

    # ── padCell: fixed-width string for one data cell ───────────────────────
    # Selected cells use bold accent color; others use markup rendering.
    $padCell = {
        param($Raw, $Width, [bool]$IsSelected = $false)
        $plain = Strip-IaMarkup -Text $Raw
        $dw    = Measure-IaWidth $plain
        if ($dw -gt $Width) {
            $cut = 0; $acc = 0; $max = [Math]::Max(1, $Width - 1)
            for ($k = 0; $k -lt $plain.Length; $k++) {
                $chW = Measure-IaWidth ([string]$plain[$k])
                if (($acc + $chW) -gt $max) { break }
                $acc += $chW; $cut++
            }
            $plain = $plain.Substring(0, [Math]::Max(1, $cut)) + '…'
            $dw    = Measure-IaWidth $plain
        }
        $padding = ' ' * [Math]::Max(0, $Width - $dw)
        if ($IsSelected) { return "$border$bold$plain$reset$padding" }
        return (ConvertFrom-IaMarkup $Raw) + $reset + $padding
    }

    # ── getFiltered: row indices that match the current search query ─────────
    $getFiltered = {
        if ([string]::IsNullOrEmpty($st.query)) { return @(0..($rows.Count - 1)) }
        $q  = $st.query.ToLower()
        $ix = [System.Collections.Generic.List[int]]::new()
        for ($ri = 0; $ri -lt $allCells.Count; $ri++) {
            foreach ($cell in $allCells[$ri]) {
                if ((Strip-IaMarkup $cell).ToLower().Contains($q)) { $ix.Add($ri); break }
            }
        }
        return @($ix)
    }

    # ── renderFrame: full screen repaint from state ──────────────────────────
    $renderFrame = {
      try {
        $filtered = @(& $getFiltered)
        $total    = $filtered.Count

        $s = $st.sel; $top = $st.top
        if ($total -eq 0) { $s = 0; $top = 0 }
        else {
            if ($s -ge $total)            { $s   = $total - 1 }
            if ($s -lt 0)                 { $s   = 0 }
            if ($s -lt $top)              { $top = $s }
            if ($s -ge ($top + $pageSize)) { $top = $s - $pageSize + 1 }
        }
        $st.sel = $s; $st.top = $top

        $buf = [System.Text.StringBuilder]::new(16384)

        # Local copies of outer-scope ANSI vars — avoids PowerShell -f scope quirk
        # in nested scriptblocks where $border/$v/$reset resolve unexpectedly.
        $_b = $border; $_v = $v; $_r = $reset; $_d = $dim; $_bo = $bold; $_wh = $white; $_h = $h

        # Title
        if ($Title) {
            $pt = Strip-IaMarkup $Title; $tw = Measure-IaWidth $pt
            $ll  = $tableWidth - 4 - $tw
            $lft = [Math]::Max(1, [int][Math]::Floor($ll / 2))
            $rgt = [Math]::Max(1, $ll - $lft)
            [void]$buf.AppendLine($_b + [char]0x256D + ($_h * $lft) + $_r + ' ' + (ConvertFrom-IaMarkup $Title) + ' ' + $_b + ($_h * $rgt) + [char]0x256E + $_r)
        }

        # Column header
        $hdrCells = @(for ($ci = 0; $ci -lt $cols.Count; $ci++) {
            $plain = Strip-IaMarkup $cols[$ci]; $w = Measure-IaWidth $plain
            $_bo + $_wh + $plain + $_r + (' ' * [Math]::Max(0, $widths[$ci] - $w))
        })
        [void]$buf.AppendLine($_b + $_v + $_r + ' ' + ($hdrCells -join " $_d$_v$_r ") + ' ' + $_b + $_v + $_r)

        # Underline
        $under = @(for ($ci = 0; $ci -lt $cols.Count; $ci++) { $_h * $widths[$ci] })
        [void]$buf.AppendLine($_b + $_v + $_r + $_h + ($under -join ($_h + [char]0x253C + $_h)) + $_h + $_b + $_v + $_r)

        # Data rows
        if ($total -eq 0) {
            $msg = if ($st.query) { "  (no rows match '$($st.query)')" } else { '  (no data)' }
            [void]$buf.AppendLine("$_d$msg$_r")
            for ($p = 1; $p -lt $pageSize; $p++) { [void]$buf.AppendLine('') }
        }
        else {
            $endIdx = [Math]::Min($top + $pageSize - 1, $total - 1)
            for ($i = $top; $i -le $endIdx; $i++) {
                $ri    = $filtered[$i]
                $rowD  = $allCells[$ri]
                $isSel = ($Selectable -and $i -eq $s)
                $cells = @(for ($ci = 0; $ci -lt $cols.Count; $ci++) {
                    $raw = if ($ci -lt $rowD.Count) { $rowD[$ci] } else { '' }
                    & $padCell $raw $widths[$ci] $isSel
                })
                [void]$buf.AppendLine($_b + $_v + $_r + ' ' + ($cells -join " $_d$_v$_r ") + ' ' + $_b + $_v + $_r)
            }
            # Pad to keep layout stable (status bar stays at fixed position)
            for ($p = ($endIdx - $top + 1); $p -lt $pageSize; $p++) { [void]$buf.AppendLine('') }
        }

        # Bottom border
        [void]$buf.AppendLine($_b + [char]0x2570 + ($_h * [Math]::Max(0, $tableWidth - 2)) + [char]0x256F + $_r)

        # Status / search bar
        $rs = if ($total -eq 0) { 0 } else { $top + 1 }
        $re = [Math]::Min($top + $pageSize, $total)
        if ($st.searching) {
            [void]$buf.Append("  $dim/ search: $reset$border$($st.query)$reset$white▌$reset  $dim Esc cancel  Enter confirm$reset")
        }
        else {
            $cnt    = "$dim[$reset$rs-$re of $total$dim]$reset"
            $selTip = if ($Selectable) { ' · Enter select' } else { '' }
            $clrTip = if ($st.query) { "  $dim(filter: $reset$border$($st.query)$reset$dim · Esc clear)$reset" } else { '' }
            [void]$buf.Append("  $cnt  $dim↑/↓ scroll · PgUp/PgDn · / search · e export · ? help$selTip · q back$reset$clrTip")
        }

        Write-IaRaw ("$($script:IaEsc)[2J$($script:IaEsc)[3J$($script:IaEsc)[H" + $buf.ToString()) -NoNewline
      } catch {
        Write-IaRaw ("`nRENDER-ERR: $($_.Exception.GetType().Name): $($_.Exception.Message)`n$($_.ScriptStackTrace)`n") -NoNewline
        throw
      }
    }

    # ── showHelp: ? overlay ─────────────────────────────────────────────────
    $showHelp = {
        $hl = [System.Collections.Generic.List[string]]::new()
        $hl.Add('')
        $hl.Add('  [bold white]Table Key Bindings[/]')
        $hl.Add('')
        $hl.Add('  [grey]↑ / k[/]       scroll up one row')
        $hl.Add('  [grey]↓ / j[/]       scroll down one row')
        $hl.Add('  [grey]PgUp / PgDn[/] scroll one page')
        $hl.Add('  [grey]Home / End[/]  jump to first / last row')
        $hl.Add('')
        $hl.Add('  [grey]/[/]           open search filter (real-time)')
        $hl.Add('  [grey]Esc[/]         clear filter / go back')
        $hl.Add('')
        $hl.Add('  [grey]e[/]           export (CSV · Excel · JSON)')
        $hl.Add('  [grey]?[/]           this help overlay')
        if ($Selectable) { $hl.Add('  [grey]Enter[/]       select row · drill-down') }
        $hl.Add('  [grey]q[/]           go back')
        $hl.Add('')
        $hl.Add('  [dim]press any key to dismiss…[/]')

        $maxW = ($hl | ForEach-Object { Measure-IaWidth (Strip-IaMarkup $_) } | Measure-Object -Maximum).Maximum
        $bW   = $maxW + 2
        $tl   = [string][char]0x256D; $tr = [string][char]0x256E
        $bl   = [string][char]0x2570; $br = [string][char]0x256F

        $out = [System.Text.StringBuilder]::new()
        [void]$out.AppendLine("$border$tl$($h * $bW)$tr$reset")
        foreach ($line in $hl) {
            $pw  = Measure-IaWidth (Strip-IaMarkup $line)
            $pad = ' ' * [Math]::Max(0, $maxW - $pw + 1)
            [void]$out.AppendLine("$border$v$reset $(ConvertFrom-IaMarkup $line)$reset$pad$border$v$reset")
        }
        [void]$out.AppendLine("$border$bl$($h * $bW)$br$reset")

        Write-IaRaw ("$($script:IaEsc)[2J$($script:IaEsc)[3J$($script:IaEsc)[H" + $out.ToString()) -NoNewline
        $null = [Console]::ReadKey($true)
        & $renderFrame
    }

    # ── Main interactive loop ─────────────────────────────────────────────────
    try {
        Write-IaRaw (Get-IaSeq '?25l') -NoNewline    # hide cursor
        & $renderFrame

        while ($true) {
            $key = [Console]::ReadKey($true)

            if ($st.searching) {
                switch ($key.Key) {
                    'Escape'    { $st.searching = $false; $st.query = ''; $st.sel = 0; $st.top = 0; & $renderFrame }
                    'Enter'     { $st.searching = $false; & $renderFrame }
                    'Backspace' {
                        if ($st.query.Length -gt 0) { $st.query = $st.query.Substring(0, $st.query.Length - 1) }
                        $st.sel = 0; $st.top = 0; & $renderFrame
                    }
                    default {
                        if ($key.KeyChar -ge ' ') { $st.query += $key.KeyChar; $st.sel = 0; $st.top = 0; & $renderFrame }
                    }
                }
            }
            else {
                $filtered = @(& $getFiltered)
                $total    = $filtered.Count
                $moved    = $false

                switch ($key.Key) {
                    'UpArrow'   { if ($st.sel -gt 0)              { $st.sel-- };                                                    $moved = $true }
                    'DownArrow' { if ($st.sel -lt ($total - 1))   { $st.sel++ };                                                    $moved = $true }
                    'PageUp'    { $st.sel = [Math]::Max(0, $st.sel - $pageSize);                                                    $moved = $true }
                    'PageDown'  { $st.sel = [Math]::Min([Math]::Max(0, $total - 1), $st.sel + $pageSize);                          $moved = $true }
                    'Home'      { $st.sel = 0;                                                                                      $moved = $true }
                    'End'       { $st.sel = [Math]::Max(0, $total - 1);                                                             $moved = $true }
                    'Escape'    {
                        if ($st.query) { $st.query = ''; $st.sel = 0; $st.top = 0; & $renderFrame }
                        else           { return $null }
                    }
                    'Enter'     {
                        if ($Selectable -and $total -gt 0) { return $rows[$filtered[$st.sel]] }
                        else                               { return $null }
                    }
                    default     {
                        switch ($key.KeyChar) {
                            '/'  { $st.searching = $true; & $renderFrame }
                            'e'  { Invoke-IaExport -Data $rows -Stem $Stem -Color $Color; & $renderFrame }
                            '?'  { & $showHelp }
                            'q'  { return $null }
                            'j'  { if ($st.sel -lt ($total - 1)) { $st.sel++ }; & $renderFrame }
                            'k'  { if ($st.sel -gt 0)            { $st.sel-- }; & $renderFrame }
                        }
                    }
                }
                if ($moved) { & $renderFrame }
            }
        }
    }
    finally {
        $bh = 50; try { $bh = [Console]::WindowHeight } catch { }
        Write-IaRaw ("$($script:IaEsc)[H" + ("$($script:IaEsc)[2K`n" * $bh) + "$($script:IaEsc)[H") -NoNewline
        Write-IaRaw (Get-IaSeq '?25h') -NoNewline    # show cursor
    }
}

function Read-IaTablePause {
    # Legacy wrapper — now delegates to Read-IaTableInteractive so every table
    # gets scrolling, search (/ key), export (e), and help (?) for free.
    [CmdletBinding()]
    param(
        [object[]]$Data,
        [string]$Stem  = 'tide-export',
        [string]$Color = 'turquoise2',
        [string]$Title = ''
    )
    [void](Read-IaTableInteractive -Data @($Data) -Stem $Stem -Color $Color -Title $Title)
}

# ─── custom report pipeline engine (pure data — unit-testable) ────────────────

$script:IaReportOperators = [ordered]@{
    'eq'          = 'equals'
    'ne'          = 'not equals'
    'contains'    = 'contains'
    'notcontains' = 'does not contain'
    'startswith'  = 'starts with'
    'endswith'    = 'ends with'
    'like'        = 'matches wildcard'
    'match'       = 'matches regex'
    'gt'          = 'greater than'
    'ge'          = 'greater or equal'
    'lt'          = 'less than'
    'le'          = 'less or equal'
    'isempty'     = 'is empty / null'
    'notempty'    = 'is not empty'
    'istrue'      = 'is true'
    'isfalse'     = 'is false'
}

function ConvertTo-IaReportNumber {
    # Coerce a value to [double] if it looks numeric, else $null.
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [int] -or $Value -is [double] -or $Value -is [long] -or
        $Value -is [decimal] -or $Value -is [single]) { return [double]$Value }
    $d = 0.0
    if ([double]::TryParse("$Value", [ref]$d)) { return $d }
    return $null
}

function Compare-IaReportValue {
    # Three-way compare: numeric first, then datetime, then case-insensitive string.
    param($A, $B)
    $na = ConvertTo-IaReportNumber $A
    $nb = ConvertTo-IaReportNumber $B
    if ($null -ne $na -and $null -ne $nb) { return [math]::Sign($na - $nb) }
    $da = [datetime]::MinValue; $db = [datetime]::MinValue
    if ([datetime]::TryParse("$A", [ref]$da) -and [datetime]::TryParse("$B", [ref]$db)) {
        return $da.CompareTo($db)
    }
    return [string]::Compare("$A", "$B", $true)
}

function Test-IaReportPredicate {
    # Evaluate one filter predicate against a cell value. Never throws.
    [OutputType([bool])]
    param($Value, [string]$Operator, $Operand)
    $sV = if ($null -eq $Value) { '' } else { "$Value" }
    switch ($Operator) {
        'eq'          { return $sV -eq "$Operand" }
        'ne'          { return $sV -ne "$Operand" }
        'contains'    { return $sV -like "*$Operand*" }
        'notcontains' { return $sV -notlike "*$Operand*" }
        'startswith'  { return $sV -like "$Operand*" }
        'endswith'    { return $sV -like "*$Operand" }
        'like'        { return $sV -like "$Operand" }
        'match'       { try { return $sV -match $Operand } catch { return $false } }
        'gt'          { return (Compare-IaReportValue $Value $Operand) -gt 0 }
        'ge'          { return (Compare-IaReportValue $Value $Operand) -ge 0 }
        'lt'          { return (Compare-IaReportValue $Value $Operand) -lt 0 }
        'le'          { return (Compare-IaReportValue $Value $Operand) -le 0 }
        'isempty'     { return [string]::IsNullOrWhiteSpace($sV) }
        'notempty'    { return -not [string]::IsNullOrWhiteSpace($sV) }
        'istrue'      { return ($sV -eq 'True'  -or $sV -eq '1') }
        'isfalse'     { return ($sV -eq 'False' -or $sV -eq '0' -or [string]::IsNullOrWhiteSpace($sV)) }
        default       { return $true }
    }
}

function Get-IaReportProperties {
    # Union of property names across a sample of rows (handles ragged objects and
    # IDictionary rows). Order: first-row order, then any extras as discovered.
    [OutputType([string[]])]
    param([object[]]$Data, [int]$Sample = 50)
    $seen = [System.Collections.Specialized.OrderedDictionary]::new()
    $n = [Math]::Min($Sample, @($Data).Count)
    for ($i = 0; $i -lt $n; $i++) {
        $row = $Data[$i]
        if ($null -eq $row) { continue }
        $names = if ($row -is [System.Collections.IDictionary]) { @($row.Keys) }
                 else { @($row.PSObject.Properties.Name) }
        foreach ($nm in $names) { if (-not $seen.Contains($nm)) { $seen.Add($nm, $true) } }
    }
    return @($seen.Keys)
}

function Get-IaReportCellValue {
    # Read a property from a row whether it's a PSObject or IDictionary.
    param($Row, [string]$Prop)
    if ($null -eq $Row) { return $null }
    if ($Row -is [System.Collections.IDictionary]) { return $Row[$Prop] }
    $p = $Row.PSObject.Properties[$Prop]
    if ($p) { return $p.Value }
    return $null
}

function Invoke-IaReportPipeline {
    <#
    .SYNOPSIS
        Apply a report recipe (where → group/aggregate → sort → select → top) to
        an in-memory object array. Pure data transform; no I/O, never throws on a
        bad predicate. Returns an object[] of PSCustomObjects.

    .PARAMETER Recipe
        Hashtable / object with keys:
          Where   : array of @{ Prop; Op; Val }       (AND-combined)
          GroupBy : property name (string) or $null
          Agg     : @{ Func = Count|Sum|Avg|Min|Max; Prop = <numeric prop> } or $null
          Sort    : array of @{ Prop; Desc }           (applied in order)
          Select  : array of property names ([] = all; ignored when GroupBy set)
          Top     : int (0 = no limit)
    #>
    [CmdletBinding()]
    param([object[]]$Data, $Recipe)

    $rows = @($Data | Where-Object { $null -ne $_ })

    # 1. WHERE — AND of every predicate.
    foreach ($f in @($Recipe.Where)) {
        if (-not $f -or -not $f.Prop) { continue }
        $rows = @($rows | Where-Object {
            Test-IaReportPredicate -Value (Get-IaReportCellValue $_ $f.Prop) -Operator $f.Op -Operand $f.Val
        })
    }

    # 2. GROUP + aggregate (terminal projection) OR passthrough.
    if ($Recipe.GroupBy) {
        $gp  = [string]$Recipe.GroupBy
        $agg = $Recipe.Agg
        $rows = @($rows | Group-Object -Property {
            Get-IaReportCellValue $_ $gp
        } | ForEach-Object {
            $o = [ordered]@{}
            $o[$gp]   = $_.Name
            $o.Count  = $_.Count
            if ($agg -and $agg.Func -and $agg.Func -ne 'Count' -and $agg.Prop) {
                $nums = @($_.Group | ForEach-Object { ConvertTo-IaReportNumber (Get-IaReportCellValue $_ $agg.Prop) } |
                         Where-Object { $null -ne $_ })
                $val = switch ($agg.Func) {
                    'Sum' { ($nums | Measure-Object -Sum).Sum }
                    'Avg' { if ($nums) { [math]::Round(($nums | Measure-Object -Average).Average, 2) } else { 0 } }
                    'Min' { if ($nums) { ($nums | Measure-Object -Minimum).Minimum } else { $null } }
                    'Max' { if ($nums) { ($nums | Measure-Object -Maximum).Maximum } else { $null } }
                    default { $null }
                }
                $o["$($agg.Func)($($agg.Prop))"] = $val
            }
            [pscustomobject]$o
        })
    }

    # 3. SORT — string Expression keys (typed values compare correctly).
    if (@($Recipe.Sort).Count -gt 0) {
        $sortKeys = @($Recipe.Sort | Where-Object { $_ -and $_.Prop } | ForEach-Object {
            @{ Expression = [string]$_.Prop; Descending = [bool]$_.Desc }
        })
        if ($sortKeys.Count -gt 0) { $rows = @($rows | Sort-Object -Property $sortKeys) }
    }

    # 4. SELECT — only when not grouped (grouping already fixes columns).
    if (-not $Recipe.GroupBy -and @($Recipe.Select).Count -gt 0) {
        $rows = @($rows | Select-Object -Property @($Recipe.Select))
    }

    # 5. TOP.
    if ([int]$Recipe.Top -gt 0) { $rows = @($rows | Select-Object -First ([int]$Recipe.Top)) }

    # Emit elements (callers wrap with @()). A unary-comma return would wrap an
    # EMPTY result into a 1-element array holding an empty array — making a
    # zero-row report look like one row. Plain @() emit keeps the empty case empty.
    return @($rows)
}
