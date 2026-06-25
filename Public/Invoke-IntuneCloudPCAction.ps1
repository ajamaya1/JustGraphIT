function Invoke-IntuneCloudPCAction {
    <#
    .SYNOPSIS
        Submit a remote action against a Windows 365 Cloud PC.

    .DESCRIPTION
        Resolves the Cloud PC by name or id and posts a lifecycle action to the
        Graph API. Actions that require extra parameters (Resize, Rename, Restore)
        are validated before submission.

    .PARAMETER CloudPC
        Cloud PC display name or id.

    .PARAMETER Action
        The action to submit.

    .PARAMETER ServicePlanId
        Required for the Resize action. The target service plan id.

    .PARAMETER NewName
        Required for the Rename action. The new display name.

    .PARAMETER SnapshotId
        Required for the Restore action. The snapshot id to restore from.

    .EXAMPLE
        Invoke-IntuneCloudPCAction -CloudPC "Alice-W365" -Action Restart

    .EXAMPLE
        Invoke-IntuneCloudPCAction -CloudPC "Alice-W365" -Action Resize -ServicePlanId "abc123"

    .OUTPUTS
        PSCustomObject: CloudPC, Action, Submitted.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$CloudPC,
        [Parameter(Mandatory)]
        [ValidateSet(
            'Reprovision', 'Resize', 'Restart', 'Rename', 'Restore',
            'Troubleshoot', 'EndGracePeriod', 'CreateSnapshot', 'PowerOn', 'PowerOff'
        )]
        [string]$Action,
        [string]$ServicePlanId,
        [string]$NewName,
        [string]$SnapshotId
    )

    switch ($Action) {
        'Resize'  { if (-not $ServicePlanId) { throw "Action 'Resize' requires -ServicePlanId." } }
        'Rename'  { if (-not $NewName)       { throw "Action 'Rename' requires -NewName." } }
        'Restore' { if (-not $SnapshotId)    { throw "Action 'Restore' requires -SnapshotId." } }
    }

    $id = Resolve-IaCloudPCId -Value $CloudPC

    $body = switch ($Action) {
        'Resize'  { @{ servicePlanId = $ServicePlanId } }
        'Rename'  { @{ displayName   = $NewName } }
        'Restore' { @{ cloudPcSnapshotId = $SnapshotId } }
        default   { @{} }
    }

    # Graph action names are camelCase; map pascal-case action names.
    $graphAction = switch ($Action) {
        'Reprovision'     { 'reprovision' }
        'Resize'          { 'resize' }
        'Restart'         { 'reboot' }
        'Rename'          { 'rename' }
        'Restore'         { 'restore' }
        'Troubleshoot'    { 'troubleshoot' }
        'EndGracePeriod'  { 'endGracePeriod' }
        'CreateSnapshot'  { 'createSnapshot' }
        'PowerOn'         { 'powerOn' }
        'PowerOff'        { 'powerOff' }
    }

    if (-not $PSCmdlet.ShouldProcess("$CloudPC — action: $Action", 'Invoke-IntuneCloudPCAction')) {
        return
    }

    Invoke-IaCloudPCPost -Id $id -Action $graphAction -Body $body | Out-Null

    [pscustomobject]@{
        CloudPC   = $CloudPC
        Action    = $Action
        Submitted = $true
    }
}
