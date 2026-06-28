# Entra ID > directory recycle bin — soft-deleted users, groups and app registrations.
# List what's recoverable, restore it, or permanently purge it. Soft-deleted directory
# objects are recoverable for 30 days (security groups purge immediately and won't appear).
# Beta /beta/directory/deletedItems.

function Get-EntraDeletedItem {
    <#
    .SYNOPSIS
        Soft-deleted directory objects (recoverable for 30 days). Beta GET
        /beta/directory/deletedItems/microsoft.graph.{user|group|application}.
    .PARAMETER Type
        User, Group, or Application.
    .EXAMPLE
        Get-EntraDeletedItem -Type User
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][ValidateSet('User', 'Group', 'Application')][string]$Type, [int]$Top = 200, [switch]$Raw)
    $cast = @{ User = 'microsoft.graph.user'; Group = 'microsoft.graph.group'; Application = 'microsoft.graph.application' }[$Type]
    $sel  = switch ($Type) { 'User' { 'id,displayName,userPrincipalName,deletedDateTime' } 'Group' { 'id,displayName,mail,deletedDateTime' } 'Application' { 'id,displayName,appId,deletedDateTime' } }
    $rows = @(Get-IaCollection (Resolve-IaUri -Path "directory/deletedItems/${cast}?`$select=$sel&`$top=$Top"))
    if ($Raw) { return $rows }
    @($rows | ForEach-Object {
        [pscustomobject][ordered]@{
            DisplayName = $_.displayName
            Identifier  = if ($Type -eq 'User') { $_.userPrincipalName } elseif ($Type -eq 'Application') { $_.appId } else { $_.mail }
            Deleted     = $_.deletedDateTime
            DaysLeft    = if ($_.deletedDateTime) { [Math]::Max(0, 30 - [int]([DateTime]::UtcNow - [DateTime]$_.deletedDateTime).TotalDays) } else { $null }
            Id          = $_.id
        }
    } | Sort-Object Deleted -Descending)
}

function Restore-EntraDeletedItem {
    <#
    .SYNOPSIS
        Restore a soft-deleted directory object. Beta POST
        /beta/directory/deletedItems/{id}/restore.
    .DESCRIPTION
        Recovers a deleted user / group / app registration with its original id and
        relationships. Works within the 30-day window.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Parameter(Mandatory, Position = 0)][ValidatePattern('^[^/?#\s]+$')][string]$Id)
    if ($PSCmdlet.ShouldProcess($Id, 'Restore deleted directory object')) {
        $r = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "directory/deletedItems/$Id/restore")
        [pscustomobject]@{ Id = $Id; Restored = $true; DisplayName = $r.displayName }
    }
}

function Remove-EntraDeletedItem {
    <#
    .SYNOPSIS
        Permanently purge a soft-deleted directory object (cannot be undone). Beta DELETE
        /beta/directory/deletedItems/{id}.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory, Position = 0)][ValidatePattern('^[^/?#\s]+$')][string]$Id)
    if ($PSCmdlet.ShouldProcess($Id, 'PERMANENTLY purge deleted directory object')) {
        Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri -Path "directory/deletedItems/$Id") | Out-Null
        [pscustomobject]@{ Id = $Id; Purged = $true }
    }
}
