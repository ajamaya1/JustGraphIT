function Get-EntraDirectoryRole {
    <#
    .SYNOPSIS
        Entra directory role definitions. Beta GET /beta/roleManagement/directory/roleDefinitions.
    #>
    [CmdletBinding()]
    param([switch]$BuiltInOnly, [switch]$Raw)
    $rows = @(Get-IaCollection (Resolve-IaUri -Path "roleManagement/directory/roleDefinitions?`$select=id,displayName,description,isBuiltIn,isEnabled,templateId"))
    if ($BuiltInOnly) { $rows = @($rows | Where-Object { $_.isBuiltIn }) }
    if ($Raw) { return $rows }
    @($rows | ForEach-Object {
        [pscustomobject][ordered]@{ Role = $_.displayName; Description = $_.description; BuiltIn = [bool]$_.isBuiltIn; Enabled = [bool]$_.isEnabled; TemplateId = $_.templateId; Id = $_.id }
    } | Sort-Object Role)
}

function Get-EntraRoleAssignment {
    <#
    .SYNOPSIS
        Active (permanent) directory-role assignments — who holds which role.
        Beta GET /beta/roleManagement/directory/roleAssignments?$expand=principal,roleDefinition.
    #>
    [CmdletBinding()]
    param([switch]$Raw)
    $rows = try {
        @(Get-IaCollection (Resolve-IaUri -Path "roleManagement/directory/roleAssignments?`$expand=principal,roleDefinition"))
    } catch {
        try { @(Get-IaCollection (Resolve-IaUri -Path "roleManagement/directory/roleAssignments")) } catch { @() }
    }
    if ($Raw) { return $rows }
    @($rows | ForEach-Object { ConvertTo-IaRoleRow $_ 'Permanent' } | Sort-Object Role, Principal)
}

function Get-EntraPimEligibility {
    <#
    .SYNOPSIS
        PIM role *eligibility* across the tenant (who can activate which role).
        Beta GET /beta/roleManagement/directory/roleEligibilityScheduleInstances?$expand=principal,roleDefinition.
    #>
    [CmdletBinding()]
    param([switch]$Raw)
    $rows = try {
        @(Get-IaCollection (Resolve-IaUri -Path "roleManagement/directory/roleEligibilityScheduleInstances?`$expand=principal,roleDefinition"))
    } catch {
        try { @(Get-IaCollection (Resolve-IaUri -Path "roleManagement/directory/roleEligibilityScheduleInstances")) } catch { @() }
    }
    if ($Raw) { return $rows }
    @($rows | ForEach-Object { ConvertTo-IaRoleRow $_ 'Eligible' } | Sort-Object Role, Principal)
}

function Get-EntraPimActive {
    <#
    .SYNOPSIS
        PIM role *active assignments* across the tenant (currently elevated).
        Beta GET /beta/roleManagement/directory/roleAssignmentScheduleInstances?$expand=principal,roleDefinition.
    #>
    [CmdletBinding()]
    param([switch]$Raw)
    $rows = try {
        @(Get-IaCollection (Resolve-IaUri -Path "roleManagement/directory/roleAssignmentScheduleInstances?`$expand=principal,roleDefinition"))
    } catch {
        try { @(Get-IaCollection (Resolve-IaUri -Path "roleManagement/directory/roleAssignmentScheduleInstances")) } catch { @() }
    }
    if ($Raw) { return $rows }
    @($rows | ForEach-Object {
        $r = ConvertTo-IaRoleRow $_ 'Active'
        $r | Add-Member -NotePropertyName EndsAt -NotePropertyValue (ConvertTo-IaSafeDateTime $_.endDateTime) -Force
        $r
    } | Sort-Object Role, Principal)
}

function ConvertTo-IaRoleRow {
    param($r, [string]$Kind)
    [pscustomobject][ordered]@{
        Role          = if ($r.roleDefinition) { $r.roleDefinition.displayName } else { $r.roleDefinitionId }
        Principal     = if ($r.principal) { ($r.principal.displayName ?? $r.principal.userPrincipalName) } else { $r.principalId }
        PrincipalUPN  = if ($r.principal) { $r.principal.userPrincipalName } else { $null }
        PrincipalType = if ($r.principal) { ($r.principal.'@odata.type' -replace '#microsoft\.graph\.', '') } else { $null }
        Assignment    = $Kind
        Scope         = $r.directoryScopeId
        Id            = $r.id
    }
}
