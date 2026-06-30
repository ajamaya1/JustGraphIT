function Set-IntuneAppAssignment {
    <#
    .SYNOPSIS
        Assign an Intune mobile app to groups, all devices, or all users.

    .DESCRIPTION
        Builds and submits an assignment payload to
        deviceAppManagement/mobileApps/{id}/assign. The app is resolved by GUID or
        display name. Group targets are resolved from display name or GUID.

        Use -Clear to remove every existing assignment from the app.

        Note: this cmdlet performs a FULL REPLACE — it overwrites every assignment
        already on the app with the ones you supply (the Graph /assign action replaces
        the whole set). To keep existing assignments, include them in this call. Because
        a single -Include can therefore wipe unrelated targets, the operation is treated
        as high-impact and prompts unless you pass -Confirm:$false.

    .PARAMETER AppId
        App display name or GUID (mandatory).

    .PARAMETER Include
        One or more group display names or GUIDs to add as include targets.

    .PARAMETER Exclude
        One or more group display names or GUIDs to add as exclude targets.

    .PARAMETER FilterId
        GUID of an assignment filter to attach to every target.

    .PARAMETER FilterType
        Whether the filter is applied as 'include' or 'exclude'. Default: include.

    .PARAMETER AllDevices
        Add an All Devices target (allDevicesAssignmentTarget).

    .PARAMETER AllUsers
        Add an All Users target (allLicensedUsersAssignmentTarget).

    .PARAMETER Clear
        Remove all existing assignments from the app (posts an empty assignments list).

    .EXAMPLE
        Set-IntuneAppAssignment -AppId 'Microsoft Teams' -Include 'SG-AllUsers'

        Assigns Teams to the SG-AllUsers group as a required install.

    .EXAMPLE
        Set-IntuneAppAssignment -AppId 'CompanyApp' -AllDevices -Exclude 'SG-Kiosks'

        Assigns to all devices, excluding the kiosk group.

    .EXAMPLE
        Set-IntuneAppAssignment -AppId 'CompanyApp' -Include 'SG-Pilot' `
            -FilterId 'f1234567-0000-0000-0000-000000000000' -FilterType include

        Assigns to SG-Pilot with an assignment filter applied.

    .EXAMPLE
        Set-IntuneAppAssignment -AppId 'OldApp' -Clear

        Removes all assignments from OldApp.

    .OUTPUTS
        PSCustomObject with properties: AppId, AssignedTo (count), Submitted.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$AppId,

        [string[]]$Include,

        [string[]]$Exclude,

        [string]$FilterId,

        [ValidateSet('include','exclude')][string]$FilterType = 'include',

        [switch]$AllDevices,

        [switch]$AllUsers,

        [switch]$Clear
    )

    # ── Resolve app ──────────────────────────────────────────────────────────
    $resolvedAppId = Resolve-IaAppId -Value $AppId

    # ── Build assignment list ─────────────────────────────────────────────────
    $assignments = [System.Collections.Generic.List[hashtable]]::new()

    if (-not $Clear) {
        # Helper: build a single assignment hashtable
        function New-IaAppAssignmentEntry {
            param(
                [string]$TargetType,
                [string]$GroupId
            )
            $target = [ordered]@{
                '@odata.type' = $TargetType
            }
            if ($GroupId) { $target['groupId'] = $GroupId }

            if ($FilterId) {
                $target['deviceAndAppManagementAssignmentFilterId']   = $FilterId
                $target['deviceAndAppManagementAssignmentFilterType'] = $FilterType
            }

            return @{
                '@odata.type' = '#microsoft.graph.mobileAppAssignment'
                intent        = 'required'
                target        = $target
            }
        }

        if ($AllDevices) {
            $assignments.Add((New-IaAppAssignmentEntry -TargetType '#microsoft.graph.allDevicesAssignmentTarget'))
        }

        if ($AllUsers) {
            $assignments.Add((New-IaAppAssignmentEntry -TargetType '#microsoft.graph.allLicensedUsersAssignmentTarget'))
        }

        foreach ($group in $Include) {
            $gid = Resolve-IaGroupId -Value $group
            $assignments.Add((New-IaAppAssignmentEntry -TargetType '#microsoft.graph.groupAssignmentTarget' -GroupId $gid))
        }

        foreach ($group in $Exclude) {
            $gid = Resolve-IaGroupId -Value $group
            $assignments.Add((New-IaAppAssignmentEntry -TargetType '#microsoft.graph.exclusionGroupAssignmentTarget' -GroupId $gid))
        }
    }

    $body = @{ mobileAppAssignments = $assignments.ToArray() }

    $action = if ($Clear) { 'clear all assignments from' } else { 'assign' }
    if (-not $PSCmdlet.ShouldProcess($AppId, "Set-IntuneAppAssignment: $action app")) { return }

    Invoke-IaRequest -Method POST `
        -Uri (Resolve-IaUri "deviceAppManagement/mobileApps/$resolvedAppId/assign") `
        -Body $body | Out-Null

    [pscustomobject][ordered]@{
        AppId      = $resolvedAppId
        AssignedTo = $assignments.Count
        Submitted  = [datetime]::UtcNow
    }
}

function Resolve-IaGroupId {
    <#
    .SYNOPSIS
        Resolves an Azure AD group display name or GUID to a GUID.
    #>
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Value)

    if (Test-IaGuid $Value) { return $Value }

    $encoded = ConvertTo-IaODataValue $Value
    $results = Get-IaCollection (Resolve-IaUri "groups?`$filter=displayName eq '$encoded'&`$select=id,displayName")

    if ($results.Count -eq 0) { throw "No group found matching '$Value'." }
    if ($results.Count -gt 1) { throw "Multiple groups match '$Value'. Provide a unique GUID." }

    $results[0].id
}
