function Add-EntraAppPermission {
    <#
    .SYNOPSIS
        Add an API permission to an app registration's requested permissions.
        Beta PATCH /beta/applications/{id} (requiredResourceAccess).
    .DESCRIPTION
        Resolves the resource API (e.g. "Microsoft Graph") and each permission name
        to its GUID, merges them into the app's requiredResourceAccess (without
        disturbing existing ones) and PATCHes. This only REQUESTS the permission —
        run Grant-EntraAdminConsent to actually consent it.
    .PARAMETER App
        App-registration display name, appId or object id.
    .PARAMETER Permission
        One or more permission names, e.g. User.Read.All, Group.ReadWrite.All.
    .PARAMETER Resource
        The API that publishes the permission (default Microsoft Graph). Accepts a
        friendly alias (Graph/SharePoint/Exchange/Intune…), an appId or a name.
    .PARAMETER Type
        Application (app-only) or Delegated. Default Application.
    .EXAMPLE
        Add-EntraAppPermission -App 'CI Pipeline' -Permission Application.ReadWrite.OwnedBy -Type Application
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$App,
        [Parameter(Mandatory, Position = 1)][string[]]$Permission,
        [string]$Resource = 'Microsoft Graph',
        [ValidateSet('Application', 'Delegated')][string]$Type = 'Application'
    )
    $appObj  = Get-EntraApplicationObject -App $App
    $resSp   = Resolve-EntraResourceApi -Resource $Resource
    $entries = @(foreach ($p in $Permission) { Resolve-EntraPermissionEntry -ResourceSp $resSp -Permission $p -Type $Type })

    $rra    = ConvertTo-IaRequiredResourceAccess -Existing $appObj.requiredResourceAccess
    $bucket = $rra | Where-Object { $_.resourceAppId -eq $resSp.appId } | Select-Object -First 1
    if (-not $bucket) {
        $bucket = [ordered]@{ resourceAppId = $resSp.appId; resourceAccess = [System.Collections.Generic.List[object]]::new() }
        $rra.Add($bucket)
    }
    $added = @()
    foreach ($e in $entries) {
        if (-not (@($bucket.resourceAccess) | Where-Object { $_.id -eq $e.Id })) {
            [void]$bucket.resourceAccess.Add([ordered]@{ id = $e.Id; type = $e.OdataType })
            $added += $e.Name
        }
    }
    if (-not $added) { Write-Warning "All requested permissions already present on '$($appObj.displayName)'."; return }
    if ($PSCmdlet.ShouldProcess($appObj.displayName, "Add $Type permission(s) [$($added -join ', ')] on $($resSp.displayName)")) {
        Invoke-IaRequest -Method PATCH -Uri (Resolve-IaUri -Path "applications/$($appObj.id)") -Body @{ requiredResourceAccess = @($rra) } | Out-Null
        [pscustomobject]@{ App = $appObj.displayName; Resource = $resSp.displayName; Type = $Type; Added = ($added -join ', ') }
    }
}

function Remove-EntraAppPermission {
    <#
    .SYNOPSIS
        Remove a requested API permission from an app registration. Beta PATCH
        /beta/applications/{id} (requiredResourceAccess).
    .DESCRIPTION
        The inverse of Add-EntraAppPermission — drops the named permission(s) from the
        app's requested set. Does not revoke already-granted consent (use
        Remove-EntraAppRoleAssignment / Remove-EntraOAuth2Grant for that).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$App,
        [Parameter(Mandatory, Position = 1)][string[]]$Permission,
        [string]$Resource = 'Microsoft Graph',
        [ValidateSet('Application', 'Delegated')][string]$Type = 'Application'
    )
    $appObj  = Get-EntraApplicationObject -App $App
    $resSp   = Resolve-EntraResourceApi -Resource $Resource
    $ids     = @(foreach ($p in $Permission) { (Resolve-EntraPermissionEntry -ResourceSp $resSp -Permission $p -Type $Type).Id })

    $rra    = ConvertTo-IaRequiredResourceAccess -Existing $appObj.requiredResourceAccess
    $bucket = $rra | Where-Object { $_.resourceAppId -eq $resSp.appId } | Select-Object -First 1
    if (-not $bucket) { Write-Warning "'$($appObj.displayName)' requests nothing from $($resSp.displayName)."; return }
    $keep = [System.Collections.Generic.List[object]]::new()
    $removed = 0
    foreach ($a in @($bucket.resourceAccess)) { if ($ids -contains [string]$a.id) { $removed++ } else { [void]$keep.Add($a) } }
    if (-not $removed) { Write-Warning 'None of those permissions were requested.'; return }
    $bucket.resourceAccess = $keep
    # drop the resource bucket entirely if it is now empty
    if (-not $keep.Count) { $rra = [System.Collections.Generic.List[object]](@($rra | Where-Object { $_.resourceAppId -ne $resSp.appId })) }
    if ($PSCmdlet.ShouldProcess($appObj.displayName, "Remove $removed $Type permission(s) on $($resSp.displayName)")) {
        Invoke-IaRequest -Method PATCH -Uri (Resolve-IaUri -Path "applications/$($appObj.id)") -Body @{ requiredResourceAccess = @($rra) } | Out-Null
        [pscustomobject]@{ App = $appObj.displayName; Resource = $resSp.displayName; Type = $Type; Removed = $removed }
    }
}

