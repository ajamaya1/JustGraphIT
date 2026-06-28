#requires -Modules Pester
# Pester v5 — fully offline (Graph mocked at Invoke-IaRequest seam).
# Run from the module folder:  Invoke-Pester -Output Detailed

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'JustGraphIT.psd1') -Force
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Resource registry' {

    It 'has unique keys' {
        InModuleScope JustGraphIT {
            $reg = Get-IaResourceRegistry
            ($reg.Key | Select-Object -Unique).Count | Should -Be $reg.Count
        }
    }

    It 'covers all expected areas' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
            $apps = Resolve-IaResourceType -Area 'Apps'
            $apps.Key | Should -Contain 'mobileApps'
            $apps.Key | Should -Contain 'mobileAppConfigurations'
            $apps.Key | Should -Contain 'targetedManagedAppConfigurations'
        }
    }

    It 'resolves types by key' {
        InModuleScope JustGraphIT {
            $r = Resolve-IaResourceType -Type 'intents'
            $r.Count | Should -Be 1
            $r[0].Area | Should -Be 'Endpoint security'
        }
    }

    It 'resolves multiple areas at once' {
        InModuleScope JustGraphIT {
            $r = Resolve-IaResourceType -Area 'Scripts', 'Remediations'
            $r.Key | Should -Contain 'deviceManagementScripts'
            $r.Key | Should -Contain 'deviceShellScripts'
            $r.Key | Should -Contain 'deviceHealthScripts'
        }
    }

    It 'returns all entries when no filter given' {
        InModuleScope JustGraphIT {
            $all  = Get-IaResourceRegistry
            $none = Resolve-IaResourceType
            $none.Count | Should -Be $all.Count
        }
    }

    It 'all entries have non-empty ListPath' {
        InModuleScope JustGraphIT {
            $reg = Get-IaResourceRegistry
            foreach ($r in $reg) {
                $r.ListPath | Should -Not -BeNullOrEmpty -Because "key=$($r.Key)"
            }
        }
    }

    It 'app area paths use deviceAppManagement prefix' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
            Resolve-IaUri -Path 'deviceManagement/managedDevices' |
                Should -Be 'https://graph.microsoft.com/beta/deviceManagement/managedDevices'
        }
    }

    It 'resolves -V1 to the beta endpoint too (module standardizes on beta)' {
        InModuleScope JustGraphIT {
            Resolve-IaUri -Path 'me' -V1 |
                Should -Be 'https://graph.microsoft.com/beta/me'
        }
    }

    It 'uses the beta base for every Graph call (no v1.0 anywhere)' {
        InModuleScope JustGraphIT {
            (Resolve-IaUri -Path 'groups')       | Should -Match '/beta/'
            (Resolve-IaUri -Path 'groups' -V1)   | Should -Match '/beta/'
            (Resolve-IaUri -Path 'groups')       | Should -Not -Match '/v1\.0/'
            (Resolve-IaUri -Path 'groups' -V1)   | Should -Not -Match '/v1\.0/'
        }
    }

    It 'returns absolute URLs unchanged' {
        InModuleScope JustGraphIT {
            $abs = 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?$skiptoken=xyz'
            Resolve-IaUri -Path $abs | Should -Be $abs
        }
    }

    It 'strips leading slash from path' {
        InModuleScope JustGraphIT {
            Resolve-IaUri -Path '/deviceManagement/intents' |
                Should -Be 'https://graph.microsoft.com/beta/deviceManagement/intents'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'OData value quoting' {

    It 'doubles a single quote then percent-encodes it (O''Brien round-trip)' {
        InModuleScope JustGraphIT {
            # O'Brien → O''Brien (OData) → O%27%27Brien (URL). Graph URL-decodes to
            # O''Brien, OData unescapes to O'Brien — the search term we wanted.
            ConvertTo-IaODataValue "O'Brien" | Should -Be 'O%27%27Brien'
        }
    }

    It 'percent-encodes spaces and ampersands without doubling them' {
        InModuleScope JustGraphIT {
            ConvertTo-IaODataValue 'AT&T Field Techs' | Should -Be 'AT%26T%20Field%20Techs'
        }
    }

    It 'leaves a plain value as a bare encoded token' {
        InModuleScope JustGraphIT {
            ConvertTo-IaODataValue 'Engineering' | Should -Be 'Engineering'
        }
    }

    It 'handles an empty value' {
        InModuleScope JustGraphIT {
            ConvertTo-IaODataValue '' | Should -Be ''
        }
    }

    It 'a name resolver embeds the doubled+encoded value in its filter' {
        InModuleScope JustGraphIT {
            $script:__capPath = $null
            # Return via the comma operator so a single row stays an array (real
            # Get-IaCollection does the same); otherwise .Count reads the hashtable keys.
            Mock Get-IaCollection { $script:__capPath = $Path; , @([pscustomobject]@{ id = 'app1'; displayName = "Bob's Tool" }) }
            Resolve-IaAppId -Value "Bob's Tool" | Should -Be 'app1'
            $script:__capPath | Should -Match "displayName eq 'Bob%27%27s%20Tool'"
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Source hygiene — string-interpolation traps' {
    It 'no bare $var? in any source string (it silently drops the variable; use ${var}?)' {
        # "Disable $Upn?" expands to "Disable " — PowerShell drops $Upn before the ?.
        # The fix everywhere is ${Upn}?. This scan guards the whole class (URLs, filters,
        # and the destructive-action confirm prompts) and ignores null-conditional ?./?[idx].
        $rx    = '\$[A-Za-z_]\w*\?(\s|"|''|\)|\[/|$)'
        $files = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public'), (Join-Path $PSScriptRoot 'Private') -Filter *.ps1 -Recurse
        $hits  = foreach ($f in $files) {
            $n = 0
            foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
                $n++
                if ($line -match $rx) { '{0}:{1}' -f $f.Name, $n }
            }
        }
        $hits | Should -BeNullOrEmpty -Because 'a bare $var before ? is dropped in string expansion — brace it as ${var}?'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'GUID detection' {

    It 'accepts a valid GUID' {
        InModuleScope JustGraphIT {
            Test-IaGuid '12345678-1234-1234-1234-123456789012' | Should -BeTrue
        }
    }

    It 'rejects a plain string' {
        InModuleScope JustGraphIT {
            Test-IaGuid 'My Policy Name' | Should -BeFalse
        }
    }

    It 'rejects an empty string' {
        InModuleScope JustGraphIT {
            Test-IaGuid '' | Should -BeFalse
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Error code resolution' {

    It 'resolves known Win32 hex code' {
        InModuleScope JustGraphIT {
            $r = Resolve-IaErrorCode '0x87D1041C'
            $r | Should -Not -BeNullOrEmpty
            $r.Short | Should -Be 'App not detected post-install'
            $r.Hint  | Should -Match 'detection rules'
        }
    }

    It 'resolves signed-negative decimal (same code)' {
        InModuleScope JustGraphIT {
            $r = Resolve-IaErrorCode (-2016345060)   # 0x87D1041C as Int32
            $r | Should -Not -BeNullOrEmpty
            $r.Short | Should -Be 'App not detected post-install'
        }
    }

    It 'resolves 0x87D1041A installation-failed code' {
        InModuleScope JustGraphIT {
            (Resolve-IaErrorCode '0x87D1041A').Short | Should -Be 'Installation failed'
        }
    }

    It 'resolves 0x80070005 access-denied code' {
        InModuleScope JustGraphIT {
            (Resolve-IaErrorCode '0x80070005').Short | Should -Be 'Access denied'
        }
    }

    It 'returns null for zero' {
        InModuleScope JustGraphIT {
            Resolve-IaErrorCode 0 | Should -BeNullOrEmpty
        }
    }

    It 'returns null for unknown code' {
        InModuleScope JustGraphIT {
            Resolve-IaErrorCode '0xDEADBEEF' | Should -BeNullOrEmpty
        }
    }

    It 'resolves friendly installStateDetail label' {
        InModuleScope JustGraphIT {
            Resolve-IaInstallDetail 'installFailed'  | Should -Be 'Installation failed'
            Resolve-IaInstallDetail 'rebootRequired' | Should -Be 'Reboot required'
        }
    }

    It 'falls through to raw string for unknown detail' {
        InModuleScope JustGraphIT {
            Resolve-IaInstallDetail 'somethingnew' | Should -Be 'somethingnew'
        }
    }

    It 'returns null for empty detail' {
        InModuleScope JustGraphIT {
            Resolve-IaInstallDetail '' | Should -BeNullOrEmpty
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'PIM duration parser' {

    It 'passes through ISO8601 duration unchanged' {
        InModuleScope JustGraphIT {
            ConvertTo-IaIsoDuration 'PT2H' | Should -Be 'PT2H'
            ConvertTo-IaIsoDuration 'P1D'  | Should -Be 'P1D'
        }
    }

    It 'converts hours shorthand' {
        InModuleScope JustGraphIT {
            ConvertTo-IaIsoDuration '8h' | Should -Be 'PT8H'
            ConvertTo-IaIsoDuration '1h' | Should -Be 'PT1H'
        }
    }

    It 'converts minutes shorthand' {
        InModuleScope JustGraphIT {
            ConvertTo-IaIsoDuration '30m' | Should -Be 'PT30M'
        }
    }

    It 'converts days shorthand' {
        InModuleScope JustGraphIT {
            ConvertTo-IaIsoDuration '1d' | Should -Be 'P1D'
        }
    }

    It 'throws on invalid format' {
        InModuleScope JustGraphIT {
            { ConvertTo-IaIsoDuration 'garbage' } | Should -Throw
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Assignment model — target conversion' {

    It 'parses allDevices target' {
        InModuleScope JustGraphIT {
            $t = ConvertFrom-IaTarget -Target ([pscustomobject]@{
                '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' })
            $t.Kind      | Should -Be 'allDevices'
            $t.IsExclude | Should -BeFalse
            $t.GroupId   | Should -BeNullOrEmpty
        }
    }

    It 'parses allLicensedUsers target' {
        InModuleScope JustGraphIT {
            $t = ConvertFrom-IaTarget -Target ([pscustomobject]@{
                '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget' })
            $t.Kind | Should -Be 'allUsers'
        }
    }

    It 'parses exclusionGroup target' {
        InModuleScope JustGraphIT {
            $t = ConvertFrom-IaTarget -Target ([pscustomobject]@{
                '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'; groupId = 'g99' })
            $t.Kind      | Should -Be 'exclusion'
            $t.IsExclude | Should -BeTrue
            $t.GroupId   | Should -Be 'g99'
        }
    }

    It 'parses a group target with a filter' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
            $t = ConvertFrom-IaTarget -Target ([pscustomobject]@{
                '@odata.type' = '#microsoft.graph.cloudPcManagementGroupAssignmentTarget'; groupId = 'g1' })
            $t.Kind | Should -Be 'group'
            (ConvertTo-IaTargetBody -Target $t)['@odata.type'] |
                Should -Be '#microsoft.graph.cloudPcManagementGroupAssignmentTarget'
        }
    }

    It 'synthesises correct @odata.type for exclusion when no original' {
        InModuleScope JustGraphIT {
            $t = New-IaGroupTarget -GroupId 'gx' -Exclude
            $body = ConvertTo-IaTargetBody -Target $t
            $body['@odata.type'] | Should -Be '#microsoft.graph.exclusionGroupAssignmentTarget'
            $body.groupId        | Should -Be 'gx'
        }
    }

    It 'adds filter fields to body when FilterId is set' {
        InModuleScope JustGraphIT {
            $t = New-IaGroupTarget -GroupId 'gf' -FilterId 'fid1' -FilterType 'exclude'
            $body = ConvertTo-IaTargetBody -Target $t
            $body.deviceAndAppManagementAssignmentFilterId   | Should -Be 'fid1'
            $body.deviceAndAppManagementAssignmentFilterType | Should -Be 'exclude'
        }
    }

    It 'omits filter fields when no FilterId' {
        InModuleScope JustGraphIT {
            $t = New-IaGroupTarget -GroupId 'gnofilter'
            $body = ConvertTo-IaTargetBody -Target $t
            $body.ContainsKey('deviceAndAppManagementAssignmentFilterId') | Should -BeFalse
        }
    }

    It 'handles unknown @odata.type gracefully' {
        InModuleScope JustGraphIT {
            $t = ConvertFrom-IaTarget -Target ([pscustomobject]@{
                '@odata.type' = '#microsoft.graph.someFutureTarget'; groupId = 'gunk' })
            $t.Kind | Should -Be 'unknown'
        }
    }

    It 'Get-IaTargetDisplay shows All Devices label' {
        InModuleScope JustGraphIT {
            $t = ConvertFrom-IaTarget -Target ([pscustomobject]@{
                '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' })
            Get-IaTargetDisplay -Target $t | Should -Be 'All Devices'
        }
    }

    It 'Get-IaTargetDisplay prefixes EXCLUDE for exclusion' {
        InModuleScope JustGraphIT {
            $t = [pscustomobject]@{ Kind = 'exclusion'; IsExclude = $true; GroupId = 'gid';
                GroupName = 'Test Group'; FilterId = $null; FilterType = 'none'; FilterName = $null }
            Get-IaTargetDisplay -Target $t | Should -Match '^EXCLUDE Test Group'
        }
    }

    It 'Get-IaTargetDisplay appends filter label' {
        InModuleScope JustGraphIT {
            $t = [pscustomobject]@{ Kind = 'group'; IsExclude = $false; GroupId = 'gid';
                GroupName = 'MyGroup'; FilterId = 'fid'; FilterType = 'include'; FilterName = 'Windows Filter' }
            Get-IaTargetDisplay -Target $t | Should -Match 'filter include: Windows Filter'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Assignment model — assignment conversion' {

    It 'preserves type-specific fields (remediation runSchedule)' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
            $a = ConvertFrom-IaAssignment -Item ([pscustomobject]@{
                id = 'y'; source = 'policySets'; sourceId = 'ps1'
                target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' } })
            $body = ConvertTo-IaAssignmentBody -Assignment $a
            $body.ContainsKey('source')   | Should -BeFalse
            $body.ContainsKey('sourceId') | Should -BeFalse
        }
    }

    It 'injects @odata.type when AssignmentODataType is provided' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT { Reset-IaDirectoryCache }
    }

    It 'returns display name from cache after first fetch' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
            Mock Invoke-IaRequest { throw 'Not Found' }
            $name = Resolve-IaGroupName -Id 'abcdef12-0000-0000-0000-000000000000'
            $name | Should -Match 'unresolved'
        }
    }

    It 'blocks further fetches after 403' {
        InModuleScope JustGraphIT {
            Mock Invoke-IaRequest { throw 'Forbidden 403' }
            $null = Resolve-IaGroupName -Id 'gid-forbidden'
            $script:IaDirectoryBlocked | Should -BeTrue
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Call log' {

    It 'Add-IaCall records method, shortened URI, status and count' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
            Clear-IaCallLog
            Add-IaCall -Method 'GET' `
                -Uri 'https://graph.microsoft.com/beta/deviceManagement/managedDevices?$filter=x' `
                -Status 200 -Ms 10 -Count 0
            (Get-IaCallLogEntries)[0].Uri | Should -Match '\?…'
        }
    }

    It 'Clear-IaCallLog empties the log' {
        InModuleScope JustGraphIT {
            Add-IaCall -Method 'GET' -Uri 'https://graph.microsoft.com/beta/foo' -Status 200 -Ms 1 -Count 0
            Clear-IaCallLog
            (Get-IaCallLogEntries).Count | Should -Be 0
        }
    }

    It 'reports the correct count for many entries (entries have a colliding .Count property)' {
        InModuleScope JustGraphIT {
            Clear-IaCallLog
            1..5 | ForEach-Object { Add-IaCall -Method 'GET' -Uri "https://graph.microsoft.com/beta/x$_" -Status 200 -Ms 1 -Count 9 }
            $entries = Get-IaCallLogEntries
            $entries = @($entries)
            $entries.Count | Should -Be 5 -Because 'direct-assign then @($var) must not collapse'
        }
    }

    It 'Get-IntuneCallLog (public) returns one object per recorded call' {
        InModuleScope JustGraphIT {
            Clear-IaCallLog
            1..4 | ForEach-Object { Add-IaCall -Method 'GET' -Uri "https://graph.microsoft.com/beta/y$_" -Status 200 -Ms 1 -Count 3 }
            @(Get-IntuneCallLog).Count       | Should -Be 4
            @(Get-IntuneCallLog -Tail 2).Count | Should -Be 2
        }
    }

    It 'Get-IntuneCallLog returns a single entry as one object, not its Count property' {
        InModuleScope JustGraphIT {
            Clear-IaCallLog
            Add-IaCall -Method 'GET' -Uri 'https://graph.microsoft.com/beta/solo' -Status 200 -Ms 1 -Count 9
            @(Get-IntuneCallLog).Count | Should -Be 1 -Because 'one call logged → one row, despite the entry.Count=9 field'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Transient retry (throttling / 429 / 503)' {

    Context 'Get-IaErrorStatus extraction' {
        It 'pulls 429 from a Too Many Requests message' {
            InModuleScope JustGraphIT {
                $er = try { throw 'Response status code 429 (Too Many Requests)' } catch { $_ }
                Get-IaErrorStatus $er | Should -Be 429
            }
        }
        It 'pulls 404 from the message text' {
            InModuleScope JustGraphIT {
                $er = try { throw 'The server returned 404 Not Found' } catch { $_ }
                Get-IaErrorStatus $er | Should -Be 404
            }
        }
        It 'returns 0 when no status is discoverable' {
            InModuleScope JustGraphIT {
                $er = try { throw 'totally opaque failure' } catch { $_ }
                Get-IaErrorStatus $er | Should -Be 0
            }
        }
    }

    Context 'Test-IaRetryable policy' {
        It 'retries 429 on any verb, but 503/504 only on idempotent verbs (not POST)' {
            InModuleScope JustGraphIT {
                Test-IaRetryable -Status 429 -Method POST  | Should -BeTrue   # rejected pre-processing
                Test-IaRetryable -Status 503 -Method PATCH | Should -BeTrue
                Test-IaRetryable -Status 504 -Method GET   | Should -BeTrue
                Test-IaRetryable -Status 504 -Method DELETE| Should -BeTrue
                # a 504 can fire after a POST create committed — retrying would duplicate
                Test-IaRetryable -Status 503 -Method POST  | Should -BeFalse
                Test-IaRetryable -Status 504 -Method POST  | Should -BeFalse
            }
        }
        It 'retries 500 only on idempotent GET' {
            InModuleScope JustGraphIT {
                Test-IaRetryable -Status 500 -Method GET  | Should -BeTrue
                Test-IaRetryable -Status 500 -Method POST | Should -BeFalse
            }
        }
        It 'never retries ordinary 4xx (404/403)' {
            InModuleScope JustGraphIT {
                Test-IaRetryable -Status 404 -Method GET | Should -BeFalse
                Test-IaRetryable -Status 403 -Method GET | Should -BeFalse
            }
        }
    }

    Context 'Invoke-IaRequest retry loop' {
        BeforeEach {
            InModuleScope JustGraphIT {
                # The Graph SDK isn't installed offline; define a module-scope stub
                # (script: so it persists out of this child scope) for Pester to mock.
                function script:Invoke-MgGraphRequest { [CmdletBinding()] param([string]$Method, [string]$Uri, $Body, [string]$ContentType, [hashtable]$Headers, [string]$OutputType) }
                $script:IaMgFeatures = $null
                $script:IaRetryBaseMs = 1
                $script:IaMaxRetry = 4
                Clear-IaCallLog
            }
        }

        It 'retries a throttled call then returns the success payload' {
            InModuleScope JustGraphIT {
                Mock Start-Sleep {}
                $script:__retryN = 0
                Mock Invoke-MgGraphRequest {
                    $script:__retryN++
                    if ($script:__retryN -lt 3) { throw 'Response status code 429 (Too Many Requests)' }
                    [pscustomobject]@{ value = @(1, 2) }
                }
                $r = Invoke-IaRequest -Method GET -Uri 'https://graph.microsoft.com/beta/users'
                @($r.value).Count | Should -Be 2
                Should -Invoke Invoke-MgGraphRequest -Times 3 -Exactly
                Should -Invoke Start-Sleep -Times 2 -Exactly
            }
        }

        It 'does not retry a 404 — throws on the first attempt' {
            InModuleScope JustGraphIT {
                Mock Start-Sleep {}
                Mock Invoke-MgGraphRequest { throw 'Response status code 404 (Not Found)' }
                { Invoke-IaRequest -Method GET -Uri 'https://graph.microsoft.com/beta/x' } | Should -Throw
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly
            }
        }

        It 'does not retry a 500 on a write (POST)' {
            InModuleScope JustGraphIT {
                Mock Start-Sleep {}
                Mock Invoke-MgGraphRequest { throw 'Response status code 500 (Internal Server Error)' }
                { Invoke-IaRequest -Method POST -Uri 'https://graph.microsoft.com/beta/x' -Body @{ a = 1 } } | Should -Throw
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly
            }
        }

        It 'gives up after IaMaxRetry attempts on persistent throttling' {
            InModuleScope JustGraphIT {
                Mock Start-Sleep {}
                Mock Invoke-MgGraphRequest { throw 'Response status code 503 (Service Unavailable)' }
                { Invoke-IaRequest -Method GET -Uri 'https://graph.microsoft.com/beta/x' } | Should -Throw
                Should -Invoke Invoke-MgGraphRequest -Times 5 -Exactly  # initial + 4 retries
            }
        }

        It 'logs the transient retry then the success in the call log' {
            InModuleScope JustGraphIT {
                Mock Start-Sleep {}
                $script:__retryN2 = 0
                Mock Invoke-MgGraphRequest {
                    $script:__retryN2++
                    if ($script:__retryN2 -lt 2) { throw 'Response status code 429 (Too Many Requests)' }
                    [pscustomobject]@{ value = @() }
                }
                Invoke-IaRequest -Method GET -Uri 'https://graph.microsoft.com/beta/users' | Out-Null
                $log = Get-IaCallLogEntries
                $log[0].Status | Should -Be 429
                $log[0].Error  | Should -Match 'transient 429'
            }
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Inventory, compare and copy (mocked Graph)' {

    BeforeEach {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
            $items = Get-IaInventory -Type 'configurationPolicies' -AssignedOnly
            $cp = $items | Where-Object Name -eq 'Win Baseline'
            ($cp.Assignments | Where-Object { -not $_.Target.IsExclude }).Target.GroupName |
                Should -Be 'All Workstations'
            ($cp.Assignments | Where-Object { $_.Target.IsExclude }).Target.GroupName |
                Should -Be 'Pilot Ring'
        }
    }

    It 'compares two groups into buckets' {
        InModuleScope JustGraphIT {
            $items = Get-IaInventory -Type 'configurationPolicies' -AssignedOnly
            (Get-IaItemGroupMode -Item ($items | Where-Object Name -eq 'Win Baseline') -GroupId 'bbbb') |
                Should -Be 'exclude'
            (Get-IaItemGroupMode -Item ($items | Where-Object Name -eq 'Only-A') -GroupId 'bbbb') |
                Should -Be 'none'
        }
    }

    It 'detects mixed include+exclude on same group' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
            $items = Get-IaInventory -Type 'configurationPolicies' -AssignedOnly
            $plans = Invoke-IaCopy -Items $items -SrcId 'aaaa' -DstId 'cccc' -DstName 'New Devices' -IncludeIds @('cp2') -Commit
            @($plans | Where-Object Added).Count | Should -Be 1
            $script:Posts.Count                  | Should -Be 1
            $script:Posts[0].Uri                 | Should -Match 'configurationPolicies/cp2/assign'
        }
    }

    It 'preview (no -Commit) writes nothing' {
        InModuleScope JustGraphIT {
            $items = Get-IaInventory -Type 'configurationPolicies' -AssignedOnly
            $null = Invoke-IaCopy -Items $items -SrcId 'aaaa' -DstId 'cccc'
            $script:Posts.Count | Should -Be 0
        }
    }

    It 'AssignedOnly filters out unassigned items' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
            Mock Invoke-IaRequest { [pscustomobject]@{ id='dev-1'; deviceName='WORKGROUP-PC'; azureADDeviceId=$null } }
            { Get-IntuneLapsCredential -Device '12345678-0000-0000-0000-000000000002' } | Should -Throw '*Azure AD device ID*'
        }
    }
}

Describe 'Public cmdlets — Get-IntuneDeviceGroupMembership' {

    It 'returns transitive groups with names and flags dynamic membership rules' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
            Mock Resolve-IaDevice { [pscustomobject]@{ Id=$null; DisplayName=$null } }
            { Get-IntuneDeviceGroupMembership -Device 'nope' } | Should -Throw '*resolve*'
        }
    }
}

Describe 'Public cmdlets — Get-IntuneUserDevice' {

    It 'filters managedDevices by userPrincipalName and projects device fields' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
            $script:capturedPath = $null
            Mock Get-IaCollection { $script:capturedPath = $Path; @() }
            Get-IntuneUserDevice -User "o'brien@contoso.com" | Out-Null
            $script:capturedPath | Should -Match "o''brien@contoso.com"   # doubled, not a broken quote
        }
    }
}

Describe 'Public cmdlets — Get-IntuneDeviceManagedApp' {

    It 'projects intent + install state for the device primary user' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
            Mock Resolve-IaManagedDeviceId { 'mdm-2' }
            Mock Invoke-IaRequest { [pscustomobject]@{ id='mdm-2'; deviceName='KIOSK-01'; userId=$null; userPrincipalName=$null } }
            $r = @(Get-IntuneDeviceManagedApp -Device 'KIOSK-01' -WarningAction SilentlyContinue)
            $r.Count | Should -Be 0
        }
    }
}

Describe 'Public cmdlets — Get-IntuneUserGroupMembership' {

    It 'classifies group Kind + Membership from the beta /users transitiveMemberOf set' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
            $script:capturedPath = $null
            Mock Invoke-IaRequest { [pscustomobject]@{ id='u-7'; userPrincipalName='x@contoso.com' } }
            Mock Get-IaCollection { $script:capturedPath = $Path; @() }
            Get-IntuneUserGroupMembership -User 'x@contoso.com' | Out-Null
            $script:capturedPath | Should -Match 'users/u-7/transitiveMemberOf/microsoft.graph.group'
        }
    }

    It 'throws when the user cannot be resolved' {
        InModuleScope JustGraphIT {
            Mock Invoke-IaRequest { [pscustomobject]@{ id=$null } }
            { Get-IntuneUserGroupMembership -User 'ghost@contoso.com' } | Should -Throw '*resolve*'
        }
    }
}

