# Identity helpers — translate Graph authentication-method @odata.type values into
# the names admins recognise.

$script:IaAuthMethodName = @{
    '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'             = 'Microsoft Authenticator'
    '#microsoft.graph.passwordlessMicrosoftAuthenticatorAuthenticationMethod' = 'Authenticator (passwordless)'
    '#microsoft.graph.phoneAuthenticationMethod'                              = 'Phone (SMS / call)'
    '#microsoft.graph.fido2AuthenticationMethod'                              = 'FIDO2 security key'
    '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod'            = 'Windows Hello for Business'
    '#microsoft.graph.passwordAuthenticationMethod'                           = 'Password'
    '#microsoft.graph.emailAuthenticationMethod'                              = 'Email OTP'
    '#microsoft.graph.softwareOathAuthenticationMethod'                       = 'Software OATH token'
    '#microsoft.graph.temporaryAccessPassAuthenticationMethod'                = 'Temporary Access Pass'
    '#microsoft.graph.certificateBasedAuthenticationConfiguration'            = 'Certificate (CBA)'
    '#microsoft.graph.platformCredentialAuthenticationMethod'                 = 'Platform credential'
}

function Get-IaAuthMethodName {
    # Friendly label for an authentication-method @odata.type; falls back to a
    # de-camel-cased version of the type name.
    param([string]$ODataType)
    if ([string]::IsNullOrWhiteSpace($ODataType)) { return '(unknown)' }
    if ($script:IaAuthMethodName.ContainsKey($ODataType)) { return $script:IaAuthMethodName[$ODataType] }
    # Strip namespace + the AuthenticationMethod suffix and space out the CamelCase.
    $leaf = ($ODataType -replace '^#microsoft\.graph\.', '' -replace 'AuthenticationMethod$', '')
    ($leaf -creplace '([a-z])([A-Z])', '$1 $2').Trim()
}
