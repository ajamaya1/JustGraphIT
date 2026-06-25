function Get-IntuneCloudPCUserSetting {
    <#
    .SYNOPSIS
        List Windows 365 Cloud PC user settings policies.

    .DESCRIPTION
        Returns Cloud PC user settings policies which control per-user features
        such as local admin rights and self-service restore options.

    .PARAMETER Policy
        Optional policy name or id. Returns all policies when omitted.

    .EXAMPLE
        Get-IntuneCloudPCUserSetting

        All user settings policies in the tenant.

    .OUTPUTS
        PSCustomObject: Name, LocalAdminEnabled, SelfServiceEnabled,
        RestorePointFrequency, Id.
    #>
    [CmdletBinding()]
    param(
        [string]$Policy
    )

    if ($Policy -and (Test-IaGuid $Policy)) {
        $item = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri (Get-IaW365Path "userSettings/$Policy"))
        $items = @($item)
    } elseif ($Policy) {
        $all   = Get-IaCollection (Get-IaW365Path 'userSettings')
        $items = @($all | Where-Object { $_.displayName -eq $Policy })
        if (-not $items) { throw "No Cloud PC user setting named '$Policy' was found." }
    } else {
        $items = Get-IaCollection (Get-IaW365Path 'userSettings')
    }

    foreach ($s in $items) {
        [pscustomobject][ordered]@{
            Name                  = $s.displayName
            LocalAdminEnabled     = $s.localAdminEnabled
            SelfServiceEnabled    = $s.selfServiceEnabled
            RestorePointFrequency = $s.restorePointSetting?.frequencyType
            Id                    = $s.id
        }
    }
}
