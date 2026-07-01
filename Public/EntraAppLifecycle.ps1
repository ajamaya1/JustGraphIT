function New-EntraAppRegistration {
    <#
    .SYNOPSIS
        Create an app registration. Beta POST /beta/applications.
    .DESCRIPTION
        Registers a new application and returns its appId (client id) and object id.
        Add credentials with New-EntraAppSecret, permissions with Add-EntraAppPermission,
        and consent with Grant-EntraAdminConsent.
    .PARAMETER Name
        Display name.
    .PARAMETER SignInAudience
        Who can sign in (default AzureADMyOrg = this tenant only).
    .PARAMETER RedirectUri
        One or more redirect URIs for -Platform.
    .PARAMETER Platform
        Redirect-URI platform: Web (default), Spa or PublicClient.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [ValidateSet('AzureADMyOrg', 'AzureADMultipleOrgs', 'AzureADandPersonalMicrosoftAccount', 'PersonalMicrosoftAccount')][string]$SignInAudience = 'AzureADMyOrg',
        [string[]]$RedirectUri,
        [ValidateSet('Web', 'Spa', 'PublicClient')][string]$Platform = 'Web',
        [string]$Description
    )
    $body = [ordered]@{ displayName = $Name; signInAudience = $SignInAudience }
    if ($Description) { $body.notes = $Description }
    if ($RedirectUri) {
        $prop = @{ 'Web' = 'web'; 'Spa' = 'spa'; 'PublicClient' = 'publicClient' }[$Platform]
        $body.$prop = @{ redirectUris = @($RedirectUri) }
    }
    if ($PSCmdlet.ShouldProcess($Name, 'Create app registration')) {
        $a = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "applications") -Body $body
        [pscustomobject]@{ DisplayName = $a.displayName; AppId = $a.appId; Id = $a.id; SignInAudience = $a.signInAudience }
    }
}

function New-EntraAppSecret {
    <#
    .SYNOPSIS
        Add a client secret to an app registration. Beta POST
        /beta/applications/{id}/addPassword.
    .DESCRIPTION
        Returns the generated secret value — which Graph reveals ONLY once, on
        creation — so capture it immediately.
    .PARAMETER Months
        Lifetime in months (default 12, max 24).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$App,
        [string]$DisplayName = 'Added by JustGraphIT',
        [ValidateRange(1, 24)][int]$Months = 12
    )
    $appObj = Get-EntraApplicationObject -App $App
    $end    = (Get-Date).ToUniversalTime().AddMonths($Months).ToString('o')
    if ($PSCmdlet.ShouldProcess($appObj.displayName, "Add a client secret (expires in $Months months)")) {
        $r = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "applications/$($appObj.id)/addPassword") `
            -Body @{ passwordCredential = @{ displayName = $DisplayName; endDateTime = $end } }
        [pscustomobject]@{
            App        = $appObj.displayName
            SecretId   = $r.keyId
            Name        = $r.displayName
            Expires    = $r.endDateTime
            Secret     = $r.secretText
            Note       = 'Copy the Secret now — Graph will not show it again.'
        }
    }
}

function Add-EntraAppRedirectUri {
    <#
    .SYNOPSIS
        Add redirect URI(s) to an app registration. Beta PATCH /beta/applications/{id}.
    .PARAMETER Platform
        Web (default), Spa or PublicClient.
    .NOTES
        ConfirmImpact High: adding an attacker-controlled reply URL to a legitimate app
        is a known token-exfiltration technique, so this prompts by default.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$App,
        [Parameter(Mandatory, Position = 1)][string[]]$Uri,
        [ValidateSet('Web', 'Spa', 'PublicClient')][string]$Platform = 'Web'
    )
    $appObj = Get-EntraApplicationObject -App $App
    $prop   = @{ 'Web' = 'web'; 'Spa' = 'spa'; 'PublicClient' = 'publicClient' }[$Platform]
    $cur    = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "applications/$($appObj.id)?`$select=$prop")
    $merged = @(@($cur.$prop.redirectUris) + $Uri | Where-Object { $_ } | Select-Object -Unique)
    if ($PSCmdlet.ShouldProcess($appObj.displayName, "Add $Platform redirect URI(s): $($Uri -join ', ')")) {
        $platformPatch = [ordered]@{}
        if ($cur.$prop) { $cur.$prop.PSObject.Properties | ForEach-Object { $platformPatch[$_.Name] = $_.Value } }
        $platformPatch['redirectUris'] = $merged
        Invoke-IaRequest -Method PATCH -Uri (Resolve-IaUri -Path "applications/$($appObj.id)") -Body @{ $prop = $platformPatch } | Out-Null
        [pscustomobject]@{ App = $appObj.displayName; Platform = $Platform; RedirectUris = $merged }
    }
}

