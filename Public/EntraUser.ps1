function Get-EntraUser {
    <#
    .SYNOPSIS
        Find / list Entra (Azure AD) users and report their properties. Beta Graph.
    .DESCRIPTION
        No -User → list users (optionally -Filter). -User → one user. -Detailed pulls
        the full property set plus resolved licenses, manager and group count. -Raw
        returns the untouched Graph object (every default property) for "all fields"
        reporting. Endpoint: GET /beta/users.
    .PARAMETER User
        UPN or object id of a single user.
    .PARAMETER Filter
        OData $filter for the list form, e.g. "accountEnabled eq false".
    .PARAMETER Top
        Cap the list (default 100).
    .PARAMETER Detailed
        For a single user, enrich with licenses (SKU names), manager and group count.
    .PARAMETER Raw
        Return the raw Graph user object (all default properties).
    .OUTPUTS
        PSCustomObject (curated), the raw object (-Raw), or an enriched object (-Detailed).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$User,
        [string]$Filter,
        [int]$Top = 100,
        [switch]$Detailed,
        [switch]$Raw
    )
    $select = 'id,displayName,userPrincipalName,mail,jobTitle,department,companyName,' +
              'accountEnabled,userType,usageLocation,country,city,officeLocation,' +
              'mobilePhone,businessPhones,givenName,surname,employeeId,employeeType,' +
              'createdDateTime,creationType,onPremisesSyncEnabled,onPremisesSamAccountName,' +
              'lastPasswordChangeDateTime,passwordPolicies,assignedLicenses,proxyAddresses,otherMails'

    if (-not $User) {
        $q = "users?`$select=$select&`$top=$Top"
        if ($Filter) { $q += "&`$filter=$([uri]::EscapeDataString($Filter))" }
        return @(Get-IaCollection (Resolve-IaUri -Path $q) | ForEach-Object { ConvertTo-IaEntraUser $_ })
    }

    $id  = Resolve-EntraUserId -User $User
    $obj = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "users/${id}?`$select=$select")
    if ($Raw) { return $obj }
    if (-not $Detailed) { return (ConvertTo-IaEntraUser $obj) }

    $lic = @()
    try { $lic = @(Get-IaCollection (Resolve-IaUri -Path "users/$id/licenseDetails?`$select=skuPartNumber,skuId") | ForEach-Object { $_.skuPartNumber }) } catch { }
    $mgr = $null
    try { $mgr = (Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "users/$id/manager?`$select=displayName,userPrincipalName")).userPrincipalName } catch { }
    $grpCount = $null
    try { $grpCount = (Get-IaCount "users/$id/transitiveMemberOf/microsoft.graph.group/`$count") } catch { }

    $base = ConvertTo-IaEntraUser $obj
    $base | Add-Member -NotePropertyName Licenses    -NotePropertyValue ($lic -join ', ') -Force
    $base | Add-Member -NotePropertyName Manager     -NotePropertyValue $mgr               -Force
    $base | Add-Member -NotePropertyName GroupCount  -NotePropertyValue $grpCount          -Force
    $base
}

