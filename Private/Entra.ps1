# Entra (Azure AD) identity helpers — id resolution with correct OData quoting and
# shared projections used by the Entra user/group cmdlets. All resolvers accept a
# GUID directly or resolve a friendly value (UPN / display name) to an object id.

function Resolve-EntraUserId {
    # UPN or object id → user object id.
    param([Parameter(Mandatory)][string]$User)
    if (Test-IaGuid $User) { return $User }
    # A UPN works directly as a key segment.
    try {
        $u = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "users/$([uri]::EscapeDataString($User))?`$select=id")
        if ($u.id) { return $u.id }
    } catch { }
    # Fall back to an EXACT match across UPN / mail / display name. We deliberately do
    # NOT prefix-match here: this id feeds privileged writes (disable, reset password,
    # role assignment), and silently resolving "rob" to "robert@…" would hit the wrong
    # person. Get-EntraUser -Filter is the place for prefix/contains searches.
    $odv = $User.Replace("'", "''")
    $f   = "userPrincipalName eq '$odv' or mail eq '$odv' or displayName eq '$odv'"
    $res = @(Get-IaCollection (Resolve-IaUri -Path "users?`$filter=$([uri]::EscapeDataString($f))&`$select=id,userPrincipalName&`$top=5"))
    if ($res.Count -eq 1) { return $res[0].id }
    if ($res.Count -gt 1) { throw "Multiple users match '$User'. Use the exact UPN or object id." }
    throw "No Entra user found matching '$User' (use the exact UPN, mail, display name, or object id)."
}

function Resolve-EntraGroupId {
    # Display name or object id → group object id.
    param([Parameter(Mandatory)][string]$Group)
    if (Test-IaGuid $Group) { return $Group }
    # Escape the whole filter for the URL — a group named "Sales & Eng" would otherwise
    # let the '&' start a new query parameter and silently truncate the filter, hitting
    # the wrong group on the destructive write paths that key off this resolver.
    $f   = "displayName eq '$($Group.Replace("'", "''"))'"
    $res = @(Get-IaCollection (Resolve-IaUri -Path "groups?`$filter=$([uri]::EscapeDataString($f))&`$select=id,displayName&`$top=5"))
    if ($res.Count -eq 1) { return $res[0].id }
    if ($res.Count -gt 1) { throw "Multiple groups named '$Group'. Use the object id." }
    throw "No Entra group found matching '$Group'."
}

function ConvertTo-IaEntraUser {
    # Normalize a Graph user object to JustGraphIT's user shape.
    param($u)
    [pscustomobject][ordered]@{
        DisplayName   = $u.displayName
        UPN           = $u.userPrincipalName
        Mail          = $u.mail
        JobTitle      = $u.jobTitle
        Department    = $u.department
        Enabled       = $u.accountEnabled
        Type          = $u.userType
        UsageLocation = $u.usageLocation
        Office        = $u.officeLocation
        Mobile        = $u.mobilePhone
        Created       = $u.createdDateTime
        Synced        = [bool]$u.onPremisesSyncEnabled
        Id            = $u.id
    }
}

function New-IaTempPassword {
    # A reasonable random temporary password (mixed case, digits, symbols).
    param([int]$Length = 16)
    $pool = @((65..90) + (97..122) + (48..57) + (33, 35, 37, 64, 38, 42))
    -join (1..$Length | ForEach-Object { [char]($pool | Get-Random) })
}

function Resolve-EntraDirectoryObjectRef {
    # The @odata.id binding used when POSTing a directory member/owner.
    param([string]$Id)
    "https://graph.microsoft.com/beta/directoryObjects/$Id"
}

function Get-IaGraphReportCsv {
    # Microsoft 365 usage reports (reports/get*) return CSV, not JSON, so they can't
    # go through Invoke-IaRequest (which forces OutputType=PSObject). Fetch the raw
    # response and parse it. Logged to the Graph-call log like everything else.
    param([Parameter(Mandatory)][string]$Path)
    $uri = Resolve-IaUri -Path $Path
    $sw  = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $resp   = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType HttpResponseMessage -ErrorAction Stop
        $text   = $resp.Content.ReadAsStringAsync().Result
        $status = try { [int]$resp.StatusCode } catch { 200 }
        if ([string]::IsNullOrWhiteSpace($text)) { Add-IaCall -Method GET -Uri $uri -Status $status -Ms $sw.Elapsed.TotalMilliseconds -Count 0; return @() }
        $text = $text.TrimStart([char]0xFEFF)   # strip UTF-8 BOM
        $rows = @($text | ConvertFrom-Csv)
        Add-IaCall -Method GET -Uri $uri -Status $status -Ms $sw.Elapsed.TotalMilliseconds -Count $rows.Count
        return $rows
    } catch {
        Add-IaCall -Method GET -Uri $uri -Status 0 -Ms $sw.Elapsed.TotalMilliseconds -Count 0 -ErrorText $_.Exception.Message
        throw
    }
}

