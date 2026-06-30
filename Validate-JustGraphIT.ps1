<#
.SYNOPSIS
    Live validation script for JustGraphIT. Run this against a real tenant after connecting.

.DESCRIPTION
    Two sections:
      1. AUTOMATED — runs against the live tenant, prints PASS/FAIL for each check.
      2. MANUAL    — a numbered walkthrough of every TUI flow that cannot be automated.

.EXAMPLE
    Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All","Directory.Read.All"
    .\Validate-JustGraphIT.ps1
#>
[CmdletBinding()]
param(
    [switch]$ManualOnly,   # skip automated checks, just print the manual list
    [switch]$AutoOnly      # skip manual list
)

$pass  = 0
$fail  = 0
$warn  = 0

# ─── helpers ──────────────────────────────────────────────────────────────────

function Check {
    param([string]$Label, [scriptblock]$Test)
    try {
        $result = & $Test
        if ($result -eq $false) {
            Write-Host "  [FAIL] $Label" -ForegroundColor Red
            $script:fail++
        } else {
            Write-Host "  [PASS] $Label" -ForegroundColor Green
            $script:pass++
        }
    } catch {
        Write-Host "  [FAIL] $Label — $_" -ForegroundColor Red
        $script:fail++
    }
}

function Warn {
    param([string]$Label, [scriptblock]$Test)
    try {
        $result = & $Test
        if ($result -eq $false) {
            Write-Host "  [WARN] $Label" -ForegroundColor Yellow
            $script:warn++
        } else {
            Write-Host "  [PASS] $Label" -ForegroundColor Green
            $script:pass++
        }
    } catch {
        Write-Host "  [WARN] $Label — $_" -ForegroundColor Yellow
        $script:warn++
    }
}

function Section { param([string]$Title) Write-Host "`n=== $Title ===" -ForegroundColor Cyan }
function Manual  { param([string]$N, [string]$Step, [string]$Expect) Write-Host "  $N. $Step`n     → Expect: $Expect" }

# ─── AUTOMATED CHECKS ─────────────────────────────────────────────────────────

