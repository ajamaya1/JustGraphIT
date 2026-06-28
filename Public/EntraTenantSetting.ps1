# Entra ID > Settings / Properties blade — tenant-wide identity toggles: the default
# user-role permissions (can users create apps / groups / tenants, read other users),
# guest-invite policy, SSPR enablement, and the Security Defaults switch. All beta.

function Get-EntraAuthorizationPolicy {
    <#
    .SYNOPSIS
        Tenant authorization policy — what the default user role can do, guest invites,
        SSPR. Beta GET /beta/policies/authorizationPolicy.
    .DESCRIPTION
        The "User settings" / "External collaboration" knobs: whether ordinary users can
        register apps, create security groups, create tenants, read other users' profiles,
        and who can invite guests.
    #>
    [CmdletBinding()]
    param([switch]$Raw)
    $p = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "policies/authorizationPolicy")
    if ($Raw) { return $p }
    $d = $p.defaultUserRolePermissions
    [pscustomobject][ordered]@{
        AllowInvitesFrom             = $p.allowInvitesFrom
        AllowedToUseSSPR             = $p.allowedToUseSSPR
        UsersCanCreateApps           = $d.allowedToCreateApps
        UsersCanCreateSecurityGroups = $d.allowedToCreateSecurityGroups
        UsersCanCreateTenants        = $d.allowedToCreateTenants
        UsersCanReadOtherUsers       = $d.allowedToReadOtherUsers
        UsersCanReadBitlockerKeys    = $d.allowedToReadBitlockerKeysForOwnedDevice
        BlockMsolPowerShell          = $p.blockMsolPowerShell
        GuestUserRoleId              = $p.guestUserRoleId
    }
}

function Set-EntraAuthorizationPolicy {
    <#
    .SYNOPSIS
        Update tenant default-user-role permissions / guest invites / SSPR. Beta PATCH
        /beta/policies/authorizationPolicy/authorizationPolicy.
    .DESCRIPTION
        Read-modify-writes defaultUserRolePermissions so changing one toggle never resets
        the others. Locking down -UsersCanCreateApps / -UsersCanCreateTenants is a common
        tenant-hardening step.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [System.Nullable[bool]]$UsersCanCreateApps,
        [System.Nullable[bool]]$UsersCanCreateSecurityGroups,
        [System.Nullable[bool]]$UsersCanCreateTenants,
        [System.Nullable[bool]]$UsersCanReadOtherUsers,
        [System.Nullable[bool]]$UsersCanReadBitlockerKeys,
        [System.Nullable[bool]]$AllowedToUseSSPR,
        [ValidateSet('none', 'adminsAndGuestInviters', 'adminsGuestInvitersAndAllMembers', 'everyone')][string]$AllowInvitesFrom
    )
    $cur  = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "policies/authorizationPolicy")
    $c    = $cur.defaultUserRolePermissions
    $body = [ordered]@{}
    # read-modify-write the whole defaultUserRolePermissions object (PATCH replaces it)
    $durp = [ordered]@{
        allowedToCreateApps                      = [bool]$c.allowedToCreateApps
        allowedToCreateSecurityGroups            = [bool]$c.allowedToCreateSecurityGroups
        allowedToCreateTenants                   = [bool]$c.allowedToCreateTenants
        allowedToReadOtherUsers                  = [bool]$c.allowedToReadOtherUsers
        allowedToReadBitlockerKeysForOwnedDevice = [bool]$c.allowedToReadBitlockerKeysForOwnedDevice
    }
    $touched = $false
    if ($PSBoundParameters.ContainsKey('UsersCanCreateApps'))           { $durp.allowedToCreateApps = [bool]$UsersCanCreateApps; $touched = $true }
    if ($PSBoundParameters.ContainsKey('UsersCanCreateSecurityGroups')) { $durp.allowedToCreateSecurityGroups = [bool]$UsersCanCreateSecurityGroups; $touched = $true }
    if ($PSBoundParameters.ContainsKey('UsersCanCreateTenants'))        { $durp.allowedToCreateTenants = [bool]$UsersCanCreateTenants; $touched = $true }
    if ($PSBoundParameters.ContainsKey('UsersCanReadOtherUsers'))       { $durp.allowedToReadOtherUsers = [bool]$UsersCanReadOtherUsers; $touched = $true }
    if ($PSBoundParameters.ContainsKey('UsersCanReadBitlockerKeys'))    { $durp.allowedToReadBitlockerKeysForOwnedDevice = [bool]$UsersCanReadBitlockerKeys; $touched = $true }
    if ($touched) { $body.defaultUserRolePermissions = $durp }
    if ($PSBoundParameters.ContainsKey('AllowedToUseSSPR')) { $body.allowedToUseSSPR = [bool]$AllowedToUseSSPR }
    if ($PSBoundParameters.ContainsKey('AllowInvitesFrom')) { $body.allowInvitesFrom = $AllowInvitesFrom }
    if (-not $body.Count) { Write-Warning 'Nothing to update.'; return }
    if ($PSCmdlet.ShouldProcess('tenant authorization policy', "Update [$(@($body.Keys) -join ', ')]")) {
        # PATCH uses the DOUBLED segment (GET is single) — documented Graph quirk.
        Invoke-IaRequest -Method PATCH -Uri (Resolve-IaUri -Path "policies/authorizationPolicy/authorizationPolicy") -Body $body | Out-Null
        [pscustomobject]@{ Updated = (@($body.Keys) -join ', ') }
    }
}

function Get-EntraSecurityDefault {
    <#
    .SYNOPSIS
        Whether Security Defaults are enabled for the tenant. Beta GET
        /beta/policies/identitySecurityDefaultsEnforcementPolicy.
    #>
    [CmdletBinding()]
    param()
    $p = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "policies/identitySecurityDefaultsEnforcementPolicy")
    [pscustomobject][ordered]@{ Name = $p.displayName; Enabled = [bool]$p.isEnabled; Description = $p.description }
}

function Set-EntraSecurityDefault {
    <#
    .SYNOPSIS
        Turn tenant Security Defaults on or off. Beta PATCH
        /beta/policies/identitySecurityDefaultsEnforcementPolicy.
    .DESCRIPTION
        Security Defaults enforce baseline MFA. Disabling them removes that baseline —
        only do so when you have Conditional Access policies in their place.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)][bool]$Enabled)
    if ($PSCmdlet.ShouldProcess('Security Defaults', "Set isEnabled=$Enabled")) {
        Invoke-IaRequest -Method PATCH -Uri (Resolve-IaUri -Path "policies/identitySecurityDefaultsEnforcementPolicy") -Body @{ isEnabled = $Enabled } | Out-Null
        [pscustomobject]@{ SecurityDefaults = $(if ($Enabled) { 'enabled' } else { 'disabled' }) }
    }
}