Describe 'Public cmdlets — Get-IntuneUserLicense' {

    It 'maps SKU part numbers to friendly names and counts enabled service plans' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
            $script:capturedPath = $null
            Mock Get-IaCollection { $script:capturedPath = $Path; @() }
            Get-IntuneUserLicense -User 'alice@contoso.com' | Out-Null
            $script:capturedPath | Should -Match 'users/alice%40contoso.com/licenseDetails'
        }
    }
}

Describe 'Public cmdlets — Get-IntuneDeviceComplianceDetail' {

    It 'reads inline settingStates; -FailingOnly drops compliant/notApplicable' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
            Mock Resolve-IaManagedDeviceId { 'md-1' }
            $script:capUri = $null; $script:capBody = $null
            Mock Invoke-IaRequest { $script:capUri = $Uri; $script:capBody = $Body }

            Invoke-IntuneDeviceAction -Device 'LAPTOP-01' -Action Sync -Confirm:$false | Out-Null
            $script:capUri | Should -Match '/managedDevices/md-1/syncDevice$'

            Invoke-IntuneDeviceAction -Device 'LAPTOP-01' -Action Rename -NewName 'NEW-PC' -Confirm:$false | Out-Null
            $script:capUri             | Should -Match '/managedDevices/md-1/setDeviceName$'   # NOT 'rename' (that binds to cloudPC)
            $script:capBody.deviceName | Should -Be 'NEW-PC'

            Invoke-IntuneDeviceAction -Device 'LAPTOP-01' -Action CollectDiagnostics -Confirm:$false | Out-Null
            $script:capUri               | Should -Match '/managedDevices/md-1/createDeviceLogCollectionRequest$'   # NOT 'collectDiagnostics'
            $script:capBody.templateType | Should -Be 'predefined'   # plain enum string, NOT a nested object
        }
    }
}