function Remove-EntraAppRedirectUri {
    <#
    .SYNOPSIS
        Remove redirect URI(s) from an app registration. Beta PATCH /beta/applications/{id}.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$App,
        [Parameter(Mandatory, Position = 1)][string[]]$Uri,
        [ValidateSet('Web', 'Spa', 'PublicClient')][string]$Platform = 'Web'
    )
    $appObj = Get-EntraApplicationObject -App $App
    $prop   = @{ 'Web' = 'web'; 'Spa' = 'spa'; 'PublicClient' = 'publicClient' }[$Platform]
    $cur    = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "applications/$($appObj.id)?`$select=$prop")
    $kept   = @(@($cur.$prop.redirectUris) | Where-Object { $Uri -notcontains $_ })
    if ($PSCmdlet.ShouldProcess($appObj.displayName, "Remove $Platform redirect URI(s)")) {
        $platformPatch = [ordered]@{}
        if ($cur.$prop) { $cur.$prop.PSObject.Properties | ForEach-Object { $platformPatch[$_.Name] = $_.Value } }
        $platformPatch['redirectUris'] = $kept
        Invoke-IaRequest -Method PATCH -Uri (Resolve-IaUri -Path "applications/$($appObj.id)") -Body @{ $prop = $platformPatch } | Out-Null
        [pscustomobject]@{ App = $appObj.displayName; Platform = $Platform; RedirectUris = $kept }
    }
}

function Get-EntraAppOwner {
    <#
    .SYNOPSIS
        List an app registration's owners. Beta GET /beta/applications/{id}/owners.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$App)
    $appObj = Get-EntraApplicationObject -App $App
    @(Get-IaCollection (Resolve-IaUri -Path "applications/$($appObj.id)/owners?`$select=id,displayName,userPrincipalName,mail") | ForEach-Object {
        [pscustomobject][ordered]@{ Name = $_.displayName; UPN = $_.userPrincipalName; Mail = $_.mail; Id = $_.id }
    })
}

function Add-EntraAppOwner {
    <#
    .SYNOPSIS
        Add an owner to an app registration. Beta POST /beta/applications/{id}/owners/$ref.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, Position = 0)][string]$App, [Parameter(Mandatory, Position = 1)][string]$Owner)
    $appObj = Get-EntraApplicationObject -App $App
    $oid    = if (Test-IaGuid $Owner) { $Owner } else { Resolve-EntraUserId -User $Owner }
    if ($PSCmdlet.ShouldProcess("$Owner → $($appObj.displayName)", 'Add app owner')) {
        Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "applications/$($appObj.id)/owners/`$ref") -Body @{ '@odata.id' = (Resolve-EntraDirectoryObjectRef $oid) } | Out-Null
        [pscustomobject]@{ App = $appObj.displayName; Owner = $Owner; Added = $true }
    }
}

function Remove-EntraAppOwner {
    <#
    .SYNOPSIS
        Remove an owner from an app registration. Beta DELETE
        /beta/applications/{id}/owners/{id}/$ref.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, Position = 0)][string]$App, [Parameter(Mandatory, Position = 1)][string]$Owner)
    $appObj = Get-EntraApplicationObject -App $App
    $oid    = if (Test-IaGuid $Owner) { $Owner } else { Resolve-EntraUserId -User $Owner }
    if ($PSCmdlet.ShouldProcess("$Owner → $($appObj.displayName)", 'Remove app owner')) {
        Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri -Path "applications/$($appObj.id)/owners/$oid/`$ref") | Out-Null
        [pscustomobject]@{ App = $appObj.displayName; Owner = $Owner; Removed = $true }
    }
}

function Set-EntraAppRegistration {
    <#
    .SYNOPSIS
        Update an app registration's name / sign-in audience / identifier URIs.
        Beta PATCH /beta/applications/{id}.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$App,
        [string]$DisplayName,
        [ValidateSet('AzureADMyOrg', 'AzureADMultipleOrgs', 'AzureADandPersonalMicrosoftAccount', 'PersonalMicrosoftAccount')][string]$SignInAudience,
        [string[]]$IdentifierUri
    )
    $appObj = Get-EntraApplicationObject -App $App
    $body   = [ordered]@{}
    if ($PSBoundParameters.ContainsKey('DisplayName'))    { $body.displayName = $DisplayName }
    if ($PSBoundParameters.ContainsKey('SignInAudience')) { $body.signInAudience = $SignInAudience }
    if ($PSBoundParameters.ContainsKey('IdentifierUri'))  { $body.identifierUris = @($IdentifierUri) }
    if (-not $body.Count) { Write-Warning 'Nothing to update.'; return }
    if ($PSCmdlet.ShouldProcess($appObj.displayName, "Set-EntraAppRegistration [$(@($body.Keys) -join ', ')]")) {
        Invoke-IaRequest -Method PATCH -Uri (Resolve-IaUri -Path "applications/$($appObj.id)") -Body $body | Out-Null
        [pscustomobject]@{ App = $appObj.displayName; Updated = (@($body.Keys) -join ', ') }
    }
}

function Remove-EntraAppRegistration {
    <#
    .SYNOPSIS
        Delete an app registration. Beta DELETE /beta/applications/{id}.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory, Position = 0)][string]$App)
    $appObj = Get-EntraApplicationObject -App $App
    if ($PSCmdlet.ShouldProcess($appObj.displayName, 'Delete app registration')) {
        Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri -Path "applications/$($appObj.id)") | Out-Null
        [pscustomobject]@{ App = $appObj.displayName; AppId = $appObj.appId; Deleted = $true }
    }
}
