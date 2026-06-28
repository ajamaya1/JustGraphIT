function Get-EntraGroup {
    <#
    .SYNOPSIS
        Find / list Entra groups and report their properties. Beta GET /beta/groups.
    .DESCRIPTION
        No -Group → list (optionally -Filter). -Group → one group. -Detailed adds owner
        and member counts. -Raw returns the untouched Graph object (every property).
    .OUTPUTS PSCustomObject.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Group,
        [string]$Filter,
        [int]$Top = 100,
        [switch]$Detailed,
        [switch]$Raw
    )
    $select = 'id,displayName,description,mail,mailNickname,mailEnabled,securityEnabled,' +
              'groupTypes,membershipRule,membershipRuleProcessingState,visibility,' +
              'isAssignableToRole,onPremisesSyncEnabled,createdDateTime,renewedDateTime,' +
              'expirationDateTime,classification,proxyAddresses'

    if (-not $Group) {
        $q = "groups?`$select=$select&`$top=$Top"
        if ($Filter) { $q += "&`$filter=$([uri]::EscapeDataString($Filter))" }
        return @(Get-IaCollection (Resolve-IaUri -Path $q) | ForEach-Object { ConvertTo-IaEntraGroup $_ })
    }

    $id  = Resolve-EntraGroupId -Group $Group
    $obj = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "groups/$id?`$select=$select")
    if ($Raw) { return $obj }
    $g = ConvertTo-IaEntraGroup $obj
    if ($Detailed) {
        $mc = $null; $oc = $null
        try { $mc = Get-IaCount "groups/$id/members/`$count" } catch { }
        try { $oc = Get-IaCount "groups/$id/owners/`$count" } catch { }
        $g | Add-Member -NotePropertyName MemberCount -NotePropertyValue $mc -Force
        $g | Add-Member -NotePropertyName OwnerCount  -NotePropertyValue $oc -Force
    }
    $g
}

function ConvertTo-IaEntraGroup {
    param($g)
    $kind = if ($g.groupTypes -contains 'Unified') { 'Microsoft 365' }
            elseif ($g.securityEnabled -and -not $g.mailEnabled) { 'Security' }
            elseif ($g.mailEnabled -and -not $g.securityEnabled) { 'Distribution' }
            else { 'Mail-enabled security' }
    $member = if ($g.groupTypes -contains 'DynamicMembership') { 'Dynamic' } else { 'Assigned' }
    [pscustomobject][ordered]@{
        DisplayName  = $g.displayName
        Type         = $kind
        Membership   = $member
        Mail         = $g.mail
        Description   = $g.description
        Rule         = $g.membershipRule
        RoleAssignable = [bool]$g.isAssignableToRole
        Visibility   = $g.visibility
        Synced       = [bool]$g.onPremisesSyncEnabled
        Created      = $g.createdDateTime
        Id           = $g.id
    }
}

function Get-EntraGroupMember {
    <#
    .SYNOPSIS
        List a group's members. Beta GET /beta/groups/{id}/members.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Group, [switch]$Transitive)
    $id   = Resolve-EntraGroupId -Group $Group
    $path = if ($Transitive) { "groups/$id/transitiveMembers" } else { "groups/$id/members" }
    @(Get-IaCollection (Resolve-IaUri -Path $path) | ForEach-Object {
        [pscustomobject][ordered]@{
            Name = $_.displayName
            UPN  = $_.userPrincipalName
            Mail = $_.mail
            Type = (($_.'@odata.type' -replace '#microsoft\.graph\.', ''))
            Id   = $_.id
        }
    })
}

function Get-EntraGroupOwner {
    <#
    .SYNOPSIS
        List a group's owners. Beta GET /beta/groups/{id}/owners.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Group)
    $id = Resolve-EntraGroupId -Group $Group
    @(Get-IaCollection (Resolve-IaUri -Path "groups/$id/owners?`$select=id,displayName,userPrincipalName,mail") | ForEach-Object {
        [pscustomobject][ordered]@{ Name = $_.displayName; UPN = $_.userPrincipalName; Mail = $_.mail; Id = $_.id }
    })
}

function New-EntraGroup {
    <#
    .SYNOPSIS
        Create a Security or Microsoft 365 group (optionally dynamic). Beta POST /beta/groups.
    .PARAMETER Type
        Security (default) or Microsoft365.
    .PARAMETER MembershipRule
        Supply to create a dynamic group (e.g. "user.department -eq \"Sales\"").
    .PARAMETER RoleAssignable
        Make a security group assignable to Entra roles (isAssignableToRole).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [string]$Description,
        [ValidateSet('Security', 'Microsoft365')][string]$Type = 'Security',
        [string]$MailNickname,
        [string]$MembershipRule,
        [switch]$RoleAssignable
    )
    if (-not $MailNickname) { $MailNickname = ($Name -replace '[^\w]', '') ; if (-not $MailNickname) { $MailNickname = 'group' } }
    $body = [ordered]@{
        displayName     = $Name
        description     = $Description
        mailNickname    = $MailNickname
        groupTypes      = @()
        mailEnabled     = ($Type -eq 'Microsoft365')
        securityEnabled = ($Type -eq 'Security')
    }
    if ($Type -eq 'Microsoft365') { $body.groupTypes = @('Unified') }
    if ($RoleAssignable)          { $body.isAssignableToRole = $true }
    if ($MembershipRule) {
        $body.groupTypes = @($body.groupTypes + 'DynamicMembership')
        $body.membershipRule = $MembershipRule
        $body.membershipRuleProcessingState = 'On'
    }
    if ($PSCmdlet.ShouldProcess($Name, "Create $Type group")) {
        $g = Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "groups") -Body $body
        ConvertTo-IaEntraGroup $g
    }
}