Describe 'Public cmdlets — null @odata.type robustness (no hashtable null-index crash)' {

    It 'Get-IntuneCompliancePolicy tolerates a policy with no @odata.type' {
        InModuleScope JustGraphIT {
            Mock Invoke-IaRequest { [pscustomobject]@{ value = @([pscustomobject]@{ id = 'p1'; displayName = 'No-Type Policy' }) } }
            { Get-IntuneCompliancePolicy } | Should -Not -Throw
        }
    }

    It 'Get-IntuneApp tolerates an app with no @odata.type' {
        InModuleScope JustGraphIT {
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

    It 'strips JUSTGRAPHIT markup from cell values' {
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
        InModuleScope JustGraphIT {
            $script:posted = $null
            Mock Invoke-IaWebhookPost { $script:posted = [pscustomobject]@{ Uri = $Uri; Json = $Json } }
            [pscustomobject]@{ X = 1 } | Send-IntuneReportToTeams -Title 'Push' -WebhookUrl 'https://hook.example/abc' -Confirm:$false
            $script:posted.Uri  | Should -Be 'https://hook.example/abc'
            $script:posted.Json | Should -Match 'AdaptiveCard'
            Should -Invoke Invoke-IaWebhookPost -Times 1 -Exactly
        }
    }

    It 'throws when no webhook URL is available and not -PassThru' {
        InModuleScope JustGraphIT {
            $saved = $env:JUSTGRAPHIT_TEAMS_WEBHOOK; $env:JUSTGRAPHIT_TEAMS_WEBHOOK = ''
            try { { [pscustomobject]@{ X = 1 } | Send-IntuneReportToTeams -Title 'NoUrl' -Confirm:$false } | Should -Throw '*webhook*' }
            finally { $env:JUSTGRAPHIT_TEAMS_WEBHOOK = $saved }
        }
    }
}

Describe 'Reporting · ConvertTo-IaDateTime (locale-robust date parsing)' {

    It 'parses relative spans (7d / 24h / 2w)' {
        InModuleScope JustGraphIT {
            (ConvertTo-IaDateTime '7d')  | Should -BeOfType [datetime]
            ((Get-Date).ToUniversalTime() - (ConvertTo-IaDateTime '7d')).TotalDays | Should -BeGreaterThan 6.5
        }
    }

    It 'parses an ISO 8601 absolute date regardless of host culture' {
        InModuleScope JustGraphIT {
            (ConvertTo-IaDateTime '2026-01-15').Year  | Should -Be 2026
            (ConvertTo-IaDateTime '2026-01-15').Month | Should -Be 1
        }
    }

    It 'throws a helpful error on an unparseable value (not a silent bad date)' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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

    It 'exports Connect-JustGraphIT' {
        Get-Command Connect-JustGraphIT -Module JustGraphIT | Should -Not -BeNullOrEmpty
    }

    It 'exports Get-IntuneApp' {
        Get-Command Get-IntuneApp -Module JustGraphIT | Should -Not -BeNullOrEmpty
    }

    It 'exports all expected public cmdlets' {
        $expected = @(
            'Connect-JustGraphIT', 'Get-IntuneApp', 'Get-IntuneScript',
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
        $exported = (Get-Module JustGraphIT).ExportedCommands.Keys
        foreach ($cmd in $expected) {
            $exported | Should -Contain $cmd -Because "$cmd must be a public export"
        }
    }

    It 'does not export private helpers' {
        $exported = (Get-Module JustGraphIT).ExportedCommands.Keys
        $exported | Should -Not -Contain 'Invoke-IaRequest'
        $exported | Should -Not -Contain 'Get-IaCollection'
        $exported | Should -Not -Contain 'Resolve-IaUri'
        $exported | Should -Not -Contain 'ConvertFrom-IaTarget'
        $exported | Should -Not -Contain 'Get-IaInventory'
    }

    It 'does not export the internal TUI engine functions' {
        $exported = (Get-Module JustGraphIT).ExportedCommands.Keys
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
        InModuleScope JustGraphIT {
            # This is the exact input that produced "Could not find color 'Apps'".
            { ConvertFrom-IaMarkup -Text 'area [Apps] x' } | Should -Not -Throw
            (Strip-IaMarkup -Text 'area [Apps] x') | Should -Be 'area [Apps] x'
        }
    }

    It 'renders a group literally named with brackets without throwing' {
        InModuleScope JustGraphIT {
            { ConvertFrom-IaMarkup -Text 'Group [Test] assigned' } | Should -Not -Throw
            (Strip-IaMarkup -Text 'Group [Test] assigned') | Should -Be 'Group [Test] assigned'
        }
    }

    It 'converts a known colour tag to an ANSI escape' {
        InModuleScope JustGraphIT {
            $esc = [char]0x1B
            (ConvertFrom-IaMarkup -Text '[grey]hello[/]') | Should -Match ([regex]::Escape($esc))
            (Strip-IaMarkup -Text '[grey]hello[/]') | Should -Be 'hello'
        }
    }

    It 'handles compound and nested tags without throwing' {
        InModuleScope JustGraphIT {
            { ConvertFrom-IaMarkup -Text '[bold white]x[/]' } | Should -Not -Throw
            { ConvertFrom-IaMarkup -Text '[grey]a[red]b[/]c[/]' } | Should -Not -Throw
            (Strip-IaMarkup -Text '[grey]a[red]b[/]c[/]') | Should -Be 'abc'
        }
    }

    It 'tolerates a stray closing tag' {
        InModuleScope JustGraphIT {
            { ConvertFrom-IaMarkup -Text 'no open[/] here' } | Should -Not -Throw
        }
    }

    It 'Strip and Convert agree on the visible text for a mixed string' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
            (Protect-IaMarkup -Text '[Test]') | Should -Be '[[Test]]'
            (ConvertFrom-IaMarkup -Text (Protect-IaMarkup -Text '[red]')) | Should -Be '[red]'
            (Strip-IaMarkup -Text (Protect-IaMarkup -Text '[red]')) | Should -Be '[red]'
        }
    }

    It 'treats empty / null input safely' {
        InModuleScope JustGraphIT {
            (ConvertFrom-IaMarkup -Text '') | Should -Be ''
            (Strip-IaMarkup -Text '') | Should -Be ''
            (Measure-IaWidth -Text '') | Should -Be 0
        }
    }
}

Describe 'TUI engine · colour & width' {

    It 'maps every accent / colour name the TUI uses' {
        InModuleScope JustGraphIT {
            # Includes every theme accent: green/amber(orange1)/lego(yellow)/deepsea
            # (turquoise2)/sunset(coral)/ocean(deepskyblue1)/forest(lime)/mono(silver).
            foreach ($c in 'green','orange1','yellow','turquoise2','coral','red',
                           'grey','white','deepskyblue1','darkslategray1','lime','silver','bold','dim') {
                (Get-IaAnsi $c) | Should -Not -Be '' -Because "$c is used in the TUI"
            }
        }
    }

    It 'returns empty (no throw) for an unknown colour name' {
        InModuleScope JustGraphIT {
            (Get-IaAnsi 'Apps') | Should -Be ''
            (Get-IaAnsi '') | Should -Be ''
        }
    }

    It 'measures ascii and wide characters' {
        InModuleScope JustGraphIT {
            (Measure-IaWidth -Text 'hello') | Should -Be 5
            (Measure-IaWidth -Text '世界')   | Should -Be 4   # 2 wide CJK glyphs
        }
    }
}

Describe 'TUI engine · mouse event classification' {
    # SGR mouse reports are  ESC [ < button ; col ; row  M/m. The classifiers below
    # turn a parsed event into the gesture the menus/tables act on.

    It 'recognises a left-button press as a click (and ignores its release)' {
        InModuleScope JustGraphIT {
            $press   = @{ Type='mouse'; Button=0; X=5; Y=3; Press=$true }
            $release = @{ Type='mouse'; Button=0; X=5; Y=3; Press=$false }
            (Test-IaMouseLeftClick $press)   | Should -BeTrue
            (Test-IaMouseLeftClick $release) | Should -BeFalse  # release must not re-fire the action
        }
    }

    It 'distinguishes wheel-up (64) from wheel-down (65)' {
        InModuleScope JustGraphIT {
            $up   = @{ Type='mouse'; Button=64; X=1; Y=1; Press=$true }
            $down = @{ Type='mouse'; Button=65; X=1; Y=1; Press=$true }
            [bool](Test-IaMouseWheelUp   $up)   | Should -BeTrue
            [bool](Test-IaMouseWheelDown $up)   | Should -BeFalse
            [bool](Test-IaMouseWheelDown $down) | Should -BeTrue
            [bool](Test-IaMouseWheelUp   $down) | Should -BeFalse
        }
    }

    It 'does not classify a wheel event as a click' {
        InModuleScope JustGraphIT {
            $wheel = @{ Type='mouse'; Button=64; X=1; Y=1; Press=$true }
            (Test-IaMouseLeftClick $wheel) | Should -BeFalse
        }
    }

    It 'treats a modified left click (e.g. Ctrl held) as a click but a right click as not' {
        InModuleScope JustGraphIT {
            $ctrlLeft = @{ Type='mouse'; Button=16; X=2; Y=2; Press=$true }  # +Ctrl modifier bit
            $right    = @{ Type='mouse'; Button=2;  X=2; Y=2; Press=$true }
            (Test-IaMouseLeftClick $ctrlLeft) | Should -BeTrue
            (Test-IaMouseLeftClick $right)    | Should -BeFalse
        }
    }
}

Describe 'TUI engine · id masking (Format-IaMaskedId)' {

    It 'reveals only the last 4 characters of a tenant GUID by default' {
        InModuleScope JustGraphIT {
            $masked = Format-IaMaskedId '11111111-2222-3333-4444-555555555555'
            $masked | Should -BeLike '*5555'
            $masked | Should -Not -Match '1111|2222|3333|4444'   # nothing identifiable leaks
            $masked | Should -Match '^•+5555$'                   # bullets + last 4 only
        }
    }

    It 'hides everything when -Reveal 0' {
        InModuleScope JustGraphIT {
            $masked = Format-IaMaskedId '11111111-2222-3333-4444-555555555555' -Reveal 0
            $masked | Should -Not -Match '[0-9a-fA-F]'           # no hex at all
            $masked | Should -Match '^•+$'
        }
    }

    It 'passes through empty / null without throwing' {
        InModuleScope JustGraphIT {
            (Format-IaMaskedId '')    | Should -Be ''
            (Format-IaMaskedId $null) | Should -BeNullOrEmpty
        }
    }
}

Describe 'TUI engine · Graph-calls footer (Get-IaCallFooter)' {

    It 'is empty when no calls have been logged' {
        InModuleScope JustGraphIT {
            Clear-IaCallLog
            (Get-IaCallFooter) | Should -Be ''
        }
    }

    It 'reports the true call count and recent calls (no double-wrap)' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
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
            Where-Object { $_.Name -ne 'JustGraphIT.Tests.ps1' }
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
        $psd = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'JustGraphIT.psd1')
        [version]$psd.PowerShellVersion | Should -BeGreaterOrEqual ([version]'7.0')
        # No CompatiblePSEditions = 'Desktop'-only lock (Desktop edition is Windows-only)
        if ($psd.ContainsKey('CompatiblePSEditions')) {
            $psd.CompatiblePSEditions | Should -Contain 'Core'
        }
    }
}

Describe 'TUI engine · table rendering' {

    It 'renders objects with markup cells without throwing' {
        InModuleScope JustGraphIT {
            $rows = @(
                [pscustomobject]@{ Area = '[green]Apps[/]'; Resource = 'Chrome [stable]'; Assigned = '[coral]EXCLUDE grp[/]' }
                [pscustomobject]@{ Area = '[green]Compliance[/]'; Resource = 'Win10'; Assigned = 'grpA; grpB' }
            )
            { Show-IaTableObjects -Rows $rows -Color turquoise2 -Title 'T [x]' 6>&1 } | Should -Not -Throw
        }
    }

    It 'produces no output for empty input' {
        InModuleScope JustGraphIT {
            $out = Show-IaTableObjects -Rows @() -Color grey -Title 'x' 6>&1
            $out | Should -BeNullOrEmpty
        }
    }

    It 'Format-IaTable accepts the exact -Data / -Accent / -Title form that crashed Spectre' {
        InModuleScope JustGraphIT {
            $rows = 1..3 | ForEach-Object { [pscustomobject]@{ Name = "App $_"; Type = 'Win32'; Publisher = 'Acme' } }
            { Format-IaTable -Data $rows -Accent turquoise2 -Title 'Apps' 6>&1 } | Should -Not -Throw
            { Format-IaTable -Data $rows -Accent turquoise2 -Title '[Apps]' 6>&1 } | Should -Not -Throw
        }
    }

    It 'Format-IaTable accepts pipeline input with markup cells' {
        InModuleScope JustGraphIT {
            $rows = 1..2 | ForEach-Object { [pscustomobject]@{ A = "[coral]x$_[/]"; B = '[Test]' } }
            { $rows | Format-IaTable -Color turquoise2 6>&1 } | Should -Not -Throw
        }
    }
}

Describe 'TUI engine · menus & prompts (non-interactive fallback)' {

    It 'Read-IaMultiMenu never throws on bracketed / area-style labels' {
        InModuleScope JustGraphIT {
            Mock Test-IaArrowSupport { $false }
            Mock Read-Host { '1 2' }
            $labels = @('1. (Apps) Chrome', '2. [Apps] Edge', '3. [Test] policy')
            { Read-IaMultiMenu -Title 'pick' -Choices $labels 6>&1 } | Should -Not -Throw
        }
    }

    It 'Read-IaMenu returns the chosen string' {
        InModuleScope JustGraphIT {
            Mock Test-IaArrowSupport { $false }
            Mock Read-Host { '3' }
            (Read-IaMenu -Title 'pick' -Choices @('a', 'b', 'c') -Color grey) | Should -Be 'c'
        }
    }

    It 'Read-IaMenu treats blank input as the first choice' {
        InModuleScope JustGraphIT {
            Mock Test-IaArrowSupport { $false }
            Mock Read-Host { '' }
            (Read-IaMenu -Title 'pick' -Choices @('a', 'b', 'c')) | Should -Be 'a'
        }
    }

    It 'Read-IaMenu returns $null for an empty choice list' {
        InModuleScope JustGraphIT {
            (Read-IaMenu -Title 'pick' -Choices @()) | Should -BeNullOrEmpty
        }
    }

    It 'Read-IaMultiMenu returns the chosen strings' {
        InModuleScope JustGraphIT {
            Mock Test-IaArrowSupport { $false }
            Mock Read-Host { '1 3' }
            $r = @(Read-IaMultiMenu -Title 'm' -Choices @('a', 'b', 'c'))
            ($r -join ',') | Should -Be 'a,c'
        }
    }

    It 'Read-IaMultiMenu supports "all"' {
        InModuleScope JustGraphIT {
            Mock Test-IaArrowSupport { $false }
            Mock Read-Host { 'all' }
            $r = @(Read-IaMultiMenu -Title 'm' -Choices @('a', 'b', 'c'))
            ($r -join ',') | Should -Be 'a,b,c'
        }
    }

    It 'Read-IaMultiMenu returns empty for blank input' {
        InModuleScope JustGraphIT {
            Mock Test-IaArrowSupport { $false }
            Mock Read-Host { '' }
            @(Read-IaMultiMenu -Title 'm' -Choices @('a', 'b', 'c')).Count | Should -Be 0
        }
    }

    It 'Read-IaText returns the default on blank, typed value otherwise' {
        InModuleScope JustGraphIT {
            Mock Read-Host { '' }
            (Read-IaText -Question 'name' -DefaultAnswer 'baseline') | Should -Be 'baseline'
        }
        InModuleScope JustGraphIT {
            Mock Read-Host { 'custom' }
            (Read-IaText -Question 'name' -DefaultAnswer 'baseline') | Should -Be 'custom'
        }
    }

    It 'Read-IaConfirm honours y / n / default' {
        InModuleScope JustGraphIT {
            Mock Read-Host { 'y' }
            (Read-IaConfirm -Message 'ok?') | Should -BeTrue
        }
        InModuleScope JustGraphIT {
            Mock Read-Host { 'n' }
            (Read-IaConfirm -Message 'ok?' -DefaultAnswer $true) | Should -BeFalse
        }
        InModuleScope JustGraphIT {
            Mock Read-Host { '' }
            (Read-IaConfirm -Message 'ok?' -DefaultAnswer $true) | Should -BeTrue
        }
    }
}

Describe 'TUI engine · status wrapper' {

    It 'returns the script block output' {
        InModuleScope JustGraphIT {
            (Invoke-IaStatus -Title 'load' -ScriptBlock { 42 }) | Should -Be 42
        }
    }

    It 'runs the block in its defining scope (no $using needed)' {
        InModuleScope JustGraphIT {
            $thing = 'Win32'
            (Invoke-IaStatus -Title 'load' -ScriptBlock { "saw $thing" }) | Should -Be 'saw Win32'
        }
    }

    It 'lets the block write a script-scoped variable' {
        InModuleScope JustGraphIT {
            $script:_iaTestOut = $null
            Invoke-IaStatus -Title 'load' -ScriptBlock { $script:_iaTestOut = 'done' } | Out-Null
            $script:_iaTestOut | Should -Be 'done'
        }
    }

    It 're-throws errors from the block' {
        InModuleScope JustGraphIT {
            { Invoke-IaStatus -Title 'load' -ScriptBlock { throw 'boom' } } | Should -Throw 'boom'
        }
    }
}

Describe 'TUI engine · output primitives do not throw' {

    It 'Write-IaHost / Write-IaRule / Write-IaFiglet render without throwing' {
        InModuleScope JustGraphIT {
            { Write-IaHost '[turquoise2]hi[/] [Apps] plain' 6>&1 } | Should -Not -Throw
            { Write-IaRule -Title 'sect' -Color darkslategray1 6>&1 } | Should -Not -Throw
            { Write-IaRule -Color grey 6>&1 } | Should -Not -Throw
            { Write-IaFiglet -Text 'JUSTGRAPHIT' -Color turquoise2 6>&1 } | Should -Not -Throw
            { Write-IaFiglet -Text 'Other Words' -Color green 6>&1 } | Should -Not -Throw
        }
    }

    It 'Get-IaFigletString returns a multi-line banner for JUSTGRAPHIT' {
        InModuleScope JustGraphIT {
            $banner = Get-IaFigletString -Text 'JUSTGRAPHIT' -Color turquoise2
            $banner | Should -Not -BeNullOrEmpty
            @($banner -split "`n").Count | Should -Be 5 -Because 'the block font is five rows tall'
        }
    }

    It 'Read-IaMenu accepts a -Header without throwing (non-interactive fallback)' {
        InModuleScope JustGraphIT {
            Mock Test-IaArrowSupport { $false }
            Mock Read-Host { '1' }
            { Read-IaMenu -Title 'pick' -Header "BANNER`nLINE2" -Choices @('a', 'b') 6>&1 } | Should -Not -Throw
        }
    }
}

