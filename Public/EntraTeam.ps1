# Microsoft Teams management. A team's id is the same as its backing Microsoft 365
# group id, so team resolution reuses the group resolver. All beta.

function Get-EntraTeamChannel {
    <#
    .SYNOPSIS
        List a team's channels. Beta GET /beta/teams/{id}/channels.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Team)
    $id = Resolve-EntraGroupId -Group $Team
    @(Get-IaCollection (Resolve-IaUri -Path "teams/$id/channels") | ForEach-Object {
        [pscustomobject][ordered]@{ Name = $_.displayName; Type = $_.membershipType; Description = $_.description; Email = $_.email; Id = $_.id }
    })
}

function New-EntraTeamChannel {
    <#
    .SYNOPSIS
        Create a channel in a team. Beta POST /beta/teams/{id}/channels.
    .PARAMETER Private
        Create a private channel (default is a standard channel).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Team,
        [Parameter(Mandatory, Position = 1)][string]$Name,
        [string]$Description,
        [switch]$Private
    )
    $id   = Resolve-EntraGroupId -Group $Team
    $body = [ordered]@{ displayName = $Name; membershipType = $(if ($Private) { 'private' } else { 'standard' }) }
    if ($Description) { $body.description = $Description }
    if ($PSCmdlet.ShouldProcess("$Name → $Team", 'Create team channel')) {
        $c = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "teams/$id/channels") -Body $body
        [pscustomobject]@{ Team = $Team; Channel = $c.displayName; Type = $c.membershipType; Id = $c.id }
    }
}

function Remove-EntraTeamChannel {
    <#
    .SYNOPSIS
        Delete a channel from a team. Beta DELETE /beta/teams/{id}/channels/{channelId}.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory, Position = 0)][string]$Team, [Parameter(Mandatory, Position = 1)][string]$Channel)
    $id  = Resolve-EntraGroupId -Group $Team
    $cid = $Channel
    if ($Channel -notmatch '^19:') {
        $hit = @(Get-EntraTeamChannel -Team $Team | Where-Object { $_.Name -eq $Channel })
        if ($hit.Count -ne 1) { throw "Channel '$Channel' not found (or ambiguous) in '$Team'." }
        $cid = $hit[0].Id
    }
    if ($PSCmdlet.ShouldProcess("$Channel in $Team", 'Delete team channel')) {
        Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri -Path "teams/$id/channels/$cid") | Out-Null
        [pscustomobject]@{ Team = $Team; Channel = $Channel; Deleted = $true }
    }
}

function Get-EntraTeamMember {
    <#
    .SYNOPSIS
        List a team's members (and their roles). Beta GET /beta/teams/{id}/members.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Team)
    $id = Resolve-EntraGroupId -Group $Team
    @(Get-IaCollection (Resolve-IaUri -Path "teams/$id/members") | ForEach-Object {
        [pscustomobject][ordered]@{ Name = $_.displayName; Email = $_.email; Roles = (@($_.roles) -join ', '); UserId = $_.userId; MembershipId = $_.id }
    })
}

function Add-EntraTeamMember {
    <#
    .SYNOPSIS
        Add a member (or owner) to a team. Beta POST /beta/teams/{id}/members.
    .PARAMETER Owner
        Add as an owner (default is a plain member).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Team,
        [Parameter(Mandatory, Position = 1)][string]$User,
        [switch]$Owner
    )
    $id     = Resolve-EntraGroupId -Group $Team
    $userId = if (Test-IaGuid $User) { $User } else { Resolve-EntraUserId -User $User }
    $body = [ordered]@{
        '@odata.type'    = '#microsoft.graph.aadUserConversationMember'
        roles            = @(if ($Owner) { 'owner' } else { @() })
        'user@odata.bind' = "https://graph.microsoft.com/beta/users('$userId')"
    }
    if ($PSCmdlet.ShouldProcess("$User → $Team", "Add team $(if ($Owner) { 'owner' } else { 'member' })")) {
        $m = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "teams/$id/members") -Body $body
        [pscustomobject]@{ Team = $Team; User = $User; Role = $(if ($Owner) { 'owner' } else { 'member' }); MembershipId = $m.id; Added = $true }
    }
}

function Remove-EntraTeamMember {
    <#
    .SYNOPSIS
        Remove a member from a team. Beta DELETE /beta/teams/{id}/members/{membershipId}.
    .DESCRIPTION
        Resolves the user to their team membership id, then removes it.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory, Position = 0)][string]$Team, [Parameter(Mandatory, Position = 1)][string]$User)
    $id     = Resolve-EntraGroupId -Group $Team
    $userId = if (Test-IaGuid $User) { $User } else { Resolve-EntraUserId -User $User }
    $member = @(Get-EntraTeamMember -Team $Team | Where-Object { $_.UserId -eq $userId }) | Select-Object -First 1
    if (-not $member) { throw "'$User' is not a member of team '$Team'." }
    if ($PSCmdlet.ShouldProcess("$User in $Team", 'Remove team member')) {
        Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri -Path "teams/$id/members/$($member.MembershipId)") | Out-Null
        [pscustomobject]@{ Team = $Team; User = $User; Removed = $true }
    }
}