function Set-EntraUser {
    <#
    .SYNOPSIS
        Update an Entra user's properties (incl. enable/disable). Beta Graph PATCH /users.
    .DESCRIPTION
        PATCHes /beta/users/{id} with only the supplied properties. Use -AccountEnabled
        to enable ($true) or disable ($false) the account.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$User,
        [string]$DisplayName, [string]$JobTitle, [string]$Department, [string]$CompanyName,
        [string]$UsageLocation, [string]$OfficeLocation, [string]$MobilePhone,
        [string]$EmployeeId, [string]$EmployeeType, [string]$ManagerUser,
        [string]$GivenName, [string]$Surname, [string]$PreferredLanguage,
        [string]$StreetAddress, [string]$City, [string]$State, [string]$Country, [string]$PostalCode,
        [Nullable[bool]]$AccountEnabled
    )
    $id   = Resolve-EntraUserId -User $User
    $body = [ordered]@{}
    foreach ($p in 'DisplayName', 'JobTitle', 'Department', 'CompanyName', 'UsageLocation', 'OfficeLocation',
        'MobilePhone', 'EmployeeId', 'EmployeeType', 'GivenName', 'Surname', 'PreferredLanguage',
        'StreetAddress', 'City', 'State', 'Country', 'PostalCode') {
        if ($PSBoundParameters.ContainsKey($p)) { $body[[char]::ToLower($p[0]) + $p.Substring(1)] = $PSBoundParameters[$p] }
    }
    if ($PSBoundParameters.ContainsKey('AccountEnabled')) { $body['accountEnabled'] = [bool]$AccountEnabled }

    if ($body.Count -and $PSCmdlet.ShouldProcess($User, 'Set-EntraUser')) {
        Invoke-IaRequest -Method PATCH -Uri (Resolve-IaUri -Path "users/$id") -Body $body | Out-Null
    }
    if ($PSBoundParameters.ContainsKey('ManagerUser') -and $PSCmdlet.ShouldProcess($User, "Set manager → $ManagerUser")) {
        $mid = Resolve-EntraUserId -User $ManagerUser
        Invoke-IaRequest -Method PUT -Uri (Resolve-IaUri -Path "users/$id/manager/`$ref") -Body @{ '@odata.id' = (Resolve-EntraDirectoryObjectRef $mid) } | Out-Null
    }
    [pscustomobject]@{ User = $User; Updated = (@($body.Keys) + @(if ($PSBoundParameters.ContainsKey('ManagerUser')) { 'manager' })) -join ', ' }
}

function Reset-EntraUserPassword {
    <#
    .SYNOPSIS
        Reset a user's password (PATCH /beta/users/{id} passwordProfile).
    .DESCRIPTION
        Generates a strong temporary password (or uses -Password) and, by default,
        forces a change at next sign-in. Returns the temporary password.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$User,
        [string]$Password,
        [switch]$NoForceChange
    )
    $id = Resolve-EntraUserId -User $User
    if (-not $Password) { $Password = New-IaTempPassword }
    $body = @{ passwordProfile = @{ password = $Password; forceChangePasswordNextSignIn = (-not $NoForceChange) } }
    if ($PSCmdlet.ShouldProcess($User, 'Reset password')) {
        Invoke-IaRequest -Method PATCH -Uri (Resolve-IaUri -Path "users/$id") -Body $body | Out-Null
        [pscustomobject]@{ User = $User; TempPassword = $Password; MustChangeAtSignIn = (-not $NoForceChange) }
    }
}

function Revoke-EntraUserSession {
    <#
    .SYNOPSIS
        Revoke all of a user's refresh tokens / sign-in sessions (sign out everywhere).
        POST /beta/users/{id}/revokeSignInSessions.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, Position = 0)][string]$User)
    $id = Resolve-EntraUserId -User $User
    if ($PSCmdlet.ShouldProcess($User, 'Revoke all sign-in sessions')) {
        Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "users/$id/revokeSignInSessions") -Body @{} | Out-Null
        [pscustomobject]@{ User = $User; SessionsRevoked = $true }
    }
}

function Add-EntraUserToGroup {
    <#
    .SYNOPSIS
        Add a user to a group. POST /beta/groups/{id}/members/$ref.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, Position = 0)][string]$User, [Parameter(Mandatory, Position = 1)][string]$Group)
    $uid = Resolve-EntraUserId -User $User; $gid = Resolve-EntraGroupId -Group $Group
    if ($PSCmdlet.ShouldProcess("$User → $Group", 'Add to group')) {
        Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "groups/$gid/members/`$ref") -Body @{ '@odata.id' = (Resolve-EntraDirectoryObjectRef $uid) } | Out-Null
        [pscustomobject]@{ User = $User; Group = $Group; Added = $true }
    }
}

function Remove-EntraUserFromGroup {
    <#
    .SYNOPSIS
        Remove a user from a group. DELETE /beta/groups/{id}/members/{uid}/$ref.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, Position = 0)][string]$User, [Parameter(Mandatory, Position = 1)][string]$Group)
    $uid = Resolve-EntraUserId -User $User; $gid = Resolve-EntraGroupId -Group $Group
    if ($PSCmdlet.ShouldProcess("$User → $Group", 'Remove from group')) {
        Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri -Path "groups/$gid/members/$uid/`$ref") | Out-Null
        [pscustomobject]@{ User = $User; Group = $Group; Removed = $true }
    }
}