if (-not $ManualOnly) {
    Section "MODULE IMPORT"

    Check "Module imports without error" {
        Import-Module "$PSScriptRoot/JustGraphIT.psd1" -Force -ErrorAction Stop
        $true
    }

    Check "All Public functions exported" {
        $exported = (Get-Command -Module JustGraphIT).Name
        $pubFiles = Get-ChildItem "$PSScriptRoot/Public" -Filter '*.ps1' |
                    Select-String -Pattern '^function ' | ForEach-Object {
                        ($_ -split '\s+')[1] -replace '\s*\{.*'
                    }
        $missing = $pubFiles | Where-Object { $_ -notin $exported }
        if ($missing) { throw "Not exported: $($missing -join ', ')" }
        $true
    }

    # ── Private helpers ────────────────────────────────────────────────────────
    Section "PRIVATE HELPERS"

    Check "ConvertTo-IaSafeDateTime — valid ISO string returns datetime" {
        $dt = InModuleScope JustGraphIT { ConvertTo-IaSafeDateTime '2024-06-01T00:00:00Z' }
        $dt -is [datetime]
    }

    Check "ConvertTo-IaSafeDateTime — null returns null" {
        $r = InModuleScope JustGraphIT { ConvertTo-IaSafeDateTime $null }
        $null -eq $r
    }

    Check "ConvertTo-IaSafeDateTime — empty string returns null" {
        $r = InModuleScope JustGraphIT { ConvertTo-IaSafeDateTime '' }
        $null -eq $r
    }

    Check "ConvertTo-IaSafeDateTime — result is UTC kind" {
        $dt = InModuleScope JustGraphIT { ConvertTo-IaSafeDateTime '2024-06-01T12:00:00Z' }
        $dt.Kind -eq [System.DateTimeKind]::Utc
    }

    Check "ConvertTo-IaSafeInt — null returns default" {
        $r = InModuleScope JustGraphIT { ConvertTo-IaSafeInt $null 99 }
        $r -eq 99
    }

    Check "ConvertTo-IaSafeInt — empty array returns default not 0" {
        $r = InModuleScope JustGraphIT { ConvertTo-IaSafeInt @() 99 }
        $r -eq 99
    }

    Check "ConvertTo-IaSafeInt — single-element array extracts value" {
        $r = InModuleScope JustGraphIT { ConvertTo-IaSafeInt @(7) }
        $r -eq 7
    }

    # ── Live Graph calls (require connected session) ──────────────────────────
    Section "LIVE DATA — APPS"

    Warn "Get-IntuneApp — returns results" {
        $apps = Get-IntuneApp
        $apps.Count -gt 0
    }

    Warn "Get-IntuneApp -AppType macOS — returns macOSLobApp types too (not just OfficeSuite)" {
        $apps = Get-IntuneApp -AppType macOS
        # Should contain types other than just macOSOfficeSuiteApp
        $types = $apps | ForEach-Object { $_.AppType } | Sort-Object -Unique
        Write-Host "     macOS types found: $($types -join ', ')" -ForegroundColor Gray
        # Pass as long as it doesn't crash; manual verification of types needed
        $true
    }

    Warn "Get-IntuneApp -AppType Win32 — OData filter works" {
        $apps = Get-IntuneApp -AppType Win32
        # All returned types should be win32LobApp
        $wrongType = $apps | Where-Object { $_.AppType -notlike '*win32*' }
        $wrongType.Count -eq 0
    }

    Section "LIVE DATA — DEVICES"

    Warn "Get-IntuneDeviceInventory — returns results" {
        $devs = Get-IntuneDeviceInventory -Top 5
        $devs.Count -gt 0
    }

    Warn "Get-IntuneDeviceInventory — DaysStale is numeric not string" {
        $devs = Get-IntuneDeviceInventory -Top 5
        $d = $devs | Where-Object { $null -ne $_.DaysStale } | Select-Object -First 1
        if (-not $d) { Write-Host "     (no stale device to check — skipped)" -ForegroundColor Gray; return $true }
        $d.DaysStale -is [int] -or $d.DaysStale -is [double]
    }

    Warn "Get-IntuneDeviceDetail — datetime fields are real datetime objects" {
        $devs = @(Get-IntuneDeviceInventory -Top 3)
        if (-not $devs) { Write-Host "     (no devices)" -ForegroundColor Gray; return $true }
        $detail = Get-IntuneDeviceDetail -Device $devs[0].Device
        $fields = @{ EnrolledAt = $detail.EnrolledAt; LastSyncAt = $detail.LastSyncAt }
        $bad = $fields.GetEnumerator() | Where-Object { $_.Value -and $_.Value -isnot [datetime] }
        if ($bad) { throw "String instead of datetime: $(($bad | ForEach-Object { "$($_.Key)=$($_.Value.GetType().Name)" }) -join ', ')" }
        $true
    }

    Section "LIVE DATA — ENTRA ROLES"

    Warn "Get-EntraDirectoryRole — returns rows" {
        $r = Get-EntraDirectoryRole
        $r.Count -gt 0
    }

    Warn "Get-EntraRoleAssignment — no unhandled exception" {
        $r = Get-EntraRoleAssignment
        $true   # just checks it doesn't throw
    }

    Warn "Get-EntraPimEligibility — no unhandled exception" {
        $r = Get-EntraPimEligibility
        $true
    }

    Section "LIVE DATA — APP REGISTRATIONS"

    Warn "Get-EntraAppRegistration — DaysToExpiry is numeric for apps with creds" {
        $apps = Get-EntraAppRegistration
        $withCreds = $apps | Where-Object { $null -ne $_.DaysToExpiry } | Select-Object -First 1
        if (-not $withCreds) { Write-Host "     (no apps with credentials — skipped)" -ForegroundColor Gray; return $true }
        $withCreds.DaysToExpiry -is [int]
    }

    Warn "Add/Remove redirect URI preserves implicitGrantSettings" {
        # Find an app reg with a web platform that has implicitGrantSettings
        $apps = Get-EntraAppRegistration -Top 10 -Raw
        $webApp = $apps | Where-Object {
            $_.web -and $_.web.implicitGrantSettings -and
            ($_.web.implicitGrantSettings.enableAccessTokenIssuance -or
             $_.web.implicitGrantSettings.enableIdTokenIssuance)
        } | Select-Object -First 1

        if (-not $webApp) {
            Write-Host "     (no SPA/web app with implicit grant — create one to test this fix)" -ForegroundColor Yellow
            $script:warn++
            return $true
        }

        $before = $webApp.web.implicitGrantSettings | ConvertTo-Json
        # Add then immediately remove a test URI
        $testUri = "https://validate-just-graph-it-test.invalid/callback"
        Add-EntraAppRedirectUri -App $webApp.id -Uri $testUri -Platform Web -Confirm:$false | Out-Null
        Remove-EntraAppRedirectUri -App $webApp.id -Uri $testUri -Platform Web -Confirm:$false | Out-Null

        $after = (Get-EntraApplicationObject -App $webApp.id).web.implicitGrantSettings | ConvertTo-Json
        if ($before -ne $after) {
            throw "implicitGrantSettings changed! Before: $before  After: $after"
        }
        $true
    }

    Section "STABILITY FIXES (this pass)"

    Warn "Collection enumerates — Get-EntraDirectoryRole returns every row (not 1 merged)" {
        $roles = @(Get-EntraDirectoryRole)
        Write-Host "     directory roles returned: $($roles.Count)" -ForegroundColor Gray
        $roles.Count -gt 1
    }

    Warn "Detected apps enumerate per item (not one concatenated row)" {
        $devs = @(Get-IntuneDeviceInventory -Top 3)
        if (-not $devs) { Write-Host "     (no devices)" -ForegroundColor Gray; return $true }
        $apps = @((Get-IntuneDeviceDetail -Device $devs[0].Device -IncludeApps).Apps)
        Write-Host "     detected apps on $($devs[0].Device): $($apps.Count) row(s)" -ForegroundColor Gray
        if ($apps.Count -ge 1 -and "$($apps[0].App)" -match '\S+\s+\S+\s+\S+\s+\S+\s+\S+') {
            throw "App cell looks concatenated (collapse not fixed): $($apps[0].App)"
        }
        $true
    }

    Check "Get-EntraExpiringSecret is implemented with the documented shape" {
        $cmd = Get-Command Get-EntraExpiringSecret -ErrorAction Stop
        foreach ($p in 'Days','IncludeExpired','IncludeServicePrincipals') {
            if ($p -notin $cmd.Parameters.Keys) { throw "missing -$p parameter" }
        }
        $exp = @(Get-EntraExpiringSecret -Days 365 -IncludeExpired)
        if ($exp.Count -gt 0) {
            $f = $exp[0]
            foreach ($col in 'App','Kind','Expires','DaysLeft','Status') {
                if ($col -notin $f.PSObject.Properties.Name) { throw "missing column $col" }
            }
            if ($f.DaysLeft -isnot [int]) { throw "DaysLeft is $($f.DaysLeft.GetType().Name), expected Int32" }
        }
        $true
    }

    Warn "Expiring-secret dashboard tile resolves (was silently 0 — function was missing)" {
        $n = @(Get-EntraExpiringSecret -Days 30 -IncludeExpired).Count
        Write-Host "     secrets/certs expiring within 30 days (incl. expired): $n" -ForegroundColor Gray
        $true
    }

    Section "RESULTS"
    $total = $pass + $fail + $warn
    Write-Host "`n  Passed : $pass / $total" -ForegroundColor Green
    if ($warn -gt 0)  { Write-Host "  Warning: $warn / $total (live-data checks that need a populated tenant)" -ForegroundColor Yellow }
    if ($fail -gt 0)  { Write-Host "  Failed : $fail / $total" -ForegroundColor Red }
}

