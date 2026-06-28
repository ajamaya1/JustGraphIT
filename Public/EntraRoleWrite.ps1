function New-EntraRoleAssignment {
    <#
    .SYNOPSIS
        Assign a directory role to a user (permanent / active). Beta POST
        /beta/roleManagement/directory/roleAssignments.
    .DESCRIPTION
        Grants an always-on role assignment (not time-bound PIM). For eligible
        (just-in-time) assignment use New-EntraPimEligibility instead. High-impact.
    .PARAMETER User
        UPN or object id of the assignee.
    .PARAMETER Role
        Directory role display name (e.g. "Helpdesk Administrator") or its id.
    .PARAMETER Scope
        Directory scope (default '/' = tenant-wide; or an administrative-unit id).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$User,
        [Parameter(Mandatory, Position = 1)][string]$Role,
        [string]$Scope = '/'
    )
    $principal = Resolve-EntraUserId -User $User
    $roleId    = Resolve-EntraRoleDefinitionId -Role $Role
    if ($PSCmdlet.ShouldProcess("$User → $Role", 'Assign directory role (permanent)')) {
        $r = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "roleManagement/directory/roleAssignments") `
            -Body @{ principalId = $principal; roleDefinitionId = $roleId; directoryScopeId = $Scope }
        [pscustomobject]@{ User = $User; Role = $Role; Scope = $Scope; AssignmentId = $r.id; Assigned = $true }
    }
}

function Remove-EntraRoleAssignment {
    <#
    .SYNOPSIS
        Remove a permanent directory-role assignment. Beta DELETE
        /beta/roleManagement/directory/roleAssignments/{id}.
    .DESCRIPTION
        Pass -AssignmentId directly, or -User + -Role to look it up.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')][string]$AssignmentId,
        [Parameter(Mandatory, ParameterSetName = 'ByName', Position = 0)][string]$User,
        [Parameter(Mandatory, ParameterSetName = 'ByName', Position = 1)][string]$Role
    )
    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        $principal = Resolve-EntraUserId -User $User
        $roleId    = Resolve-EntraRoleDefinitionId -Role $Role
        $a = @(Get-IaCollection (Resolve-IaUri -Path "roleManagement/directory/roleAssignments?`$filter=principalId eq '$principal' and roleDefinitionId eq '$roleId'")) | Select-Object -First 1
        if (-not $a) { throw "No active assignment of '$Role' to '$User'." }
        $AssignmentId = $a.id
        $label = "$User / $Role"
    } else { $label = $AssignmentId }
    if ($PSCmdlet.ShouldProcess($label, 'Remove directory role assignment')) {
        Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri -Path "roleManagement/directory/roleAssignments/$AssignmentId") | Out-Null
        [pscustomobject]@{ Assignment = $label; Removed = $true }
    }
}

function New-EntraPimEligibility {
    <#
    .SYNOPSIS
        Make a user ELIGIBLE for a directory role (PIM admin-assign). Beta POST
        /beta/roleManagement/directory/roleEligibilityScheduleRequests.
    .DESCRIPTION
        The assignee can then activate the role just-in-time (Enable-EntraPimRole).
        Omit -Duration for permanent eligibility, or give e.g. 90d for a time-boxed one.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$User,
        [Parameter(Mandatory, Position = 1)][string]$Role,
        [string]$Duration,
        [string]$Justification = 'Granted via JustGraphIT',
        [string]$Scope = '/'
    )
    $principal = Resolve-EntraUserId -User $User
    $roleId    = Resolve-EntraRoleDefinitionId -Role $Role
    $sched = @{ startDateTime = (Get-Date).ToUniversalTime().ToString('o') }
    $sched.expiration = if ($Duration) { @{ type = 'afterDuration'; duration = (ConvertTo-IaIsoDuration $Duration) } } else { @{ type = 'noExpiration' } }
    if ($PSCmdlet.ShouldProcess("$User → $Role", 'Grant PIM role eligibility')) {
        $r = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "roleManagement/directory/roleEligibilityScheduleRequests") `
            -Body @{ action = 'adminAssign'; principalId = $principal; roleDefinitionId = $roleId; directoryScopeId = $Scope; justification = $Justification; scheduleInfo = $sched }
        [pscustomobject]@{ User = $User; Role = $Role; Eligibility = $(if ($Duration) { "for $Duration" } else { 'permanent' }); Status = $r.status; RequestId = $r.id }
    }
}

function Remove-EntraPimEligibility {
    <#
    .SYNOPSIS
        Remove a user's eligibility for a directory role (PIM admin-remove). Beta POST
        /beta/roleManagement/directory/roleEligibilityScheduleRequests (adminRemove).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$User,
        [Parameter(Mandatory, Position = 1)][string]$Role,
        [string]$Justification = 'Removed via JustGraphIT',
        [string]$Scope = '/'
    )
    $principal = Resolve-EntraUserId -User $User
    $roleId    = Resolve-EntraRoleDefinitionId -Role $Role
    if ($PSCmdlet.ShouldProcess("$User → $Role", 'Remove PIM role eligibility')) {
        $r = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "roleManagement/directory/roleEligibilityScheduleRequests") `
            -Body @{ action = 'adminRemove'; principalId = $principal; roleDefinitionId = $roleId; directoryScopeId = $Scope; justification = $Justification }
        [pscustomobject]@{ User = $User; Role = $Role; Status = $r.status; RequestId = $r.id; Removed = $true }
    }
}

function Enable-EntraPimRole {
    <#
    .SYNOPSIS
        Activate one of YOUR eligible directory roles (PIM self-activate). Beta POST
        /beta/roleManagement/directory/roleAssignmentScheduleRequests.
    .DESCRIPTION
        Elevates the signed-in user into an eligible role for -Duration. Delegated
        sign-in only (app-only has no user to elevate). Run Get-EntraPimEligibility to
        see what you can activate.
    .PARAMETER Role
        The eligible role's display name (or id).
    .PARAMETER Duration
        How long to activate (default PT8H; accepts 2h / 30m / 1d / ISO8601).
    .PARAMETER Justification
        Reason (required by most PIM policies).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Role,
        [string]$Duration = 'PT8H',
        [Parameter(Mandatory)][string]$Justification,
        [string]$TicketNumber,
        [string]$TicketSystem
    )
    $me    = Get-IaMyPrincipalId
    $elig  = @(Get-IaEligibleRoles -PrincipalId $me.Id)
    $match = $elig | Where-Object { $_.roleDefinition.displayName -eq $Role -or $_.roleDefinitionId -eq $Role } | Select-Object -First 1
    if (-not $match) { throw "You are not eligible for '$Role'. Run Get-EntraPimEligibility to see your eligible roles." }
    $dur = ConvertTo-IaIsoDuration $Duration
    if ($PSCmdlet.ShouldProcess($Role, "Activate eligible PIM role for $dur")) {
        $p = @{ PrincipalId = $me.Id; RoleDefinitionId = $match.roleDefinitionId; Duration = $dur; Justification = $Justification; DirectoryScopeId = ($match.directoryScopeId ?? '/') }
        if ($TicketNumber) { $p.TicketNumber = $TicketNumber; $p.TicketSystem = $TicketSystem }
        $r = Invoke-IaActivateRole @p
        [pscustomobject]@{ Role = $Role; Duration = $dur; Status = $r.status; RequestId = $r.id; Activated = $true }
    }
}
