# Entra ID > Users > per-user authentication — the modern per-user MFA state (the
# replacement for the legacy Set-MsolUser -StrongAuthenticationRequirements) and
# admin-registered phone methods. All beta under /beta/users/{id}/authentication.

function Get-EntraUserMfaState {
    <#
    .SYNOPSIS
        A user's per-user MFA state. Beta GET
        /beta/users/{id}/authentication/requirements.
    .DESCRIPTION
        The modern equivalent of the legacy MSOnline per-user MFA state —
        disabled / enabled / enforced.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$User)
    $id = Resolve-EntraUserId -User $User
    $r  = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "users/$id/authentication/requirements")
    [pscustomobject]@{ User = $User; PerUserMfaState = $r.perUserMfaState }
}

function Set-EntraUserMfaState {
    <#
    .SYNOPSIS
        Set a user's per-user MFA state. Beta PATCH
        /beta/users/{id}/authentication/requirements.
    .PARAMETER State
        disabled | enabled | enforced. (Setting 'enabled' for a user who already
        registered a method auto-transitions to 'enforced'.)
    .EXAMPLE
        Set-EntraUserMfaState -User bob@x.com -State enforced
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$User,
        [Parameter(Mandatory, Position = 1)][ValidateSet('disabled', 'enabled', 'enforced')][string]$State
    )
    $id = Resolve-EntraUserId -User $User
    if ($PSCmdlet.ShouldProcess($User, "Set per-user MFA state → $State")) {
        Invoke-IaRequest -Method PATCH -Uri (Resolve-IaUri -Path "users/$id/authentication/requirements") -Body @{ perUserMfaState = $State } | Out-Null
        [pscustomobject]@{ User = $User; PerUserMfaState = $State }
    }
}

function Add-EntraUserPhoneMethod {
    <#
    .SYNOPSIS
        Register a phone authentication method for a user. Beta POST
        /beta/users/{id}/authentication/phoneMethods.
    .PARAMETER PhoneNumber
        E.164-ish format, e.g. '+1 2065551234'.
    .PARAMETER PhoneType
        mobile (default), alternateMobile, or office. A mobile must exist before an
        alternateMobile can be added.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$User,
        [Parameter(Mandatory, Position = 1)][string]$PhoneNumber,
        [ValidateSet('mobile', 'alternateMobile', 'office')][string]$PhoneType = 'mobile'
    )
    $id = Resolve-EntraUserId -User $User
    if ($PSCmdlet.ShouldProcess($User, "Add $PhoneType phone $PhoneNumber")) {
        $r = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "users/$id/authentication/phoneMethods") -Body @{ phoneNumber = $PhoneNumber; phoneType = $PhoneType }
        [pscustomobject]@{ User = $User; PhoneNumber = $PhoneNumber; PhoneType = $PhoneType; Id = $r.id }
    }
}
