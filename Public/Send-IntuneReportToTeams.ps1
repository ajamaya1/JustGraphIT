function Send-IntuneReportToTeams {
    <#
    .SYNOPSIS
        Push a report (any array of objects) to a Microsoft Teams channel as an
        Adaptive Card, via a Power Automate "Workflows" incoming webhook.

    .DESCRIPTION
        Turns the piped objects into an Adaptive Card (a titled table) and POSTs it to
        a Teams incoming-webhook URL. This is the supported successor to the retired
        Office 365 connector webhooks — the webhook needs no auth beyond its secret
        URL, so the same call works interactively or unattended from a runbook /
        scheduled task (pair it with Connect-IntuneTide app-only auth).

        Create the webhook in Teams: channel ··· → Workflows → "Post to a channel when
        a webhook request is received" → copy the HTTP POST URL.

    .PARAMETER InputObject
        The report rows (pipe a cmdlet's output straight in).

    .PARAMETER Title
        Card heading, e.g. "Non-compliant devices".

    .PARAMETER WebhookUrl
        The Workflows incoming-webhook URL. Defaults to $env:TIDE_TEAMS_WEBHOOK so it
        can be supplied from a runbook variable / Key Vault without hard-coding.

    .PARAMETER Summary
        Optional sub-heading line under the title.

    .PARAMETER Column
        Restrict/order the columns shown (defaults to the first row's properties).

    .PARAMETER MaxRows
        Cap the rows rendered in the card (default 15); the rest are summarised as
        "… and N more".

    .PARAMETER PassThru
        Return the message JSON instead of posting — for preview or piping elsewhere.

    .EXAMPLE
        Get-IntuneComplianceStatus | Where-Object State -eq noncompliant |
            Send-IntuneReportToTeams -Title 'Non-compliant devices' -WebhookUrl $url

    .EXAMPLE
        Get-IntuneCloudPCReport -Report TotalUsage |
            Send-IntuneReportToTeams -Title 'Cloud PC usage' -PassThru   # preview the card JSON

    .OUTPUTS
        None by default; the webhook response, or (with -PassThru) the message JSON string.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]$InputObject,
        [Parameter(Mandatory)][string]$Title,
        [string]$WebhookUrl = $env:TIDE_TEAMS_WEBHOOK,
        [string]$Summary,
        [string[]]$Column,
        [ValidateRange(1, 60)][int]$MaxRows = 15,
        [switch]$PassThru
    )
    begin { $rows = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($o in $InputObject) { if ($null -ne $o) { [void]$rows.Add($o) } } }
    end {
        $card    = New-IaAdaptiveCard -Title $Title -Summary $Summary -Rows $rows.ToArray() -MaxRows $MaxRows -Column $Column
        $message = New-IaTeamsMessage -Card $card
        $json    = $message | ConvertTo-Json -Depth 40

        if ($PassThru) { return $json }
        if ([string]::IsNullOrWhiteSpace($WebhookUrl)) {
            throw "No Teams webhook URL. Pass -WebhookUrl or set `$env:TIDE_TEAMS_WEBHOOK to a Power Automate 'Workflows' incoming-webhook URL."
        }
        if ($PSCmdlet.ShouldProcess($WebhookUrl, "POST Adaptive Card '$Title' ($($rows.Count) row(s))")) {
            Invoke-IaWebhookPost -Uri $WebhookUrl -Json $json
        }
    }
}