function Set-EntraGroup {
    <#
    .SYNOPSIS
        Update a group's name / description / dynamic rule. Beta PATCH /beta/groups/{id}.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Group,
        [string]$DisplayName, [string]$Description, [string]$MembershipRule
    )
    $id   = Resolve-EntraGroupId -Group $Group
    $body = [ordered]@{}
    if ($PSBoundParameters.ContainsKey('DisplayName'))    { $body.displayName = $DisplayName }
    if ($PSBoundParameters.ContainsKey('Description'))    { $body.description = $Description }
    if ($PSBoundParameters.ContainsKey('MembershipRule')) { $body.membershipRule = $MembershipRule; $body.membershipRuleProcessingState = 'On' }
    if ($body.Count -and $PSCmdlet.ShouldProcess($Group, 'Set-EntraGroup')) {
        Invoke-IaRequest -Method PATCH -Uri (Resolve-IaUri -Path "groups/$id") -Body $body | Out-Null
    }
    [pscustomobject]@{ Group = $Group; Updated = @($body.Keys) -join ', ' }
}

function Add-EntraGroupMember {
    <#
    .SYNOPSIS
        Add a member (user UPN or any directory-object id) to a group.
        Beta POST /beta/groups/{id}/members/$ref.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, Position = 0)][string]$Group, [Parameter(Mandatory, Position = 1)][string]$Member)
    $gid = Resolve-EntraGroupId -Group $Group
    $mid = if (Test-IaGuid $Member) { $Member } else { Resolve-EntraUserId -User $Member }
    if ($PSCmdlet.ShouldProcess("$Member → $Group", 'Add group member')) {
        Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "groups/$gid/members/`$ref") -Body @{ '@odata.id' = (Resolve-EntraDirectoryObjectRef $mid) } | Out-Null
        [pscustomobject]@{ Group = $Group; Member = $Member; Added = $true }
    }
}

function Remove-EntraGroupMember {
    <#
    .SYNOPSIS
        Remove a member from a group. Beta DELETE /beta/groups/{id}/members/{id}/$ref.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, Position = 0)][string]$Group, [Parameter(Mandatory, Position = 1)][string]$Member)
    $gid = Resolve-EntraGroupId -Group $Group
    $mid = if (Test-IaGuid $Member) { $Member } else { Resolve-EntraUserId -User $Member }
    if ($PSCmdlet.ShouldProcess("$Member → $Group", 'Remove group member')) {
        Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri -Path "groups/$gid/members/$mid/`$ref") | Out-Null
        [pscustomobject]@{ Group = $Group; Member = $Member; Removed = $true }
    }
}

function Add-EntraGroupOwner {
    <#
    .SYNOPSIS
        Add an owner (user) to a group. Beta POST /beta/groups/{id}/owners/$ref.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, Position = 0)][string]$Group, [Parameter(Mandatory, Position = 1)][string]$Owner)
    $gid = Resolve-EntraGroupId -Group $Group
    $oid = if (Test-IaGuid $Owner) { $Owner } else { Resolve-EntraUserId -User $Owner }
    if ($PSCmdlet.ShouldProcess("$Owner → $Group", 'Add group owner')) {
        Invoke-IaRequest -Method POST -Uri (Resolve-IaUri -Path "groups/$gid/owners/`$ref") -Body @{ '@odata.id' = (Resolve-EntraDirectoryObjectRef $oid) } | Out-Null
        [pscustomobject]@{ Group = $Group; Owner = $Owner; Added = $true }
    }
}

function Remove-EntraGroupOwner {
    <#
    .SYNOPSIS
        Remove an owner from a group. Beta DELETE /beta/groups/{id}/owners/{id}/$ref.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, Position = 0)][string]$Group, [Parameter(Mandatory, Position = 1)][string]$Owner)
    $gid = Resolve-EntraGroupId -Group $Group
    $oid = if (Test-IaGuid $Owner) { $Owner } else { Resolve-EntraUserId -User $Owner }
    if ($PSCmdlet.ShouldProcess("$Owner → $Group", 'Remove group owner')) {
        Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri -Path "groups/$gid/owners/$oid/`$ref") | Out-Null
        [pscustomobject]@{ Group = $Group; Owner = $Owner; Removed = $true }
    }
}

function Remove-EntraGroup {
    <#
    .SYNOPSIS
        Delete a group. Beta DELETE /beta/groups/{id}.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory, Position = 0)][string]$Group)
    $id = Resolve-EntraGroupId -Group $Group
    if ($PSCmdlet.ShouldProcess($Group, 'Delete group')) {
        Invoke-IaRequest -Method DELETE -Uri (Resolve-IaUri -Path "groups/$id") | Out-Null
        [pscustomobject]@{ Group = $Group; Deleted = $true }
    }
}