Describe 'TUI engine · report predicate' {

    It 'evaluates string operators' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT {
            # Lexically "9" > "10"; numerically 9 < 10. Must use numeric.
            Test-IaReportPredicate -Value 9  -Operator lt -Operand 10 | Should -BeTrue
            Test-IaReportPredicate -Value 45 -Operator gt -Operand 30 | Should -BeTrue
            Test-IaReportPredicate -Value 30 -Operator ge -Operand 30 | Should -BeTrue
            Test-IaReportPredicate -Value 30 -Operator le -Operand 30 | Should -BeTrue
        }
    }

    It 'evaluates empty / boolean operators' {
        InModuleScope JustGraphIT {
            Test-IaReportPredicate -Value ''       -Operator isempty  -Operand '' | Should -BeTrue
            Test-IaReportPredicate -Value $null    -Operator isempty  -Operand '' | Should -BeTrue
            Test-IaReportPredicate -Value 'x'      -Operator notempty -Operand '' | Should -BeTrue
            Test-IaReportPredicate -Value 'True'   -Operator istrue   -Operand '' | Should -BeTrue
            Test-IaReportPredicate -Value 'False'  -Operator isfalse  -Operand '' | Should -BeTrue
        }
    }

    It 'never throws on a bad regex' {
        InModuleScope JustGraphIT {
            { Test-IaReportPredicate -Value 'x' -Operator match -Operand '[unterminated' } | Should -Not -Throw
            Test-IaReportPredicate -Value 'x' -Operator match -Operand '[unterminated' | Should -BeFalse
        }
    }

    It 'compares dates chronologically' {
        InModuleScope JustGraphIT {
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
        InModuleScope JustGraphIT -Parameters @{ data = $script:rptData } {
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
        InModuleScope JustGraphIT -Parameters @{ data = $script:rptData } {
            param($data)
            $r = Invoke-IaReportPipeline -Data $data -Recipe @{
                Where = @(); Sort = @(@{ Prop = 'Days'; Desc = $true }); Select = @(); Top = 0; GroupBy = $null; Agg = $null
            }
            $r[0].Device  | Should -Be 'PC-2'   # 45
            $r[-1].Device | Should -Be 'PC-1'   # 2
        }
    }

    It 'projects with SELECT' {
        InModuleScope JustGraphIT -Parameters @{ data = $script:rptData } {
            param($data)
            $r = Invoke-IaReportPipeline -Data $data -Recipe @{
                Where = @(); Sort = @(); Select = @('Device', 'OS'); Top = 0; GroupBy = $null; Agg = $null
            }
            @($r[0].PSObject.Properties.Name) | Should -Be @('Device', 'OS')
        }
    }

    It 'limits with TOP' {
        InModuleScope JustGraphIT -Parameters @{ data = $script:rptData } {
            param($data)
            $r = Invoke-IaReportPipeline -Data $data -Recipe @{
                Where = @(); Sort = @(); Select = @(); Top = 2; GroupBy = $null; Agg = $null
            }
            @($r).Count | Should -Be 2
        }
    }

    It 'groups with COUNT' {
        InModuleScope JustGraphIT -Parameters @{ data = $script:rptData } {
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
        InModuleScope JustGraphIT -Parameters @{ data = $script:rptData } {
            param($data)
            $r = Invoke-IaReportPipeline -Data $data -Recipe @{
                Where = @(); Sort = @(); Select = @(); Top = 0; GroupBy = 'OS'; Agg = @{ Func = 'Sum'; Prop = 'GB' }
            }
            $win = $r | Where-Object { $_.OS -eq 'Windows' }
            $win.'Sum(GB)' | Should -Be 896   # 256 + 512 + 128
        }
    }

    It 'groups with AVG aggregate' {
        InModuleScope JustGraphIT -Parameters @{ data = $script:rptData } {
            param($data)
            $r = Invoke-IaReportPipeline -Data $data -Recipe @{
                Where = @(); Sort = @(); Select = @(); Top = 0; GroupBy = 'Compliance'; Agg = @{ Func = 'Avg'; Prop = 'Days' }
            }
            $nc = $r | Where-Object { $_.Compliance -eq 'noncompliant' }
            $nc.'Avg(Days)' | Should -Be 24    # (45 + 3) / 2
        }
    }

    It 'yields exactly one element for a single-row match (wrapped by caller)' {
        InModuleScope JustGraphIT -Parameters @{ data = $script:rptData } {
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
        InModuleScope JustGraphIT -Parameters @{ data = $script:rptData } {
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
        InModuleScope JustGraphIT {
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

Describe 'Get-IntunePatchReport (patch reporting from Intune update reports)' {

    It 'normalizes quality + feature rows to one common shape (tagged by UpdateType)' {
        InModuleScope JustGraphIT {
            Mock Invoke-IaReportExport {
                @(
                    [pscustomobject]@{ DeviceName='PC-1'; UPN='a@x.com'; PolicyName='QU-Ring'; AggregateState='Success'; CurrentDeviceUpdateStatus='UpToDate'; CurrentDeviceUpdateSubstatus=''; LatestAlertMessage=''; EventDateTimeUTC='2026-06-01' }
                    [pscustomobject]@{ DeviceName='PC-2'; UPN='b@x.com'; PolicyName='QU-Ring'; AggregateState='Error';   CurrentDeviceUpdateStatus='Failed';   CurrentDeviceUpdateSubstatus='DownloadError'; LatestAlertMessage='0x80070002'; EventDateTimeUTC='2026-06-02' }
                )
            } -ParameterFilter { $ReportName -eq 'QualityUpdateDeviceStatusByPolicy' }
            Mock Invoke-IaReportExport {
                @(
                    [pscustomobject]@{ DeviceName='PC-1'; UPN='a@x.com'; PolicyName='FU-23H2'; AggregateState='Success'; FeatureUpdateVersion='Windows 11, version 23H2'; CurrentDeviceUpdateStatus='UpToDate'; EventDateTimeUTC='2026-06-01' }
                )
            } -ParameterFilter { $ReportName -eq 'FeatureUpdateDeviceState' }

            $r = @(Get-IntunePatchReport)
            $r.Count | Should -Be 3
            @($r | Where-Object UpdateType -eq 'Quality').Count | Should -Be 2
            @($r | Where-Object UpdateType -eq 'Feature').Count | Should -Be 1
            ($r | Where-Object Device -eq 'PC-2').State | Should -Be 'Error'
            # Feature 'Detail' surfaces the target version; quality surfaces the alert message.
            ($r | Where-Object UpdateType -eq 'Feature').Detail | Should -Be 'Windows 11, version 23H2'
            ($r | Where-Object Device -eq 'PC-2').Detail        | Should -Be '0x80070002'
        }
    }

    It '-Summary returns per-(type,state) device counts' {
        InModuleScope JustGraphIT {
            Mock Invoke-IaReportExport {
                @(
                    [pscustomobject]@{ DeviceName='PC-1'; AggregateState='Success' }
                    [pscustomobject]@{ DeviceName='PC-2'; AggregateState='Error' }
                    [pscustomobject]@{ DeviceName='PC-3'; AggregateState='Error' }
                )
            } -ParameterFilter { $ReportName -eq 'QualityUpdateDeviceStatusByPolicy' }
            Mock Invoke-IaReportExport { @() } -ParameterFilter { $ReportName -eq 'FeatureUpdateDeviceState' }

            $s = Get-IntunePatchReport -Type Quality -Summary
            ($s | Where-Object { $_.State -eq 'Success' }).Devices | Should -Be 1
            ($s | Where-Object { $_.State -eq 'Error' }).Devices   | Should -Be 2
        }
    }

    It '-State filters and -Type Quality only runs the quality report' {
        InModuleScope JustGraphIT {
            Mock Invoke-IaReportExport {
                @(
                    [pscustomobject]@{ DeviceName='PC-1'; AggregateState='Success' }
                    [pscustomobject]@{ DeviceName='PC-2'; AggregateState='Error' }
                )
            } -ParameterFilter { $ReportName -eq 'QualityUpdateDeviceStatusByPolicy' }
            Mock Invoke-IaReportExport { throw 'feature report should not run for -Type Quality' } -ParameterFilter { $ReportName -eq 'FeatureUpdateDeviceState' }

            $err = @(Get-IntunePatchReport -Type Quality -State Error)
            $err.Count | Should -Be 1
            $err[0].Device | Should -Be 'PC-2'
        }
    }

    It '-Raw preserves original columns and tags UpdateType' {
        InModuleScope JustGraphIT {
            Mock Invoke-IaReportExport {
                @( [pscustomobject]@{ DeviceName='PC-2'; AggregateState='Error'; LatestAlertMessage='0x80070002' } )
            } -ParameterFilter { $ReportName -eq 'QualityUpdateDeviceStatusByPolicy' }

            $raw = @(Get-IntunePatchReport -Type Quality -Raw)
            $raw[0].UpdateType        | Should -Be 'Quality'
            $raw[0].LatestAlertMessage | Should -Be '0x80070002'
        }
    }
}

Describe 'Entra user cmdlets — beta endpoints, methods and bodies' {

    It 'Get-EntraUser fetches by id with a well-formed ?$select (id not dropped)' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraUserId { 'uid-1' }
            $script:u = $null
            Mock Invoke-IaRequest { $script:u = $Uri; [pscustomobject]@{ id = 'uid-1'; userPrincipalName = 'a@x.com' } }
            Get-EntraUser -User 'a@x.com' | Out-Null
            # Regression: "users/$id?`$select" mis-parses to "users/$select"; require id + ?$select
            $script:u | Should -Match 'graph\.microsoft\.com/beta/users/uid-1\?\$select='
            $script:u | Should -Not -Match 'users/\$select'
        }
    }

    It 'Set-EntraUser disables an account via PATCH /beta/users/{id}' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraUserId { 'uid-1' }
            $script:m=$null;$script:u=$null;$script:b=$null
            Mock Invoke-IaRequest { $script:m=$Method;$script:u=$Uri;$script:b=$Body }
            Set-EntraUser -User 'a@x.com' -AccountEnabled $false -JobTitle 'Tech' -Confirm:$false | Out-Null
            $script:m | Should -Be 'PATCH'
            $script:u | Should -Match 'graph\.microsoft\.com/beta/users/uid-1$'
            $script:b.accountEnabled | Should -Be $false
            $script:b.jobTitle       | Should -Be 'Tech'
        }
    }

    It 'Reset-EntraUserPassword PATCHes a passwordProfile and returns the temp password' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraUserId { 'uid-1' }
            $script:b=$null;$script:u=$null
            Mock Invoke-IaRequest { $script:b=$Body;$script:u=$Uri }
            $r = Reset-EntraUserPassword -User 'a@x.com' -Confirm:$false
            $script:u | Should -Match 'graph\.microsoft\.com/beta/users/uid-1$'
            $script:b.passwordProfile.forceChangePasswordNextSignIn | Should -Be $true
            $r.TempPassword | Should -Not -BeNullOrEmpty
        }
    }

    It 'Revoke-EntraUserSession POSTs revokeSignInSessions (beta)' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraUserId { 'uid-1' }
            $script:m=$null;$script:u=$null
            Mock Invoke-IaRequest { $script:m=$Method;$script:u=$Uri }
            Revoke-EntraUserSession -User 'a@x.com' -Confirm:$false | Out-Null
            $script:m | Should -Be 'POST'
            $script:u | Should -Match 'graph\.microsoft\.com/beta/users/uid-1/revokeSignInSessions$'
        }
    }

    It 'Add-EntraUserToGroup POSTs a beta directoryObjects @odata.id to members/$ref' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraUserId { 'uid-1' }; Mock Resolve-EntraGroupId { 'gid-1' }
            $script:u=$null;$script:b=$null
            Mock Invoke-IaRequest { $script:u=$Uri;$script:b=$Body }
            Add-EntraUserToGroup -User 'a@x.com' -Group 'Sales' -Confirm:$false | Out-Null
            $script:u | Should -Match 'graph\.microsoft\.com/beta/groups/gid-1/members/\$ref$'
            $script:b.'@odata.id' | Should -Match 'graph\.microsoft\.com/beta/directoryObjects/uid-1$'
        }
    }

    It 'Remove-EntraUserFromGroup DELETEs the member ref (beta)' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraUserId { 'uid-1' }; Mock Resolve-EntraGroupId { 'gid-1' }
            $script:m=$null;$script:u=$null
            Mock Invoke-IaRequest { $script:m=$Method;$script:u=$Uri }
            Remove-EntraUserFromGroup -User 'a@x.com' -Group 'Sales' -Confirm:$false | Out-Null
            $script:m | Should -Be 'DELETE'
            $script:u | Should -Match 'graph\.microsoft\.com/beta/groups/gid-1/members/uid-1/\$ref$'
        }
    }

    It 'Set-EntraUserLicense resolves SKU part numbers and POSTs assignLicense (beta)' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraUserId { 'uid-1' }
            Mock Get-IaCollection { @([pscustomobject]@{ skuId='sku-guid-1'; skuPartNumber='ENTERPRISEPACK' }) }
            $script:u=$null;$script:b=$null
            Mock Invoke-IaRequest { $script:u=$Uri;$script:b=$Body }
            Set-EntraUserLicense -User 'a@x.com' -AddSku 'ENTERPRISEPACK' -Confirm:$false | Out-Null
            $script:u | Should -Match 'graph\.microsoft\.com/beta/users/uid-1/assignLicense$'
            $script:b.addLicenses[0].skuId | Should -Be 'sku-guid-1'
        }
    }

    It 'New-EntraUserTempAccessPass POSTs temporaryAccessPassMethods (beta) and returns the pass' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraUserId { 'uid-1' }
            $script:u=$null
            Mock Invoke-IaRequest { $script:u=$Uri; @{ temporaryAccessPass='TAP123'; lifetimeInMinutes=60; isUsableOnce=$true; startDateTime='2026' } }
            $r = New-EntraUserTempAccessPass -User 'a@x.com' -OneTime -Confirm:$false
            $script:u | Should -Match 'graph\.microsoft\.com/beta/users/uid-1/authentication/temporaryAccessPassMethods$'
            $r.TemporaryAccessPass | Should -Be 'TAP123'
        }
    }

    It 'Reset-EntraUserMfa deletes each removable method by its beta method-type segment' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraUserId { 'uid-1' }
            Mock Get-IaCollection { @(
                [pscustomobject]@{ '@odata.type'='#microsoft.graph.fido2AuthenticationMethod'; id='f1' }
                [pscustomobject]@{ '@odata.type'='#microsoft.graph.passwordAuthenticationMethod'; id='p1' }
            ) }
            $script:deletes = New-Object System.Collections.Generic.List[string]
            Mock Invoke-IaRequest { if ($Method -eq 'DELETE') { $script:deletes.Add($Uri) } }
            $r = Reset-EntraUserMfa -User 'a@x.com' -Confirm:$false
            $r.MethodsRemoved | Should -Be 1   # password method is left alone
            ($script:deletes -join ' ') | Should -Match 'graph\.microsoft\.com/beta/users/uid-1/authentication/fido2Methods/f1$'
            ($script:deletes -join ' ') | Should -Not -Match 'passwordMethods'
        }
    }
}

Describe 'Entra group cmdlets — beta endpoints and create bodies' {

    It 'Get-EntraGroup fetches by id with a well-formed ?$select (id not dropped)' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraGroupId { 'gid-1' }
            $script:u = $null
            Mock Invoke-IaRequest { $script:u = $Uri; [pscustomobject]@{ id = 'gid-1'; displayName = 'Eng' } }
            Get-EntraGroup -Group 'Eng' | Out-Null
            $script:u | Should -Match 'graph\.microsoft\.com/beta/groups/gid-1\?\$select='
            $script:u | Should -Not -Match 'groups/\$select'
        }
    }

    It 'New-EntraGroup (Security) POSTs securityEnabled with no groupTypes (beta)' {
        InModuleScope JustGraphIT {
            $script:u=$null;$script:b=$null
            Mock Invoke-IaRequest { $script:u=$Uri;$script:b=$Body; @{ id='g1'; displayName='Sec'; securityEnabled=$true; mailEnabled=$false; groupTypes=@() } }
            New-EntraGroup -Name 'Sec' -Confirm:$false | Out-Null
            $script:u | Should -Match 'graph\.microsoft\.com/beta/groups$'
            $script:b.securityEnabled | Should -Be $true
            $script:b.mailEnabled     | Should -Be $false
            @($script:b.groupTypes).Count | Should -Be 0
        }
    }

    It 'New-EntraGroup (Microsoft365) sets Unified + mailEnabled' {
        InModuleScope JustGraphIT {
            $script:b=$null
            Mock Invoke-IaRequest { $script:b=$Body; @{ id='g2'; groupTypes=@('Unified') } }
            New-EntraGroup -Name 'Team' -Type Microsoft365 -Confirm:$false | Out-Null
            $script:b.groupTypes | Should -Contain 'Unified'
            $script:b.mailEnabled | Should -Be $true
        }
    }

    It 'New-EntraGroup -MembershipRule makes it dynamic' {
        InModuleScope JustGraphIT {
            $script:b=$null
            Mock Invoke-IaRequest { $script:b=$Body; @{ id='g3' } }
            New-EntraGroup -Name 'Dyn' -MembershipRule 'user.department -eq "Sales"' -Confirm:$false | Out-Null
            $script:b.groupTypes | Should -Contain 'DynamicMembership'
            $script:b.membershipRuleProcessingState | Should -Be 'On'
            $script:b.membershipRule | Should -Match 'Sales'
        }
    }

    It 'Add-EntraGroupOwner POSTs a beta directoryObjects ref to owners/$ref' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraGroupId { 'gid-1' }; Mock Resolve-EntraUserId { 'uid-1' }
            $script:u=$null;$script:b=$null
            Mock Invoke-IaRequest { $script:u=$Uri;$script:b=$Body }
            Add-EntraGroupOwner -Group 'Sales' -Owner 'a@x.com' -Confirm:$false | Out-Null
            $script:u | Should -Match 'graph\.microsoft\.com/beta/groups/gid-1/owners/\$ref$'
            $script:b.'@odata.id' | Should -Match 'graph\.microsoft\.com/beta/directoryObjects/uid-1$'
        }
    }

    It 'Remove-EntraGroup DELETEs /beta/groups/{id}' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraGroupId { 'gid-1' }
            $script:m=$null;$script:u=$null
            Mock Invoke-IaRequest { $script:m=$Method;$script:u=$Uri }
            Remove-EntraGroup -Group 'Sales' -Confirm:$false | Out-Null
            $script:m | Should -Be 'DELETE'
            $script:u | Should -Match 'graph\.microsoft\.com/beta/groups/gid-1$'
        }
    }
}