function ConvertTo-IaGB { param($Bytes) if ($Bytes) { [math]::Round([double]$Bytes / 1GB, 2) } else { 0 } }

# Well-known appId of the Microsoft Graph service principal — used to enumerate
# every app that holds a Graph application permission (tenant-wide consent audit).
$script:IaGraphAppId = '00000003-0000-0000-c000-000000000000'

# Application (and a couple delegated) permissions that grant broad tenant power.
# Holding one of these app-only roles effectively makes a service principal an admin,
# so the consent reports flag them as High risk.
$script:IaHighRiskPerms = @(
    'Directory.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'Application.ReadWrite.All',
    'Application.ReadWrite.OwnedBy', 'AppRoleAssignment.ReadWrite.All', 'Group.ReadWrite.All',
    'GroupMember.ReadWrite.All', 'User.ReadWrite.All', 'Device.ReadWrite.All',
    'Mail.ReadWrite', 'Mail.Send', 'MailboxSettings.ReadWrite', 'Files.ReadWrite.All',
    'Sites.FullControl.All', 'Sites.ReadWrite.All', 'full_access_as_app',
    'PrivilegedAccess.ReadWrite.AzureAD', 'PrivilegedAccess.ReadWrite.AzureADGroup',
    'Policy.ReadWrite.ConditionalAccess', 'DeviceManagementConfiguration.ReadWrite.All',
    'DeviceManagementManagedDevices.ReadWrite.All', 'DeviceManagementRBAC.ReadWrite.All',
    'UserAuthenticationMethod.ReadWrite.All', 'IdentityRiskyUser.ReadWrite.All',
    'Directory.AccessAsUser.All',
    # consent-grant / policy escalation — an app that can grant itself consent
    'DelegatedPermissionGrant.ReadWrite.All', 'Policy.ReadWrite.PermissionGrant',
    # federation / domain takeover (golden-SAML class)
    'Domain.ReadWrite.All',
    # privileged-role assignment
    'RoleManagement.ReadWrite.Exchange', 'RoleEligibilitySchedule.ReadWrite.Directory',
    'RoleAssignmentSchedule.ReadWrite.Directory', 'RoleManagementPolicy.ReadWrite.Directory',
    # account / identity manipulation
    'Synchronization.ReadWrite.All', 'User.EnableDisableAccount.All', 'User.ManageIdentities.All',
    'User-PasswordProfile.ReadWrite.All'
)

function Test-EntraHighRiskPermission {
    # True if a permission (by name) is in the broad-power set above.
    param([string]$Name)
    [bool]($Name -and ($script:IaHighRiskPerms -contains $Name))
}

function Resolve-EntraServicePrincipalId {
    # Enterprise-app display name, appId (client id) or SP object id → SP object id.
    param([Parameter(Mandatory)][string]$App)
    if (Test-IaGuid $App) {
        # A GUID is ambiguous: try it as the SP object id, then as an appId.
        try { $sp = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "servicePrincipals/${App}?`$select=id"); if ($sp.id) { return $sp.id } } catch { }
        $byApp = @(Get-IaCollection (Resolve-IaUri -Path "servicePrincipals?`$filter=appId eq '$App'&`$select=id"))
        if ($byApp.Count -ge 1) { return $byApp[0].id }
        return $App
    }
    $f   = "displayName eq '$($App.Replace("'", "''"))'"
    $res = @(Get-IaCollection (Resolve-IaUri -Path "servicePrincipals?`$filter=$([uri]::EscapeDataString($f))&`$select=id,displayName&`$top=5"))
    if ($res.Count -eq 1) { return $res[0].id }
    if ($res.Count -gt 1) { throw "Multiple service principals named '$App'. Use the appId or object id." }
    throw "No enterprise app / service principal found matching '$App'."
}

function Get-EntraResourceSp {
    # Fetch (and cache) a resource service principal so its appRoles can map an
    # appRoleId GUID back to a friendly permission name. Cache is per report run.
    param([string]$Id, [hashtable]$Cache)
    if (-not $Id) { return $null }
    if ($Cache.ContainsKey($Id)) { return $Cache[$Id] }
    $sp = try { Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "servicePrincipals/${Id}?`$select=id,displayName,appId,appRoles,oauth2PermissionScopes") } catch { $null }
    $Cache[$Id] = $sp
    $sp
}

function Get-EntraAppRoleMap {
    # appRoleId (GUID) → permission name, for one resource service principal.
    param($ResourceSp)
    $map = @{}
    if ($ResourceSp) { foreach ($r in @($ResourceSp.appRoles)) { if ($r.id) { $map[[string]$r.id] = $r.value } } }
    $map
}
