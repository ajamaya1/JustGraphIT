# Shared helpers for the Entra *write* surface (app-registration permissions,
# admin consent, provisioning). Resolvers here turn friendly names into the GUIDs
# and @odata.type bindings the Graph write endpoints expect. All beta.

# Well-known first-party API appIds, so "Graph" / "SharePoint" etc. resolve without
# the operator hunting GUIDs. Keys are lowercased + de-spaced for lookup.
$script:IaWellKnownApi = @{
    'graph'                = '00000003-0000-0000-c000-000000000000'  # Microsoft Graph
    'microsoftgraph'       = '00000003-0000-0000-c000-000000000000'
    'msgraph'              = '00000003-0000-0000-c000-000000000000'
    'sharepoint'           = '00000003-0000-0ff1-ce00-000000000000'  # Office 365 SharePoint Online
    'exchange'             = '00000002-0000-0ff1-ce00-000000000000'  # Office 365 Exchange Online
    'office365management'  = 'c5393580-f805-4401-95e8-94b7a6ef2fc2'  # Office 365 Management APIs
    'azureservicemanagement' = '797f4846-ba00-4fd7-ba43-dac1f8f63013'
    'powerbi'              = '00000009-0000-0000-c000-000000000000'  # Power BI Service
    'intune'               = 'c161e42e-d4df-4a3d-9b42-e7a3c31f59d4'  # Microsoft Intune API
}

function Resolve-EntraResourceApi {
    # Resource API name / alias / appId / SP object id → the resource service
    # principal with its publishable permission catalogue (appRoles for application
    # permissions, oauth2PermissionScopes for delegated). Used by both the
    # permission-add and consent flows.
    param([Parameter(Mandatory)][string]$Resource)
    $sel = 'id,appId,displayName,appRoles,oauth2PermissionScopes'
    $key = $Resource.ToLower() -replace '[\s\.]', ''
    $appId = if ($script:IaWellKnownApi.ContainsKey($key)) { $script:IaWellKnownApi[$key] }
             elseif (Test-IaGuid $Resource) { $Resource } else { $null }
    if ($appId) {
        $sp = @(Get-IaCollection (Resolve-IaUri -Path "servicePrincipals?`$filter=appId eq '$appId'&`$select=$sel"))
        # a GUID might be the SP object id rather than the appId
        if (-not $sp -and (Test-IaGuid $Resource)) {
            try { $one = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "servicePrincipals/${Resource}?`$select=$sel"); if ($one.id) { $sp = @($one) } } catch { }
        }
    } else {
        $f  = "displayName eq '$($Resource.Replace("'", "''"))'"
        $sp = @(Get-IaCollection (Resolve-IaUri -Path "servicePrincipals?`$filter=$([uri]::EscapeDataString($f))&`$select=$sel"))
    }
    if (-not $sp) { throw "Resource API '$Resource' is not provisioned as a service principal in this tenant." }
    $sp[0]
}

function Resolve-EntraPermissionEntry {
    # Permission name (e.g. User.Read.All) on a resource SP → { Id; OdataType }.
    # OdataType is 'Role' for an application permission, 'Scope' for delegated —
    # the value requiredResourceAccess.resourceAccess.type takes.
    param(
        [Parameter(Mandatory)]$ResourceSp,
        [Parameter(Mandatory)][string]$Permission,
        [Parameter(Mandatory)][ValidateSet('Application', 'Delegated')][string]$Type
    )
    if ($Type -eq 'Application') {
        $r = @($ResourceSp.appRoles) | Where-Object { $_.value -eq $Permission -and $_.isEnabled } | Select-Object -First 1
        if (-not $r) { throw "Application permission '$Permission' is not published by $($ResourceSp.displayName)." }
        return [pscustomobject]@{ Id = [string]$r.id; OdataType = 'Role'; Name = $r.value }
    }
    $s = @($ResourceSp.oauth2PermissionScopes) | Where-Object { $_.value -eq $Permission } | Select-Object -First 1
    if (-not $s) { throw "Delegated permission '$Permission' is not published by $($ResourceSp.displayName)." }
    [pscustomobject]@{ Id = [string]$s.id; OdataType = 'Scope'; Name = $s.value }
}

function Get-EntraApplicationObject {
    # App registration name / appId / object id → the application object (with the
    # fields the write flows need). Applications are keyed by OBJECT id for PATCH,
    # so a bare appId is resolved through a filter.
    param([Parameter(Mandatory)][string]$App)
    $sel = 'id,appId,displayName,requiredResourceAccess,signInAudience'
    if (Test-IaGuid $App) {
        try { $a = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "applications/${App}?`$select=$sel"); if ($a.id) { return $a } } catch { }
        $byApp = @(Get-IaCollection (Resolve-IaUri -Path "applications?`$filter=appId eq '$App'&`$select=$sel"))
        if ($byApp) { return $byApp[0] }
        throw "No app registration found with id/appId '$App'."
    }
    $f   = "displayName eq '$($App.Replace("'", "''"))'"
    $res = @(Get-IaCollection (Resolve-IaUri -Path "applications?`$filter=$([uri]::EscapeDataString($f))&`$select=$sel&`$top=5"))
    if ($res.Count -eq 1) { return $res[0] }
    if ($res.Count -gt 1) { throw "Multiple app registrations named '$App'. Use the appId or object id." }
    throw "No app registration found matching '$App'."
}

function ConvertTo-IaRequiredResourceAccess {
    # Deep-copy a Graph requiredResourceAccess collection into plain ordered
    # hashtables we can safely mutate before PATCHing it back.
    param($Existing)
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($r in @($Existing)) {
        $access = [System.Collections.Generic.List[object]]::new()
        foreach ($a in @($r.resourceAccess)) { [void]$access.Add([ordered]@{ id = [string]$a.id; type = [string]$a.type }) }
        [void]$out.Add([ordered]@{ resourceAppId = [string]$r.resourceAppId; resourceAccess = $access })
    }
    , $out
}

function Get-EntraClientServicePrincipal {
    # The enterprise app (service principal) for an app registration's appId,
    # creating it if absent. Admin consent is recorded against the SP, so it must
    # exist before grants can be made. Returns the SP object.
    param([Parameter(Mandatory)][string]$AppId, [switch]$CreateIfMissing)
    $sp = @(Get-IaCollection (Resolve-IaUri -Path "servicePrincipals?`$filter=appId eq '$AppId'&`$select=id,appId,displayName"))
    if ($sp) { return $sp[0] }
    if (-not $CreateIfMissing) { return $null }
    Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "servicePrincipals") -Body @{ appId = $AppId }
}
