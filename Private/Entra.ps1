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
    # Fall back to a prefix search across UPN / mail / display name.
    $odv = $User.Replace("'", "''")
    $f   = "startswith(userPrincipalName,'$odv') or startswith(mail,'$odv') or startswith(displayName,'$odv')"
    $res = @(Get-IaCollection (Resolve-IaUri -Path "users?`$filter=$([uri]::EscapeDataString($f))&`$select=id,userPrincipalName&`$top=5"))
    if ($res.Count -eq 1) { return $res[0].id }
    if ($res.Count -gt 1) { throw "Multiple users match '$User'. Use the exact UPN or object id." }
    throw "No Entra user found matching '$User'."
}

function Resolve-EntraGroupId {
    # Display name or object id → group object id.
    param([Parameter(Mandatory)][string]$Group)
    if (Test-IaGuid $Group) { return $Group }
    $odv = $Group.Replace("'", "''")
    $res = @(Get-IaCollection (Resolve-IaUri -Path "groups?`$filter=displayName eq '$odv'&`$select=id,displayName&`$top=5"))
    if ($res.Count -eq 1) { return $res[0].id }
    if ($res.Count -gt 1) { throw "Multiple groups named '$Group'. Use the object id." }
    throw "No Entra group found matching '$Group'."
}

function ConvertTo-IaEntraUser {
    # Normalize a Graph user object to GRAPHITE's user shape.
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
