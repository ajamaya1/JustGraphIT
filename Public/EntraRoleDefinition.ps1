# Entra ID > Roles & admins > Roles / Custom roles — the unified-RBAC role definitions
# (built-in + custom) and the catalogue of directory resource actions you compose a
# custom role from. Create / edit / delete apply to CUSTOM roles only (built-ins are
# read-only). All beta; requires Entra ID P1/P2 for custom roles.

function Get-EntraRoleDefinition {
    <#
    .SYNOPSIS
        Directory role definitions (built-in + custom). Beta GET
        /beta/roleManagement/directory/roleDefinitions.
    .PARAMETER CustomOnly
        Only tenant-created (isBuiltIn=false) roles.
    #>
    [CmdletBinding()]
    param([switch]$CustomOnly, [switch]$Raw)
    $q = "roleManagement/directory/roleDefinitions?`$select=id,displayName,description,isBuiltIn,isEnabled,isPrivileged,templateId,rolePermissions"
    if ($CustomOnly) { $q += "&`$filter=$([uri]::EscapeDataString('isBuiltIn eq false'))" }
    $rows = @(Get-IaCollection (Resolve-IaUri -Path $q))
    if ($Raw) { return $rows }
    @($rows | ForEach-Object {
        [pscustomobject][ordered]@{
            DisplayName = $_.displayName
            Type        = if ($_.isBuiltIn) { 'Built-in' } else { 'Custom' }
            Enabled     = $_.isEnabled
            Privileged  = $_.isPrivileged
            Actions     = @($_.rolePermissions.allowedResourceActions).Count
            Id          = $_.id
        }
    } | Sort-Object Type, DisplayName)
}

function Get-EntraRoleAction {
    <#
    .SYNOPSIS
        The directory resource actions a custom role can grant. Beta GET
        /beta/roleManagement/directory/resourceNamespaces/microsoft.directory/resourceActions.
    .DESCRIPTION
        Each .Action value (e.g. microsoft.directory/applications/basic/read) is exactly
        what goes into a custom role's -AllowedResourceAction. -Like filters by name or
        description.
    #>
    [CmdletBinding()]
    param([string]$Like, [switch]$Raw)
    $rows = @(Get-IaCollection (Resolve-IaUri -Path "roleManagement/directory/resourceNamespaces/microsoft.directory/resourceActions?`$select=id,name,actionVerb,description,isPrivileged"))
    if ($Like) { $rows = @($rows | Where-Object { $_.name -like "*$Like*" -or $_.description -like "*$Like*" }) }
    if ($Raw) { return $rows }
    @($rows | ForEach-Object { [pscustomobject][ordered]@{ Action = $_.name; Verb = $_.actionVerb; Privileged = $_.isPrivileged; Description = $_.description } } | Sort-Object Action)
}

function New-EntraRoleDefinition {
    <#
    .SYNOPSIS
        Create a custom directory role. Beta POST
        /beta/roleManagement/directory/roleDefinitions.
    .PARAMETER AllowedResourceAction
        One or more action strings (see Get-EntraRoleAction), e.g.
        microsoft.directory/applications/basic/read.
    .EXAMPLE
        New-EntraRoleDefinition -Name 'App Reg Support' -AllowedResourceAction microsoft.directory/applications/basic/read
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Mandatory)][string[]]$AllowedResourceAction,
        [string]$Description,
        [bool]$Enabled = $true
    )
    $body = [ordered]@{
        displayName     = $Name
        description     = $Description
        isEnabled       = $Enabled
        resourceScopes  = @('/')
        rolePermissions = @(@{ allowedResourceActions = @($AllowedResourceAction) })
    }
    if ($PSCmdlet.ShouldProcess($Name, "Create custom directory role ($(@($AllowedResourceAction).Count) action(s))")) {
        $r = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "roleManagement/directory/roleDefinitions") -Body $body
        [pscustomobject]@{ Name = $r.displayName; Id = $r.id; Custom = $true }
    }
}

function Set-EntraRoleDefinition {
    <#
    .SYNOPSIS
        Update a custom directory role (rename / description / enable / actions). Beta
        PATCH /beta/roleManagement/directory/roleDefinitions/{id}.
    .DESCRIPTION
        Built-in roles are read-only; this only succeeds on custom roles. -AllowedResourceAction
        REPLACES the whole permission set.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Role,
        [string]$DisplayName,
        [string]$Description,
        [System.Nullable[bool]]$Enabled,
        [string[]]$AllowedResourceAction
    )
    $id   = Resolve-EntraRoleDefinitionId -Role $Role
    $body = [ordered]@{}
    if ($DisplayName)                                  { $body.displayName = $DisplayName }
    if ($PSBoundParameters.ContainsKey('Description')) { $body.description = $Description }
    if ($PSBoundParameters.ContainsKey('Enabled'))     { $body.isEnabled = [bool]$Enabled }
    if ($AllowedResourceAction)                        { $body.rolePermissions = @(@{ allowedResourceActions = @($AllowedResourceAction) }) }
    if (-not $body.Count) { Write-Warning 'Nothing to update.'; return }
    if ($PSCmdlet.ShouldProcess($Role, "Update custom role [$(@($body.Keys) -join ', ')]")) {
        Invoke-IaRequest -Method PATCH -Uri (Resolve-IaUri -Path "roleManagement/directory/roleDefinitions/$id") -Body $body | Out-Null
        [pscustomobject]@{ Role = $Role; Updated = (@($body.Keys) -join ', ') }
    }
}

function Remove-EntraRoleDefinition {
    <#
    .SYNOPSIS
        Delete a custom directory role. Beta DELETE
        /beta/roleManagement/directory/roleDefinitions/{id}. Built-in roles cannot be deleted.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory, Position = 0)][string]$Role)
    $id = Resolve-EntraRoleDefinitionId -Role $Role
    if ($PSCmdlet.ShouldProcess($Role, 'Delete custom directory role')) {
        Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri -Path "roleManagement/directory/roleDefinitions/$id") | Out-Null
        [pscustomobject]@{ Role = $Role; Deleted = $true }
    }
}