Describe 'Entra access / apps / roles / security — beta endpoint paths' {
    It 'Get-EntraSignIn → beta /auditLogs/signIns with a failures filter' {
        InModuleScope JustGraphIT {
            $script:u=$null; Mock Get-IaCollection { $script:u = $Path; @() }
            Get-EntraSignIn -FailuresOnly -Top 5 | Out-Null
            $script:u | Should -Match 'graph\.microsoft\.com/beta/auditLogs/signIns'
        }
    }
    It 'Set-EntraConditionalAccessState maps reportOnly and PATCHes the beta policy' {
        InModuleScope JustGraphIT {
            $script:u=$null;$script:b=$null;$script:m=$null
            Mock Invoke-IaRequest { $script:u=$Uri;$script:b=$Body;$script:m=$Method }
            Set-EntraConditionalAccessState -Id 'p1' -State reportOnly -Confirm:$false | Out-Null
            $script:m | Should -Be 'PATCH'
            $script:u | Should -Match 'graph\.microsoft\.com/beta/identity/conditionalAccess/policies/p1$'
            $script:b.state | Should -Be 'enabledForReportingButNotEnforced'
        }
    }
    It 'Set-EntraRiskyUser POSTs confirmCompromised with userIds (beta)' {
        InModuleScope JustGraphIT {
            $script:u=$null;$script:b=$null
            Mock Invoke-IaRequest { $script:u=$Uri;$script:b=$Body }
            Set-EntraRiskyUser -UserId 'u1','u2' -Action Compromise -Confirm:$false | Out-Null
            $script:u | Should -Match 'graph\.microsoft\.com/beta/identityProtection/riskyUsers/confirmCompromised$'
            $script:b.userIds | Should -Contain 'u1'
        }
    }
    It 'Get-EntraManagedIdentity filters servicePrincipalType on beta /servicePrincipals' {
        InModuleScope JustGraphIT {
            $script:u=$null; Mock Get-IaCollection { $script:u = $Path; @() }
            Get-EntraManagedIdentity | Out-Null
            $script:u | Should -Match 'graph\.microsoft\.com/beta/servicePrincipals'
            $script:u | Should -Match 'ManagedIdentity'
        }
    }
    It 'Get-EntraRoleAssignment expands principal on the beta roleManagement path' {
        InModuleScope JustGraphIT {
            $script:u=$null; Mock Get-IaCollection { $script:u = $Path; @() }
            Get-EntraRoleAssignment | Out-Null
            $script:u | Should -Match 'graph\.microsoft\.com/beta/roleManagement/directory/roleAssignments'
            $script:u | Should -Match 'expand=principal'
        }
    }
    It 'Get-EntraSecurityAlert reads beta /security/alerts_v2' {
        InModuleScope JustGraphIT {
            $script:u=$null; Mock Get-IaCollection { $script:u = $Path; @() }
            Get-EntraSecurityAlert -Severity high | Out-Null
            $script:u | Should -Match 'graph\.microsoft\.com/beta/security/alerts_v2'
        }
    }
}

Describe 'Entra create-user + app governance (beta)' {
    It 'New-EntraUser POSTs an enabled user with a passwordProfile and returns the temp password' {
        InModuleScope JustGraphIT {
            $script:u=$null;$script:b=$null
            Mock Invoke-IaRequest { $script:u=$Uri;$script:b=$Body; @{ id='u1'; userPrincipalName='new@x.com'; displayName='New User' } }
            $r = New-EntraUser -UserPrincipalName 'new@x.com' -DisplayName 'New User' -Confirm:$false
            $script:u | Should -Match 'graph\.microsoft\.com/beta/users$'
            $script:b.accountEnabled | Should -Be $true
            $script:b.passwordProfile.forceChangePasswordNextSignIn | Should -Be $true
            $r.TempPassword | Should -Not -BeNullOrEmpty
        }
    }
    It 'Get-EntraExpiringSecret returns credentials inside the window from beta /applications' {
        InModuleScope JustGraphIT {
            $script:p=$null
            Mock Get-IaCollection { $script:p=$Path; @([pscustomobject]@{ displayName='App1'; appId='a1'; passwordCredentials=@(@{ displayName='s1'; endDateTime=(Get-Date).AddDays(10).ToUniversalTime().ToString('o') }); keyCredentials=@() }) }
            $rows = @(Get-EntraExpiringSecret -Days 30)
            $script:p | Should -Match 'applications'
            $rows.Count | Should -BeGreaterThan 0
            $rows[0].Kind | Should -Be 'Secret'
            $rows[0].DaysLeft | Should -BeLessOrEqual 30
        }
    }
    It 'Get-EntraAppWithoutOwner expands owners and keeps only zero-owner apps' {
        InModuleScope JustGraphIT {
            $script:p=$null
            Mock Get-IaCollection { $script:p=$Path; @(
                [pscustomobject]@{ displayName='Owned'; appId='a1'; owners=@(@{id='o1'}) }
                [pscustomobject]@{ displayName='Orphan'; appId='a2'; owners=@() }
            ) }
            $rows = @(Get-EntraAppWithoutOwner)
            $script:p | Should -Match 'expand=owners'
            $rows.Count | Should -Be 1
            $rows[0].Name | Should -Be 'Orphan'
        }
    }
}

Describe 'Entra app permissions & consent (beta)' {
    It 'Test-EntraHighRiskPermission flags broad-power roles only' {
        InModuleScope JustGraphIT {
            Test-EntraHighRiskPermission 'Directory.ReadWrite.All' | Should -BeTrue
            Test-EntraHighRiskPermission 'RoleManagement.ReadWrite.Directory' | Should -BeTrue
            Test-EntraHighRiskPermission 'User.Read' | Should -BeFalse
            Test-EntraHighRiskPermission '' | Should -BeFalse
        }
    }

    It 'Get-EntraAppPermission reads beta oauth2PermissionGrants + appRoleAssignments and resolves names' {
        InModuleScope JustGraphIT {
            Mock Invoke-IaRequest {
                if ($Uri -match '/servicePrincipals/11111111-1111-1111-1111-111111111111\?') { return [pscustomobject]@{ id = '11111111-1111-1111-1111-111111111111' } }
                if ($Uri -match '/servicePrincipals/graphsp') {
                    return [pscustomobject]@{ id = 'graphsp'; displayName = 'Microsoft Graph'; appRoles = @([pscustomobject]@{ id = 'role1'; value = 'Directory.ReadWrite.All' }) }
                }
                return $null
            }
            $script:capPaths = @()
            Mock Get-IaCollection {
                $script:capPaths += $Path
                if ($Path -match 'oauth2PermissionGrants') { return @([pscustomobject]@{ resourceId = 'graphsp'; scope = 'User.Read Directory.AccessAsUser.All'; consentType = 'AllPrincipals' }) }
                if ($Path -match 'appRoleAssignments')      { return @([pscustomobject]@{ resourceId = 'graphsp'; appRoleId = 'role1'; resourceDisplayName = 'Microsoft Graph' }) }
                return @()
            }
            $rows = @(Get-EntraAppPermission -App '11111111-1111-1111-1111-111111111111')
            ($script:capPaths -join ' ') | Should -Match 'graph\.microsoft\.com/beta/servicePrincipals/.+/oauth2PermissionGrants'
            ($script:capPaths -join ' ') | Should -Match 'graph\.microsoft\.com/beta/servicePrincipals/.+/appRoleAssignments'
            # Application row: appRoleId resolved to the friendly name and flagged High
            $appRow = $rows | Where-Object { $_.Type -eq 'Application' }
            $appRow.Permission | Should -Be 'Directory.ReadWrite.All'
            $appRow.Risk       | Should -Be 'High'
            $appRow.Resource   | Should -Be 'Microsoft Graph'
            # Delegated scopes split out; the high-risk one flagged
            ($rows | Where-Object { $_.Permission -eq 'Directory.AccessAsUser.All' }).Risk | Should -Be 'High'
            ($rows | Where-Object { $_.Permission -eq 'User.Read' }).Risk | Should -Be ''
        }
    }

    It 'Get-EntraRiskyAppPermission audits Graph appRoleAssignedTo and keeps only High by default' {
        InModuleScope JustGraphIT {
            $script:cap = $null
            Mock Get-IaCollection {
                $script:cap = "$script:cap $Path"
                if ($Path -match "appId eq '00000003-0000-0000-c000-000000000000'") {
                    return @([pscustomobject]@{ id = 'graphsp'; displayName = 'Microsoft Graph'; appRoles = @(
                        [pscustomobject]@{ id = 'r1'; value = 'Directory.ReadWrite.All' }
                        [pscustomobject]@{ id = 'r2'; value = 'User.Read.All' }
                    ) })
                }
                if ($Path -match 'appRoleAssignedTo') {
                    return @(
                        [pscustomobject]@{ id = 'a1'; principalDisplayName = 'Backup App'; principalId = 'p1'; principalType = 'ServicePrincipal'; appRoleId = 'r1' }
                        [pscustomobject]@{ id = 'a2'; principalDisplayName = 'Reader App'; principalId = 'p2'; principalType = 'ServicePrincipal'; appRoleId = 'r2' }
                    )
                }
                return @()
            }
            $risky = @(Get-EntraRiskyAppPermission)
            $script:cap | Should -Match 'graph\.microsoft\.com/beta/servicePrincipals/graphsp/appRoleAssignedTo'
            $risky.Count       | Should -Be 1
            $risky[0].App      | Should -Be 'Backup App'
            $risky[0].Permission | Should -Be 'Directory.ReadWrite.All'
            $risky[0].Risk     | Should -Be 'High'
            # -All keeps the benign grant too
            @(Get-EntraRiskyAppPermission -All).Count | Should -Be 2
        }
    }

    It 'Get-EntraRiskyAppPermission surfaces an unresolved appRoleId as Unknown (never hides it)' {
        InModuleScope JustGraphIT {
            Mock Get-IaCollection {
                if ($Path -match "appId eq '00000003-0000-0000-c000-000000000000'") {
                    return @([pscustomobject]@{ id = 'graphsp'; displayName = 'Microsoft Graph'; appRoles = @([pscustomobject]@{ id = 'rKnown'; value = 'User.Read.All' }) })
                }
                if ($Path -match 'appRoleAssignedTo') {
                    return @(
                        [pscustomobject]@{ id = 'a1'; principalDisplayName = 'Mystery App'; principalId = 'p1'; principalType = 'ServicePrincipal'; appRoleId = 'rUNRESOLVED' }
                        [pscustomobject]@{ id = 'a2'; principalDisplayName = 'Reader App';  principalId = 'p2'; principalType = 'ServicePrincipal'; appRoleId = 'rKnown' }
                    )
                }
                return @()
            }
            $rows = @(Get-EntraRiskyAppPermission)   # default (no -All)
            # benign-resolved (User.Read.All) is dropped; unresolved is kept as Unknown
            $rows.App  | Should -Contain 'Mystery App'
            $rows.App  | Should -Not -Contain 'Reader App'
            ($rows | Where-Object App -eq 'Mystery App').Risk | Should -Be 'Unknown'
        }
    }

    It 'Remove-EntraAppRoleAssignment / Remove-EntraOAuth2Grant reject ids with URL metacharacters' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraServicePrincipalId { 'sp-1' }
            Mock Invoke-IaRequest { }
            { Remove-EntraAppRoleAssignment -ServicePrincipal 'p1' -AssignmentId '../victim/x' -Confirm:$false } | Should -Throw
            { Remove-EntraOAuth2Grant -GrantId 'a/b?c' -Confirm:$false } | Should -Throw
            Should -Invoke Invoke-IaRequest -Times 0 -Exactly   # never reached the DELETE
        }
    }

    It 'Resolve-EntraServicePrincipalId resolves a display name via beta /servicePrincipals filter' {
        InModuleScope JustGraphIT {
            $script:u = $null
            Mock Get-IaCollection { $script:u = $Path; , @([pscustomobject]@{ id = 'sp9'; displayName = "Tim's App" }) }
            Resolve-EntraServicePrincipalId -App "Tim's App" | Should -Be 'sp9'
            $script:u | Should -Match 'graph\.microsoft\.com/beta/servicePrincipals'
            # whole filter is EscapeDataString'd, so the doubled apostrophe encodes to %27%27
            $script:u | Should -Match 'Tim%27%27s%20App'
        }
    }

    It 'Remove-EntraAppRoleAssignment DELETEs the beta appRoleAssignment on the client SP' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraServicePrincipalId { 'sp-1' }
            $script:m = $null; $script:u = $null
            Mock Invoke-IaRequest { $script:m = $Method; $script:u = $Uri }
            Remove-EntraAppRoleAssignment -ServicePrincipal 'p1' -AssignmentId 'a1' -Confirm:$false | Out-Null
            $script:m | Should -Be 'DELETE'
            $script:u | Should -Match 'graph\.microsoft\.com/beta/servicePrincipals/sp-1/appRoleAssignments/a1$'
        }
    }

    It 'Remove-EntraOAuth2Grant DELETEs the beta oauth2PermissionGrant by id' {
        InModuleScope JustGraphIT {
            $script:m = $null; $script:u = $null
            Mock Invoke-IaRequest { $script:m = $Method; $script:u = $Uri }
            Remove-EntraOAuth2Grant -GrantId 'g-9' -Confirm:$false | Out-Null
            $script:m | Should -Be 'DELETE'
            $script:u | Should -Match 'graph\.microsoft\.com/beta/oauth2PermissionGrants/g-9$'
        }
    }
}

Describe 'Entra lifecycle hygiene (beta)' {
    It 'Get-EntraInactiveUser keeps stale + never-signed-in enabled accounts, drops recent ones' {
        InModuleScope JustGraphIT {
            $script:p = $null
            # $script: scope so the Pester mock body (module scope) can read them
            $script:recent = (Get-Date).AddDays(-10).ToString('o')
            $script:stale  = (Get-Date).AddDays(-200).ToString('o')
            Mock Get-IaCollection {
                $script:p = $Path
                @(
                    [pscustomobject]@{ userPrincipalName = 'stale@x.com';  displayName = 'Stale';  accountEnabled = $true;  department = 'IT'; createdDateTime = '2019-01-01T00:00:00Z'; signInActivity = [pscustomobject]@{ lastSignInDateTime = $script:stale } }
                    [pscustomobject]@{ userPrincipalName = 'recent@x.com'; displayName = 'Recent'; accountEnabled = $true;  department = 'HR'; createdDateTime = '2024-01-01T00:00:00Z'; signInActivity = [pscustomobject]@{ lastSignInDateTime = $script:recent } }
                    [pscustomobject]@{ userPrincipalName = 'never@x.com';  displayName = 'Never';  accountEnabled = $true;  department = 'Ops';createdDateTime = '2024-06-01T00:00:00Z'; signInActivity = $null }
                    [pscustomobject]@{ userPrincipalName = 'off@x.com';    displayName = 'Off';    accountEnabled = $false; department = 'IT'; createdDateTime = '2018-01-01T00:00:00Z'; signInActivity = [pscustomobject]@{ lastSignInDateTime = $script:stale } }
                )
            }
            $rows = @(Get-EntraInactiveUser -Days 90)
            $script:p | Should -Match 'graph\.microsoft\.com/beta/users'
            $script:p | Should -Match 'signInActivity'
            $names = $rows.User
            $names | Should -Contain 'stale@x.com'
            $names | Should -Contain 'never@x.com'   # never-signed-in counts as inactive
            $names | Should -Not -Contain 'recent@x.com'
            $names | Should -Not -Contain 'off@x.com' # disabled excluded by default
            ($rows | Where-Object User -eq 'never@x.com').DaysInactive | Should -Be 'never'
            # -IncludeDisabled brings the disabled stale account back
            @(Get-EntraInactiveUser -Days 90 -IncludeDisabled).User | Should -Contain 'off@x.com'
        }
    }

    It 'Get-EntraGuestUser filters userType eq Guest on beta /users' {
        InModuleScope JustGraphIT {
            $script:p = $null
            Mock Get-IaCollection {
                $script:p = $Path
                @([pscustomobject]@{ displayName = 'Ext Partner'; mail = 'p@partner.com'; userPrincipalName = 'p_partner.com#EXT#@x.onmicrosoft.com'; accountEnabled = $true; externalUserState = 'Accepted'; createdDateTime = '2025-01-01T00:00:00Z'; signInActivity = $null })
            }
            $rows = @(Get-EntraGuestUser)
            $script:p | Should -Match 'graph\.microsoft\.com/beta/users'
            $script:p | Should -Match "userType%20eq%20%27Guest%27"
            $rows[0].State | Should -Be 'Accepted'
            $rows[0].LastSignIn | Should -Be 'never'
        }
    }
}

