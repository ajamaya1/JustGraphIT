#requires -Modules Pester
# Pester v5 — fully offline (Graph mocked at Invoke-IaRequest seam).
# Run from the module folder:  Invoke-Pester -Output Detailed

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'IntuneTide.psd1') -Force
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Resource registry' {

    It 'has unique keys' {
        InModuleScope IntuneTide {
            $reg = Get-IaResourceRegistry
            ($reg.Key | Select-Object -Unique).Count | Should -Be $reg.Count
        }
    }

    It 'covers all expected areas' {
        InModuleScope IntuneTide {
            $areas = (Get-IaResourceRegistry).Area | Select-Object -Unique
            $areas | Should -Contain 'Configuration'
            $areas | Should -Contain 'Compliance'
            $areas | Should -Contain 'Scripts'
            $areas | Should -Contain 'Remediations'
            $areas | Should -Contain 'Windows Update'
            $areas | Should -Contain 'Endpoint security'
            $areas | Should -Contain 'Enrollment'
            $areas | Should -Contain 'Apps'
            $areas | Should -Contain 'App protection'
            $areas | Should -Contain 'Cloud PC'
            $areas | Should -Contain 'Scope tags'
        }
    }

    It 'contains key landmarks by key name' {
        InModuleScope IntuneTide {
            $keys = (Get-IaResourceRegistry).Key
            $keys | Should -Contain 'cloudPcProvisioningPolicies'
            $keys | Should -Contain 'roleScopeTags'
            $keys | Should -Contain 'mobileApps'
            $keys | Should -Contain 'deviceHealthScripts'
            $keys | Should -Contain 'windowsManagedAppProtections'
            $keys | Should -Contain 'mdmWindowsInformationProtectionPolicies'
            $keys | Should -Contain 'intents'
        }
    }

    It 'resolves types by area' {
        InModuleScope IntuneTide {
            $apps = Resolve-IaResourceType -Area 'Apps'
            $apps.Key | Should -Contain 'mobileApps'
            $apps.Key | Should -Contain 'mobileAppConfigurations'
            $apps.Key | Should -Contain 'targetedManagedAppConfigurations'
        }
    }

    It 'resolves types by key' {
        InModuleScope IntuneTide {
            $r = Resolve-IaResourceType -Type 'intents'
            $r.Count | Should -Be 1
            $r[0].Area | Should -Be 'Endpoint security'
        }
    }

    It 'resolves multiple areas at once' {
        InModuleScope IntuneTide {
            $r = Resolve-IaResourceType -Area 'Scripts', 'Remediations'
            $r.Key | Should -Contain 'deviceManagementScripts'
            $r.Key | Should -Contain 'deviceShellScripts'
            $r.Key | Should -Contain 'deviceHealthScripts'
        }
    }

    It 'returns all entries when no filter given' {
        InModuleScope IntuneTide {
            $all  = Get-IaResourceRegistry
            $none = Resolve-IaResourceType
            $none.Count | Should -Be $all.Count
        }
    }

    It 'all entries have non-empty ListPath' {
        InModuleScope IntuneTide {
            $reg = Get-IaResourceRegistry
            foreach ($r in $reg) {
                $r.ListPath | Should -Not -BeNullOrEmpty -Because "key=$($r.Key)"
            }
        }
    }

    It 'app area paths use deviceAppManagement prefix' {
        InModuleScope IntuneTide {
            $appKeys = 'mobileApps', 'mobileAppConfigurations',
                       'targetedManagedAppConfigurations',
                       'iosManagedAppProtections', 'androidManagedAppProtections',
                       'windowsManagedAppProtections',
                       'mdmWindowsInformationProtectionPolicies'
            $reg = Get-IaResourceRegistry
            foreach ($key in $appKeys) {
                $entry = $reg | Where-Object Key -eq $key
                $entry | Should -Not -BeNullOrEmpty -Because "key=$key should exist"
                $entry.ListPath | Should -Match '^deviceAppManagement/' -Because "key=$key must use deviceAppManagement"
            }
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Graph URI construction' {

    It 'builds beta URI for plain path' {
        InModuleScope IntuneTide {
            Resolve-IaUri -Path 'deviceManagement/managedDevices' |
                Should -Be 'https://graph.microsoft.com/beta/deviceManagement/managedDevices'
        }
    }

    It 'resolves -V1 to the beta endpoint too (module standardizes on beta)' {
        InModuleScope IntuneTide {
            Resolve-IaUri -Path 'me' -V1 |
                Should -Be 'https://graph.microsoft.com/beta/me'
        }
    }

    It 'uses the beta base for every Graph call (no v1.0 anywhere)' {
        InModuleScope IntuneTide {
            (Resolve-IaUri -Path 'groups')       | Should -Match '/beta/'
            (Resolve-IaUri -Path 'groups' -V1)   | Should -Match '/beta/'
            (Resolve-IaUri -Path 'groups')       | Should -Not -Match '/v1\.0/'
            (Resolve-IaUri -Path 'groups' -V1)   | Should -Not -Match '/v1\.0/'
        }
    }

    It 'returns absolute URLs unchanged' {
        InModuleScope IntuneTide {
            $abs = 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?$skiptoken=xyz'
            Resolve-IaUri -Path $abs | Should -Be $abs
        }
    }

    It 'strips leading slash from path' {
        InModuleScope IntuneTide {
            Resolve-IaUri -Path '/deviceManagement/intents' |
                Should -Be 'https://graph.microsoft.com/beta/deviceManagement/intents'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'GUID detection' {

    It 'accepts a valid GUID' {
        InModuleScope IntuneTide {
            Test-IaGuid '12345678-1234-1234-1234-123456789012' | Should -BeTrue
        }
    }

    It 'rejects a plain string' {
        InModuleScope IntuneTide {
            Test-IaGuid 'My Policy Name' | Should -BeFalse
        }
    }

    It 'rejects an empty string' {
        InModuleScope IntuneTide {
            Test-IaGuid '' | Should -BeFalse
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Error code resolution' {

    It 'resolves known Win32 hex code' {
        InModuleScope IntuneTide {
            $r = Resolve-IaErrorCode '0x87D1041C'
            $r | Should -Not -BeNullOrEmpty
            $r.Short | Should -Be 'App not detected post-install'
            $r.Hint  | Should -Match 'detection rules'
        }
    }

    It 'resolves signed-negative decimal (same code)' {
        InModuleScope IntuneTide {
            $r = Resolve-IaErrorCode (-2016345060)   # 0x87D1041C as Int32
            $r | Should -Not -BeNullOrEmpty
            $r.Short | Should -Be 'App not detected post-install'
        }
    }

    It 'resolves 0x87D1041A installation-failed code' {
        InModuleScope IntuneTide {
            (Resolve-IaErrorCode '0x87D1041A').Short | Should -Be 'Installation failed'
        }
    }

    It 'resolves 0x80070005 access-denied code' {
        InModuleScope IntuneTide {
            (Resolve-IaErrorCode '0x80070005').Short | Should -Be 'Access denied'
        }
    }

    It 'returns null for zero' {
        InModuleScope IntuneTide {
            Resolve-IaErrorCode 0 | Should -BeNullOrEmpty
        }
    }

    It 'returns null for unknown code' {
        InModuleScope IntuneTide {
            Resolve-IaErrorCode '0xDEADBEEF' | Should -BeNullOrEmpty
        }
    }

    It 'resolves friendly installStateDetail label' {
        InModuleScope IntuneTide {
            Resolve-IaInstallDetail 'installFailed'  | Should -Be 'Installation failed'
            Resolve-IaInstallDetail 'rebootRequired' | Should -Be 'Reboot required'
        }
    }

    It 'falls through to raw string for unknown detail' {
        InModuleScope IntuneTide {
            Resolve-IaInstallDetail 'somethingnew' | Should -Be 'somethingnew'
        }
    }

    It 'returns null for empty detail' {
        InModuleScope IntuneTide {
            Resolve-IaInstallDetail '' | Should -BeNullOrEmpty
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'PIM duration parser' {

    It 'passes through ISO8601 duration unchanged' {
        InModuleScope IntuneTide {
            ConvertTo-IaIsoDuration 'PT2H' | Should -Be 'PT2H'
            ConvertTo-IaIsoDuration 'P1D'  | Should -Be 'P1D'
        }
    }

    It 'converts hours shorthand' {
        InModuleScope IntuneTide {
            ConvertTo-IaIsoDuration '8h' | Should -Be 'PT8H'
            ConvertTo-IaIsoDuration '1h' | Should -Be 'PT1H'
        }
    }

    It 'converts minutes shorthand' {
        InModuleScope IntuneTide {
            ConvertTo-IaIsoDuration '30m' | Should -Be 'PT30M'
        }
    }

    It 'converts days shorthand' {
        InModuleScope IntuneTide {
            ConvertTo-IaIsoDuration '1d' | Should -Be 'P1D'
        }
    }

    It 'throws on invalid format' {
        InModuleScope IntuneTide {
            { ConvertTo-IaIsoDuration 'garbage' } | Should -Throw
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Assignment model — target conversion' {

    It 'parses allDevices target' {
        InModuleScope IntuneTide {
            $t = ConvertFrom-IaTarget -Target ([pscustomobject]@{
                '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' })
            $t.Kind      | Should -Be 'allDevices'
            $t.IsExclude | Should -BeFalse
            $t.GroupId   | Should -BeNullOrEmpty
        }
    }

    It 'parses allLicensedUsers target' {
        InModuleScope IntuneTide {
            $t = ConvertFrom-IaTarget -Target ([pscustomobject]@{
                '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget' })
            $t.Kind | Should -Be 'allUsers'
        }
    }

    It 'parses exclusionGroup target' {
        InModuleScope IntuneTide {
            $t = ConvertFrom-IaTarget -Target ([pscustomobject]@{
                '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'; groupId = 'g99' })
            $t.Kind      | Should -Be 'exclusion'
            $t.IsExclude | Should -BeTrue
            $t.GroupId   | Should -Be 'g99'
        }
    }

    It 'parses a group target with a filter' {
        InModuleScope IntuneTide {
            $t = ConvertFrom-IaTarget -Target ([pscustomobject]@{
                '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'g1'
                deviceAndAppManagementAssignmentFilterId   = 'f1'
                deviceAndAppManagementAssignmentFilterType = 'include' })
            $t.Kind       | Should -Be 'group'
            $t.IsExclude  | Should -BeFalse
            $t.FilterType | Should -Be 'include'
            $t.FilterId   | Should -Be 'f1'
        }
    }

    It 'preserves Cloud PC @odata.type on roundtrip' {
        InModuleScope IntuneTide {
            $t = ConvertFrom-IaTarget -Target ([pscustomobject]@{
                '@odata.type' = '#microsoft.graph.cloudPcManagementGroupAssignmentTarget'; groupId = 'g1' })
            $t.Kind | Should -Be 'group'
            (ConvertTo-IaTargetBody -Target $t)['@odata.type'] |
                Should -Be '#microsoft.graph.cloudPcManagementGroupAssignmentTarget'
        }
    }

    It 'synthesises correct @odata.type for exclusion when no original' {
        InModuleScope IntuneTide {
            $t = New-IaGroupTarget -GroupId 'gx' -Exclude
            $body = ConvertTo-IaTargetBody -Target $t
            $body['@odata.type'] | Should -Be '#microsoft.graph.exclusionGroupAssignmentTarget'
            $body.groupId        | Should -Be 'gx'
        }
    }

    It 'adds filter fields to body when FilterId is set' {
        InModuleScope IntuneTide {
            $t = New-IaGroupTarget -GroupId 'gf' -FilterId 'fid1' -FilterType 'exclude'
            $body = ConvertTo-IaTargetBody -Target $t
            $body.deviceAndAppManagementAssignmentFilterId   | Should -Be 'fid1'
            $body.deviceAndAppManagementAssignmentFilterType | Should -Be 'exclude'
        }
    }

    It 'omits filter fields when no FilterId' {
        InModuleScope IntuneTide {
            $t = New-IaGroupTarget -GroupId 'gnofilter'
            $body = ConvertTo-IaTargetBody -Target $t
            $body.ContainsKey('deviceAndAppManagementAssignmentFilterId') | Should -BeFalse
        }
    }

    It 'handles unknown @odata.type gracefully' {
        InModuleScope IntuneTide {
            $t = ConvertFrom-IaTarget -Target ([pscustomobject]@{
                '@odata.type' = '#microsoft.graph.someFutureTarget'; groupId = 'gunk' })
            $t.Kind | Should -Be 'unknown'
        }
    }

    It 'Get-IaTargetDisplay shows All Devices label' {
        InModuleScope IntuneTide {
            $t = ConvertFrom-IaTarget -Target ([pscustomobject]@{
                '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' })
            Get-IaTargetDisplay -Target $t | Should -Be 'All Devices'
        }
    }

    It 'Get-IaTargetDisplay prefixes EXCLUDE for exclusion' {
        InModuleScope IntuneTide {
            $t = [pscustomobject]@{ Kind = 'exclusion'; IsExclude = $true; GroupId = 'gid';
                GroupName = 'Test Group'; FilterId = $null; FilterType = 'none'; FilterName = $null }
            Get-IaTargetDisplay -Target $t | Should -Match '^EXCLUDE Test Group'
        }
    }

    It 'Get-IaTargetDisplay appends filter label' {
        InModuleScope IntuneTide {
            $t = [pscustomobject]@{ Kind = 'group'; IsExclude = $false; GroupId = 'gid';
                GroupName = 'MyGroup'; FilterId = 'fid'; FilterType = 'include'; FilterName = 'Windows Filter' }
            Get-IaTargetDisplay -Target $t | Should -Match 'filter include: Windows Filter'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Assignment model — assignment conversion' {

    It 'preserves type-specific fields (remediation runSchedule)' {
        InModuleScope IntuneTide {
            $a = ConvertFrom-IaAssignment -Item ([pscustomobject]@{
                id = 'x'; source = 'direct'
                target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'g1' }
                runRemediationScript = $true
                runSchedule = [pscustomobject]@{ interval = 1 } })
            $body = ConvertTo-IaAssignmentBody -Assignment $a
            $body.runRemediationScript | Should -BeTrue
            $body.runSchedule.interval | Should -Be 1
            $body.ContainsKey('id')    | Should -BeFalse
        }
    }

    It 'strips source and sourceId from body' {
        InModuleScope IntuneTide {
            $a = ConvertFrom-IaAssignment -Item ([pscustomobject]@{
                id = 'y'; source = 'policySets'; sourceId = 'ps1'
                target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' } })
            $body = ConvertTo-IaAssignmentBody -Assignment $a
            $body.ContainsKey('source')   | Should -BeFalse
            $body.ContainsKey('sourceId') | Should -BeFalse
        }
    }

    It 'injects @odata.type when AssignmentODataType is provided' {
        InModuleScope IntuneTide {
            $a = ConvertFrom-IaAssignment -Item ([pscustomobject]@{
                id = 'z'
                target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' } })
            $body = ConvertTo-IaAssignmentBody -Assignment $a -AssignmentODataType '#microsoft.graph.mobileAppAssignment'
            $body['@odata.type'] | Should -Be '#microsoft.graph.mobileAppAssignment'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Directory cache — group resolution' {

    BeforeEach {
        InModuleScope IntuneTide { Reset-IaDirectoryCache }
    }

    It 'returns display name from cache after first fetch' {
        InModuleScope IntuneTide {
            Mock Invoke-IaRequest {
                return [pscustomobject]@{ id = 'gid1'; displayName = 'Engineering' }
            }
            $name = Resolve-IaGroupName -Id 'gid1'
            $name | Should -Be 'Engineering'
            # Second call must not hit Graph again
            Should -Invoke Invoke-IaRequest -Times 1 -Exactly
            $name2 = Resolve-IaGroupName -Id 'gid1'
            $name2 | Should -Be 'Engineering'
            Should -Invoke Invoke-IaRequest -Times 1 -Exactly
        }
    }

    It 'stubs unresolvable group with truncated id' {
        InModuleScope IntuneTide {
            Mock Invoke-IaRequest { throw 'Not Found' }
            $name = Resolve-IaGroupName -Id 'abcdef12-0000-0000-0000-000000000000'
            $name | Should -Match 'unresolved'
        }
    }

    It 'blocks further fetches after 403' {
        InModuleScope IntuneTide {
            Mock Invoke-IaRequest { throw 'Forbidden 403' }
            $null = Resolve-IaGroupName -Id 'gid-forbidden'
            $script:IaDirectoryBlocked | Should -BeTrue
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Call log' {

    It 'Add-IaCall records method, shortened URI, status and count' {
        InModuleScope IntuneTide {
            Clear-IaCallLog
            $fullUri = 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?$select=id,name'
            Add-IaCall -Method 'GET' -Uri $fullUri -Status 200 -Ms 55 -Count 7
            $log = Get-IaCallLogEntries
            $log.Count     | Should -Be 1
            $log[0].Method | Should -Be 'GET'
            $log[0].Status | Should -Be 200
            $log[0].Count  | Should -Be 7
            $log[0].Uri    | Should -Match 'configurationPolicies'
            # Graph base URL should be stripped
            $log[0].Uri    | Should -Not -Match 'graph\.microsoft\.com'
        }
    }

    It 'Add-IaCall replaces query string with ellipsis' {
        InModuleScope IntuneTide {
            Clear-IaCallLog
            Add-IaCall -Method 'GET' `
                -Uri 'https://graph.microsoft.com/beta/deviceManagement/managedDevices?$filter=x' `
                -Status 200 -Ms 10 -Count 0
            (Get-IaCallLogEntries)[0].Uri | Should -Match '\?…'
        }
    }

    It 'Clear-IaCallLog empties the log' {
        InModuleScope IntuneTide {
            Add-IaCall -Method 'GET' -Uri 'https://graph.microsoft.com/beta/foo' -Status 200 -Ms 1 -Count 0
            Clear-IaCallLog
            (Get-IaCallLogEntries).Count | Should -Be 0
        }
    }

    It 'reports the correct count for many entries (entries have a colliding .Count property)' {
        InModuleScope IntuneTide {
            Clear-IaCallLog
            1..5 | ForEach-Object { Add-IaCall -Method 'GET' -Uri "https://graph.microsoft.com/beta/x$_" -Status 200 -Ms 1 -Count 9 }
            $entries = Get-IaCallLogEntries
            $entries = @($entries)
            $entries.Count | Should -Be 5 -Because 'direct-assign then @($var) must not collapse'
        }
    }

    It 'Get-IntuneCallLog (public) returns one object per recorded call' {
        InModuleScope IntuneTide {
            Clear-IaCallLog
            1..4 | ForEach-Object { Add-IaCall -Method 'GET' -Uri "https://graph.microsoft.com/beta/y$_" -Status 200 -Ms 1 -Count 3 }
            @(Get-IntuneCallLog).Count       | Should -Be 4
            @(Get-IntuneCallLog -Tail 2).Count | Should -Be 2
        }
    }

    It 'Get-IntuneCallLog returns a single entry as one object, not its Count property' {
        InModuleScope IntuneTide {
            Clear-IaCallLog
            Add-IaCall -Method 'GET' -Uri 'https://graph.microsoft.com/beta/solo' -Status 200 -Ms 1 -Count 9
            @(Get-IntuneCallLog).Count | Should -Be 1 -Because 'one call logged → one row, despite the entry.Count=9 field'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Inventory, compare and copy (mocked Graph)' {

    BeforeEach {
        InModuleScope IntuneTide {
            Reset-IaDirectoryCache
            $script:Posts = [System.Collections.Generic.List[object]]::new()
            $script:Groups = @{
                'aaaa' = 'All Workstations'
                'bbbb' = 'Pilot Ring'
                'cccc' = 'New Devices'
            }
            function script:tgt($id, $excl) {
                [pscustomobject]@{
                    '@odata.type' = $(if ($excl) { '#microsoft.graph.exclusionGroupAssignmentTarget' }
                                     else        { '#microsoft.graph.groupAssignmentTarget' })
                    groupId = $id
                }
            }
            Mock Invoke-IaRequest {
                if ($Method -eq 'POST') {
                    $script:Posts.Add([pscustomobject]@{ Uri = $Uri; Body = $Body })
                    return $null
                }
                if ($Uri -match '/members/\$count')  { return 0 }
                if ($Uri -match 'assignmentFilters') { return [pscustomobject]@{ value = @() } }
                if ($Uri -match '/groups/([^?]+)') {
                    $gid = $Matches[1]
                    if ($script:Groups.ContainsKey($gid)) {
                        return [pscustomobject]@{ id = $gid; displayName = $script:Groups[$gid] }
                    }
                    throw 'not found'
                }
                if ($Uri -match 'configurationPolicies') {
                    return [pscustomobject]@{ value = @(
                        [pscustomobject]@{ id = 'cp1'; name = 'Win Baseline'; '@odata.type' = '#x'
                            assignments = @(
                                [pscustomobject]@{ target = (tgt 'aaaa' $false) }
                                [pscustomobject]@{ target = (tgt 'bbbb' $true)  }) }
                        [pscustomobject]@{ id = 'cp2'; name = 'Only-A'; '@odata.type' = '#x'
                            assignments = @([pscustomobject]@{ target = (tgt 'aaaa' $false) }) }
                    ) }
                }
                return [pscustomobject]@{ value = @() }
            }
        }
    }

    It 'enumerates and resolves group names + exclude intent' {
        InModuleScope IntuneTide {
            $items = Get-IaInventory -Type 'configurationPolicies' -AssignedOnly
            $cp = $items | Where-Object Name -eq 'Win Baseline'
            ($cp.Assignments | Where-Object { -not $_.Target.IsExclude }).Target.GroupName |
                Should -Be 'All Workstations'
            ($cp.Assignments | Where-Object { $_.Target.IsExclude }).Target.GroupName |
                Should -Be 'Pilot Ring'
        }
    }

    It 'compares two groups into buckets' {
        InModuleScope IntuneTide {
            $items = Get-IaInventory -Type 'configurationPolicies' -AssignedOnly
            (Get-IaItemGroupMode -Item ($items | Where-Object Name -eq 'Win Baseline') -GroupId 'bbbb') |
                Should -Be 'exclude'
            (Get-IaItemGroupMode -Item ($items | Where-Object Name -eq 'Only-A') -GroupId 'bbbb') |
                Should -Be 'none'
        }
    }

    It 'detects mixed include+exclude on same group' {
        InModuleScope IntuneTide {
            Mock Invoke-IaRequest {
                if ($Method -eq 'POST') { $script:Posts.Add([pscustomobject]@{ Uri = $Uri; Body = $Body }); return $null }
                if ($Uri -match 'assignmentFilters') { return [pscustomobject]@{ value = @() } }
                if ($Uri -match '/groups/') { return [pscustomobject]@{ id = 'gx'; displayName = 'Mixed' } }
                return [pscustomobject]@{ value = @(
                    [pscustomobject]@{ id = 'mx'; name = 'Mixed Policy'; '@odata.type' = '#x'
                        assignments = @(
                            [pscustomobject]@{ target = (tgt 'gx' $false) }
                            [pscustomobject]@{ target = (tgt 'gx' $true)  }) }
                ) }
            }
            $items = Get-IaInventory -Type 'configurationPolicies'
            $mode = Get-IaItemGroupMode -Item ($items | Where-Object Name -eq 'Mixed Policy') -GroupId 'gx'
            $mode | Should -Be 'mixed'
        }
    }

    It 'copies selected resources and posts merged assignments' {
        InModuleScope IntuneTide {
            $items = Get-IaInventory -Type 'configurationPolicies' -AssignedOnly
            $plans = Invoke-IaCopy -Items $items -SrcId 'aaaa' -DstId 'cccc' -DstName 'New Devices' -IncludeIds @('cp2') -Commit
            @($plans | Where-Object Added).Count | Should -Be 1
            $script:Posts.Count                  | Should -Be 1
            $script:Posts[0].Uri                 | Should -Match 'configurationPolicies/cp2/assign'
        }
    }

    It 'preview (no -Commit) writes nothing' {
        InModuleScope IntuneTide {
            $items = Get-IaInventory -Type 'configurationPolicies' -AssignedOnly
            $null = Invoke-IaCopy -Items $items -SrcId 'aaaa' -DstId 'cccc'
            $script:Posts.Count | Should -Be 0
        }
    }

    It 'AssignedOnly filters out unassigned items' {
        InModuleScope IntuneTide {
            Mock Invoke-IaRequest {
                if ($Uri -match 'assignmentFilters') { return [pscustomobject]@{ value = @() } }
                return [pscustomobject]@{ value = @(
                    [pscustomobject]@{ id = 'p1'; name = 'Has Assignment'; '@odata.type' = '#x'
                        assignments = @([pscustomobject]@{ target = (tgt 'aaaa' $false) }) }
                    [pscustomobject]@{ id = 'p2'; name = 'No Assignments'; '@odata.type' = '#x'
                        assignments = @() }
                ) }
            }
            $assigned = Get-IaInventory -Type 'configurationPolicies' -AssignedOnly
            $assigned.Count | Should -Be 1
            $assigned[0].Name | Should -Be 'Has Assignment'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Public cmdlets — Get-IntuneAssignmentFilter' {

    It 'returns all filters when no platform specified' {
        InModuleScope IntuneTide {
            Reset-IaDirectoryCache
            Mock Invoke-IaRequest {
                return [pscustomobject]@{ value = @(
                    [pscustomobject]@{ id = 'f1'; displayName = 'Win Filter'; platform = 'windows10AndLater' }
                    [pscustomobject]@{ id = 'f2'; displayName = 'iOS Filter'; platform = 'iOS' }
                ) }
            }
            $result = Get-IntuneAssignmentFilter
            $result.Count | Should -Be 2
        }
    }

    It 'passes platform filter to Graph URI' {
        InModuleScope IntuneTide {
            Reset-IaDirectoryCache
            $uris = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-IaRequest {
                $uris.Add($Uri)
                return [pscustomobject]@{ value = @() }
            }
            Get-IntuneAssignmentFilter -Platform Windows
            ($uris -join '|') | Should -Match 'windows10AndLater'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Public cmdlets — Get-IntuneApp' {

    It 'queries deviceAppManagement (not deviceManagement)' {
        InModuleScope IntuneTide {
            $uris = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-IaRequest {
                $uris.Add($Uri)
                return [pscustomobject]@{ value = @() }
            }
            Get-IntuneApp
            ($uris -join '|') | Should -Match 'deviceAppManagement/mobileApps'
            ($uris -join '|') | Should -Not -Match '[^A-Za-z]deviceManagement/mobileApps'
        }
    }

    It 'returns app objects with expected properties' {
        InModuleScope IntuneTide {
            Mock Invoke-IaRequest {
                return [pscustomobject]@{ value = @(
                    [pscustomobject]@{ id = 'app1'; displayName = 'Contoso App';
                        '@odata.type' = '#microsoft.graph.win32LobApp'
                        publishingState = 'published'; platform = 'windows10AndLater' }
                ) }
            }
            $apps = Get-IntuneApp
            $apps.Count   | Should -Be 1
            $apps[0].Name | Should -Be 'Contoso App'
            $apps[0].Id   | Should -Be 'app1'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Public cmdlets — Get-IntuneScript' {

    It 'lists all scripts across both platforms' {
        InModuleScope IntuneTide {
            $uris = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-IaRequest {
                $uris.Add($Uri)
                return [pscustomobject]@{ value = @() }
            }
            Get-IntuneScript
            $joined = $uris -join '|'
            $joined | Should -Match 'deviceManagementScripts'
            $joined | Should -Match 'deviceShellScripts'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Public cmdlets — Get-IntuneRemediation' {

    It 'queries deviceHealthScripts' {
        InModuleScope IntuneTide {
            $uris = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-IaRequest {
                $uris.Add($Uri)
                return [pscustomobject]@{ value = @() }
            }
            Get-IntuneRemediation
            ($uris -join '|') | Should -Match 'deviceHealthScripts'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Public cmdlets — Get-IntuneCompliancePolicy' {

    It 'queries deviceCompliancePolicies' {
        InModuleScope IntuneTide {
            $uris = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-IaRequest {
                $uris.Add($Uri)
                return [pscustomobject]@{ value = @() }
            }
            Get-IntuneCompliancePolicy
            ($uris -join '|') | Should -Match 'deviceCompliancePolicies'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Public cmdlets — Get-IntuneConfigurationPolicy' {

    It 'queries configurationPolicies (settings catalog)' {
        InModuleScope IntuneTide {
            $uris = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-IaRequest {
                $uris.Add($Uri)
                return [pscustomobject]@{ value = @() }
            }
            Get-IntuneConfigurationPolicy
            ($uris -join '|') | Should -Match 'configurationPolicies'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Public cmdlets — Get-IntuneUpdateRing' {

    It 'queries deviceConfigurations' {
        InModuleScope IntuneTide {
            $uris = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-IaRequest {
                $uris.Add($Uri)
                return [pscustomobject]@{ value = @() }
            }
            Get-IntuneUpdateRing
            ($uris -join '|') | Should -Match 'deviceConfigurations'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Public cmdlets — Get-IntuneAppProtectionPolicy' {

    It 'queries both Windows protection policy endpoints' {
        InModuleScope IntuneTide {
            $uris = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-IaRequest {
                $uris.Add($Uri)
                return [pscustomobject]@{ value = @() }
            }
            Get-IntuneAppProtectionPolicy -Platform Windows
            $joined = $uris -join '|'
            $joined | Should -Match 'mdmWindowsInformationProtectionPolicies'
            $joined | Should -Match 'windowsManagedAppProtections'
        }
    }

    It 'queries only iOS endpoint for iOS platform' {
        InModuleScope IntuneTide {
            $uris = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-IaRequest {
                $uris.Add($Uri)
                return [pscustomobject]@{ value = @() }
            }
            Get-IntuneAppProtectionPolicy -Platform iOS
            $joined = $uris -join '|'
            $joined | Should -Match 'iosManagedAppProtections'
            $joined | Should -Not -Match 'windowsManagedAppProtections'
        }
    }

    It 'queries Android endpoint for Android platform' {
        InModuleScope IntuneTide {
            $uris = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-IaRequest {
                $uris.Add($Uri)
                return [pscustomobject]@{ value = @() }
            }
            Get-IntuneAppProtectionPolicy -Platform Android
            $joined = $uris -join '|'
            $joined | Should -Match 'androidManagedAppProtections'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Public cmdlets — Get-IntuneDeviceDetail' {

    It 'uses managedDeviceOwnerType (not ownerType)' {
        InModuleScope IntuneTide {
            Mock Invoke-IaRequest {
                # Resolve-IaManagedDeviceId by GUID skips the filter call; return full device record
                return [pscustomobject]@{
                    id = '12345678-0000-0000-0000-000000000001'
                    deviceName = 'DESKTOP-001'; operatingSystem = 'Windows'
                    osVersion = '10.0.22631'; complianceState = 'compliant'
                    managedDeviceOwnerType = 'company'; lastSyncDateTime = '2025-01-01T00:00:00Z'
                    userPrincipalName = 'user@contoso.com'
                    value = $null
                }
            }
            $dev = Get-IntuneDeviceDetail -Device '12345678-0000-0000-0000-000000000001'
            $dev.OwnerType | Should -Be 'company'
        }
    }

    It 'reads ipAddressV4 from hardwareInformation and drops the nonexistent activationLockEnabled' {
        InModuleScope IntuneTide {
            Mock Invoke-IaRequest {
                if ($Uri -match 'select=hardwareInformation') {
                    return [pscustomobject]@{ hardwareInformation = [pscustomobject]@{ ipAddressV4 = '10.1.2.3' } }
                }
                # top-level ipAddressV4 is WRONG (not a managedDevice property); must be ignored
                return [pscustomobject]@{ id = 'dev-1'; deviceName = 'PC'; ipAddressV4 = 'WRONG'; activationLockEnabled = $true }
            }
            $dev = Get-IntuneDeviceDetail -Device '12345678-0000-0000-0000-000000000002'
            $dev.IPAddressV4                          | Should -Be '10.1.2.3'    # from hardwareInformation
            $dev.PSObject.Properties['ActivationLock'] | Should -BeNullOrEmpty   # field removed — no such Graph property
        }
    }
}

Describe 'Public cmdlets — Get-IntuneLapsCredential' {

    It 'resolves the AAD device id and decodes the base64 password (newest backup first)' {
        InModuleScope IntuneTide {
            Mock Invoke-IaRequest {
                if ($Uri -match 'deviceLocalCredentials') {
                    return [pscustomobject]@{ credentials = @(
                        [pscustomobject]@{ accountName='Administrator'; accountSid='S-1-5-21-1'; backupDateTime='2026-06-20T00:00:00Z'
                                           passwordBase64=([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('old-pass'))) }
                        [pscustomobject]@{ accountName='Administrator'; accountSid='S-1-5-21-1'; backupDateTime='2026-06-26T00:00:00Z'
                                           passwordBase64=([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('P@ssw0rd-NEW!'))) }
                    ) }
                }
                return [pscustomobject]@{ id='dev-1'; deviceName='DESKTOP-001'; azureADDeviceId='aad-guid-1' }
            }
            $r = @(Get-IntuneLapsCredential -Device '12345678-0000-0000-0000-000000000001')
            $r[0].Account  | Should -Be 'Administrator'
            $r[0].Password | Should -Be 'P@ssw0rd-NEW!'     # newest backup decoded & first
            $r[0].Device   | Should -Be 'DESKTOP-001'
            $r[1].Password | Should -Be 'old-pass'
        }
    }

    It 'throws when the device has no Azure AD device id' {
        InModuleScope IntuneTide {
            Mock Invoke-IaRequest { [pscustomobject]@{ id='dev-1'; deviceName='WORKGROUP-PC'; azureADDeviceId=$null } }
            { Get-IntuneLapsCredential -Device '12345678-0000-0000-0000-000000000002' } | Should -Throw '*Azure AD device ID*'
        }
    }
}

Describe 'Public cmdlets — Get-IntuneDeviceGroupMembership' {

    It 'returns transitive groups with names and flags dynamic membership rules' {
        InModuleScope IntuneTide {
            Mock Resolve-IaDevice { [pscustomobject]@{ Id='dev-obj-1'; DisplayName='LAPTOP-01' } }
            Mock Get-IaCollection {
                @(
                    [pscustomobject]@{ id='g1'; displayName='All Pilot Devices'; membershipRule=$null }
                    [pscustomobject]@{ id='g2'; displayName='Autopilot Devices'; membershipRule='(device.devicePhysicalIds -any (_ -contains "[ZTDId]"))' }
                )
            }
            $r = @(Get-IntuneDeviceGroupMembership -Device 'LAPTOP-01')
            $r.Count                | Should -Be 2
            $r[0].GroupName         | Should -Be 'All Pilot Devices'
            $r[0].MembershipRule    | Should -BeNullOrEmpty           # assigned (static) group
            $r[1].MembershipRule    | Should -Match 'ZTDId'           # dynamic group rule surfaced
        }
    }

    It 'throws when the device cannot be resolved to an Entra object' {
        InModuleScope IntuneTide {
            Mock Resolve-IaDevice { [pscustomobject]@{ Id=$null; DisplayName=$null } }
            { Get-IntuneDeviceGroupMembership -Device 'nope' } | Should -Throw '*resolve*'
        }
    }
}

Describe 'Public cmdlets — Get-IntuneUserDevice' {

    It 'filters managedDevices by userPrincipalName and projects device fields' {
        InModuleScope IntuneTide {
            $script:capturedPath = $null
            Mock Get-IaCollection {
                $script:capturedPath = $Path
                @(
                    [pscustomobject]@{ id='d1'; deviceName='LAPTOP-01'; operatingSystem='Windows'; osVersion='10.0.22631'
                                       complianceState='compliant'; managedDeviceOwnerType='company'
                                       lastSyncDateTime='2026-06-26T00:00:00Z'; manufacturer='Dell'; model='Latitude 7420' }
                    [pscustomobject]@{ id='d2'; deviceName='PHONE-01'; operatingSystem='iOS'; osVersion='17.5'
                                       complianceState='noncompliant'; managedDeviceOwnerType='personal'
                                       lastSyncDateTime='2026-06-25T00:00:00Z'; manufacturer='Apple'; model='iPhone 15' }
                )
            }
            $r = @(Get-IntuneUserDevice -User 'alice@contoso.com')
            $script:capturedPath | Should -Match "userPrincipalName eq 'alice@contoso.com'"
            $r.Count             | Should -Be 2
            $r[0].Device         | Should -Be 'LAPTOP-01'
            $r[0].OS             | Should -Be 'Windows 10.0.22631'
            $r[0].Model          | Should -Be 'Dell Latitude 7420'
            $r[0].Owner          | Should -Be 'company'
        }
    }

    It 'escapes apostrophes in the UPN to keep the OData filter valid' {
        InModuleScope IntuneTide {
            $script:capturedPath = $null
            Mock Get-IaCollection { $script:capturedPath = $Path; @() }
            Get-IntuneUserDevice -User "o'brien@contoso.com" | Out-Null
            $script:capturedPath | Should -Match "o''brien@contoso.com"   # doubled, not a broken quote
        }
    }
}

Describe 'Public cmdlets — Get-IntuneDeviceManagedApp' {

    It 'projects intent + install state for the device primary user' {
        InModuleScope IntuneTide {
            Mock Resolve-IaManagedDeviceId { 'mdm-1' }
            Mock Invoke-IaRequest {
                if ($Uri -match 'mobileAppIntentAndStates') {
                    return [pscustomobject]@{ mobileAppList = @(
                        [pscustomobject]@{ displayName='Company Portal'; mobileAppIntent='required'; installState='installed'; displayVersion='5.0' }
                        [pscustomobject]@{ displayName='Contoso VPN';    mobileAppIntent='available'; installState='failed';    displayVersion='2.1' }
                    ) }
                }
                return [pscustomobject]@{ id='mdm-1'; deviceName='LAPTOP-01'; userId='user-1'; userPrincipalName='alice@contoso.com' }
            }
            $r = @(Get-IntuneDeviceManagedApp -Device 'LAPTOP-01')
            $r.Count     | Should -Be 2
            $r[0].App    | Should -Be 'Company Portal'
            $r[0].Intent | Should -Be 'required'
            $r[0].State  | Should -Be 'installed'
            $r[1].State  | Should -Be 'failed'
        }
    }

    It 'warns and returns nothing for a device with no primary user (shared/kiosk)' {
        InModuleScope IntuneTide {
            Mock Resolve-IaManagedDeviceId { 'mdm-2' }
            Mock Invoke-IaRequest { [pscustomobject]@{ id='mdm-2'; deviceName='KIOSK-01'; userId=$null; userPrincipalName=$null } }
            $r = @(Get-IntuneDeviceManagedApp -Device 'KIOSK-01' -WarningAction SilentlyContinue)
            $r.Count | Should -Be 0
        }
    }
}

Describe 'Public cmdlets — Get-IntuneUserGroupMembership' {

    It 'classifies group Kind + Membership from the beta /users transitiveMemberOf set' {
        InModuleScope IntuneTide {
            Mock Invoke-IaRequest { [pscustomobject]@{ id='u-1'; displayName='Alice'; userPrincipalName='alice@contoso.com' } }
            Mock Get-IaCollection {
                @(
                    [pscustomobject]@{ id='g1'; displayName='Finance Users'; securityEnabled=$true;  mailEnabled=$false; groupTypes=@();          membershipRule=$null }
                    [pscustomobject]@{ id='g2'; displayName='All Staff';     securityEnabled=$false; mailEnabled=$true;  groupTypes=@('Unified'); membershipRule=$null }
                    [pscustomobject]@{ id='g3'; displayName='IT Dynamic';    securityEnabled=$true;  mailEnabled=$false; groupTypes=@();          membershipRule='(user.department -eq "IT")' }
                )
            }
            $r = @(Get-IntuneUserGroupMembership -User 'alice@contoso.com')
            $r.Count            | Should -Be 3
            $r[0].Kind          | Should -Be 'Security'
            $r[0].Membership    | Should -Be 'assigned'
            $r[1].Kind          | Should -Be 'Microsoft 365'        # groupTypes contains Unified
            $r[2].Membership    | Should -Be 'dynamic'              # has a membershipRule
            $r[2].MembershipRule| Should -Match 'department'
        }
    }

    It 'queries the user transitiveMemberOf group path' {
        InModuleScope IntuneTide {
            $script:capturedPath = $null
            Mock Invoke-IaRequest { [pscustomobject]@{ id='u-7'; userPrincipalName='x@contoso.com' } }
            Mock Get-IaCollection { $script:capturedPath = $Path; @() }
            Get-IntuneUserGroupMembership -User 'x@contoso.com' | Out-Null
            $script:capturedPath | Should -Match 'users/u-7/transitiveMemberOf/microsoft.graph.group'
        }
    }

    It 'throws when the user cannot be resolved' {
        InModuleScope IntuneTide {
            Mock Invoke-IaRequest { [pscustomobject]@{ id=$null } }
            { Get-IntuneUserGroupMembership -User 'ghost@contoso.com' } | Should -Throw '*resolve*'
        }
    }
}

Describe 'Public cmdlets — Get-IntuneUserLicense' {

    It 'maps SKU part numbers to friendly names and counts enabled service plans' {
        InModuleScope IntuneTide {
            Mock Get-IaCollection {
                @(
                    [pscustomobject]@{ id='l1'; skuId='sku-e5'; skuPartNumber='SPE_E5'; servicePlans=@(
                        [pscustomobject]@{ servicePlanName='TEAMS1'; provisioningStatus='Success' }
                        [pscustomobject]@{ servicePlanName='INTUNE_A'; provisioningStatus='Success' }
                        [pscustomobject]@{ servicePlanName='MCOEV'; provisioningStatus='PendingProvisioning' }
                    ) }
                    [pscustomobject]@{ id='l2'; skuId='sku-x'; skuPartNumber='SOME_UNMAPPED_SKU'; servicePlans=@(
                        [pscustomobject]@{ servicePlanName='FOO'; provisioningStatus='Success' }
                    ) }
                )
            }
            $r = @(Get-IntuneUserLicense -User 'alice@contoso.com')
            $r.Count           | Should -Be 2
            $r[0].License      | Should -Be 'Microsoft 365 E5'      # SPE_E5 → friendly
            $r[0].Services     | Should -Be '2/3 enabled'
            $r[0].DisabledPlans| Should -Be 'MCOEV'                 # the non-Success plan surfaced
            $r[1].License      | Should -Be 'SOME_UNMAPPED_SKU'     # unmapped → raw part number
        }
    }

    It 'queries the beta /users licenseDetails endpoint' {
        InModuleScope IntuneTide {
            $script:capturedPath = $null
            Mock Get-IaCollection { $script:capturedPath = $Path; @() }
            Get-IntuneUserLicense -User 'alice@contoso.com' | Out-Null
            $script:capturedPath | Should -Match 'users/alice%40contoso.com/licenseDetails'
        }
    }
}

Describe 'Public cmdlets — Get-IntuneDeviceComplianceDetail' {

    It 'reads inline settingStates; -FailingOnly drops compliant/notApplicable' {
        InModuleScope IntuneTide {
            Mock Resolve-IaManagedDeviceId { 'dev-1' }
            Mock Invoke-IaRequest { throw 'should not be called — settingStates is inline' }
            Mock Get-IaCollection {
                @([pscustomobject]@{ id='ps1'; displayName='Win Compliance'; state='nonCompliant'; platformType='windows10AndLater'; settingStates=@(
                    [pscustomobject]@{ setting='pol.bitlocker'; settingName='BitLocker'; state='nonCompliant'; currentValue='NotEncrypted'; errorCode=0; errorDescription='' }
                    [pscustomobject]@{ setting='pol.os';        settingName='Min OS';   state='nonCompliant'; currentValue='10.0.19045';  errorCode=0; errorDescription='too old' }
                    [pscustomobject]@{ setting='pol.pw';        settingName='Password'; state='compliant';    currentValue='True';         errorCode=0; errorDescription='' }
                ) })
            }
            (@(Get-IntuneDeviceComplianceDetail -Device 'LAPTOP-01')).Count | Should -Be 3
            $fail = @(Get-IntuneDeviceComplianceDetail -Device 'LAPTOP-01' -FailingOnly)
            $fail.Count      | Should -Be 2
            $fail[0].Setting | Should -Be 'BitLocker'
            $fail[0].Policy  | Should -Be 'Win Compliance'
            $fail[1].Setting | Should -Be 'Min OS'
        }
    }

    It 'falls back to the single-entity read when the collection omits settingStates' {
        InModuleScope IntuneTide {
            Mock Resolve-IaManagedDeviceId { 'dev-1' }
            Mock Get-IaCollection { @([pscustomobject]@{ id='ps1'; displayName='Win Compliance'; state='nonCompliant' }) }   # no inline settingStates
            Mock Invoke-IaRequest { [pscustomobject]@{ id='ps1'; displayName='Win Compliance'; settingStates=@(
                [pscustomobject]@{ setting='pol.bitlocker'; settingName='BitLocker'; state='nonCompliant'; currentValue='NotEncrypted'; errorCode=0; errorDescription='' }
            ) } }
            $r = @(Get-IntuneDeviceComplianceDetail -Device 'LAPTOP-01' -FailingOnly)
            $r.Count      | Should -Be 1
            $r[0].Setting | Should -Be 'BitLocker'
            Should -Invoke Invoke-IaRequest -Times 1 -Exactly
        }
    }
}

Describe 'Public cmdlets — Get-IntuneDeviceConfigConflict' {

    It 'surfaces conflict settings (inline) and names the conflicting profiles (sources)' {
        InModuleScope IntuneTide {
            Mock Resolve-IaManagedDeviceId { 'dev-1' }
            Mock Invoke-IaRequest { throw 'should not be called — settingStates is inline' }
            Mock Get-IaCollection {
                @(
                    [pscustomobject]@{ id='cs1'; displayName='Edge Hardening'; state='conflict'; settingStates=@(
                        [pscustomobject]@{ setting='edge.home';  settingName='Edge home page'; state='conflict';  currentValue='(conflict)'; sources=@(
                            [pscustomobject]@{ id='p1'; displayName='Edge Hardening' }
                            [pscustomobject]@{ id='p2'; displayName='Edge Baseline' }) }
                        [pscustomobject]@{ setting='power.sleep'; settingName='Sleep'; state='compliant'; currentValue='15'; sources=@() }
                    ) }
                    [pscustomobject]@{ id='cs2'; displayName='Wi-Fi'; state='compliant'; settingStates=@() }   # skipped — not a conflict
                )
            }
            $r = @(Get-IntuneDeviceConfigConflict -Device 'LAPTOP-01')
            $r.Count       | Should -Be 1
            $r[0].Setting  | Should -Be 'Edge home page'
            $r[0].Profiles | Should -Be 'Edge Hardening, Edge Baseline'
        }
    }
}

Describe 'Public cmdlets — Get-IntuneUserSignIn' {

    It 'maps status, surfaces the blocking CA policy, and builds the signIns query' {
        InModuleScope IntuneTide {
            $script:capturedUri = $null
            Mock Invoke-IaRequest {
                $script:capturedUri = $Uri
                [pscustomobject]@{ value = @(
                    [pscustomobject]@{ createdDateTime='2026-06-27T08:00:00Z'; appDisplayName='Teams';    ipAddress='1.1.1.1'; clientAppUsed='Browser'; conditionalAccessStatus='success'; status=[pscustomobject]@{ errorCode=0;     failureReason='Other.' };     deviceDetail=[pscustomobject]@{ displayName='LAPTOP-01' }; appliedConditionalAccessPolicies=@() }
                    [pscustomobject]@{ createdDateTime='2026-06-27T07:00:00Z'; appDisplayName='Exchange'; ipAddress='2.2.2.2'; clientAppUsed='Mobile';  conditionalAccessStatus='failure'; status=[pscustomobject]@{ errorCode=53003; failureReason='Blocked by CA.' }; deviceDetail=[pscustomobject]@{ displayName='' };          appliedConditionalAccessPolicies=@(
                        [pscustomobject]@{ displayName='Require compliant device'; result='failure' }
                        [pscustomobject]@{ displayName='MFA';                      result='success' }) }
                ) }
            }
            $r = @(Get-IntuneUserSignIn -User 'alice@contoso.com' -Top 5)
            $r.Count          | Should -Be 2
            $r[0].Status      | Should -Be 'success'
            $r[1].Status      | Should -Be 'failure (53003)'
            $r[1].BlockedBy   | Should -Be 'Require compliant device'   # only result=failure surfaced
            $script:capturedUri | Should -Match "userPrincipalName eq 'alice@contoso.com'"
            $script:capturedUri | Should -Match '\$top=5'
            $script:capturedUri | Should -Match 'orderby=createdDateTime desc'
        }
    }
}

Describe 'Public cmdlets — Get-IntuneUserAuthMethod' {

    It 'maps @odata.type to friendly names and coalesces the detail' {
        InModuleScope IntuneTide {
            Mock Get-IaCollection {
                @(
                    [pscustomobject]@{ '@odata.type'='#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'; id='m1'; displayName='Pixel 8' }
                    [pscustomobject]@{ '@odata.type'='#microsoft.graph.phoneAuthenticationMethod';                  id='m2'; phoneNumber='+1 206 555 0142'; phoneType='mobile' }
                    [pscustomobject]@{ '@odata.type'='#microsoft.graph.fido2AuthenticationMethod';                  id='m3'; displayName='YubiKey 5' }
                    [pscustomobject]@{ '@odata.type'='#microsoft.graph.someBrandNewAuthenticationMethod';           id='m4' }
                )
            }
            $r = @(Get-IntuneUserAuthMethod -User 'alice@contoso.com')
            $r.Count     | Should -Be 4
            $r[0].Method | Should -Be 'Microsoft Authenticator'
            $r[0].Detail | Should -Be 'Pixel 8'
            $r[1].Method | Should -Be 'Phone (SMS / call)'
            $r[1].Detail | Should -Be '+1 206 555 0142'
            $r[3].Method | Should -Be 'some Brand New'                  # unknown type → de-camel-cased fallback
        }
    }
}

Describe 'Public cmdlets — Invoke-IntuneDeviceAction (CSDL-verified action verbs)' {

    It 'maps friendly actions to the correct managedDevice action names + bodies' {
        InModuleScope IntuneTide {
            Mock Resolve-IaManagedDeviceId { 'md-1' }
            $script:capUri = $null; $script:capBody = $null
            Mock Invoke-IaRequest { $script:capUri = $Uri; $script:capBody = $Body }

            Invoke-IntuneDeviceAction -Device 'LAPTOP-01' -Action Sync -Confirm:$false | Out-Null
            $script:capUri | Should -Match '/managedDevices/md-1/syncDevice$'

            Invoke-IntuneDeviceAction -Device 'LAPTOP-01' -Action Rename -NewName 'NEW-PC' -Confirm:$false | Out-Null
            $script:capUri             | Should -Match '/managedDevices/md-1/setDeviceName$'   # NOT 'rename' (that binds to cloudPC)
            $script:capBody.deviceName | Should -Be 'NEW-PC'

            Invoke-IntuneDeviceAction -Device 'LAPTOP-01' -Action CollectDiagnostics -Confirm:$false | Out-Null
            $script:capUri                            | Should -Match '/managedDevices/md-1/createDeviceLogCollectionRequest$'   # NOT 'collectDiagnostics'
            $script:capBody.templateType.templateType | Should -Be 'predefined'
        }
    }
}

Describe 'Public cmdlets — null @odata.type robustness (no hashtable null-index crash)' {

    It 'Get-IntuneCompliancePolicy tolerates a policy with no @odata.type' {
        InModuleScope IntuneTide {
            Mock Invoke-IaRequest { [pscustomobject]@{ value = @([pscustomobject]@{ id = 'p1'; displayName = 'No-Type Policy' }) } }
            { Get-IntuneCompliancePolicy } | Should -Not -Throw
        }
    }

    It 'Get-IntuneApp tolerates an app with no @odata.type' {
        InModuleScope IntuneTide {
            Mock Invoke-IaRequest { [pscustomobject]@{ value = @([pscustomobject]@{ id = 'a1'; displayName = 'No-Type App' }) } }
            { Get-IntuneApp } | Should -Not -Throw
        }
    }
}

Describe 'Public cmdlets — Send-IntuneReportToTeams (Adaptive Card)' {

    BeforeAll {
        $script:tRows = @(
            [pscustomobject]@{ Device = 'LAPTOP-01'; State = '[coral]noncompliant[/]' }
            [pscustomobject]@{ Device = 'LAPTOP-02'; State = '[accent]compliant[/]' }
        )
    }

    It 'builds the Workflows message envelope wrapping an AdaptiveCard 1.5 table' {
        $m = ($script:tRows | Send-IntuneReportToTeams -Title 'Devices' -PassThru) | ConvertFrom-Json
        $m.type                       | Should -Be 'message'
        $m.attachments[0].contentType | Should -Be 'application/vnd.microsoft.card.adaptive'
        $card = $m.attachments[0].content
        $card.type    | Should -Be 'AdaptiveCard'
        $card.version | Should -Be '1.5'
        $card.body[0].text | Should -Be 'Devices'
        $table = $card.body | Where-Object { $_.type -eq 'Table' }
        $table.firstRowAsHeaders | Should -BeTrue
        $table.rows.Count        | Should -Be 3      # header + 2 data
    }

    It 'strips TIDE markup from cell values' {
        $json = $script:tRows | Send-IntuneReportToTeams -Title 'X' -PassThru
        $json | Should -Not -Match '\[coral\]'
        $json | Should -Match 'noncompliant'
    }

    It 'caps rows at -MaxRows and notes the remainder' {
        $many = 1..20 | ForEach-Object { [pscustomobject]@{ N = $_ } }
        $card = (($many | Send-IntuneReportToTeams -Title 'Many' -MaxRows 5 -PassThru) | ConvertFrom-Json).attachments[0].content
        $table = $card.body | Where-Object { $_.type -eq 'Table' }
        $table.rows.Count | Should -Be 6             # header + 5
        (($card.body | ForEach-Object { $_.text }) -join ' ') | Should -Match 'and 15 more'
    }

    It 'restricts + orders columns with -Column' {
        $json  = ([pscustomobject]@{ A = 1; B = 2; C = 3 }) | Send-IntuneReportToTeams -Title 'Cols' -Column A, C -PassThru
        $table = ($json | ConvertFrom-Json).attachments[0].content.body | Where-Object { $_.type -eq 'Table' }
        (($table.rows[0].cells | ForEach-Object { $_.items[0].text }) -join ',') | Should -Be 'A,C'
    }

    It 'POSTs the JSON to the webhook when a URL is supplied' {
        InModuleScope IntuneTide {
            $script:posted = $null
            Mock Invoke-IaWebhookPost { $script:posted = [pscustomobject]@{ Uri = $Uri; Json = $Json } }
            [pscustomobject]@{ X = 1 } | Send-IntuneReportToTeams -Title 'Push' -WebhookUrl 'https://hook.example/abc' -Confirm:$false
            $script:posted.Uri  | Should -Be 'https://hook.example/abc'
            $script:posted.Json | Should -Match 'AdaptiveCard'
            Should -Invoke Invoke-IaWebhookPost -Times 1 -Exactly
        }
    }

    It 'throws when no webhook URL is available and not -PassThru' {
        InModuleScope IntuneTide {
            $saved = $env:TIDE_TEAMS_WEBHOOK; $env:TIDE_TEAMS_WEBHOOK = ''
            try { { [pscustomobject]@{ X = 1 } | Send-IntuneReportToTeams -Title 'NoUrl' -Confirm:$false } | Should -Throw '*webhook*' }
            finally { $env:TIDE_TEAMS_WEBHOOK = $saved }
        }
    }
}

Describe 'Reporting · ConvertTo-IaDateTime (locale-robust date parsing)' {

    It 'parses relative spans (7d / 24h / 2w)' {
        InModuleScope IntuneTide {
            (ConvertTo-IaDateTime '7d')  | Should -BeOfType [datetime]
            ((Get-Date).ToUniversalTime() - (ConvertTo-IaDateTime '7d')).TotalDays | Should -BeGreaterThan 6.5
        }
    }

    It 'parses an ISO 8601 absolute date regardless of host culture' {
        InModuleScope IntuneTide {
            (ConvertTo-IaDateTime '2026-01-15').Year  | Should -Be 2026
            (ConvertTo-IaDateTime '2026-01-15').Month | Should -Be 1
        }
    }

    It 'throws a helpful error on an unparseable value (not a silent bad date)' {
        InModuleScope IntuneTide {
            { ConvertTo-IaDateTime 'not-a-date' } | Should -Throw '*Could not parse date*'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'New-IntuneAssignmentFilter parameter validation' {

    It 'accepts devices as AssignmentFilterManagementType' {
        { New-IntuneAssignmentFilter -Name 'Test' -Rule 'device.platform -eq "Windows"' `
              -Platform windows10AndLater -AssignmentFilterManagementType devices -WhatIf } |
            Should -Not -Throw
    }

    It 'accepts apps as AssignmentFilterManagementType' {
        { New-IntuneAssignmentFilter -Name 'Test' -Rule 'app.name -eq "Outlook"' `
              -Platform iOS -AssignmentFilterManagementType apps -WhatIf } |
            Should -Not -Throw
    }

    It 'rejects invalid AssignmentFilterManagementType' {
        { New-IntuneAssignmentFilter -Name 'Test' -Rule 'x' -Platform windows10AndLater `
              -AssignmentFilterManagementType 'include' } |
            Should -Throw
    }

    It 'rejects invalid Platform' {
        { New-IntuneAssignmentFilter -Name 'Test' -Rule 'x' -Platform 'dos' } |
            Should -Throw
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Public cmdlets — Cloud PC' {

    It 'Get-IntuneCloudPC queries virtualEndpoint/cloudPCs' {
        InModuleScope IntuneTide {
            $uris = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-IaRequest {
                $uris.Add($Uri)
                return [pscustomobject]@{ value = @() }
            }
            Get-IntuneCloudPC
            ($uris -join '|') | Should -Match 'virtualEndpoint/cloudPCs'
        }
    }

    It 'maps Region from deviceRegionName and LastLogin from lastLoginResult.time' {
        InModuleScope IntuneTide {
            Mock Invoke-IaRequest {
                return [pscustomobject]@{ value = @(
                    [pscustomobject]@{ id = 'cpc1'; displayName = 'CPC-1'; status = 'provisioned'
                        deviceRegionName = 'westus2'; lastLoginResult = [pscustomobject]@{ time = '2026-06-26T09:00:00Z' } }
                ) }
            }
            $pc = @(Get-IntuneCloudPC)[0]
            $pc.Region    | Should -Be 'westus2'                  # deviceRegionName, not 'region'
            $pc.LastLogin | Should -Be '2026-06-26T09:00:00Z'    # lastLoginResult.time, not 'lastLoginDateTime'
        }
    }

    It 'Get-IntuneCloudPCReport posts the CSDL-verified report action + reportName' {
        InModuleScope IntuneTide {
            $script:capUri = $null; $script:capBody = $null
            Mock Invoke-IaRequest { $script:capUri = $Uri; $script:capBody = $Body; return [pscustomobject]@{ schema = @(); values = @() } }

            Get-IntuneCloudPCReport -Report TotalUsage | Out-Null
            $script:capUri | Should -Match 'getTotalAggregatedRemoteConnectionReports$'

            Get-IntuneCloudPCReport -Report ConnectionQuality | Out-Null
            $script:capUri | Should -Match 'getConnectionQualityReports$'   # NOT getCloudPcRecommendationReports

            Get-IntuneCloudPCReport -Report Frontline | Out-Null
            $script:capUri              | Should -Match 'getFrontlineReport$'
            $script:capBody.reportName  | Should -Be 'frontlineLicenseUsageReport'

            Get-IntuneCloudPCReport -Report Inaccessible | Out-Null
            $script:capUri              | Should -Match 'getInaccessibleCloudPcReports$'
            $script:capBody.reportName  | Should -Be 'inaccessibleCloudPcReports'
        }
    }

    It 'Get-IntuneCloudPCProvisioningPolicy queries provisioningPolicies' {
        InModuleScope IntuneTide {
            $uris = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-IaRequest {
                $uris.Add($Uri)
                return [pscustomobject]@{ value = @() }
            }
            Get-IntuneCloudPCProvisioningPolicy
            ($uris -join '|') | Should -Match 'virtualEndpoint/provisioningPolicies'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Public cmdlets — PIM wrappers' {

    It 'Get-IntuneEligibleRole returns structured output' {
        InModuleScope IntuneTide {
            Mock Invoke-IaRequest {
                if ($Uri -match 'me\?') {
                    return [pscustomobject]@{ id = 'user1'; userPrincipalName = 'admin@contoso.com' }
                }
                return [pscustomobject]@{ value = @(
                    [pscustomobject]@{
                        id = 'elig1'
                        roleDefinition = [pscustomobject]@{ displayName = 'Intune Administrator' }
                        endDateTime = '2025-12-31T23:59:59Z'
                    }
                ) }
            }
            $roles = Get-IntuneEligibleRole
            $roles.Count | Should -BeGreaterOrEqual 1
        }
    }

    It 'Get-IntuneActiveRole returns structured output' {
        InModuleScope IntuneTide {
            Mock Invoke-IaRequest {
                if ($Uri -match 'me\?') {
                    return [pscustomobject]@{ id = 'user1'; userPrincipalName = 'admin@contoso.com' }
                }
                return [pscustomobject]@{ value = @(
                    [pscustomobject]@{
                        id = 'active1'
                        roleDefinition = [pscustomobject]@{ displayName = 'Intune Administrator' }
                        endDateTime = '2025-06-30T23:59:59Z'
                    }
                ) }
            }
            $roles = Get-IntuneActiveRole
            $roles.Count | Should -BeGreaterOrEqual 1
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Backup and restore' {

    It 'Backup-IntuneAssignment serialises to JSON and round-trips' {
        InModuleScope IntuneTide {
            Reset-IaDirectoryCache
            $tmp = [System.IO.Path]::GetTempFileName()
            try {
                Mock Invoke-IaRequest {
                    if ($Uri -match 'assignmentFilters') { return [pscustomobject]@{ value = @() } }
                    return [pscustomobject]@{ value = @(
                        [pscustomobject]@{ id = 'cp1'; name = 'Baseline'; '@odata.type' = '#x'
                            assignments = @([pscustomobject]@{
                                target = [pscustomobject]@{
                                    '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
                                }}) }
                    ) }
                }
                Backup-IntuneAssignment -Path $tmp -Area 'Configuration'
                $content = Get-Content $tmp -Raw | ConvertFrom-Json
                $content | Should -Not -BeNullOrEmpty
            } finally {
                Remove-Item $tmp -ErrorAction SilentlyContinue
            }
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Module export completeness' {

    It 'exports Connect-IntuneTide' {
        Get-Command Connect-IntuneTide -Module IntuneTide | Should -Not -BeNullOrEmpty
    }

    It 'exports Get-IntuneApp' {
        Get-Command Get-IntuneApp -Module IntuneTide | Should -Not -BeNullOrEmpty
    }

    It 'exports all expected public cmdlets' {
        $expected = @(
            'Connect-IntuneTide', 'Get-IntuneApp', 'Get-IntuneScript',
            'Get-IntuneRemediation', 'Get-IntuneCompliancePolicy',
            'Get-IntuneConfigurationPolicy', 'Get-IntuneUpdateRing',
            'Get-IntuneAssignmentFilter', 'New-IntuneAssignmentFilter',
            'Remove-IntuneAssignmentFilter', 'Get-IntuneDeviceDetail',
            'Get-IntuneCloudPC', 'Get-IntuneCloudPCProvisioningPolicy',
            'Get-IntuneEligibleRole', 'Get-IntuneActiveRole',
            'Enable-IntuneAdminRole', 'Backup-IntuneAssignment',
            'Restore-IntuneAssignment', 'Compare-IntuneAssignment',
            'Copy-IntuneAssignment', 'Get-IntuneGroupAssignment',
            'Get-IntuneEffectiveAssignment', 'Get-IntuneDeploymentSummary',
            'Export-IntuneAssignmentReport', 'Add-IntuneBulkAssignment'
        )
        $exported = (Get-Module IntuneTide).ExportedCommands.Keys
        foreach ($cmd in $expected) {
            $exported | Should -Contain $cmd -Because "$cmd must be a public export"
        }
    }

    It 'does not export private helpers' {
        $exported = (Get-Module IntuneTide).ExportedCommands.Keys
        $exported | Should -Not -Contain 'Invoke-IaRequest'
        $exported | Should -Not -Contain 'Get-IaCollection'
        $exported | Should -Not -Contain 'Resolve-IaUri'
        $exported | Should -Not -Contain 'ConvertFrom-IaTarget'
        $exported | Should -Not -Contain 'Get-IaInventory'
    }

    It 'does not export the internal TUI engine functions' {
        $exported = (Get-Module IntuneTide).ExportedCommands.Keys
        $exported | Should -Not -Contain 'ConvertFrom-IaMarkup'
        $exported | Should -Not -Contain 'Read-IaMenu'
        $exported | Should -Not -Contain 'Write-IaHost'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# TUI engine (Private/Tui.ps1) — the layer that replaced PwshSpectreConsole.
# The headline guarantee: it NEVER throws on data that merely looks like markup,
# which is exactly the failure mode that crashed the Spectre-based TUI.
Describe 'TUI engine · markup parser' {

    It 'never throws on an unknown colour tag and renders it literally' {
        InModuleScope IntuneTide {
            # This is the exact input that produced "Could not find color 'Apps'".
            { ConvertFrom-IaMarkup -Text 'area [Apps] x' } | Should -Not -Throw
            (Strip-IaMarkup -Text 'area [Apps] x') | Should -Be 'area [Apps] x'
        }
    }

    It 'renders a group literally named with brackets without throwing' {
        InModuleScope IntuneTide {
            { ConvertFrom-IaMarkup -Text 'Group [Test] assigned' } | Should -Not -Throw
            (Strip-IaMarkup -Text 'Group [Test] assigned') | Should -Be 'Group [Test] assigned'
        }
    }

    It 'converts a known colour tag to an ANSI escape' {
        InModuleScope IntuneTide {
            $esc = [char]0x1B
            (ConvertFrom-IaMarkup -Text '[grey]hello[/]') | Should -Match ([regex]::Escape($esc))
            (Strip-IaMarkup -Text '[grey]hello[/]') | Should -Be 'hello'
        }
    }

    It 'handles compound and nested tags without throwing' {
        InModuleScope IntuneTide {
            { ConvertFrom-IaMarkup -Text '[bold white]x[/]' } | Should -Not -Throw
            { ConvertFrom-IaMarkup -Text '[grey]a[red]b[/]c[/]' } | Should -Not -Throw
            (Strip-IaMarkup -Text '[grey]a[red]b[/]c[/]') | Should -Be 'abc'
        }
    }

    It 'tolerates a stray closing tag' {
        InModuleScope IntuneTide {
            { ConvertFrom-IaMarkup -Text 'no open[/] here' } | Should -Not -Throw
        }
    }

    It 'Strip and Convert agree on the visible text for a mixed string' {
        InModuleScope IntuneTide {
            $s = 'pre [grey]mid[/] [Apps] [coral]end[/] post'
            # ConvertFrom keeps the visible glyphs (plus ANSI); stripping the ANSI
            # from the converted form must equal Strip-IaMarkup's output.
            $esc = [char]0x1B
            $converted = ConvertFrom-IaMarkup -Text $s
            $noAnsi = [regex]::Replace($converted, "$([regex]::Escape($esc))\[[0-9;]*m", '')
            $noAnsi | Should -Be (Strip-IaMarkup -Text $s)
        }
    }

    It 'Protect-IaMarkup escapes brackets and round-trips to literal text' {
        InModuleScope IntuneTide {
            (Protect-IaMarkup -Text '[Test]') | Should -Be '[[Test]]'
            (ConvertFrom-IaMarkup -Text (Protect-IaMarkup -Text '[red]')) | Should -Be '[red]'
            (Strip-IaMarkup -Text (Protect-IaMarkup -Text '[red]')) | Should -Be '[red]'
        }
    }

    It 'treats empty / null input safely' {
        InModuleScope IntuneTide {
            (ConvertFrom-IaMarkup -Text '') | Should -Be ''
            (Strip-IaMarkup -Text '') | Should -Be ''
            (Measure-IaWidth -Text '') | Should -Be 0
        }
    }
}

Describe 'TUI engine · colour & width' {

    It 'maps every accent / colour name the TUI uses' {
        InModuleScope IntuneTide {
            # Includes every theme accent: green/amber(orange1)/lego(yellow)/deepsea
            # (turquoise2)/sunset(coral)/ocean(deepskyblue1)/forest(lime)/mono(silver).
            foreach ($c in 'green','orange1','yellow','turquoise2','coral','red',
                           'grey','white','deepskyblue1','darkslategray1','lime','silver','bold','dim') {
                (Get-IaAnsi $c) | Should -Not -Be '' -Because "$c is used in the TUI"
            }
        }
    }

    It 'returns empty (no throw) for an unknown colour name' {
        InModuleScope IntuneTide {
            (Get-IaAnsi 'Apps') | Should -Be ''
            (Get-IaAnsi '') | Should -Be ''
        }
    }

    It 'measures ascii and wide characters' {
        InModuleScope IntuneTide {
            (Measure-IaWidth -Text 'hello') | Should -Be 5
            (Measure-IaWidth -Text '世界')   | Should -Be 4   # 2 wide CJK glyphs
        }
    }
}

Describe 'TUI engine · mouse event classification' {
    # SGR mouse reports are  ESC [ < button ; col ; row  M/m. The classifiers below
    # turn a parsed event into the gesture the menus/tables act on.

    It 'recognises a left-button press as a click (and ignores its release)' {
        InModuleScope IntuneTide {
            $press   = @{ Type='mouse'; Button=0; X=5; Y=3; Press=$true }
            $release = @{ Type='mouse'; Button=0; X=5; Y=3; Press=$false }
            (Test-IaMouseLeftClick $press)   | Should -BeTrue
            (Test-IaMouseLeftClick $release) | Should -BeFalse  # release must not re-fire the action
        }
    }

    It 'distinguishes wheel-up (64) from wheel-down (65)' {
        InModuleScope IntuneTide {
            $up   = @{ Type='mouse'; Button=64; X=1; Y=1; Press=$true }
            $down = @{ Type='mouse'; Button=65; X=1; Y=1; Press=$true }
            [bool](Test-IaMouseWheelUp   $up)   | Should -BeTrue
            [bool](Test-IaMouseWheelDown $up)   | Should -BeFalse
            [bool](Test-IaMouseWheelDown $down) | Should -BeTrue
            [bool](Test-IaMouseWheelUp   $down) | Should -BeFalse
        }
    }

    It 'does not classify a wheel event as a click' {
        InModuleScope IntuneTide {
            $wheel = @{ Type='mouse'; Button=64; X=1; Y=1; Press=$true }
            (Test-IaMouseLeftClick $wheel) | Should -BeFalse
        }
    }

    It 'treats a modified left click (e.g. Ctrl held) as a click but a right click as not' {
        InModuleScope IntuneTide {
            $ctrlLeft = @{ Type='mouse'; Button=16; X=2; Y=2; Press=$true }  # +Ctrl modifier bit
            $right    = @{ Type='mouse'; Button=2;  X=2; Y=2; Press=$true }
            (Test-IaMouseLeftClick $ctrlLeft) | Should -BeTrue
            (Test-IaMouseLeftClick $right)    | Should -BeFalse
        }
    }
}

Describe 'TUI engine · id masking (Format-IaMaskedId)' {

    It 'reveals only the last 4 characters of a tenant GUID by default' {
        InModuleScope IntuneTide {
            $masked = Format-IaMaskedId '11111111-2222-3333-4444-555555555555'
            $masked | Should -BeLike '*5555'
            $masked | Should -Not -Match '1111|2222|3333|4444'   # nothing identifiable leaks
            $masked | Should -Match '^•+5555$'                   # bullets + last 4 only
        }
    }

    It 'hides everything when -Reveal 0' {
        InModuleScope IntuneTide {
            $masked = Format-IaMaskedId '11111111-2222-3333-4444-555555555555' -Reveal 0
            $masked | Should -Not -Match '[0-9a-fA-F]'           # no hex at all
            $masked | Should -Match '^•+$'
        }
    }

    It 'passes through empty / null without throwing' {
        InModuleScope IntuneTide {
            (Format-IaMaskedId '')    | Should -Be ''
            (Format-IaMaskedId $null) | Should -BeNullOrEmpty
        }
    }
}

Describe 'TUI engine · Graph-calls footer (Get-IaCallFooter)' {

    It 'is empty when no calls have been logged' {
        InModuleScope IntuneTide {
            Clear-IaCallLog
            (Get-IaCallFooter) | Should -Be ''
        }
    }

    It 'reports the true call count and recent calls (no double-wrap)' {
        InModuleScope IntuneTide {
            Clear-IaCallLog
            Add-IaCall -Method GET  -Uri 'https://graph.microsoft.com/beta/groups?x=1' -Status 200 -Ms 3 -Count 5
            Add-IaCall -Method GET  -Uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -Status 200 -Ms 2 -Count 6
            Add-IaCall -Method POST -Uri 'https://graph.microsoft.com/beta/x/assign' -Status 204 -Ms 9 -Count 0
            $f = Get-IaCallFooter                      # contains ANSI, but the text is findable
            $f | Should -Match '3 Graph calls'         # the real count, not 1 (the double-wrap bug)
            $f | Should -Match 'POST'                  # most-recent call shown
            $f | Should -Not -Match 'GET.{0,6}GET'     # methods not flattened/adjacent across entries
            Clear-IaCallLog
        }
    }

    It 'renders a multi-line, copy-pasteable panel with full path + query, one call per line' {
        InModuleScope IntuneTide {
            Clear-IaCallLog
            Add-IaCall -Method GET  -Uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?$select=id,name' -Status 200 -Ms 12 -Count 6
            Add-IaCall -Method POST -Uri 'https://graph.microsoft.com/beta/x/assign' -Status 204 -Ms 9 -Count 0
            $panel = Get-IaCallPanelLines -Max 10 -Width 120         # do NOT @()-wrap (,@() idiom)
            $panel.Count | Should -Be 3                              # header + 2 calls
            ($panel -join "`n") | Should -Match '\$select=id,name'   # query string preserved for copy-paste
            $panel[1] | Should -Match 'configurationPolicies'        # one call per line (oldest-shown first)
            Clear-IaCallLog
        }
    }
}

Describe 'TUI engine · save-path picker (Read-IaSavePath)' {

    It 'falls back to a typed path prompt when no native dialog is available' {
        InModuleScope IntuneTide {
            Mock Get-Command { $null } -ParameterFilter { $Name -in 'osascript', 'zenity' }
            Mock Read-IaText { 'typed-fallback.html' }
            (Read-IaSavePath -Prompt 'x' -DefaultName 'typed-fallback.html') | Should -Be 'typed-fallback.html'
            Should -Invoke Read-IaText -Times 1 -Exactly
        }
    }
}

Describe 'Cross-platform safety (runs on macOS / Linux, not just Windows)' {
    # The TUI is a self-contained ANSI renderer — the cross-platform stand-in for
    # Out-GridView. These guards stop a Windows-only dependency from creeping back
    # in and breaking the module on macOS.

    BeforeAll {
        $script:srcFiles = Get-ChildItem -Path $PSScriptRoot -Recurse -Filter *.ps1 |
            Where-Object { $_.Name -ne 'IntuneTide.Tests.ps1' }
    }

    It 'never calls Out-GridView (Windows-only; throws on macOS/Linux)' {
        ($script:srcFiles | Select-String -Pattern 'Out-GridView' -SimpleMatch) | Should -BeNullOrEmpty
    }

    It 'uses no GUI toolkit (WPF / WinForms / GraphicalTools)' {
        $hits = $script:srcFiles | Select-String -Pattern 'System\.Windows|PresentationFramework|WindowsForms|GraphicalTools'
        $hits | Should -BeNullOrEmpty
    }

    It 'uses no COM / WMI automation (Windows-only)' {
        $hits = $script:srcFiles | Select-String -Pattern '-ComObject|Get-WmiObject|New-Object\s+-Com'
        $hits | Should -BeNullOrEmpty
    }

    It 'guards every platform-specific shell call behind an $Is* check' {
        # explorer.exe / open / xdg-open must only run under the matching platform.
        foreach ($f in $script:srcFiles) {
            $lines = Get-Content $f.FullName
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match 'explorer\.exe|xdg-open|open -R') {
                    # the same line must carry the platform guard
                    $lines[$i] | Should -Match '\$IsWindows|\$IsMacOS|\$IsLinux' -Because "line $($i+1) of $($f.Name) runs a platform-specific command"
                }
            }
        }
    }

    It 'manifest requires PowerShell 7+ and is not locked to a Windows edition' {
        $psd = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'IntuneTide.psd1')
        [version]$psd.PowerShellVersion | Should -BeGreaterOrEqual ([version]'7.0')
        # No CompatiblePSEditions = 'Desktop'-only lock (Desktop edition is Windows-only)
        if ($psd.ContainsKey('CompatiblePSEditions')) {
            $psd.CompatiblePSEditions | Should -Contain 'Core'
        }
    }
}

Describe 'TUI engine · table rendering' {

    It 'renders objects with markup cells without throwing' {
        InModuleScope IntuneTide {
            $rows = @(
                [pscustomobject]@{ Area = '[green]Apps[/]'; Resource = 'Chrome [stable]'; Assigned = '[coral]EXCLUDE grp[/]' }
                [pscustomobject]@{ Area = '[green]Compliance[/]'; Resource = 'Win10'; Assigned = 'grpA; grpB' }
            )
            { Show-IaTableObjects -Rows $rows -Color turquoise2 -Title 'T [x]' 6>&1 } | Should -Not -Throw
        }
    }

    It 'produces no output for empty input' {
        InModuleScope IntuneTide {
            $out = Show-IaTableObjects -Rows @() -Color grey -Title 'x' 6>&1
            $out | Should -BeNullOrEmpty
        }
    }

    It 'Format-IaTable accepts the exact -Data / -Accent / -Title form that crashed Spectre' {
        InModuleScope IntuneTide {
            $rows = 1..3 | ForEach-Object { [pscustomobject]@{ Name = "App $_"; Type = 'Win32'; Publisher = 'Acme' } }
            { Format-IaTable -Data $rows -Accent turquoise2 -Title 'Apps' 6>&1 } | Should -Not -Throw
            { Format-IaTable -Data $rows -Accent turquoise2 -Title '[Apps]' 6>&1 } | Should -Not -Throw
        }
    }

    It 'Format-IaTable accepts pipeline input with markup cells' {
        InModuleScope IntuneTide {
            $rows = 1..2 | ForEach-Object { [pscustomobject]@{ A = "[coral]x$_[/]"; B = '[Test]' } }
            { $rows | Format-IaTable -Color turquoise2 6>&1 } | Should -Not -Throw
        }
    }
}

Describe 'TUI engine · menus & prompts (non-interactive fallback)' {

    It 'Read-IaMultiMenu never throws on bracketed / area-style labels' {
        InModuleScope IntuneTide {
            Mock Test-IaArrowSupport { $false }
            Mock Read-Host { '1 2' }
            $labels = @('1. (Apps) Chrome', '2. [Apps] Edge', '3. [Test] policy')
            { Read-IaMultiMenu -Title 'pick' -Choices $labels 6>&1 } | Should -Not -Throw
        }
    }

    It 'Read-IaMenu returns the chosen string' {
        InModuleScope IntuneTide {
            Mock Test-IaArrowSupport { $false }
            Mock Read-Host { '3' }
            (Read-IaMenu -Title 'pick' -Choices @('a', 'b', 'c') -Color grey) | Should -Be 'c'
        }
    }

    It 'Read-IaMenu treats blank input as the first choice' {
        InModuleScope IntuneTide {
            Mock Test-IaArrowSupport { $false }
            Mock Read-Host { '' }
            (Read-IaMenu -Title 'pick' -Choices @('a', 'b', 'c')) | Should -Be 'a'
        }
    }

    It 'Read-IaMenu returns $null for an empty choice list' {
        InModuleScope IntuneTide {
            (Read-IaMenu -Title 'pick' -Choices @()) | Should -BeNullOrEmpty
        }
    }

    It 'Read-IaMultiMenu returns the chosen strings' {
        InModuleScope IntuneTide {
            Mock Test-IaArrowSupport { $false }
            Mock Read-Host { '1 3' }
            $r = @(Read-IaMultiMenu -Title 'm' -Choices @('a', 'b', 'c'))
            ($r -join ',') | Should -Be 'a,c'
        }
    }

    It 'Read-IaMultiMenu supports "all"' {
        InModuleScope IntuneTide {
            Mock Test-IaArrowSupport { $false }
            Mock Read-Host { 'all' }
            $r = @(Read-IaMultiMenu -Title 'm' -Choices @('a', 'b', 'c'))
            ($r -join ',') | Should -Be 'a,b,c'
        }
    }

    It 'Read-IaMultiMenu returns empty for blank input' {
        InModuleScope IntuneTide {
            Mock Test-IaArrowSupport { $false }
            Mock Read-Host { '' }
            @(Read-IaMultiMenu -Title 'm' -Choices @('a', 'b', 'c')).Count | Should -Be 0
        }
    }

    It 'Read-IaText returns the default on blank, typed value otherwise' {
        InModuleScope IntuneTide {
            Mock Read-Host { '' }
            (Read-IaText -Question 'name' -DefaultAnswer 'baseline') | Should -Be 'baseline'
        }
        InModuleScope IntuneTide {
            Mock Read-Host { 'custom' }
            (Read-IaText -Question 'name' -DefaultAnswer 'baseline') | Should -Be 'custom'
        }
    }

    It 'Read-IaConfirm honours y / n / default' {
        InModuleScope IntuneTide {
            Mock Read-Host { 'y' }
            (Read-IaConfirm -Message 'ok?') | Should -BeTrue
        }
        InModuleScope IntuneTide {
            Mock Read-Host { 'n' }
            (Read-IaConfirm -Message 'ok?' -DefaultAnswer $true) | Should -BeFalse
        }
        InModuleScope IntuneTide {
            Mock Read-Host { '' }
            (Read-IaConfirm -Message 'ok?' -DefaultAnswer $true) | Should -BeTrue
        }
    }
}

Describe 'TUI engine · status wrapper' {

    It 'returns the script block output' {
        InModuleScope IntuneTide {
            (Invoke-IaStatus -Title 'load' -ScriptBlock { 42 }) | Should -Be 42
        }
    }

    It 'runs the block in its defining scope (no $using needed)' {
        InModuleScope IntuneTide {
            $thing = 'Win32'
            (Invoke-IaStatus -Title 'load' -ScriptBlock { "saw $thing" }) | Should -Be 'saw Win32'
        }
    }

    It 'lets the block write a script-scoped variable' {
        InModuleScope IntuneTide {
            $script:_iaTestOut = $null
            Invoke-IaStatus -Title 'load' -ScriptBlock { $script:_iaTestOut = 'done' } | Out-Null
            $script:_iaTestOut | Should -Be 'done'
        }
    }

    It 're-throws errors from the block' {
        InModuleScope IntuneTide {
            { Invoke-IaStatus -Title 'load' -ScriptBlock { throw 'boom' } } | Should -Throw 'boom'
        }
    }
}

Describe 'TUI engine · output primitives do not throw' {

    It 'Write-IaHost / Write-IaRule / Write-IaFiglet render without throwing' {
        InModuleScope IntuneTide {
            { Write-IaHost '[turquoise2]hi[/] [Apps] plain' 6>&1 } | Should -Not -Throw
            { Write-IaRule -Title 'sect' -Color darkslategray1 6>&1 } | Should -Not -Throw
            { Write-IaRule -Color grey 6>&1 } | Should -Not -Throw
            { Write-IaFiglet -Text 'TIDE' -Color turquoise2 6>&1 } | Should -Not -Throw
            { Write-IaFiglet -Text 'Other Words' -Color green 6>&1 } | Should -Not -Throw
        }
    }

    It 'Get-IaFigletString returns a multi-line banner for TIDE' {
        InModuleScope IntuneTide {
            $banner = Get-IaFigletString -Text 'TIDE' -Color turquoise2
            $banner | Should -Not -BeNullOrEmpty
            @($banner -split "`n").Count | Should -Be 5 -Because 'the block font is five rows tall'
        }
    }

    It 'Read-IaMenu accepts a -Header without throwing (non-interactive fallback)' {
        InModuleScope IntuneTide {
            Mock Test-IaArrowSupport { $false }
            Mock Read-Host { '1' }
            { Read-IaMenu -Title 'pick' -Header "BANNER`nLINE2" -Choices @('a', 'b') 6>&1 } | Should -Not -Throw
        }
    }
}

Describe 'TUI engine · report predicate' {

    It 'evaluates string operators' {
        InModuleScope IntuneTide {
            Test-IaReportPredicate -Value 'Windows'    -Operator eq          -Operand 'Windows' | Should -BeTrue
            Test-IaReportPredicate -Value 'Windows'    -Operator ne          -Operand 'macOS'   | Should -BeTrue
            Test-IaReportPredicate -Value 'Windows 11' -Operator contains    -Operand 'dows'    | Should -BeTrue
            Test-IaReportPredicate -Value 'Windows 11' -Operator notcontains -Operand 'mac'     | Should -BeTrue
            Test-IaReportPredicate -Value 'Windows'    -Operator startswith  -Operand 'Win'     | Should -BeTrue
            Test-IaReportPredicate -Value 'Windows'    -Operator endswith    -Operand 'ows'     | Should -BeTrue
            Test-IaReportPredicate -Value 'PC-42'      -Operator match       -Operand 'PC-\d+'  | Should -BeTrue
        }
    }

    It 'evaluates numeric comparisons numerically (not lexically)' {
        InModuleScope IntuneTide {
            # Lexically "9" > "10"; numerically 9 < 10. Must use numeric.
            Test-IaReportPredicate -Value 9  -Operator lt -Operand 10 | Should -BeTrue
            Test-IaReportPredicate -Value 45 -Operator gt -Operand 30 | Should -BeTrue
            Test-IaReportPredicate -Value 30 -Operator ge -Operand 30 | Should -BeTrue
            Test-IaReportPredicate -Value 30 -Operator le -Operand 30 | Should -BeTrue
        }
    }

    It 'evaluates empty / boolean operators' {
        InModuleScope IntuneTide {
            Test-IaReportPredicate -Value ''       -Operator isempty  -Operand '' | Should -BeTrue
            Test-IaReportPredicate -Value $null    -Operator isempty  -Operand '' | Should -BeTrue
            Test-IaReportPredicate -Value 'x'      -Operator notempty -Operand '' | Should -BeTrue
            Test-IaReportPredicate -Value 'True'   -Operator istrue   -Operand '' | Should -BeTrue
            Test-IaReportPredicate -Value 'False'  -Operator isfalse  -Operand '' | Should -BeTrue
        }
    }

    It 'never throws on a bad regex' {
        InModuleScope IntuneTide {
            { Test-IaReportPredicate -Value 'x' -Operator match -Operand '[unterminated' } | Should -Not -Throw
            Test-IaReportPredicate -Value 'x' -Operator match -Operand '[unterminated' | Should -BeFalse
        }
    }

    It 'compares dates chronologically' {
        InModuleScope IntuneTide {
            Test-IaReportPredicate -Value '2026-06-01' -Operator gt -Operand '2026-01-01' | Should -BeTrue
            Test-IaReportPredicate -Value '2026-01-01' -Operator lt -Operand '2026-06-01' | Should -BeTrue
        }
    }
}

Describe 'TUI engine · report pipeline' {

    BeforeAll {
        $script:rptData = @(
            [pscustomobject]@{ Device = 'PC-1';  OS = 'Windows'; Compliance = 'compliant';    Days = 2;  GB = 256 }
            [pscustomobject]@{ Device = 'PC-2';  OS = 'Windows'; Compliance = 'noncompliant'; Days = 45; GB = 512 }
            [pscustomobject]@{ Device = 'MAC-1'; OS = 'macOS';   Compliance = 'compliant';    Days = 10; GB = 1024 }
            [pscustomobject]@{ Device = 'PC-3';  OS = 'Windows'; Compliance = 'noncompliant'; Days = 3;  GB = 128 }
        )
    }

    It 'filters with WHERE (AND-combined)' {
        InModuleScope IntuneTide -Parameters @{ data = $script:rptData } {
            param($data)
            $r = Invoke-IaReportPipeline -Data $data -Recipe @{
                Where = @(@{ Prop = 'OS'; Op = 'eq'; Val = 'Windows' }, @{ Prop = 'Compliance'; Op = 'eq'; Val = 'noncompliant' })
                Sort = @(); Select = @(); Top = 0; GroupBy = $null; Agg = $null
            }
            @($r).Count | Should -Be 2
            @($r.Device) | Should -Contain 'PC-2'
            @($r.Device) | Should -Contain 'PC-3'
        }
    }

    It 'sorts numerically descending' {
        InModuleScope IntuneTide -Parameters @{ data = $script:rptData } {
            param($data)
            $r = Invoke-IaReportPipeline -Data $data -Recipe @{
                Where = @(); Sort = @(@{ Prop = 'Days'; Desc = $true }); Select = @(); Top = 0; GroupBy = $null; Agg = $null
            }
            $r[0].Device  | Should -Be 'PC-2'   # 45
            $r[-1].Device | Should -Be 'PC-1'   # 2
        }
    }

    It 'projects with SELECT' {
        InModuleScope IntuneTide -Parameters @{ data = $script:rptData } {
            param($data)
            $r = Invoke-IaReportPipeline -Data $data -Recipe @{
                Where = @(); Sort = @(); Select = @('Device', 'OS'); Top = 0; GroupBy = $null; Agg = $null
            }
            @($r[0].PSObject.Properties.Name) | Should -Be @('Device', 'OS')
        }
    }

    It 'limits with TOP' {
        InModuleScope IntuneTide -Parameters @{ data = $script:rptData } {
            param($data)
            $r = Invoke-IaReportPipeline -Data $data -Recipe @{
                Where = @(); Sort = @(); Select = @(); Top = 2; GroupBy = $null; Agg = $null
            }
            @($r).Count | Should -Be 2
        }
    }

    It 'groups with COUNT' {
        InModuleScope IntuneTide -Parameters @{ data = $script:rptData } {
            param($data)
            $r = Invoke-IaReportPipeline -Data $data -Recipe @{
                Where = @(); Sort = @(); Select = @(); Top = 0; GroupBy = 'OS'; Agg = @{ Func = 'Count'; Prop = $null }
            }
            $win = $r | Where-Object { $_.OS -eq 'Windows' }
            $win.Count | Should -Be 3
            ($r | Where-Object { $_.OS -eq 'macOS' }).Count | Should -Be 1
        }
    }

    It 'groups with SUM aggregate' {
        InModuleScope IntuneTide -Parameters @{ data = $script:rptData } {
            param($data)
            $r = Invoke-IaReportPipeline -Data $data -Recipe @{
                Where = @(); Sort = @(); Select = @(); Top = 0; GroupBy = 'OS'; Agg = @{ Func = 'Sum'; Prop = 'GB' }
            }
            $win = $r | Where-Object { $_.OS -eq 'Windows' }
            $win.'Sum(GB)' | Should -Be 896   # 256 + 512 + 128
        }
    }

    It 'groups with AVG aggregate' {
        InModuleScope IntuneTide -Parameters @{ data = $script:rptData } {
            param($data)
            $r = Invoke-IaReportPipeline -Data $data -Recipe @{
                Where = @(); Sort = @(); Select = @(); Top = 0; GroupBy = 'Compliance'; Agg = @{ Func = 'Avg'; Prop = 'Days' }
            }
            $nc = $r | Where-Object { $_.Compliance -eq 'noncompliant' }
            $nc.'Avg(Days)' | Should -Be 24    # (45 + 3) / 2
        }
    }

    It 'yields exactly one element for a single-row match (wrapped by caller)' {
        InModuleScope IntuneTide -Parameters @{ data = $script:rptData } {
            param($data)
            $r = @(Invoke-IaReportPipeline -Data $data -Recipe @{
                Where = @(@{ Prop = 'Device'; Op = 'eq'; Val = 'MAC-1' })
                Sort = @(); Select = @(); Top = 0; GroupBy = $null; Agg = $null
            })
            $r.Count | Should -Be 1
            $r[0].Device | Should -Be 'MAC-1'
        }
    }

    It 'returns a genuinely empty set for a no-match filter (not a phantom row)' {
        InModuleScope IntuneTide -Parameters @{ data = $script:rptData } {
            param($data)
            $r = @(Invoke-IaReportPipeline -Data $data -Recipe @{
                Where = @(@{ Prop = 'OS'; Op = 'eq'; Val = 'Solaris' })
                Sort = @(); Select = @(); Top = 0; GroupBy = $null; Agg = $null
            })
            $r.Count | Should -Be 0
            [bool]$r | Should -BeFalse -Because 'an empty report must be falsy, not a 1-element wrapper'
        }
    }

    It 'discovers the union of properties across rows' {
        InModuleScope IntuneTide {
            $ragged = @(
                [pscustomobject]@{ A = 1; B = 2 }
                [pscustomobject]@{ A = 1; C = 3 }
            )
            $props = Get-IaReportProperties -Data $ragged
            $props | Should -Contain 'A'
            $props | Should -Contain 'B'
            $props | Should -Contain 'C'
        }
    }
}
