function Get-EntraSecureScore {
    <#
    .SYNOPSIS
        Microsoft Secure Score (recent snapshots). Beta GET /beta/security/secureScores.
    .DESCRIPTION
        Returns the most recent scores with the achieved/maximum points and percentage.
        -Detailed expands the per-control breakdown of the latest snapshot.
    #>
    [CmdletBinding()]
    param([int]$Top = 7, [switch]$Detailed, [switch]$Raw)
    $rows = @(Get-IaCollection (Resolve-IaUri -Path "security/secureScores?`$top=$Top"))
    if ($Raw) { return $rows }
    if ($Detailed -and $rows.Count) {
        return @($rows[0].controlScores | ForEach-Object {
            [pscustomobject][ordered]@{ Control = $_.controlName; Category = $_.controlCategory; Score = $_.score; Implementation = $_.implementationStatus; Description = $_.description }
        })
    }
    @($rows | ForEach-Object {
        $pct = if ($_.maxScore) { [int][math]::Round($_.currentScore / $_.maxScore * 100) } else { 0 }
        [pscustomobject][ordered]@{ Date = $_.createdDateTime; Current = $_.currentScore; Max = $_.maxScore; Percent = $pct; Users = $_.activeUserCount; LicensedUsers = $_.licensedUserCount }
    })
}

function Get-EntraSecurityAlert {
    <#
    .SYNOPSIS
        Microsoft 365 Defender / XDR alerts. Beta GET /beta/security/alerts_v2.
    #>
    [CmdletBinding()]
    param([ValidateSet('high', 'medium', 'low', 'informational')][string]$Severity, [int]$Top = 100, [switch]$Raw)
    $q = "security/alerts_v2?`$top=$Top"
    if ($Severity) { $q += "&`$filter=$([uri]::EscapeDataString("severity eq '$Severity'"))" }
    $rows = @(Get-IaCollection (Resolve-IaUri -Path $q))
    if ($Raw) { return $rows }
    @($rows | ForEach-Object {
        [pscustomobject][ordered]@{
            Title    = $_.title
            Severity = $_.severity
            Status   = $_.status
            Category = $_.category
            Service  = $_.serviceSource
            Created  = $_.createdDateTime
            Assigned = $_.assignedTo
            Id       = $_.id
        }
    })
}

function Get-EntraSecurityIncident {
    <#
    .SYNOPSIS
        Microsoft 365 Defender / XDR incidents. Beta GET /beta/security/incidents.
    #>
    [CmdletBinding()]
    param([int]$Top = 100, [switch]$Raw)
    $rows = @(Get-IaCollection (Resolve-IaUri -Path "security/incidents?`$top=$Top"))
    if ($Raw) { return $rows }
    @($rows | ForEach-Object {
        [pscustomobject][ordered]@{
            Name        = $_.displayName
            Severity    = $_.severity
            Status      = $_.status
            Assigned    = $_.assignedTo
            Classification = $_.classification
            Determination  = $_.determination
            Created     = $_.createdDateTime
            Updated     = $_.lastUpdateDateTime
            Id          = $_.id
        }
    })
}