function Set-EntraUserLicense {
    <#
    .SYNOPSIS
        Assign and/or remove license SKUs for a user. POST /beta/users/{id}/assignLicense.
    .DESCRIPTION
        -AddSku / -RemoveSku take SKU part numbers (e.g. ENTERPRISEPACK) or skuIds;
        they're resolved against /beta/subscribedSkus. The user must have a usageLocation
        set (Set-EntraUser -UsageLocation) or Graph rejects the assignment.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, Position = 0)][string]$User, [string[]]$AddSku, [string[]]$RemoveSku)
    $id   = Resolve-EntraUserId -User $User
    $add  = @(Resolve-EntraSkuId -Sku $AddSku | ForEach-Object { @{ skuId = $_ } })
    $rem  = @(Resolve-EntraSkuId -Sku $RemoveSku)
    $body = @{ addLicenses = $add; removeLicenses = $rem }
    if ($PSCmdlet.ShouldProcess($User, "License +[$($AddSku -join ',')] -[$($RemoveSku -join ',')]")) {
        Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "users/$id/assignLicense") -Body $body | Out-Null
        [pscustomobject]@{ User = $User; Added = ($AddSku -join ', '); Removed = ($RemoveSku -join ', ') }
    }
}

function Get-EntraUserAuthMethod {
    <#
    .SYNOPSIS
        List a user's registered authentication (MFA) methods.
        GET /beta/users/{id}/authentication/methods.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$User)
    $id = Resolve-EntraUserId -User $User
    @(Get-IaCollection (Resolve-IaUri -Path "users/$id/authentication/methods") | ForEach-Object {
        [pscustomobject][ordered]@{
            Method = (Get-IaAuthMethodName $_.'@odata.type')
            Detail = ($_.phoneNumber ?? $_.emailAddress ?? $_.displayName ?? $_.model ?? '')
            Id     = $_.id
        }
    })
}

function Reset-EntraUserMfa {
    <#
    .SYNOPSIS
        Reset a user's MFA — delete every removable strong auth method so they must
        re-register. DELETE /beta/users/{id}/authentication/{methodType}/{id}.
    .DESCRIPTION
        Removes phone, email, Authenticator, FIDO2/passkey, software OATH, Temporary
        Access Pass and Windows Hello methods. The password method is never touched.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory, Position = 0)][string]$User)
    $id      = Resolve-EntraUserId -User $User
    $methods = @(Get-IaCollection (Resolve-IaUri -Path "users/$id/authentication/methods"))
    $seg     = @{
        '#microsoft.graph.phoneAuthenticationMethod'                   = 'phoneMethods'
        '#microsoft.graph.emailAuthenticationMethod'                   = 'emailMethods'
        '#microsoft.graph.fido2AuthenticationMethod'                   = 'fido2Methods'
        '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'  = 'microsoftAuthenticatorMethods'
        '#microsoft.graph.softwareOathAuthenticationMethod'            = 'softwareOathMethods'
        '#microsoft.graph.temporaryAccessPassAuthenticationMethod'     = 'temporaryAccessPassMethods'
        '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod' = 'windowsHelloForBusinessMethods'
    }
    $removed = 0; $errors = @()
    if ($PSCmdlet.ShouldProcess($User, 'Reset MFA — delete strong auth methods')) {
        foreach ($m in $methods) {
            $s = $seg[[string]$m.'@odata.type']
            if (-not $s) { continue }   # passwordAuthenticationMethod etc. — leave alone
            try { Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri -Path "users/$id/authentication/$s/$($m.id)") | Out-Null; $removed++ }
            catch { $errors += "$s/$($m.id): $($_.Exception.Message)" }
        }
        [pscustomobject]@{ User = $User; MethodsRemoved = $removed; Errors = ($errors -join '; ') }
    }
}

