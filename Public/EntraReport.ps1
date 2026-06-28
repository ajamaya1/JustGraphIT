function Get-EntraMailboxUsage {
    <#
    .SYNOPSIS
        Mailbox storage usage and quota per user (the "who's near their quota" report).
        Beta GET /beta/reports/getMailboxUsageDetail(period='D30').
    .DESCRIPTION
        Returns used storage, the prohibit-send/receive quota, percent used and the
        warning quota, sorted by percent used. -Raw returns the raw CSV columns.
        Needs Reports.Read.All. Tenant "concealed names" privacy setting can mask UPNs.
    .PARAMETER Period
        Reporting window: D7, D30 (default), D90 or D180.
    .OUTPUTS
        PSCustomObject: User, DisplayName, ItemCount, UsedGB, QuotaGB, PercentUsed,
        IssueWarningGB, LastActivity.
    #>
    [CmdletBinding()]
    param([ValidateSet('D7', 'D30', 'D90', 'D180')][string]$Period = 'D30', [switch]$Raw)
    $rows = @(Get-IaGraphReportCsv "reports/getMailboxUsageDetail(period='$Period')")
    if ($Raw) { return $rows }
    @($rows | ForEach-Object {
        $used  = ConvertTo-IaGB $_.'Storage Used (Byte)'
        $quota = ConvertTo-IaGB $_.'Prohibit Send/Receive Quota (Byte)'
        [pscustomobject][ordered]@{
            User         = $_.'User Principal Name'
            DisplayName  = $_.'Display Name'
            ItemCount    = $_.'Item Count'
            UsedGB       = $used
            QuotaGB      = $quota
            PercentUsed  = if ($quota) { [int][math]::Round($used / $quota * 100) } else { 0 }
            IssueWarningGB = (ConvertTo-IaGB $_.'Issue Warning Quota (Byte)')
            LastActivity = $_.'Last Activity Date'
        }
    } | Sort-Object PercentUsed -Descending)
}

function Get-EntraOneDriveUsage {
    <#
    .SYNOPSIS
        OneDrive storage usage and quota per account. Beta
        GET /beta/reports/getOneDriveUsageAccountDetail(period='D30').
    #>
    [CmdletBinding()]
    param([ValidateSet('D7', 'D30', 'D90', 'D180')][string]$Period = 'D30', [switch]$Raw)
    $rows = @(Get-IaGraphReportCsv "reports/getOneDriveUsageAccountDetail(period='$Period')")
    if ($Raw) { return $rows }
    @($rows | ForEach-Object {
        $used  = ConvertTo-IaGB $_.'Storage Used (Byte)'
        $alloc = ConvertTo-IaGB $_.'Storage Allocated (Byte)'
        [pscustomobject][ordered]@{
            Owner        = $_.'Owner Principal Name'
            DisplayName  = $_.'Owner Display Name'
            Files        = $_.'File Count'
            ActiveFiles  = $_.'Active File Count'
            UsedGB       = $used
            AllocatedGB  = $alloc
            PercentUsed  = if ($alloc) { [int][math]::Round($used / $alloc * 100) } else { 0 }
            LastActivity = $_.'Last Activity Date'
        }
    } | Sort-Object PercentUsed -Descending)
}

function Get-EntraSharePointUsage {
    <#
    .SYNOPSIS
        SharePoint site storage usage. Beta
        GET /beta/reports/getSharePointSiteUsageDetail(period='D30').
    #>
    [CmdletBinding()]
    param([ValidateSet('D7', 'D30', 'D90', 'D180')][string]$Period = 'D30', [switch]$Raw)
    $rows = @(Get-IaGraphReportCsv "reports/getSharePointSiteUsageDetail(period='$Period')")
    if ($Raw) { return $rows }
    @($rows | ForEach-Object {
        $used  = ConvertTo-IaGB $_.'Storage Used (Byte)'
        $alloc = ConvertTo-IaGB $_.'Storage Allocated (Byte)'
        [pscustomobject][ordered]@{
            Site         = $_.'Site URL'
            Owner        = $_.'Owner Display Name'
            Files        = $_.'File Count'
            ActiveFiles  = $_.'Active File Count'
            UsedGB       = $used
            AllocatedGB  = $alloc
            PercentUsed  = if ($alloc) { [int][math]::Round($used / $alloc * 100) } else { 0 }
            LastActivity = $_.'Last Activity Date'
        }
    } | Sort-Object UsedGB -Descending)
}

function Get-EntraTeamsUsage {
    <#
    .SYNOPSIS
        Per-user Teams activity (messages, meetings, calls, last activity). Beta
        GET /beta/reports/getTeamsUserActivityUserDetail(period='D30').
    #>
    [CmdletBinding()]
    param([ValidateSet('D7', 'D30', 'D90', 'D180')][string]$Period = 'D30', [switch]$Raw)
    $rows = @(Get-IaGraphReportCsv "reports/getTeamsUserActivityUserDetail(period='$Period')")
    if ($Raw) { return $rows }
    @($rows | ForEach-Object {
        [pscustomobject][ordered]@{
            User          = $_.'User Principal Name'
            UserId        = $_.'User Id'
            TeamChat      = $_.'Team Chat Message Count'
            PrivateChat   = $_.'Private Chat Message Count'
            Calls         = $_.'Call Count'
            Meetings      = $_.'Meeting Count'
            LastActivity  = $_.'Last Activity Date'
            ProductsAssigned = $_.'Assigned Products'
        }
    } | Sort-Object LastActivity -Descending)
}

function Get-EntraM365AppUsage {
    <#
    .SYNOPSIS
        Per-user Microsoft 365 Apps activation/usage (which apps & platforms they use).
        Beta GET /beta/reports/getM365AppUserDetail(period='D30').
    #>
    [CmdletBinding()]
    param([ValidateSet('D7', 'D30', 'D90', 'D180')][string]$Period = 'D30', [switch]$Raw)
    $rows = @(Get-IaGraphReportCsv "reports/getM365AppUserDetail(period='$Period')")
    if ($Raw) { return $rows }
    @($rows | ForEach-Object {
        [pscustomobject][ordered]@{
            User         = $_.'User Principal Name'
            LastActivity = $_.'Last Activation Date'
            Windows      = $_.'Windows'
            Mac          = $_.'Mac'
            Mobile       = $_.'Mobile'
            Web          = $_.'Web'
            Outlook      = $_.'Outlook'
            Word         = $_.'Word'
            Excel        = $_.'Excel'
            Teams        = $_.'Teams'
        }
    })
}