function Get-EntraAppRequestedPermission {
    <#
    .SYNOPSIS
        The API permissions an app registration currently REQUESTS (its
        requiredResourceAccess), resolved to friendly names. Beta /beta/applications.
    .DESCRIPTION
        The read side of Add/Remove-EntraAppPermission — one row per requested
        permission with its resource, name, Application/Delegated type and the raw id
        (so the TUI can drive a remove picker). High-risk application permissions are
        flagged, and an id that can't be resolved shows as its GUID with Risk=Unknown.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$App)
    $appObj = Get-EntraApplicationObject -App $App
    $rows   = @()
    foreach ($req in @($appObj.requiredResourceAccess)) {
        $resSp    = try { Resolve-EntraResourceApi -Resource ([string]$req.resourceAppId) } catch { $null }
        $roleMap  = @{}; $scopeMap = @{}
        if ($resSp) {
            foreach ($r in @($resSp.appRoles))               { $roleMap[[string]$r.id]  = $r.value }
            foreach ($s in @($resSp.oauth2PermissionScopes)) { $scopeMap[[string]$s.id] = $s.value }
        }
        foreach ($a in @($req.resourceAccess)) {
            $isRole   = ($a.type -eq 'Role')
            $name     = if ($isRole) { $roleMap[[string]$a.id] } else { $scopeMap[[string]$a.id] }
            $resolved = [bool]$name
            $rows += [pscustomobject][ordered]@{
                Resource   = if ($resSp) { $resSp.displayName } else { [string]$req.resourceAppId }
                Permission = if ($resolved) { $name } else { [string]$a.id }
                Type       = if ($isRole) { 'Application' } else { 'Delegated' }
                Risk       = if (Test-EntraHighRiskPermission $name) { 'High' } elseif (-not $resolved) { 'Unknown' } else { '' }
                Id         = [string]$a.id
            }
        }
    }
    @($rows | Sort-Object Resource, Type, Permission)
}

function New-EntraServicePrincipal {
    <#
    .SYNOPSIS
        Create the enterprise app (service principal) for an app registration.
        Beta POST /beta/servicePrincipals (appId). Admin consent is recorded against
        the SP, so this is a prerequisite for granting it.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, Position = 0)][string]$App)
    $appObj   = Get-EntraApplicationObject -App $App
    $existing = Get-EntraClientServicePrincipal -AppId $appObj.appId
    if ($existing) {
        Write-Warning "Enterprise app already exists for '$($appObj.displayName)'."
        return [pscustomobject]@{ App = $appObj.displayName; AppId = $appObj.appId; Id = $existing.id; Created = $false }
    }
    if ($PSCmdlet.ShouldProcess($appObj.displayName, 'Create enterprise app (service principal)')) {
        $sp = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "servicePrincipals") -Body @{ appId = $appObj.appId }
        [pscustomobject]@{ App = $appObj.displayName; AppId = $appObj.appId; Id = $sp.id; Created = $true }
    }
}