Describe 'Entra write actions — permissions, consent, provisioning (beta)' {

    It 'Add-EntraAppPermission resolves names and PATCHes requiredResourceAccess (Role)' {
        InModuleScope JustGraphIT {
            $script:m = $null; $script:u = $null; $script:b = $null
            Mock Invoke-IaRequest {
                $script:m = $Method; $script:u = $Uri; $script:b = $Body
                if ($Method -eq 'GET' -and $Uri -match '/applications/22222222') {
                    return [pscustomobject]@{ id = '22222222-2222-2222-2222-222222222222'; appId = 'client-app-id'; displayName = 'CI App'; requiredResourceAccess = @() }
                }
                return $null
            }
            Mock Get-IaCollection {
                if ($Path -match "appId eq '00000003-0000-0000-c000-000000000000'") {
                    return @([pscustomobject]@{ id = 'graphsp'; appId = '00000003-0000-0000-c000-000000000000'; displayName = 'Microsoft Graph'
                            appRoles = @([pscustomobject]@{ id = 'role-urall'; value = 'User.Read.All'; isEnabled = $true }); oauth2PermissionScopes = @() })
                }
                return @()
            }
            Add-EntraAppPermission -App '22222222-2222-2222-2222-222222222222' -Permission 'User.Read.All' -Type Application -Confirm:$false | Out-Null
            $script:m | Should -Be 'PATCH'
            $script:u | Should -Match 'graph\.microsoft\.com/beta/applications/22222222-2222-2222-2222-222222222222$'
            $rra = @($script:b.requiredResourceAccess)
            $rra[0].resourceAppId          | Should -Be '00000003-0000-0000-c000-000000000000'
            @($rra[0].resourceAccess)[0].id   | Should -Be 'role-urall'
            @($rra[0].resourceAccess)[0].type | Should -Be 'Role'
        }
    }

    It 'Resolve-EntraResourceApi throws on an ambiguous name rather than silently picking one' {
        InModuleScope JustGraphIT {
            # two SPs share a display name; consenting against the wrong one is a security
            # footgun, so a bare name must error instead of guessing.
            Mock Get-IaCollection {
                @(
                    [pscustomobject]@{ id = 'sp-a'; appId = 'app-a'; displayName = 'Contoso API'; appRoles = @(); oauth2PermissionScopes = @() }
                    [pscustomobject]@{ id = 'sp-b'; appId = 'app-b'; displayName = 'Contoso API'; appRoles = @(); oauth2PermissionScopes = @() }
                )
            }
            { Resolve-EntraResourceApi -Resource 'Contoso API' } | Should -Throw -ExpectedMessage '*Multiple service principals*'
        }
    }

    It 'Resolve-EntraResourceApi resolves a well-known alias to the Graph SP without ambiguity' {
        InModuleScope JustGraphIT {
            $script:p = $null
            Mock Get-IaCollection {
                $script:p = $Path
                @([pscustomobject]@{ id = 'graphsp'; appId = '00000003-0000-0000-c000-000000000000'; displayName = 'Microsoft Graph'; appRoles = @(); oauth2PermissionScopes = @() })
            }
            $sp = Resolve-EntraResourceApi -Resource 'Graph'
            $sp.id | Should -Be 'graphsp'
            # alias maps to the appId filter, never a displayName guess
            $script:p | Should -Match "appId eq '00000003-0000-0000-c000-000000000000'"
        }
    }

    It 'Grant-EntraAdminConsent creates an appRoleAssignment (Role) and an AllPrincipals grant (Scope)' {
        InModuleScope JustGraphIT {
            $script:posts = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-IaRequest {
                if ($Method -eq 'GET' -and $Uri -match '/applications/33333333') {
                    return [pscustomobject]@{ id = '33333333-3333-3333-3333-333333333333'; appId = 'client-app-id'; displayName = 'Worker'
                        requiredResourceAccess = @([pscustomobject]@{ resourceAppId = '00000003-0000-0000-c000-000000000000'
                                resourceAccess = @([pscustomobject]@{ id = 'role1'; type = 'Role' }, [pscustomobject]@{ id = 'scope1'; type = 'Scope' }) }) }
                }
                if ($Method -eq 'POST') { $script:posts.Add([pscustomobject]@{ Uri = $Uri; Body = $Body }) }
                return [pscustomobject]@{ id = 'new' }
            }
            Mock Get-IaCollection {
                if ($Path -match "appId eq 'client-app-id'") { return @([pscustomobject]@{ id = 'clientsp'; appId = 'client-app-id'; displayName = 'Worker' }) }
                if ($Path -match "appId eq '00000003-0000-0000-c000-000000000000'") {
                    return @([pscustomobject]@{ id = 'graphsp'; appId = '00000003-0000-0000-c000-000000000000'; displayName = 'Microsoft Graph'
                            appRoles = @([pscustomobject]@{ id = 'role1'; value = 'Directory.ReadWrite.All' })
                            oauth2PermissionScopes = @([pscustomobject]@{ id = 'scope1'; value = 'User.Read' }) })
                }
                if ($Path -match 'oauth2PermissionGrants\?') { return @() }   # no existing grant
                return @()
            }
            Grant-EntraAdminConsent -App '33333333-3333-3333-3333-333333333333' -Confirm:$false | Out-Null
            $rolePost  = $script:posts | Where-Object { $_.Uri -match '/servicePrincipals/clientsp/appRoleAssignments$' } | Select-Object -First 1
            $grantPost = $script:posts | Where-Object { $_.Uri -match '/oauth2PermissionGrants$' } | Select-Object -First 1
            $rolePost  | Should -Not -BeNullOrEmpty
            $rolePost.Body.appRoleId   | Should -Be 'role1'
            $rolePost.Body.resourceId  | Should -Be 'graphsp'
            $rolePost.Body.principalId | Should -Be 'clientsp'
            $grantPost | Should -Not -BeNullOrEmpty
            $grantPost.Body.consentType | Should -Be 'AllPrincipals'
            $grantPost.Body.scope       | Should -Be 'User.Read'
        }
    }

    It 'New-EntraServicePrincipal POSTs the appId to beta /servicePrincipals' {
        InModuleScope JustGraphIT {
            $script:u = $null; $script:b = $null
            Mock Invoke-IaRequest {
                $script:u = $Uri; $script:b = $Body
                if ($Method -eq 'GET') { return [pscustomobject]@{ id = '44444444-4444-4444-4444-444444444444'; appId = 'the-app-id'; displayName = 'New Daemon' } }
                return [pscustomobject]@{ id = 'sp-new' }
            }
            Mock Get-IaCollection { @() }   # no existing SP
            $r = New-EntraServicePrincipal -App '44444444-4444-4444-4444-444444444444' -Confirm:$false
            $script:u | Should -Match 'graph\.microsoft\.com/beta/servicePrincipals$'
            $script:b.appId | Should -Be 'the-app-id'
            $r.Created | Should -BeTrue
        }
    }

    It 'New-EntraGuestInvitation POSTs the invitation and returns the redeem URL' {
        InModuleScope JustGraphIT {
            $script:u = $null; $script:b = $null
            Mock Invoke-IaRequest {
                $script:u = $Uri; $script:b = $Body
                [pscustomobject]@{ status = 'PendingAcceptance'; inviteRedeemUrl = 'https://redeem/abc'; invitedUserDisplayName = 'Dana'; invitedUser = [pscustomobject]@{ id = 'guest-1' } }
            }
            $r = New-EntraGuestInvitation -EmailAddress 'dana@contoso.com' -DisplayName 'Dana' -Confirm:$false
            $script:u | Should -Match 'graph\.microsoft\.com/beta/invitations$'
            $script:b.invitedUserEmailAddress | Should -Be 'dana@contoso.com'
            $script:b.sendInvitationMessage   | Should -Be $false
            $r.UserId    | Should -Be 'guest-1'
            $r.RedeemUrl | Should -Be 'https://redeem/abc'
        }
    }

    It 'New-EntraTeam creates a Unified group with an owner bind then PUTs the team' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraUserId { 'owner-1' }
            $script:calls = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-IaRequest {
                $script:calls.Add([pscustomobject]@{ Method = $Method; Uri = $Uri; Body = $Body })
                if ($Method -eq 'POST') { return [pscustomobject]@{ id = 'grp-1' } }
                return [pscustomobject]@{ id = 'team-1' }   # PUT teamify
            }
            $r = New-EntraTeam -Name 'Project Atlas' -Owner 'aaron@x.com' -Visibility Private -Confirm:$false
            $groupPost = $script:calls | Where-Object { $_.Method -eq 'POST' -and $_.Uri -match '/groups$' } | Select-Object -First 1
            $teamPut   = $script:calls | Where-Object { $_.Method -eq 'PUT'  -and $_.Uri -match '/groups/grp-1/team$' } | Select-Object -First 1
            $groupPost | Should -Not -BeNullOrEmpty
            @($groupPost.Body.groupTypes)               | Should -Contain 'Unified'
            $groupPost.Body.'owners@odata.bind'         | Should -Match 'users/owner-1'
            $groupPost.Body.visibility                  | Should -Be 'Private'
            $teamPut   | Should -Not -BeNullOrEmpty
            $r.Teamified | Should -BeTrue
            $r.GroupId   | Should -Be 'grp-1'
        }
    }
}

Describe 'Entra app-registration lifecycle (beta)' {
    It 'New-EntraAppRegistration POSTs displayName + audience + web redirect URI' {
        InModuleScope JustGraphIT {
            $script:u = $null; $script:b = $null
            Mock Invoke-IaRequest { $script:u = $Uri; $script:b = $Body; [pscustomobject]@{ id = 'app-obj'; appId = 'app-id'; displayName = 'New App'; signInAudience = 'AzureADMyOrg' } }
            $r = New-EntraAppRegistration -Name 'New App' -RedirectUri 'https://app/callback' -Platform Web -Confirm:$false
            $script:u | Should -Match 'graph\.microsoft\.com/beta/applications$'
            $script:b.displayName    | Should -Be 'New App'
            $script:b.signInAudience | Should -Be 'AzureADMyOrg'
            @($script:b.web.redirectUris) | Should -Contain 'https://app/callback'
            $r.AppId | Should -Be 'app-id'
        }
    }

    It 'New-EntraAppSecret POSTs addPassword and surfaces the one-time secret' {
        InModuleScope JustGraphIT {
            Mock Invoke-IaRequest {
                if ($Method -eq 'GET') { return [pscustomobject]@{ id = 'app-obj'; appId = 'app-id'; displayName = 'CI App' } }
                $script:u = $Uri; $script:b = $Body
                [pscustomobject]@{ keyId = 'sec-1'; displayName = 'ci'; endDateTime = '2027-06-28T00:00:00Z'; secretText = 'S3cr3t!value' }
            }
            $r = New-EntraAppSecret -App '55555555-5555-5555-5555-555555555555' -DisplayName 'ci' -Months 6 -Confirm:$false
            $script:u | Should -Match 'graph\.microsoft\.com/beta/applications/app-obj/addPassword$'
            $script:b.passwordCredential.displayName | Should -Be 'ci'
            $r.Secret   | Should -Be 'S3cr3t!value'
            $r.SecretId | Should -Be 'sec-1'
        }
    }

    It 'Add-EntraAppRedirectUri merges with existing URIs and PATCHes the platform' {
        InModuleScope JustGraphIT {
            $script:patch = $null
            Mock Invoke-IaRequest {
                if ($Method -eq 'GET' -and $Uri -match 'addPassword') { return $null }
                if ($Method -eq 'GET' -and $Uri -match '\$select=web') { return [pscustomobject]@{ web = [pscustomobject]@{ redirectUris = @('https://old/cb') } } }
                if ($Method -eq 'GET') { return [pscustomobject]@{ id = 'app-obj'; appId = 'a'; displayName = 'App' } }
                if ($Method -eq 'PATCH') { $script:patch = $Body }
                $null
            }
            Add-EntraAppRedirectUri -App '66666666-6666-6666-6666-666666666666' -Uri 'https://new/cb' -Platform Web -Confirm:$false | Out-Null
            @($script:patch.web.redirectUris) | Should -Contain 'https://old/cb'
            @($script:patch.web.redirectUris) | Should -Contain 'https://new/cb'
        }
    }

    It 'Add-EntraAppOwner POSTs a directoryObjects ref to applications/{id}/owners/$ref' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraUserId { 'user-7' }
            Mock Invoke-IaRequest {
                if ($Method -eq 'GET') { return [pscustomobject]@{ id = 'app-obj'; appId = 'a'; displayName = 'App' } }
                $script:u = $Uri; $script:b = $Body; $null
            }
            Add-EntraAppOwner -App '77777777-7777-7777-7777-777777777777' -Owner 'bob@x.com' -Confirm:$false | Out-Null
            $script:u | Should -Match 'graph\.microsoft\.com/beta/applications/app-obj/owners/\$ref$'
            $script:b.'@odata.id' | Should -Match 'directoryObjects/user-7$'
        }
    }

    It 'Remove-EntraAppRegistration DELETEs /beta/applications/{id}' {
        InModuleScope JustGraphIT {
            Mock Invoke-IaRequest {
                if ($Method -eq 'GET') { return [pscustomobject]@{ id = 'app-obj'; appId = 'a'; displayName = 'Doomed' } }
                $script:m = $Method; $script:u = $Uri; $null
            }
            Remove-EntraAppRegistration -App '88888888-8888-8888-8888-888888888888' -Confirm:$false | Out-Null
            $script:m | Should -Be 'DELETE'
            $script:u | Should -Match 'graph\.microsoft\.com/beta/applications/app-obj$'
        }
    }
}

Describe 'Entra role & PIM writes (beta)' {
    It 'New-EntraRoleAssignment POSTs principalId/roleDefinitionId/scope to roleAssignments' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraUserId { 'u-1' }
            Mock Resolve-EntraRoleDefinitionId { 'role-1' }
            $script:u = $null; $script:b = $null
            Mock Invoke-IaRequest { $script:u = $Uri; $script:b = $Body; [pscustomobject]@{ id = 'ra-1' } }
            New-EntraRoleAssignment -User 'a@x.com' -Role 'Helpdesk Administrator' -Confirm:$false | Out-Null
            $script:u | Should -Match 'graph\.microsoft\.com/beta/roleManagement/directory/roleAssignments$'
            $script:b.principalId      | Should -Be 'u-1'
            $script:b.roleDefinitionId | Should -Be 'role-1'
            $script:b.directoryScopeId | Should -Be '/'
        }
    }

    It 'Remove-EntraRoleAssignment (ByName) looks up then DELETEs the assignment' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraUserId { 'u-1' }
            Mock Resolve-EntraRoleDefinitionId { 'role-1' }
            Mock Get-IaCollection { @([pscustomobject]@{ id = 'ra-9' }) }
            $script:m = $null; $script:u = $null
            Mock Invoke-IaRequest { $script:m = $Method; $script:u = $Uri }
            Remove-EntraRoleAssignment -User 'a@x.com' -Role 'Helpdesk Administrator' -Confirm:$false | Out-Null
            $script:m | Should -Be 'DELETE'
            $script:u | Should -Match 'roleManagement/directory/roleAssignments/ra-9$'
        }
    }

    It 'New-EntraPimEligibility POSTs an adminAssign request with a duration schedule' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraUserId { 'u-1' }
            Mock Resolve-EntraRoleDefinitionId { 'role-1' }
            $script:u = $null; $script:b = $null
            Mock Invoke-IaRequest { $script:u = $Uri; $script:b = $Body; [pscustomobject]@{ id = 'req'; status = 'Granted' } }
            New-EntraPimEligibility -User 'a@x.com' -Role 'Helpdesk Administrator' -Duration 90d -Confirm:$false | Out-Null
            $script:u | Should -Match 'roleManagement/directory/roleEligibilityScheduleRequests$'
            $script:b.action | Should -Be 'adminAssign'
            $script:b.scheduleInfo.expiration.duration | Should -Be 'P90D'
        }
    }

    It 'Enable-EntraPimRole self-activates an eligible role via Invoke-IaActivateRole' {
        InModuleScope JustGraphIT {
            Mock Get-IaMyPrincipalId { [pscustomobject]@{ Id = 'me-1'; Upn = 'me@x.com' } }
            Mock Get-IaEligibleRoles { @([pscustomobject]@{ roleDefinitionId = 'role-9'; directoryScopeId = '/'; roleDefinition = [pscustomobject]@{ displayName = 'Global Reader' } }) }
            $script:rid = $null; $script:dur = $null
            Mock Invoke-IaActivateRole { $script:rid = $RoleDefinitionId; $script:dur = $Duration; [pscustomobject]@{ id = 'req-1'; status = 'Provisioned' } }
            $r = Enable-EntraPimRole -Role 'Global Reader' -Justification 'audit window' -Duration 2h -Confirm:$false
            $script:rid | Should -Be 'role-9'
            $script:dur | Should -Be 'PT2H'
            $r.Activated | Should -BeTrue
        }
    }

    It 'Enable-EntraPimRole throws when the user is not eligible for the role' {
        InModuleScope JustGraphIT {
            Mock Get-IaMyPrincipalId { [pscustomobject]@{ Id = 'me-1'; Upn = 'me@x.com' } }
            Mock Get-IaEligibleRoles { @() }
            { Enable-EntraPimRole -Role 'Global Administrator' -Justification 'x' -Confirm:$false } | Should -Throw
        }
    }
}