function New-EntraUserTempAccessPass {
    <#
    .SYNOPSIS
        Issue a Temporary Access Pass so the user can register a passkey/MFA method.
        POST /beta/users/{id}/authentication/temporaryAccessPassMethods.
    .DESCRIPTION
        A TAP is the admin-grantable, time-boxed credential a user redeems to enroll a
        passkey (FIDO2) or Authenticator. Returns the pass — copy it to the user.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$User,
        [int]$LifetimeMinutes = 60,
        [switch]$OneTime
    )
    $id   = Resolve-EntraUserId -User $User
    $body = @{ lifetimeInMinutes = $LifetimeMinutes; isUsableOnce = [bool]$OneTime }
    if ($PSCmdlet.ShouldProcess($User, 'Issue Temporary Access Pass')) {
        $r = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "users/$id/authentication/temporaryAccessPassMethods") -Body $body
        [pscustomobject]@{ User = $User; TemporaryAccessPass = $r.temporaryAccessPass; LifetimeMinutes = $r.lifetimeInMinutes; OneTime = $r.isUsableOnce; StartsAt = $r.startDateTime }
    }
}

function New-EntraUser {
    <#
    .SYNOPSIS
        Create an Entra member user. Beta POST /beta/users.
    .DESCRIPTION
        Creates an enabled user with a temporary password (returned; the user must
        change it at next sign-in). The UPN's domain must be a verified tenant domain.
    .OUTPUTS
        PSCustomObject: User, DisplayName, Id, TempPassword.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$UserPrincipalName,
        [Parameter(Mandatory, Position = 1)][string]$DisplayName,
        [string]$MailNickname,
        [string]$Password,
        [string]$JobTitle, [string]$Department, [string]$UsageLocation,
        [switch]$NoForceChange
    )
    if (-not $MailNickname) { $MailNickname = ($UserPrincipalName -split '@')[0] }
    if (-not $Password)     { $Password = New-IaTempPassword }
    $body = [ordered]@{
        accountEnabled    = $true
        displayName       = $DisplayName
        mailNickname      = $MailNickname
        userPrincipalName = $UserPrincipalName
        passwordProfile   = @{ password = $Password; forceChangePasswordNextSignIn = (-not $NoForceChange) }
    }
    if ($JobTitle)      { $body.jobTitle = $JobTitle }
    if ($Department)    { $body.department = $Department }
    if ($UsageLocation) { $body.usageLocation = $UsageLocation }
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Create user')) {
        $u = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "users") -Body $body
        [pscustomobject]@{ User = $u.userPrincipalName; DisplayName = $u.displayName; Id = $u.id; TempPassword = $Password }
    }
}

function Get-EntraUserManager {
    <#
    .SYNOPSIS
        Show a user's manager. Beta GET /beta/users/{id}/manager.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$User)
    $id = Resolve-EntraUserId -User $User
    $m  = try { Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "users/${id}/manager?`$select=id,displayName,userPrincipalName,mail,jobTitle") } catch { $null }
    if (-not $m) { Write-Warning "'$User' has no manager assigned."; return }
    [pscustomobject]@{ User = $User; Manager = $m.displayName; ManagerUPN = $m.userPrincipalName; ManagerTitle = $m.jobTitle; Id = $m.id }
}

function Remove-EntraUserManager {
    <#
    .SYNOPSIS
        Clear a user's manager. Beta DELETE /beta/users/{id}/manager/$ref.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, Position = 0)][string]$User)
    $id = Resolve-EntraUserId -User $User
    if ($PSCmdlet.ShouldProcess($User, 'Clear manager')) {
        Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri -Path "users/$id/manager/`$ref") | Out-Null
        [pscustomobject]@{ User = $User; ManagerCleared = $true }
    }
}

