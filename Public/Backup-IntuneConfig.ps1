function Backup-IntuneConfig {
    <#
    .SYNOPSIS
        Full configuration backup — every Intune config exported as its own file.

    .DESCRIPTION
        Captures each resource's *complete definition* (not just its assignments)
        and writes one self-contained JSON file per config into a per-area folder,
        plus a manifest.json index. Settings-catalog settings, security-baseline
        settings, and ADMX definition values are embedded so each file stands
        alone. Pair with Restore-IntuneConfig.

        This is broader than Backup-IntuneAssignment (which snapshots only
        targeting). Use it for archival, version control, or disaster recovery.

    .PARAMETER Path
        Destination folder. Optional — defaults to a timestamped folder
        (intunetide-config-yyyy-MM-dd-HHmm) in the current directory.

    .PARAMETER Area
        Limit the backup to one or more areas (Apps, Configuration, …).

    .PARAMETER Type
        Limit to one or more resource type keys.

    .PARAMETER AssignedOnly
        Only back up resources that currently have assignments.

    .EXAMPLE
        Backup-IntuneConfig

        Full-tenant config backup into a timestamped folder.

    .EXAMPLE
        Backup-IntuneConfig -Path .\baseline -Area Configuration, Compliance

        Back up just configuration and compliance policies.

    .OUTPUTS
        PSCustomObject: Path, Count, Areas, Files (and writes files to -Path).

    .LINK
        Restore-IntuneConfig
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [string[]]$Area,
        [string[]]$Type,
        [switch]$AssignedOnly
    )
    if (-not $Path) { $Path = Get-IaBackupName -Prefix 'intunetide-config' -Extension '' }
    $null = New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop

    $items = Get-IaInventory -Area $Area -Type $Type -AssignedOnly:$AssignedOnly
    $tenant = try { (Get-MgContext).TenantId } catch { $null }
    $index = [System.Collections.Generic.List[object]]::new()
    $used = @{}
    $n = 0; $total = @($items).Count

    foreach ($it in $items) {
        $n++
        Write-Progress -Activity 'Backing up Intune configs' -Status "$($it.Area) / $($it.Name)" -PercentComplete (($n / [math]::Max($total, 1)) * 100)
        $record = Get-IaFullResource -Item $it
        $areaDir = Join-Path $Path (Get-IaSafeFileName -Name $it.Area)
        $null = New-Item -ItemType Directory -Path $areaDir -Force -ErrorAction SilentlyContinue

        $base = Get-IaSafeFileName -Name $it.Name
        $key = "$($it.Area)/$base".ToLower()
        if ($used.ContainsKey($key)) {
            $stub = "$($it.Id)".Substring(0, [math]::Min(8, "$($it.Id)".Length))
            $base = "$base ($stub)"
        }
        $used[$key] = $true

        $file = Join-Path $areaDir "$base.json"
        $record | ConvertTo-Json -Depth 30 | Set-Content -Path $file -Encoding utf8
        $index.Add([pscustomobject]@{
                area = $it.Area; type = $it.ResourceType; name = $it.Name; id = $it.Id
                file = (Resolve-Path -Path $file -Relative -ErrorAction SilentlyContinue) ?? $file
            })
    }
    Write-Progress -Activity 'Backing up Intune configs' -Completed

    $manifest = [pscustomobject]@{
        schema  = 'intunetide/config-backup-manifest/1'
        created = (Get-Date).ToUniversalTime().ToString('o')
        tenant  = $tenant
        count   = $index.Count
        files   = @($index)
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $Path 'manifest.json') -Encoding utf8

    [pscustomobject]@{
        Path  = (Resolve-Path -Path $Path -ErrorAction SilentlyContinue).Path ?? $Path
        Count = $index.Count
        Areas = @($items | Group-Object Area | ForEach-Object { $_.Name } | Sort-Object)
        Files = @($index)
    }
}