function Grant-EntraAdminConsent {
    <#
    .SYNOPSIS
        Grant tenant-wide admin consent for an app registration's requested
        permissions. Beta POST /servicePrincipals/{id}/appRoleAssignments (application)
        and POST/PATCH /oauth2PermissionGrants (delegated, AllPrincipals).
    .DESCRIPTION
        The CLI equivalent of the portal's "Grant admin consent" button. Ensures the
        app's enterprise app (service principal) exists, then for every requested
        permission creates the matching application-role assignment or delegated
        consent grant. Delegated scopes for a resource are merged into one
        AllPrincipals grant. Reports each permission's result.
    .PARAMETER App
        App-registration display name, appId or object id.
    .PARAMETER Resource
        Optionally limit consent to one resource API (default: everything requested).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$App,
        [string]$Resource
    )
    $appObj = Get-EntraApplicationObject -App $App
    $rra    = @($appObj.requiredResourceAccess)
    if ($Resource) {
        $only = Resolve-EntraResourceApi -Resource $Resource
        $rra  = @($rra | Where-Object { $_.resourceAppId -eq $only.appId })
    }
    if (-not $rra) { Write-Warning "'$($appObj.displayName)' has no requested permissions to consent."; return }
    if (-not $PSCmdlet.ShouldProcess($appObj.displayName, "Grant admin consent for $(@($rra).Count) resource API(s)")) { return }

    $client = Get-EntraClientServicePrincipal -AppId $appObj.appId -CreateIfMissing
    $out    = @()
    foreach ($req in $rra) {
        $resSp     = Resolve-EntraResourceApi -Resource ([string]$req.resourceAppId)
        $roleIds   = @($req.resourceAccess | Where-Object { $_.type -eq 'Role' }  | ForEach-Object { [string]$_.id })
        $scopeIds  = @($req.resourceAccess | Where-Object { $_.type -eq 'Scope' } | ForEach-Object { [string]$_.id })

        foreach ($rid in $roleIds) {
            $name = (@($resSp.appRoles) | Where-Object { [string]$_.id -eq $rid } | Select-Object -First 1).value
            try {
                Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "servicePrincipals/$($client.id)/appRoleAssignments") `
                    -Body @{ principalId = $client.id; resourceId = $resSp.id; appRoleId = $rid } | Out-Null
                $out += [pscustomobject]@{ Resource = $resSp.displayName; Permission = ($name ?? $rid); Type = 'Application'; Consented = $true; Error = $null }
            } catch {
                $out += [pscustomobject]@{ Resource = $resSp.displayName; Permission = ($name ?? $rid); Type = 'Application'; Consented = $false; Error = $_.Exception.Message }
            }
        }

        if ($scopeIds.Count) {
            $scopeNames = @($scopeIds | ForEach-Object { $sid = $_; (@($resSp.oauth2PermissionScopes) | Where-Object { [string]$_.id -eq $sid } | Select-Object -First 1).value } | Where-Object { $_ })
            try {
                $existing = @(Get-IaCollection (Resolve-IaUri -Path "oauth2PermissionGrants?`$filter=clientId eq '$($client.id)' and resourceId eq '$($resSp.id)'")) |
                    Where-Object { $_.consentType -eq 'AllPrincipals' } | Select-Object -First 1
                if ($existing) {
                    $merged = (@(($existing.scope -split '\s+') + $scopeNames) | Where-Object { $_ } | Select-Object -Unique) -join ' '
                    Invoke-IaRequest -Method PATCH -Uri (Resolve-IaUri -Path "oauth2PermissionGrants/$($existing.id)") -Body @{ scope = $merged } | Out-Null
                } else {
                    Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "oauth2PermissionGrants") `
                        -Body @{ clientId = $client.id; consentType = 'AllPrincipals'; resourceId = $resSp.id; scope = ($scopeNames -join ' ') } | Out-Null
                }
                foreach ($n in $scopeNames) { $out += [pscustomobject]@{ Resource = $resSp.displayName; Permission = $n; Type = 'Delegated'; Consented = $true; Error = $null } }
            } catch {
                $out += [pscustomobject]@{ Resource = $resSp.displayName; Permission = ($scopeNames -join ' '); Type = 'Delegated'; Consented = $false; Error = $_.Exception.Message }
            }
        }
    }
    $out
}
