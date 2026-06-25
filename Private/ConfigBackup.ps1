# Full-configuration backup / restore. Unlike the assignment snapshot (which
# captures only *who is targeted*), this captures each resource's complete
# definition — one self-contained JSON file per config — so a tenant's configs
# can be archived, version-controlled, or re-created.
#
# Export is read-only and covers every area. Restore is preview-first and
# conservative: it UPDATES existing configs and (opt-in) CREATES missing ones
# for the self-contained types below; complex types that need child resources
# or a server template are exported for reference but reported, not blind-written.

# Resource types whose body can be re-created from a single POST. Settings
# catalog carries its settings as a child collection embedded on export.
$script:IaConfigCreatable = @{
    configurationPolicies    = @{ SettingsInline = $true }
    deviceConfigurations     = @{ SettingsInline = $false }
    deviceCompliancePolicies = @{ SettingsInline = $false }
    deviceManagementScripts  = @{ SettingsInline = $false }
    deviceShellScripts       = @{ SettingsInline = $false }
    deviceHealthScripts      = @{ SettingsInline = $false }
}

function Get-IaResourceChildren {
    # Type-specific child collections that don't ride along on the base GET, so
    # the exported file is self-contained.
    param([Parameter(Mandatory)][object]$Item)
    $children = [ordered]@{}
    switch ($Item.ResourceType) {
        'configurationPolicies' {
            $children.settings = @(Get-IaCollection "deviceManagement/configurationPolicies/$($Item.Id)/settings")
        }
        'intents' {
            $children.settings = @(Get-IaCollection "deviceManagement/intents/$($Item.Id)/settings")
        }
        'groupPolicyConfigurations' {
            $children.definitionValues = @(Get-IaCollection "deviceManagement/groupPolicyConfigurations/$($Item.Id)/definitionValues?`$expand=definition,presentationValues")
        }
    }
    $children
}

function Get-IaFullResource {
    # The complete, self-contained backup record for one inventory item: the full
    # config object, any embedded child config, and the assignment snapshot.
    param([Parameter(Mandatory)][object]$Item)
    $rt = Find-IaResourceType -Key $Item.ResourceType
    $full = $null
    try { $full = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "$($rt.ListPath)/$($Item.Id)") }
    catch { $full = $Item.Raw }
    $snap = ConvertTo-IaAssignmentSnapshot -Item $Item
    [pscustomobject][ordered]@{
        schema       = 'intunetide/config-backup/1'
        resourceType = $Item.ResourceType
        area         = $Item.Area
        id           = $Item.Id
        name         = $Item.Name
        odataType    = $Item.ODataType
        config       = $full
        children     = (Get-IaResourceChildren -Item $Item)
        assignments  = $snap.assignments
    }
}

function Get-IaSafeFileName {
    # A filesystem-safe file name derived from a resource display name.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)
    $clean = "$Name"
    foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) { $clean = $clean.Replace($c, '_') }
    $clean = $clean.Trim().TrimEnd('.')
    if (-not $clean) { $clean = 'unnamed' }
    if ($clean.Length -gt 120) { $clean = $clean.Substring(0, 120) }
    $clean
}

function Remove-IaReadOnlyField {
    # Strip server-managed / computed fields so a config body is safe to POST/PATCH.
    param([Parameter(Mandatory)][object]$Config)
    $drop = @(
        '@odata.context', '@odata.id', 'id', 'createdDateTime', 'lastModifiedDateTime',
        'version', 'isAssigned', 'assignments', 'settingCount', 'creationSource',
        'deviceStatusOverview', 'userStatusOverview', 'deviceStatuses', 'userStatuses',
        'deviceSettingStateSummaries', 'supportsScopeTags'
    )
    $h = [ordered]@{}
    foreach ($p in $Config.PSObject.Properties) {
        if ($p.Name -in $drop) { continue }
        $h[$p.Name] = $p.Value
    }
    $h
}

function New-IaConfigCreateBody {
    # Build the POST body to re-create a config from a backup record. Returns
    # $null for types that can't be re-created from a single self-contained body.
    param([Parameter(Mandatory)][object]$Record)
    if (-not $script:IaConfigCreatable.ContainsKey($Record.resourceType)) { return $null }
    $body = Remove-IaReadOnlyField -Config $Record.config
    if ($script:IaConfigCreatable[$Record.resourceType].SettingsInline -and $Record.children.settings) {
        $body.settings = @(foreach ($s in $Record.children.settings) {
                @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = $s.settingInstance }
            })
    }
    $body
}

function Find-IaLiveResource {
    # Locate the live resource for a backup record: by id first, then by name.
    param([Parameter(Mandatory)][object]$Record, [Parameter(Mandatory)][object]$ResourceType)
    try { return Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "$($ResourceType.ListPath)/$($Record.id)") } catch { }
    try {
        $hit = Get-IaCollection "$($ResourceType.ListPath)?`$select=id,$($ResourceType.NameField)" |
            Where-Object { $_.$($ResourceType.NameField) -eq $Record.name } | Select-Object -First 1
        if ($hit) { return Invoke-IaRequest -Method GET -Uri (Resolve-IaUri -Path "$($ResourceType.ListPath)/$($hit.id)") }
    } catch { }
    $null
}

function Read-IaConfigBackup {
    # Load every config record from a backup folder (recursively), newest schema.
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { throw "Backup folder not found: $Path" }
    $files = Get-ChildItem -Path $Path -Filter '*.json' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'manifest.json' }
    foreach ($f in $files) {
        $rec = Get-Content -Path $f.FullName -Raw | ConvertFrom-Json
        if ($rec.schema -eq 'intunetide/config-backup/1') { $rec }
    }
}
