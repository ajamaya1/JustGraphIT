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

    It 'builds v1.0 URI when -V1 is set' {
        InModuleScope IntuneTide {
            Resolve-IaUri -Path 'me' -V1 |
                Should -Be 'https://graph.microsoft.com/v1.0/me'
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
}
