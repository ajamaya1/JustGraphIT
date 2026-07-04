function Get-EntraMfaRegistration {
    <#
    .SYNOPSIS
        Per-user MFA registration posture — who is registered, who is actually
        MFA-capable, which methods, and which ADMINS are unprotected. Beta GET
        /beta/reports/authenticationMethods/userRegistrationDetails.

    .DESCRIPTION
        The pre-flight for any Conditional Access MFA rollout and the list every
        security review asks for. One row per user with IsMfaRegistered (has the
        user ever registered a strong method), IsMfaCapable (can they satisfy an
        MFA challenge right now — the enforceable bit), SSPR posture, the methods
        they registered, and whether the account holds an admin role.

        Requires an Entra ID P1/P2 tenant and Reports.Read.All (already in the
        module's default connect scopes).

    .PARAMETER GapsOnly
        Only users who are NOT MFA-capable — the remediation list. An account that
        registered a method but is no longer capable still counts as a gap.

    .PARAMETER AdminsOnly
        Only accounts holding an admin role. Combine with -GapsOnly for the
        "unprotected admins" fire list.

    .EXAMPLE
        Get-EntraMfaRegistration -GapsOnly | Export-Csv .\mfa-gaps.csv

        Everyone who could not satisfy an MFA challenge today.

    .EXAMPLE
        Get-EntraMfaRegistration -GapsOnly -AdminsOnly

        Admin accounts with no working MFA — fix these first.

    .OUTPUTS
        PSCustomObject: User, UPN, IsAdmin, MfaRegistered, MfaCapable,
        SsprRegistered, SsprCapable, Methods, DefaultMethod, UserType, Id.
    #>
    [CmdletBinding()]
    param(
        [switch]$GapsOnly,
        [switch]$AdminsOnly
    )

    $rows = Get-IaCollection (Resolve-IaUri 'reports/authenticationMethods/userRegistrationDetails')
    $rows = @($rows)

    $out = foreach ($u in $rows) {
        [pscustomobject][ordered]@{
            User           = $u.userDisplayName
            UPN            = $u.userPrincipalName
            IsAdmin        = [bool]$u.isAdmin
            MfaRegistered  = [bool]$u.isMfaRegistered
            MfaCapable     = [bool]$u.isMfaCapable
            SsprRegistered = [bool]$u.isSsprRegistered
            SsprCapable    = [bool]$u.isSsprCapable
            Methods        = (@($u.methodsRegistered) -join ', ')
            DefaultMethod  = $u.defaultMfaMethod
            UserType       = $u.userType
            Id             = $u.id
        }
    }
    $out = @($out)
    if ($AdminsOnly) { $out = @($out | Where-Object IsAdmin) }
    if ($GapsOnly)   { $out = @($out | Where-Object { -not $_.MfaCapable }) }
    # unprotected admins first, then unregistered before registered
    @($out | Sort-Object @{ Expression = 'IsAdmin'; Descending = $true },
                         @{ Expression = 'MfaCapable' }, UPN)
}
