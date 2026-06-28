function New-EntraGuestInvitation {
    <#
    .SYNOPSIS
        Invite an external (B2B guest) user into the tenant. Beta POST /beta/invitations.
    .DESCRIPTION
        Creates the guest account and (optionally) emails the invitation. Returns the
        new user's object id, status and the redemption URL — so you can hand the URL
        over even when -SendInvitationMessage is off. Needs User.Invite.All.
    .PARAMETER EmailAddress
        The external person's email address.
    .PARAMETER DisplayName
        Friendly name for the guest account (optional).
    .PARAMETER RedirectUrl
        Where the invite lands after redemption (default the My Apps portal).
    .PARAMETER SendInvitationMessage
        Email the invitation (default off — you get the redeem URL back to share).
    .PARAMETER CustomMessage
        A custom note included in the invitation email.
    .EXAMPLE
        New-EntraGuestInvitation -EmailAddress dana@contoso.com -DisplayName 'Dana (Contoso)' -SendInvitationMessage
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$EmailAddress,
        [string]$DisplayName,
        [string]$RedirectUrl = 'https://myapplications.microsoft.com',
        [switch]$SendInvitationMessage,
        [string]$CustomMessage
    )
    $body = [ordered]@{
        invitedUserEmailAddress = $EmailAddress
        inviteRedirectUrl       = $RedirectUrl
        sendInvitationMessage   = [bool]$SendInvitationMessage
    }
    if ($DisplayName)   { $body.invitedUserDisplayName = $DisplayName }
    if ($CustomMessage) { $body.invitedUserMessageInfo = @{ customizedMessageBody = $CustomMessage } }
    if ($PSCmdlet.ShouldProcess($EmailAddress, 'Invite external (guest) user')) {
        $r = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "invitations") -Body $body
        [pscustomobject]@{
            Email       = $EmailAddress
            DisplayName  = $r.invitedUserDisplayName
            UserId      = $r.invitedUser.id
            Status      = $r.status
            EmailSent   = [bool]$SendInvitationMessage
            RedeemUrl   = $r.inviteRedeemUrl
        }
    }
}

function New-EntraTeam {
    <#
    .SYNOPSIS
        Create a Microsoft 365 Team. Beta POST /beta/groups (Unified) then
        PUT /beta/groups/{id}/team to teamify it.
    .DESCRIPTION
        Creates the backing Microsoft 365 group with the owner bound at creation, then
        enables Teams on it. Teamify is retried briefly to ride out group replication.
        An owner is required (Teams will not enable on an ownerless group). Needs
        Group.ReadWrite.All + Team.Create (or Directory write).
    .PARAMETER Name
        The team / group display name.
    .PARAMETER Owner
        UPN or object id of the team owner (also added as a member).
    .PARAMETER Description
        Optional description.
    .PARAMETER Visibility
        Private (default) or Public.
    .EXAMPLE
        New-EntraTeam -Name 'Project Atlas' -Owner aaron@keebitfresh.com -Visibility Private
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Mandatory)][string]$Owner,
        [string]$Description,
        [ValidateSet('Public', 'Private')][string]$Visibility = 'Private'
    )
    if (-not $PSCmdlet.ShouldProcess($Name, "Create Microsoft 365 Team (owner $Owner)")) { return }
    $ownerId = Resolve-EntraUserId -User $Owner
    $nick    = ($Name -replace '[^\w]', ''); if (-not $nick) { $nick = 'team' }
    $groupBody = [ordered]@{
        displayName          = $Name
        description          = $Description
        mailNickname         = $nick
        groupTypes           = @('Unified')
        mailEnabled          = $true
        securityEnabled      = $false
        visibility           = $Visibility
        'owners@odata.bind'  = @("https://graph.microsoft.com/beta/users/$ownerId")
        'members@odata.bind' = @("https://graph.microsoft.com/beta/users/$ownerId")
    }
    $group = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "groups") -Body $groupBody

    # Teamify. The group can take a moment to replicate, so retry a few times — a 404
    # here means "not visible yet", which the central retry layer deliberately leaves
    # to the caller (it isn't a transient 5xx).
    $teamBody = @{
        memberSettings    = @{ allowCreateUpdateChannels = $true; allowCreatePrivateChannels = $true }
        messagingSettings = @{ allowUserEditMessages = $true; allowUserDeleteMessages = $true }
    }
    $team = $null; $lastErr = $null
    foreach ($try in 1..6) {
        try { $team = Invoke-IaRequest -Method PUT -Uri (Resolve-IaUri -Path "groups/$($group.id)/team") -Body $teamBody; break }
        catch { $lastErr = $_; Start-Sleep -Seconds 5 }
    }
    if (-not $team) {
        Write-Warning "Group '$Name' created ($($group.id)) but teamify is still pending ($($lastErr.Exception.Message)). It usually completes within a minute — re-run or check Teams."
    }
    [pscustomobject]@{
        Name       = $Name
        GroupId    = $group.id
        TeamId     = if ($team) { $team.id } else { $group.id }
        Owner      = $Owner
        Visibility = $Visibility
        Teamified  = [bool]$team
    }
}
