function Clear-IntuneCallLog {
    <#
    .SYNOPSIS
        Clear the in-memory Graph call log.
    .EXAMPLE
        Clear-IntuneCallLog
    .LINK
        Get-IntuneCallLog
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if ($PSCmdlet.ShouldProcess('Graph call log', 'Clear')) { Clear-IaCallLog }
}
