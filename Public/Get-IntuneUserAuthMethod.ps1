function Get-IntuneUserAuthMethod {
    <#
    .SYNOPSIS
        The authentication (MFA) methods a user has registered.

    .DESCRIPTION
        Lists every registered authentication method for a user with a friendly name
        (Microsoft Authenticator, FIDO2 security key, Phone, Windows Hello, etc.) and a
        detail (device name / phone number / email). Pairs with Get-IntuneUserSignIn to
        answer "their MFA isn't working" — you can see whether they have a strong method
        registered at all.

        Graph (beta):
            GET /beta/users/{id}/authentication/methods
        Permission: UserAuthenticationMethod.Read.All.

    .PARAMETER User
        The user's principal name (UPN) or object id.

    .EXAMPLE
        Get-IntuneUserAuthMethod -User jdoe@contoso.com

    .OUTPUTS
        PSCustomObject: Method, Detail, Id.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$User
    )

    $enc     = [uri]::EscapeDataString($User)
    $methods = Get-IaCollection "users/$enc/authentication/methods"

    foreach ($m in $methods) {
        $detail = $m.displayName
        if (-not $detail) { $detail = $m.phoneNumber }
        if (-not $detail) { $detail = $m.emailAddress }
        if (-not $detail -and $m.phoneType) { $detail = $m.phoneType }
        [pscustomobject][ordered]@{
            Method = Get-IaAuthMethodName -ODataType "$($m.'@odata.type')"
            Detail = $detail
            Id     = $m.id
        }
    }
}