Describe 'Entra Conditional Access authoring (beta)' {
    It 'New-EntraConditionalAccessPolicy builds conditions + grantControls and POSTs' {
        InModuleScope JustGraphIT {
            $script:u = $null; $script:b = $null
            Mock Invoke-IaRequest { $script:u = $Uri; $script:b = $Body; [pscustomobject]@{ id = 'ca-1'; displayName = 'MFA'; state = 'enabled' } }
            New-EntraConditionalAccessPolicy -Name 'MFA' -IncludeGroups 'g1' -ExcludeUsers 'u-break-glass' -RequireMfa -State enabled -Confirm:$false | Out-Null
            $script:u | Should -Match 'graph\.microsoft\.com/beta/identity/conditionalAccess/policies$'
            $script:b.displayName | Should -Be 'MFA'
            $script:b.state       | Should -Be 'enabled'
            @($script:b.conditions.users.includeGroups) | Should -Contain 'g1'
            @($script:b.conditions.users.excludeUsers)  | Should -Contain 'u-break-glass'
            @($script:b.grantControls.builtInControls)  | Should -Contain 'mfa'
            $script:b.grantControls.operator | Should -Be 'OR'
        }
    }

    It 'New-EntraConditionalAccessPolicy -BlockAccess overrides other grant controls' {
        InModuleScope JustGraphIT {
            $script:b = $null
            Mock Invoke-IaRequest { $script:b = $Body; [pscustomobject]@{ id = 'ca-2'; displayName = 'Block legacy'; state = 'enabled' } }
            New-EntraConditionalAccessPolicy -Name 'Block legacy' -ClientAppTypes exchangeActiveSync, other -RequireMfa -BlockAccess -State enabled -Confirm:$false | Out-Null
            @($script:b.grantControls.builtInControls) | Should -Be @('block')
            @($script:b.conditions.clientAppTypes)     | Should -Contain 'exchangeActiveSync'
        }
    }

    It 'New-EntraConditionalAccessPolicy with -IncludeGroups only sets includeUsers=None (no silent tenant-wide union)' {
        InModuleScope JustGraphIT {
            $script:b = $null
            Mock Invoke-IaRequest { $script:b = $Body; [pscustomobject]@{ id = 'ca-3'; displayName = 'Grp'; state = 'enabledForReportingButNotEnforced' } }
            New-EntraConditionalAccessPolicy -Name 'Grp' -IncludeGroups 'g1' -RequireMfa -Confirm:$false | Out-Null
            # CA unions includeUsers + includeGroups; scoping by group must NOT pull in 'All' users.
            @($script:b.conditions.users.includeUsers)  | Should -Be @('None')
            @($script:b.conditions.users.includeGroups) | Should -Contain 'g1'
        }
    }

    It 'New-EntraConditionalAccessPolicy with no user/group scoping defaults includeUsers=All' {
        InModuleScope JustGraphIT {
            $script:b = $null
            Mock Invoke-IaRequest { $script:b = $Body; [pscustomobject]@{ id = 'ca-4'; displayName = 'AllUsers'; state = 'enabledForReportingButNotEnforced' } }
            New-EntraConditionalAccessPolicy -Name 'AllUsers' -RequireMfa -Confirm:$false | Out-Null
            @($script:b.conditions.users.includeUsers) | Should -Be @('All')
        }
    }

    It 'New-EntraConditionalAccessPolicy honors an explicit -IncludeUsers even alongside -IncludeGroups' {
        InModuleScope JustGraphIT {
            $script:b = $null
            Mock Invoke-IaRequest { $script:b = $Body; [pscustomobject]@{ id = 'ca-5'; displayName = 'Both'; state = 'enabledForReportingButNotEnforced' } }
            New-EntraConditionalAccessPolicy -Name 'Both' -IncludeUsers 'u-1' -IncludeGroups 'g1' -RequireMfa -Confirm:$false | Out-Null
            @($script:b.conditions.users.includeUsers)  | Should -Be @('u-1')
            @($script:b.conditions.users.includeGroups) | Should -Contain 'g1'
        }
    }

    It 'Remove-EntraConditionalAccessPolicy resolves the name then DELETEs' {
        InModuleScope JustGraphIT {
            Mock Get-IaCollection { @([pscustomobject]@{ id = 'ca-9'; displayName = 'Old policy' }) }
            $script:m = $null; $script:u = $null
            Mock Invoke-IaRequest { $script:m = $Method; $script:u = $Uri }
            Remove-EntraConditionalAccessPolicy -Policy 'Old policy' -Confirm:$false | Out-Null
            $script:m | Should -Be 'DELETE'
            $script:u | Should -Match 'identity/conditionalAccess/policies/ca-9$'
        }
    }

    It 'New-EntraNamedLocation (IP) POSTs an ipNamedLocation with CIDR ranges' {
        InModuleScope JustGraphIT {
            $script:u = $null; $script:b = $null
            Mock Invoke-IaRequest { $script:u = $Uri; $script:b = $Body; [pscustomobject]@{ id = 'nl-1'; displayName = 'Corp HQ' } }
            New-EntraNamedLocation -Name 'Corp HQ' -IpRange '203.0.113.0/24' -Trusted -Confirm:$false | Out-Null
            $script:u | Should -Match 'identity/conditionalAccess/namedLocations$'
            $script:b.'@odata.type' | Should -Be '#microsoft.graph.ipNamedLocation'
            $script:b.isTrusted     | Should -Be $true
            @($script:b.ipRanges)[0].cidrAddress | Should -Be '203.0.113.0/24'
        }
    }

    It 'Get-EntraNamedLocation projects IP ranges and country lists by kind' {
        InModuleScope JustGraphIT {
            Mock Get-IaCollection {
                @(
                    [pscustomobject]@{ '@odata.type' = '#microsoft.graph.ipNamedLocation'; displayName = 'Corp'; isTrusted = $true; ipRanges = @([pscustomobject]@{ cidrAddress = '10.0.0.0/8' }) }
                    [pscustomobject]@{ '@odata.type' = '#microsoft.graph.countryNamedLocation'; displayName = 'Allowed'; countriesAndRegions = @('US', 'CA') }
                )
            }
            $rows = @(Get-EntraNamedLocation)
            ($rows | Where-Object Name -eq 'Corp').Detail    | Should -Be '10.0.0.0/8'
            ($rows | Where-Object Name -eq 'Allowed').Detail | Should -Be 'US, CA'
            ($rows | Where-Object Name -eq 'Corp').Kind      | Should -Be 'ipNamedLocation'
        }
    }
}

Describe 'TUI write-menu smoke (new wiring)' {
    It 'Invoke-IaTuiEntraCACreate assembles an All-users / MFA / report-only policy and calls the cmdlet' {
        InModuleScope JustGraphIT {
            $script:ca_iu = 'unset'; $script:ca_state = 'unset'; $script:ca_mfa = $false; $script:ca_called = $false
            Mock Read-IaText { 'Test CA' }                       # policy name
            Mock Read-IaMenu {
                switch -Wildcard ($Title) {
                    'Who*'     { 'All users' }
                    'Grant*'   { 'Require MFA' }
                    'Initial*' { 'Report-only (recommended)' }
                    default    { 'Cancel' }
                }
            }
            Mock Read-IaConfirm { $true }                        # no break-glass group (Select-IaGroup → null), then final confirm
            Mock Select-IaGroup { $null }
            Mock Read-IaPause {}
            Mock Write-IaHost {}
            Mock New-EntraConditionalAccessPolicy {
                $script:ca_called = $true; $script:ca_iu = $IncludeUsers; $script:ca_state = $State; $script:ca_mfa = [bool]$RequireMfa
                [pscustomobject]@{ Name = $Name; State = $State; Id = 'ca-x' }
            }
            Invoke-IaTuiEntraCACreate -Accent 'cyan'
            $script:ca_called | Should -BeTrue
            @($script:ca_iu)  | Should -Be @('All')
            $script:ca_mfa    | Should -BeTrue
            $script:ca_state  | Should -Be 'enabledForReportingButNotEnforced'
        }
    }

    It 'Invoke-IaTuiEntraCACreate scoped to a group does NOT pass IncludeUsers (avoids tenant-wide union)' {
        InModuleScope JustGraphIT {
            $script:ca_ig = 'unset'; $script:ca_hasIU = $true; $script:ca_called = $false
            Mock Read-IaText { 'Grp CA' }
            Mock Read-IaMenu {
                switch -Wildcard ($Title) {
                    'Who*'     { 'A specific group' }
                    'Grant*'   { 'Require MFA' }
                    'Initial*' { 'Report-only (recommended)' }
                    default    { 'Cancel' }
                }
            }
            Mock Read-IaConfirm { if ($Message -like 'Exclude*') { $false } else { $true } }
            Mock Select-IaGroup { [pscustomobject]@{ Id = 'g-1'; DisplayName = 'Admins' } }
            Mock Read-IaPause {}
            Mock Write-IaHost {}
            Mock New-EntraConditionalAccessPolicy {
                $script:ca_called = $true; $script:ca_ig = $IncludeGroups; $script:ca_hasIU = $PSBoundParameters.ContainsKey('IncludeUsers')
                [pscustomobject]@{ Name = $Name; State = $State; Id = 'ca-y' }
            }
            Invoke-IaTuiEntraCACreate -Accent 'cyan'
            $script:ca_called  | Should -BeTrue
            @($script:ca_ig)   | Should -Be @('g-1')
            $script:ca_hasIU   | Should -BeFalse
        }
    }

    It 'new write menus back out cleanly on Back (no runtime errors)' {
        InModuleScope JustGraphIT {
            Mock Read-IaMenu { 'Back' }
            Mock Read-IaSelection { $null }
            Mock Read-IaTableInteractive { $null }
            Mock Read-IaTablePause {}
            Mock Read-IaText { '' }
            Mock Read-IaConfirm { $false }
            Mock Read-IaPause {}
            Mock Write-IaHost {}
            Mock Write-IaTuiHeader {}
            Mock Invoke-IaStatus { $null }
            foreach ($fn in 'Invoke-IaTuiEntraCA', 'Invoke-IaTuiAssignmentFilters', 'Invoke-IaTuiLegacyConfig', 'Invoke-IaTuiEntraNamedLocation') {
                { & $fn -Accent 'cyan' } | Should -Not -Throw -Because "$fn must enter and exit its menu loop cleanly"
            }
        }
    }

    It 'Invoke-IaTuiEntraEnterpriseApp revokes the picked delegated grant by its grant id' {
        InModuleScope JustGraphIT {
            $script:ti = 0; $script:mc = 0; $script:revoked = $null
            Mock Invoke-IaStatus { & $ScriptBlock }                # run the loader so the grant list is real
            Mock Get-EntraEnterpriseApp { @([pscustomobject]@{ DisplayName = 'Backup SP'; AppId = 'app-1'; Id = 'sp-1' }) }
            Mock Get-EntraAppPermission { [pscustomobject]@{ Delegated = @([pscustomobject]@{ id = 'grant-xyz'; scope = 'Mail.Read Mail.Send'; consentType = 'AllPrincipals' }); Application = @() } }
            Mock Read-IaTableInteractive {
                $script:ti++
                if ($script:ti -eq 1) { [pscustomobject]@{ Id = 'sp-1'; DisplayName = 'Backup SP' } }       # pick the SP
                elseif ($script:ti -eq 2) { [pscustomobject]@{ Consent = 'Admin (all users)'; Scopes = 'Mail.Read'; GrantId = '•••'; _GrantId = 'grant-xyz' } }  # pick the grant (real id hidden)
                else { $null }                                      # exit the outer loop
            }
            Mock Read-IaMenu { $script:mc++; if ($script:mc -eq 1) { 'Revoke a delegated grant' } else { 'Back' } }
            Mock Read-IaConfirm { $true }
            Mock Read-IaPause {}
            Mock Write-IaHost {}
            Mock Remove-EntraOAuth2Grant { $script:revoked = $GrantId; [pscustomobject]@{ GrantId = $GrantId; Revoked = $true } }
            Invoke-IaTuiEntraEnterpriseApp -Accent 'cyan'
            $script:revoked | Should -Be 'grant-xyz'
            Should -Invoke Remove-EntraOAuth2Grant -Times 1 -Exactly
        }
    }

    It 'Invoke-IaTuiEntraEnterpriseApp revokes the picked application permission by sp + assignment id' {
        InModuleScope JustGraphIT {
            $script:ti = 0; $script:mc = 0; $script:rmSp = $null; $script:rmId = $null
            Mock Invoke-IaStatus { & $ScriptBlock }
            Mock Get-EntraEnterpriseApp { @([pscustomobject]@{ DisplayName = 'Backup SP'; AppId = 'app-1'; Id = 'sp-1' }) }
            Mock Get-EntraAppPermission { [pscustomobject]@{ Delegated = @(); Application = @([pscustomobject]@{ id = 'assign-1'; appRoleId = 'role-1'; resourceDisplayName = 'Microsoft Graph' }) } }
            Mock Read-IaTableInteractive {
                $script:ti++
                if ($script:ti -eq 1) { [pscustomobject]@{ Id = 'sp-1'; DisplayName = 'Backup SP' } }
                elseif ($script:ti -eq 2) { [pscustomobject]@{ Resource = 'Microsoft Graph'; AppRoleId = 'role-1'; AssignmentId = '•••'; _AssignmentId = 'assign-1' } }
                else { $null }
            }
            Mock Read-IaMenu { $script:mc++; if ($script:mc -eq 1) { 'Revoke an application permission' } else { 'Back' } }
            Mock Read-IaConfirm { $true }
            Mock Read-IaPause {}
            Mock Write-IaHost {}
            Mock Remove-EntraAppRoleAssignment { $script:rmSp = $ServicePrincipal; $script:rmId = $AssignmentId; [pscustomobject]@{ Revoked = $true } }
            Invoke-IaTuiEntraEnterpriseApp -Accent 'cyan'
            $script:rmSp | Should -Be 'sp-1'
            $script:rmId | Should -Be 'assign-1'
        }
    }
}