function Get-EntraInactiveUser {
    <#
    .SYNOPSIS
        Users who haven't signed in for N days (the "stale accounts" report).
        Beta GET /beta/users?$select=…,signInActivity.
    .DESCRIPTION
        Reads each member account's last interactive sign-in (signInActivity, needs
        AuditLog.Read.All) and keeps those idle for at least -Days (default 90), plus
        accounts that have never signed in. Sorted by most-stale first. -IncludeDisabled
        also lists disabled accounts; by default only enabled ones are shown (the ones
        worth cleaning up). -Raw returns the untouched user objects.
    .PARAMETER Days
        Inactivity threshold in days (default 90).
    .OUTPUTS
        PSCustomObject: User, DisplayName, LastSignIn, DaysInactive, Enabled,
        Department, Created, Id.
    #>
    [CmdletBinding()]
    param([int]$Days = 90, [switch]$IncludeDisabled, [ValidateRange(1, 999)][int]$Top = 999, [switch]$Raw)
    $select = 'id,displayName,userPrincipalName,accountEnabled,userType,department,createdDateTime,signInActivity'
    $users  = @(Get-IaCollection (Resolve-IaUri -Path "users?`$select=$select&`$top=$Top"))
    if ($Raw) { return $users }
    # signInActivity needs AuditLog.Read.All; without it Graph returns it null for
    # everyone and every account looks "never signed in" — warn rather than mislead.
    if ($users.Count -and -not @($users | Where-Object { $_.signInActivity.lastSignInDateTime })) {
        Write-Warning 'No sign-in data returned for any user. Consent AuditLog.Read.All (or every account is genuinely dormant); results may over-report inactivity.'
    }
    $now = (Get-Date).ToUniversalTime()
    @($users | ForEach-Object {
        if (-not $IncludeDisabled -and -not $_.accountEnabled) { return }
        $last = $_.signInActivity.lastSignInDateTime
        $lastDt = ConvertTo-IaSafeDateTime $last
        $idle = if ($lastDt) { [int][math]::Floor(($now - $lastDt.ToUniversalTime()).TotalDays) } else { [int]::MaxValue }
        if ($idle -lt $Days) { return }
        [pscustomobject][ordered]@{
            User         = $_.userPrincipalName
            DisplayName  = $_.displayName
            LastSignIn   = if ($lastDt) { $lastDt.ToString('yyyy-MM-dd') } else { 'never' }
            DaysInactive = if ($idle -eq [int]::MaxValue) { 'never' } else { $idle }
            Enabled      = [bool]$_.accountEnabled
            Department   = $_.department
            Created      = $_.createdDateTime
            Id           = $_.id
        }
    } | Sort-Object @{ Expression = { if ($_.DaysInactive -eq 'never') { [int]::MaxValue } else { [int]$_.DaysInactive } } } -Descending)
}

function Get-EntraGuestUser {
    <#
    .SYNOPSIS
        Guest (B2B) accounts with invitation state and last sign-in. Beta GET
        /beta/users filtered to userType eq 'Guest'.
    .DESCRIPTION
        Surfaces external collaborators — when they were invited, whether they've
        accepted (externalUserState), and their last sign-in — for access reviews.
        -Raw returns the untouched user objects.
    #>
    [CmdletBinding()]
    param([ValidateRange(1, 999)][int]$Top = 999, [switch]$Raw)
    $select = 'id,displayName,userPrincipalName,mail,accountEnabled,createdDateTime,' +
              'externalUserState,externalUserStateChangeDateTime,creationType,signInActivity'
    $f     = "userType eq 'Guest'"
    $users = @(Get-IaCollection (Resolve-IaUri -Path "users?`$filter=$([uri]::EscapeDataString($f))&`$select=$select&`$top=$Top"))
    if ($Raw) { return $users }
    @($users | ForEach-Object {
        $last = $_.signInActivity.lastSignInDateTime
        $lastDt = ConvertTo-IaSafeDateTime $last
        [pscustomobject][ordered]@{
            DisplayName  = $_.displayName
            Mail         = $_.mail
            State        = $_.externalUserState
            Enabled      = [bool]$_.accountEnabled
            LastSignIn   = if ($lastDt) { $lastDt.ToString('yyyy-MM-dd') } else { 'never' }
            Invited      = $_.createdDateTime
            UPN          = $_.userPrincipalName
            Id           = $_.id
        }
    } | Sort-Object State, DisplayName)
}