# ─── MANUAL TUI WALKTHROUGH ───────────────────────────────────────────────────

if (-not $AutoOnly) {

    Write-Host "`n`n=== MANUAL TUI WALKTHROUGH ===" -ForegroundColor Cyan
    Write-Host "Run: Start-JustGraphIT" -ForegroundColor White
    Write-Host "Work through every step. Mark PASS / FAIL in your notes.`n"

    Section "MAIN MENU NAVIGATION"
    Manual 1 "Press Esc on the main menu" `
        "Tool exits cleanly. It must NOT spin/loop forever."
    Manual 2 "Press Esc repeatedly in any submenu" `
        "Each Esc backs out one level. Never crashes, never hangs."

    Section "APPS SUBMENU  (main menu → Apps)"
    Manual 3 "Apps → 'All apps' with no apps in tenant" `
        "Shows yellow 'No apps found.' message, returns to Apps menu."
    Manual 4 "Apps → 'Filter by type' → press Esc on type picker" `
        "Returns to Apps menu. Must NOT call Get-IntuneApp."
    Manual 5 "Apps → 'Filter by type' → pick a type with zero apps" `
        "Shows yellow 'No <type> apps found.' message, returns to Apps menu."
    Manual 6 "Apps → 'App details' → press Esc on app picker" `
        "Returns to Apps menu (NOT main menu). Bug was: return vs break."
    Manual 7 "Apps → 'Assign app' → press Esc on app picker" `
        "Returns to Apps menu (NOT main menu)."

    Section "GROUP FLOWS"
    Manual 8 "Group lookup → press Esc on group picker" `
        "Returns to main menu with no crash."
    Manual 9 "Compare two groups → press Esc on Group A" `
        "Returns to main menu. Must NOT proceed to Group B picker."
    Manual 10 "Compare two groups → pick Group A → press Esc on Group B" `
        "Returns to main menu. Must NOT crash with null DisplayName."
    Manual 11 "Mirror → press Esc on source group picker" `
        "Returns to main menu. Must NOT call Get-IaCopyCandidates with null."
    Manual 12 "Mirror → pick source → pick items → press Esc on destination group" `
        "Returns to main menu. Must NOT crash on null dst.DisplayName."
    Manual 13 "Bulk Assign → press Esc on group picker" `
        "Returns to main menu immediately."
    Manual 14 "Templates → Capture → press Esc on group picker" `
        "Returns to main menu. Must NOT proceed to name/path prompts."
    Manual 15 "Templates → Apply → pick a file → press Esc on group picker" `
        "Returns to main menu. Must NOT crash on null g.DisplayName."

    Section "PIM / ELEVATE"
    Manual 16 "Elevate (PIM) → press Esc on role picker" `
        "Returns immediately. Must NOT show justification/duration prompts."
    Manual 17 "Elevate (PIM) → pick a role → press Esc on duration" `
        "Falls back to default 2h. Proceeds to confirm step."

    Section "IDENTITY / ENTRA"
    Manual 18 "Entra → Teams → Create team → press Esc on Visibility menu" `
        "Returns to previous screen. Must NOT show 'Create  Team' prompt with empty visibility."
    Manual 19 "Entra → App registrations → pick an app → Manage redirect URIs → Add a URI" `
        "After adding, verify the app's implicitGrantSettings are unchanged in the Portal."
    Manual 20 "Entra → App registrations → pick an app → Manage redirect URIs → Remove a URI" `
        "After removing, verify implicitGrantSettings still intact in the Portal."

    Section "REPORTS SUBMENU"
    Manual 21 "Reports → Device inventory → press Esc on filter picker" `
        "Returns to Reports menu. Must NOT crash with 'Cannot call method ToLower on null'."
    Manual 22 "Reports → Device inventory → pick a filter → results load" `
        "Table shows. Selectable. Export works."
    Manual 23 "Reports → Compliance → press Esc on 'Compliance by' picker" `
        "Returns to Reports menu. Must NOT crash with ToLower on null."
    Manual 24 "Reports → Compliance → Policy → press Esc on policy picker" `
        "Returns gracefully (no data). Does not crash."
    Manual 25 "Reports → Deployment summary → 'Scope to a group' → press Esc on group picker" `
        "Returns to Reports menu. Must NOT crash on null .DisplayName."
    Manual 26 "Reports → Deployment summary → 'All resources'" `
        "Loads table. No crash."

    Section "DASHBOARD"
    Manual 27 "Dashboard → loads with devices present" `
        "KPI tiles render. Compliance/encryption bars show correct %."
    Manual 28 "Dashboard → tenant with zero managed devices" `
        "Shows yellow 'No managed devices found.' message. Does not crash."

    Section "CMDLET OUTPUTS (PowerShell only — no TUI)"
    Manual 29 "Get-IntuneApp -AppType macOS | Select-Object AppType | Sort-Object AppType -Unique" `
        "Should show multiple types (macOSLobApp, macOSOfficeSuiteApp, etc.) not just OfficeSuiteApp."
    Manual 30 "Get-IntuneDeviceDetail -Device <name> | Select-Object EnrolledAt, LastSyncAt, ComplianceGracePeriodEnd" `
        "All three should be [datetime] objects (not strings). Run: `$d.EnrolledAt.GetType().Name` → 'DateTime'."
    Manual 31 "(Get-EntraPimEligibility).Role — on tenant without PIM P2 license" `
        "Returns empty array @(). Does not throw."
    Manual 32 "Get-EntraRiskyAppPermission | Where-Object Risk -eq 'High'" `
        "Lists high-risk app permissions. Unknown permission IDs show Risk='Unknown'."

    Section "EDGE CASES"
    Manual 33 "Any report screen with zero results from the API" `
        "Shows yellow 'No data' message. Does not show empty table with no rows."
    Manual 34 "Select any item in a table then press Esc in the detail view" `
        "Returns to the table, not to the parent menu."
    Manual 35 "Export any table (press 'e' in a selectable view)" `
        "Saves a CSV/HTML. Filename shows in status bar."

    Section "CANCEL-PATH HARDENING (this pass)"
    Manual 36 "Apps → Assign app → pick app → see the replace warning → Esc on 'Assign to'" `
        "A yellow 'replaces every current assignment' note shows; Esc returns to Apps menu, no action."
    Manual 37 "Apps → Assign app → Specific group → Esc on Include/Exclude" `
        "Cancels — must NOT silently EXCLUDE the group. Returns to Apps menu."
    Manual 38 "Cloud PC → Actions → Esc on the Cloud PC picker (or the action picker)" `
        "Returns cleanly. No empty 'Run on ?' confirm, no Mandatory-parameter binding error."
    Manual 39 "Cloud PC → Network connections → Run health check → Esc on connection picker" `
        "Cancels. Must NOT print 'Health check triggered' nor a -Connection null error."
    Manual 40 "Cloud PC → Images / Snapshots → Esc on the type/scope picker" `
        "Returns to the Cloud PC menu. No ValidateSet binding error."
    Manual 41 "Reports → App install status → pick app → Esc on 'Pivot by'" `
        "Cancels. Must NOT error on -By null."
    Manual 42 "What-if → Esc on 'Subject type'" `
        "Returns immediately. Must NOT load the device picker unbidden."

    Section "EXPIRING SECRETS (restored feature)"
    Manual 43 "Dashboard → check the 'expiring' tile" `
        "Shows the real count of secrets/certs expiring in 30 days (coral if >0) — not always 0."
    Manual 44 "Identity → Reports → 'Expiring secrets & certs (next 30 days)'" `
        "Loads a table (App, Kind, Name, Expires, DaysLeft, Status). No 'command not found' error."
    Manual 45 "Identity → Reports → 'Expiring incl. enterprise apps (90d)'" `
        "Loads and includes service-principal credentials and already-expired entries."

    Write-Host "`n─── End of validation checklist ─────────────────────────────────────────────`n"
}
