function Get-IntuneCompliancePolicy {
    <#
    .SYNOPSIS
        List or retrieve Intune compliance policies.

    .DESCRIPTION
        Returns compliance policies from /deviceManagement/deviceCompliancePolicies.
        Platform is derived from the @odata.type of each policy.
        Use -Id to retrieve a single policy with its scheduled actions and assignments.

    .PARAMETER Id
        Policy name or GUID. Returns a single policy with assignments expanded.

    .PARAMETER Platform
        Filter by platform: Windows, macOS, iOS, Android, AndroidWorkProfile,
        AndroidDeviceAdministrator, all (default).

    .EXAMPLE
        Get-IntuneCompliancePolicy

    .EXAMPLE
        Get-IntuneCompliancePolicy -Platform iOS

    .EXAMPLE
        Get-IntuneCompliancePolicy -Id 'Windows Compliance Baseline'

    .OUTPUTS
        PSCustomObject: Id, Name, Platform, Description, Created, Modified, Settings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Id,
        [ValidateSet('Windows','macOS','iOS','Android','AndroidWorkProfile','AndroidDeviceAdministrator','all')]
        [string]$Platform = 'all'
    )

    if ($Id) {
        $resolved = Resolve-IaCompliancePolicyId -Value $Id
        $policy = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/deviceCompliancePolicies/${resolved}?`$expand=assignments,scheduledActionsForRule")
        return ConvertTo-IaCompliancePolicyObject -Policy $policy
    }

    $all = Get-IaCollection (Resolve-IaUri 'deviceManagement/deviceCompliancePolicies')
    foreach ($p in $all) {
        $obj = ConvertTo-IaCompliancePolicyObject -Policy $p
        if ($Platform -eq 'all' -or $obj.Platform -eq $Platform) { $obj }
    }
}

function Resolve-IaCompliancePolicyId {
    param([string]$Value)
    if (Test-IaGuid $Value) { return $Value }
    $encoded = [uri]::EscapeDataString($Value)
    $results = Get-IaCollection (Resolve-IaUri "deviceManagement/deviceCompliancePolicies?`$filter=displayName eq '$encoded'&`$select=id,displayName")
    if ($results.Count -eq 0) { throw "No compliance policy found matching '$Value'." }
    if ($results.Count -gt 1) { throw "Multiple policies match '$Value'. Provide a unique id." }
    $results[0].id
}

function ConvertTo-IaCompliancePolicyObject {
    param($Policy)
    $platformMap = @{
        '#microsoft.graph.windows10CompliancePolicy'                   = 'Windows'
        '#microsoft.graph.macOSCompliancePolicy'                       = 'macOS'
        '#microsoft.graph.iosCompliancePolicy'                         = 'iOS'
        '#microsoft.graph.androidCompliancePolicy'                     = 'Android'
        '#microsoft.graph.androidWorkProfileCompliancePolicy'          = 'AndroidWorkProfile'
        '#microsoft.graph.androidDeviceOwnerCompliancePolicy'          = 'AndroidDeviceOwner'
        '#microsoft.graph.aospDeviceOwnerCompliancePolicy'             = 'AndroidAOSP'
    }
    # Coerce to string so a missing/null @odata.type can't throw on the hashtable index
    # ($hashtable[$null] is an error; $hashtable[''] is just a miss).
    $odataType = [string]$Policy.'@odata.type'
    $platform  = $platformMap[$odataType] ?? ($odataType -replace '#microsoft.graph.', '' -replace 'CompliancePolicy', '')

    [pscustomobject][ordered]@{
        Id          = $Policy.id
        Name        = $Policy.displayName
        Platform    = $platform
        Description = $Policy.description
        ODataType   = $odataType
        Created     = $Policy.createdDateTime
        Modified    = $Policy.lastModifiedDateTime
        Settings    = $Policy
    }
}
