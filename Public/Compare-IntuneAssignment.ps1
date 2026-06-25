function Compare-IntuneAssignment {
    <#
    .SYNOPSIS
        Diff the assignments of two groups.
    .DESCRIPTION
        Emits one row per resource that either group touches, classified as
        OnlyA, OnlyB, Both, or Conflict (one includes while the other excludes).
        Use -Path to export the diff directly to a file; -Format selects the
        output format (default Csv). The rows are always written to the pipeline
        too, so piping still works.
    .EXAMPLE
        Compare-IntuneAssignment -GroupA "Pilot Ring" -GroupB "Production Ring" |
            Where-Object Relationship -eq OnlyA
    .EXAMPLE
        Compare-IntuneAssignment -GroupA "Pilot" -GroupB "Prod" -Path diff.csv
    .EXAMPLE
        Compare-IntuneAssignment -GroupA "Pilot" -GroupB "Prod" -Path diff.html -Format Html
    .OUTPUTS
        PSCustomObject: Area, Resource, Relationship (OnlyA/OnlyB/Both/Conflict), AMode, BMode.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GroupA,
        [Parameter(Mandatory)][string]$GroupB,
        [string[]]$Area,
        [string[]]$Type,
        [string]$Path,
        [ValidateSet('Csv', 'Excel', 'Html')][string]$Format = 'Csv'
    )
    $a = Resolve-IaGroup -Value $GroupA
    $b = Resolve-IaGroup -Value $GroupB
    $items = Get-IaInventory -Area $Area -Type $Type -AssignedOnly
    $rows = @(foreach ($it in $items) {
        $am = Get-IaItemGroupMode -Item $it -GroupId $a.Id
        $bm = Get-IaItemGroupMode -Item $it -GroupId $b.Id
        if ($am -eq 'none' -and $bm -eq 'none') { continue }
        $rel =
            if ($am -ne 'none' -and $bm -eq 'none') { 'OnlyA' }
            elseif ($bm -ne 'none' -and $am -eq 'none') { 'OnlyB' }
            elseif (($am -eq 'include' -and $bm -eq 'exclude') -or ($am -eq 'exclude' -and $bm -eq 'include')) { 'Conflict' }
            else { 'Both' }
        [pscustomobject]@{
            Area = $it.Area; Resource = $it.Name; Relationship = $rel; AMode = $am; BMode = $bm
        }
    })

    if ($Path) {
        switch ($Format) {
            'Csv'   { $rows | Export-Csv -Path $Path -NoTypeInformation -Encoding utf8 }
            'Excel' { $rows | Export-IntuneExcel -Path $Path -WorksheetName 'Comparison' -Title "Group diff: $($a.DisplayName) vs $($b.DisplayName)" }
            'Html'  { New-IaGroupComparisonHtml -Rows $rows -GroupA $a.DisplayName -GroupB $b.DisplayName |
                          Set-Content -Path $Path -Encoding utf8 }
        }
        Write-Verbose "Wrote $Format comparison ($($rows.Count) row(s)) to $Path"
    }

    $rows
}
