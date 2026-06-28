function Get-EntraSignIn {
    <#
    .SYNOPSIS
        Tenant sign-in logs (interactive + non-interactive). Beta GET /beta/auditLogs/signIns.
    .DESCRIPTION
        -User filters to one UPN; -FailuresOnly keeps non-zero error codes; -Top caps the
        page (newest first). Needs AuditLog.Read.All + an Entra ID P1/P2 tenant.
    .OUTPUTS PSCustomObject per sign-in (or raw with -Raw).
    #>
    [CmdletBinding()]
    param([string]$User, [switch]$FailuresOnly, [int]$Top = 100, [switch]$Raw)
    $filters = @()
    if ($User)         { $filters += "userPrincipalName eq '$($User.Replace("'","''"))'" }
    if ($FailuresOnly) { $filters += "status/errorCode ne 0" }
    $q = "auditLogs/signIns?`$top=$Top"
    if ($filters) { $q += "&`$filter=$([uri]::EscapeDataString($filters -join ' and '))" }
    $rows = @(Get-IaCollection (Resolve-IaUri -Path $q))
    if ($Raw) { return $rows }
    @($rows | ForEach-Object {
        [pscustomobject][ordered]@{
            When        = $_.createdDateTime
            User        = $_.userPrincipalName
            App         = $_.appDisplayName
            Status      = if ($_.status.errorCode -eq 0) { 'success' } else { "fail $($_.status.errorCode)" }
            Reason      = $_.status.failureReason
            CA          = $_.conditionalAccessStatus
            Risk        = $_.riskLevelDuringSignIn
            Client      = $_.clientAppUsed
            IP          = $_.ipAddress
            Location    = "$($_.location.city) $($_.location.countryOrRegion)".Trim()
            Device      = $_.deviceDetail.displayName
            Id          = $_.id
        }
    })
}

function Get-EntraConditionalAccessPolicy {
    <#
    .SYNOPSIS
        Conditional Access policies. Beta GET /beta/identity/conditionalAccess/policies.
        -Raw returns the full policy object (conditions, grant/session controls).
    #>
    [CmdletBinding()]
    param([switch]$Raw)
    $rows = @(Get-IaCollection (Resolve-IaUri -Path "identity/conditionalAccess/policies"))
    if ($Raw) { return $rows }
    @($rows | ForEach-Object {
        [pscustomobject][ordered]@{
            Name        = $_.displayName
            State       = $_.state
            Users       = (@($_.conditions.users.includeUsers) -join ',')
            Apps        = (@($_.conditions.applications.includeApplications) -join ',')
            Controls    = (@($_.grantControls.builtInControls) -join ',')
            Created     = $_.createdDateTime
            Modified    = $_.modifiedDateTime
            Id          = $_.id
        }
    } | Sort-Object Name)
}

function Set-EntraConditionalAccessState {
    <#
    .SYNOPSIS
        Enable / disable / report-only a CA policy. Beta PATCH the policy's state.
    .PARAMETER State
        enabled | disabled | reportOnly.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Id,
        [Parameter(Mandatory, Position = 1)][ValidateSet('enabled', 'disabled', 'reportOnly')][string]$State
    )
    $graphState = switch ($State) { 'reportOnly' { 'enabledForReportingButNotEnforced' } default { $State } }
    if ($PSCmdlet.ShouldProcess($Id, "CA state → $State")) {
        Invoke-IaRequest -Method PATCH -Uri (Resolve-IaUri -Path "identity/conditionalAccess/policies/$Id") -Body @{ state = $graphState } | Out-Null
        [pscustomobject]@{ Id = $Id; State = $graphState }
    }
}

function Get-EntraRiskyUser {
    <#
    .SYNOPSIS
        Users flagged by Identity Protection. Beta GET /beta/identityProtection/riskyUsers.
    #>
    [CmdletBinding()]
    param([switch]$AtRiskOnly, [int]$Top = 100, [switch]$Raw)
    $q = "identityProtection/riskyUsers?`$top=$Top"
    if ($AtRiskOnly) { $q += "&`$filter=$([uri]::EscapeDataString("riskState eq 'atRisk'"))" }
    $rows = @(Get-IaCollection (Resolve-IaUri -Path $q))
    if ($Raw) { return $rows }
    @($rows | ForEach-Object {
        [pscustomobject][ordered]@{
            User      = $_.userPrincipalName
            Name      = $_.userDisplayName
            RiskLevel = $_.riskLevel
            RiskState = $_.riskState
            RiskDetail = $_.riskDetail
            Updated   = $_.riskLastUpdatedDateTime
            Id        = $_.id
        }
    })
}

function Get-EntraRiskDetection {
    <#
    .SYNOPSIS
        Identity Protection risk detections. Beta GET /beta/identityProtection/riskDetections.
    #>
    [CmdletBinding()]
    param([int]$Top = 100, [switch]$Raw)
    $rows = @(Get-IaCollection (Resolve-IaUri -Path "identityProtection/riskDetections?`$top=$Top"))
    if ($Raw) { return $rows }
    @($rows | ForEach-Object {
        [pscustomobject][ordered]@{
            When      = $_.detectedDateTime
            User      = $_.userPrincipalName
            RiskEvent = $_.riskEventType
            Level     = $_.riskLevel
            State     = $_.riskState
            IP        = $_.ipAddress
            Location  = "$($_.location.city) $($_.location.countryOrRegion)".Trim()
            Id        = $_.id
        }
    })
}

function Set-EntraRiskyUser {
    <#
    .SYNOPSIS
        Confirm-compromised or dismiss risk for one or more users.
        Beta POST /beta/identityProtection/riskyUsers/{confirmCompromised|dismiss}.
    .PARAMETER Action
        Compromise (confirmCompromised) or Dismiss.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string[]]$UserId,
        [Parameter(Mandatory, Position = 1)][ValidateSet('Compromise', 'Dismiss')][string]$Action
    )
    $seg = if ($Action -eq 'Compromise') { 'confirmCompromised' } else { 'dismiss' }
    if ($PSCmdlet.ShouldProcess(($UserId -join ','), "Risky user → $seg")) {
        Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "identityProtection/riskyUsers/$seg") -Body @{ userIds = @($UserId) } | Out-Null
        [pscustomobject]@{ UserIds = ($UserId -join ', '); Action = $seg }
    }
}