Describe 'Security hardening (review fixes)' {
    It 'inj-1: Resolve-EntraGroupId percent-encodes the $filter so "&" cannot split the query' {
        InModuleScope JustGraphIT {
            $script:p = $null
            Mock Get-IaCollection { $script:p = $Path; @([pscustomobject]@{ id = 'g-1'; displayName = 'Sales & Eng' }) }
            Resolve-EntraGroupId -Group 'Sales & Eng' | Should -Be 'g-1'
            $script:p | Should -Match 'displayName%20eq%20'          # filter is URL-encoded
            $script:p | Should -Match 'Sales%20%26%20Eng'            # the & is %26, not a raw separator
            $script:p | Should -Not -Match "displayName eq 'Sales & Eng'"
        }
    }

    It 'inj-3: Resolve-EntraUserId resolves by EXACT equality, never a silent prefix match' {
        InModuleScope JustGraphIT {
            Mock Invoke-IaRequest { throw 'not a routable UPN' }      # exact users/{key} GET fails → fall to filter
            $script:p = $null
            Mock Get-IaCollection { $script:p = $Path; @([pscustomobject]@{ id = 'u-1'; userPrincipalName = 'rob@x.com' }) }
            Resolve-EntraUserId -User 'rob' | Should -Be 'u-1'
            $script:p | Should -Match 'userPrincipalName%20eq%20'     # exact equality, URL-encoded
            $script:p | Should -Not -Match 'startswith'               # no prefix matching on the write path
        }
    }

    It 'inj-4: Resolve-EntraDeviceObjectId throws instead of guessing when a deviceId is not unique' {
        InModuleScope JustGraphIT {
            Mock Get-IaCollection { @([pscustomobject]@{ id = 'd-1' }, [pscustomobject]@{ id = 'd-2' }) }
            { Resolve-EntraDeviceObjectId -AzureAdDeviceId 'dup' } | Should -Throw -ExpectedMessage '*Multiple Entra devices*'
        }
    }

    It 'authz-2: Grant-EntraAdminConsent warns before consenting a tenant-takeover-class permission' {
        InModuleScope JustGraphIT {
            Mock Invoke-IaRequest {
                if ($Method -eq 'GET' -and $Uri -match '/applications/33333333') {
                    return [pscustomobject]@{ id = '33333333-3333-3333-3333-333333333333'; appId = 'client-app-id'; displayName = 'Worker'
                        requiredResourceAccess = @([pscustomobject]@{ resourceAppId = '00000003-0000-0000-c000-000000000000'
                                resourceAccess = @([pscustomobject]@{ id = 'role1'; type = 'Role' }) }) }
                }
                return [pscustomobject]@{ id = 'new' }
            }
            Mock Get-IaCollection {
                if ($Path -match "appId eq 'client-app-id'") { return @([pscustomobject]@{ id = 'clientsp'; appId = 'client-app-id'; displayName = 'Worker' }) }
                if ($Path -match "appId eq '00000003-0000-0000-c000-000000000000'") {
                    return @([pscustomobject]@{ id = 'graphsp'; appId = '00000003-0000-0000-c000-000000000000'; displayName = 'Microsoft Graph'
                            appRoles = @([pscustomobject]@{ id = 'role1'; value = 'Directory.ReadWrite.All' }); oauth2PermissionScopes = @() })
                }
                return @()
            }
            Grant-EntraAdminConsent -App '33333333-3333-3333-3333-333333333333' -Confirm:$false -WarningVariable wv -WarningAction SilentlyContinue | Out-Null
            ($wv -join ' ') | Should -Match 'tenant-takeover-class'
            ($wv -join ' ') | Should -Match 'Directory\.ReadWrite\.All'
        }
    }

    It 'authz-M2: New-EntraConditionalAccessPolicy warns on a block-all -BodyObject with no exclusion' {
        InModuleScope JustGraphIT {
            Mock Invoke-IaRequest { [pscustomobject]@{ id = 'ca-1'; displayName = 'Lockout'; state = 'enabled' } }
            $body = @{ state = 'enabled'; grantControls = @{ builtInControls = @('block') }; conditions = @{ users = @{ includeUsers = @('All') } } }
            New-EntraConditionalAccessPolicy -Name 'Lockout' -BodyObject $body -Confirm:$false -WarningVariable wv -WarningAction SilentlyContinue | Out-Null
            ($wv -join ' ') | Should -Match 'BLOCKS all users'
        }
    }

    It 'authz-M2: New-EntraConditionalAccessPolicy does NOT warn when the block-all body excludes a break-glass group' {
        InModuleScope JustGraphIT {
            Mock Invoke-IaRequest { [pscustomobject]@{ id = 'ca-2'; displayName = 'Safe'; state = 'enabled' } }
            $body = @{ state = 'enabled'; grantControls = @{ builtInControls = @('block') }; conditions = @{ users = @{ includeUsers = @('All'); excludeGroups = @('bg-1') } } }
            New-EntraConditionalAccessPolicy -Name 'Safe' -BodyObject $body -Confirm:$false -WarningVariable wv -WarningAction SilentlyContinue | Out-Null
            ($wv -join ' ') | Should -Not -Match 'BLOCKS all users'
        }
    }

    It 'authz-1: the TUI does NOT issue a Temporary Access Pass when the operator declines' {
        InModuleScope JustGraphIT {
            Mock Get-EntraUser { [pscustomobject]@{ Enabled = $true } }
            $script:mc = 0
            Mock Read-IaMenu { $script:mc++; if ($script:mc -eq 1) { 'Issue Temporary Access Pass (passkey enrollment)' } else { 'Back' } }
            Mock Read-IaConfirm { $false }                 # decline
            Mock Read-IaPause {}; Mock Write-IaHost {}
            Mock New-EntraUserTempAccessPass { [pscustomobject]@{ TemporaryAccessPass = 'SECRET'; LifetimeMinutes = 60 } }
            Invoke-IaTuiUserActions -Accent 'cyan' -Upn 'u@x.com'
            Should -Invoke New-EntraUserTempAccessPass -Times 0 -Exactly
        }
    }

    It 'authz-1: the TUI issues the TAP only after an explicit confirmation' {
        InModuleScope JustGraphIT {
            Mock Get-EntraUser { [pscustomobject]@{ Enabled = $true } }
            $script:mc = 0
            Mock Read-IaMenu { $script:mc++; if ($script:mc -eq 1) { 'Issue Temporary Access Pass (passkey enrollment)' } else { 'Back' } }
            Mock Read-IaConfirm { $true }                  # confirm
            Mock Read-IaPause {}; Mock Write-IaHost {}
            Mock New-EntraUserTempAccessPass { [pscustomobject]@{ TemporaryAccessPass = 'SECRET'; LifetimeMinutes = 60 } }
            Invoke-IaTuiUserActions -Accent 'cyan' -Upn 'u@x.com'
            Should -Invoke New-EntraUserTempAccessPass -Times 1 -Exactly
        }
    }

    It 'mask: Read-IaTableInteractive -HideColumns drops the column from render/export, not the row' {
        InModuleScope JustGraphIT {
            $script:shown = $null
            Mock Test-IaArrowSupport { $false }                  # force the non-interactive projection path
            Mock Show-IaTableObjects { $script:shown = $Rows }   # capture what would render / export
            Mock Read-IaPause {}
            $data = @([pscustomobject]@{ Name = 'A'; GrantId = '•••'; _GrantId = 'real-grant-1' })
            Read-IaTableInteractive -Data $data -HideColumns '_GrantId' | Out-Null
            $cols = @($script:shown[0].PSObject.Properties.Name)
            $cols | Should -Contain 'GrantId'                    # masked placeholder still shown
            $cols | Should -Not -Contain '_GrantId'              # real id never leaves to render/export
            $script:shown[0].GrantId | Should -Be '•••'
        }
    }
}

Describe 'Query to group pipeline (beta)' {
    It 'Get-IntuneStaleDevice filters managedDevices on lastSyncDateTime and computes DaysStale' {
        InModuleScope JustGraphIT {
            $script:p = $null
            Mock Get-IaCollection {
                $script:p = $Path
                @([pscustomobject]@{ deviceName = 'OLD-PC'; operatingSystem = 'Windows'; osVersion = '10.0'; lastSyncDateTime = '2020-01-01T00:00:00Z'
                        userPrincipalName = 'a@x.com'; managedDeviceOwnerType = 'company'; complianceState = 'compliant'; azureADDeviceId = 'aad-1'; id = 'md-1' })
            }
            $rows = @(Get-IntuneStaleDevice -Days 30)
            $script:p | Should -Match 'graph\.microsoft\.com/beta/deviceManagement/managedDevices'
            $script:p | Should -Match 'lastSyncDateTime'
            $rows[0].DeviceName      | Should -Be 'OLD-PC'
            $rows[0].AzureAdDeviceId | Should -Be 'aad-1'
            $rows[0].DaysStale       | Should -BeGreaterThan 30
        }
    }

    It 'Resolve-EntraDeviceObjectId maps an azureADDeviceId to the Entra device object id' {
        InModuleScope JustGraphIT {
            $script:p = $null
            Mock Get-IaCollection { $script:p = $Path; @([pscustomobject]@{ id = 'dev-obj-1' }) }
            Resolve-EntraDeviceObjectId -AzureAdDeviceId 'aad-xyz' | Should -Be 'dev-obj-1'
            $script:p | Should -Match "devices\?.*deviceId eq 'aad-xyz'"
        }
    }

    It 'Add-EntraGroupMemberBulk adds each member via $ref and counts already-members as added' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraGroupId { 'g-1' }
            $script:n = 0
            Mock Invoke-IaRequest {
                $script:n++
                if ($script:n -eq 2) { throw 'One or more added object references already exist for the following modified properties: members.' }
            }
            $r = Add-EntraGroupMemberBulk -Group 'Stale devices' -MemberId 'o1', 'o2', 'o3' -Confirm:$false
            Should -Invoke Invoke-IaRequest -Times 3 -Exactly
            $r.Added    | Should -Be 3
            $r.Failed   | Should -Be 0
            $r.Requested | Should -Be 3
        }
    }

    It 'Add-EntraGroupMemberBulk records genuine failures' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraGroupId { 'g-1' }
            Mock Invoke-IaRequest { throw 'Insufficient privileges' }
            $r = Add-EntraGroupMemberBulk -Group 'g' -MemberId 'o1', 'o2' -Confirm:$false
            $r.Added  | Should -Be 0
            $r.Failed | Should -Be 2
        }
    }
}

Describe 'Entra Teams depth (beta)' {
    It 'New-EntraTeamChannel POSTs a channel with membershipType' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraGroupId { 'team-1' }
            $script:u = $null; $script:b = $null
            Mock Invoke-IaRequest { $script:u = $Uri; $script:b = $Body; [pscustomobject]@{ id = '19:abc'; displayName = 'Releases'; membershipType = 'private' } }
            New-EntraTeamChannel -Team 'Project Atlas' -Name 'Releases' -Private -Confirm:$false | Out-Null
            $script:u | Should -Match 'graph\.microsoft\.com/beta/teams/team-1/channels$'
            $script:b.displayName    | Should -Be 'Releases'
            $script:b.membershipType | Should -Be 'private'
        }
    }

    It 'Add-EntraTeamMember POSTs an aadUserConversationMember with the owner role' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraGroupId { 'team-1' }
            Mock Resolve-EntraUserId { 'user-9' }
            $script:u = $null; $script:b = $null
            Mock Invoke-IaRequest { $script:u = $Uri; $script:b = $Body; [pscustomobject]@{ id = 'mem-1' } }
            Add-EntraTeamMember -Team 'Project Atlas' -User 'bob@x.com' -Owner -Confirm:$false | Out-Null
            $script:u | Should -Match 'graph\.microsoft\.com/beta/teams/team-1/members$'
            $script:b.'@odata.type'     | Should -Be '#microsoft.graph.aadUserConversationMember'
            @($script:b.roles)          | Should -Contain 'owner'
            $script:b.'user@odata.bind' | Should -Match "users\('user-9'\)"
        }
    }

    It 'Remove-EntraTeamMember resolves the membership id then DELETEs it' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraGroupId { 'team-1' }
            Mock Resolve-EntraUserId { 'user-9' }
            Mock Get-IaCollection { @([pscustomobject]@{ id = 'membership-77'; userId = 'user-9'; displayName = 'Bob'; roles = @() }) }
            $script:m = $null; $script:u = $null
            Mock Invoke-IaRequest { $script:m = $Method; $script:u = $Uri }
            Remove-EntraTeamMember -Team 'Project Atlas' -User 'bob@x.com' -Confirm:$false | Out-Null
            $script:m | Should -Be 'DELETE'
            $script:u | Should -Match 'teams/team-1/members/membership-77$'
        }
    }
}

Describe 'Entra users & licensing depth (beta)' {
    It 'Set-EntraUser PATCHes the extended address / name properties' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraUserId { 'u-1' }
            $script:b = $null
            Mock Invoke-IaRequest { $script:b = $Body }
            Set-EntraUser -User 'a@x.com' -City 'Seattle' -Country 'US' -GivenName 'Ada' -EmployeeType 'Contractor' -Confirm:$false | Out-Null
            $script:b.city         | Should -Be 'Seattle'
            $script:b.country      | Should -Be 'US'
            $script:b.givenName    | Should -Be 'Ada'
            $script:b.employeeType | Should -Be 'Contractor'
        }
    }

    It 'Get-EntraUserManager reads the beta manager navigation' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraUserId { 'u-1' }
            $script:u = $null
            Mock Invoke-IaRequest { $script:u = $Uri; [pscustomobject]@{ id = 'mgr-1'; displayName = 'Boss'; userPrincipalName = 'boss@x.com'; jobTitle = 'VP' } }
            $r = Get-EntraUserManager -User 'a@x.com'
            $script:u | Should -Match 'graph\.microsoft\.com/beta/users/u-1/manager\?\$select='
            $r.Manager    | Should -Be 'Boss'
            $r.ManagerUPN | Should -Be 'boss@x.com'
        }
    }

    It 'Remove-EntraUserManager DELETEs the manager $ref' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraUserId { 'u-1' }
            $script:m = $null; $script:u = $null
            Mock Invoke-IaRequest { $script:m = $Method; $script:u = $Uri }
            Remove-EntraUserManager -User 'a@x.com' -Confirm:$false | Out-Null
            $script:m | Should -Be 'DELETE'
            $script:u | Should -Match 'users/u-1/manager/\$ref$'
        }
    }

    It 'Set-EntraGroupLicense resolves the SKU part number and POSTs assignLicense' {
        InModuleScope JustGraphIT {
            Mock Resolve-EntraGroupId { 'g-1' }
            Mock Get-IaCollection { @([pscustomobject]@{ skuId = 'sku-guid-1'; skuPartNumber = 'ENTERPRISEPACK' }) }
            $script:u = $null; $script:b = $null
            Mock Invoke-IaRequest { $script:u = $Uri; $script:b = $Body }
            Set-EntraGroupLicense -Group 'Sales' -AddSku 'ENTERPRISEPACK' -Confirm:$false | Out-Null
            $script:u | Should -Match 'graph\.microsoft\.com/beta/groups/g-1/assignLicense$'
            @($script:b.addLicenses)[0].skuId | Should -Be 'sku-guid-1'
        }
    }
}

Describe 'Intune device writes (beta)' {
    It 'Set-IntuneDevicePrimaryUser POSTs a users/$ref to the managed device' {
        InModuleScope JustGraphIT {
            Mock Resolve-IaManagedDeviceId { 'md-1' }
            Mock Resolve-EntraUserId { 'u-9' }
            $script:u = $null; $script:b = $null
            Mock Invoke-IaRequest { $script:u = $Uri; $script:b = $Body }
            Set-IntuneDevicePrimaryUser -Device 'LAPTOP-7' -User 'a@x.com' -Confirm:$false | Out-Null
            $script:u | Should -Match 'graph\.microsoft\.com/beta/deviceManagement/managedDevices/md-1/users/\$ref$'
            $script:b.'@odata.id' | Should -Match 'users/u-9$'
        }
    }

    It 'Set-IntuneDeviceCategory resolves the category name then PUTs the ref' {
        InModuleScope JustGraphIT {
            Mock Resolve-IaManagedDeviceId { 'md-1' }
            Mock Get-IaCollection { @([pscustomobject]@{ id = 'cat-1'; displayName = 'Kiosks'; description = '' }) }
            $script:m = $null; $script:u = $null; $script:b = $null
            Mock Invoke-IaRequest { $script:m = $Method; $script:u = $Uri; $script:b = $Body }
            Set-IntuneDeviceCategory -Device 'KIOSK-1' -Category 'Kiosks' -Confirm:$false | Out-Null
            $script:m | Should -Be 'PUT'
            $script:u | Should -Match 'managedDevices/md-1/deviceCategory/\$ref$'
            $script:b.'@odata.id' | Should -Match 'deviceCategories/cat-1$'
        }
    }
}

Describe 'Entra usage reports (CSV → objects)' {
    It 'Get-EntraMailboxUsage computes UsedGB / QuotaGB / PercentUsed from the report CSV' {
        InModuleScope JustGraphIT {
            Mock Get-IaGraphReportCsv {
                @([pscustomobject]@{
                    'User Principal Name'='a@x.com'; 'Display Name'='Aaron'; 'Item Count'='1200'
                    'Storage Used (Byte)'='53687091200'                    # 50 GB
                    'Prohibit Send/Receive Quota (Byte)'='107374182400'    # 100 GB
                    'Issue Warning Quota (Byte)'='106300440576'; 'Last Activity Date'='2026-06-01' })
            }
            $r = @(Get-EntraMailboxUsage)
            $r[0].UsedGB      | Should -Be 50
            $r[0].QuotaGB     | Should -Be 100
            $r[0].PercentUsed | Should -Be 50
            $r[0].User        | Should -Be 'a@x.com'
        }
    }
    It 'Get-EntraMailboxUsage -Period builds the beta getMailboxUsageDetail path' {
        InModuleScope JustGraphIT {
            $script:p=$null
            Mock Get-IaGraphReportCsv { $script:p=$Path; @() }
            Get-EntraMailboxUsage -Period D7 | Out-Null
            $script:p | Should -Be "reports/getMailboxUsageDetail(period='D7')"
        }
    }
}
