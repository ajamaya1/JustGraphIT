function Watch-IntuneTenant {
    <#
    .SYNOPSIS
        Poll for compliance changes and non-compliant device alerts on a schedule.

    .DESCRIPTION
        Runs a polling loop that calls Get-IntuneTenantSummary (or
        Get-IntuneComplianceStatus -Summary equivalent) every -IntervalSeconds
        seconds. On each iteration it:

          1. Computes the current non-compliant device count.
          2. Detects newly non-compliant devices since the previous iteration.
          3. Invokes -OnNonCompliant with new non-compliant device objects when any
             are found.
          4. Invokes -OnAlert when the non-compliant percentage exceeds
             -AlertThresholdPercent.
          5. Writes a Verbose status line with timestamp and current counts.
          6. Sleeps for -IntervalSeconds.

        The loop runs indefinitely (Ctrl+C to stop) unless -MaxIterations is set
        to a positive value, in which case it exits after that many cycles.

        Use -AsJob to run the poller in a PowerShell background job so your shell
        remains interactive.

    .PARAMETER IntervalSeconds
        How many seconds to wait between compliance polls. Default: 300 (5 minutes).

    .PARAMETER MaxIterations
        Stop automatically after this many iterations. 0 (default) = run forever
        until Ctrl+C.

    .PARAMETER OnNonCompliant
        Scriptblock invoked whenever new non-compliant devices are detected since
        the previous iteration. Receives an array of PSCustomObjects describing the
        non-compliant devices as the first argument ($args[0]).

    .PARAMETER OnAlert
        Scriptblock invoked whenever the percentage of non-compliant devices exceeds
        -AlertThresholdPercent. Receives the summary PSCustomObject as $args[0] and
        the current non-compliant percentage as $args[1].

    .PARAMETER AlertThresholdPercent
        Non-compliant percentage that triggers the -OnAlert callback. Default: 20.

    .PARAMETER AsJob
        Run the polling loop as a PowerShell background job. Returns the job object
        so you can receive output with Receive-Job later.

    .EXAMPLE
        Watch-IntuneTenant -Verbose

        Polls every 5 minutes, writing status to the verbose stream.

    .EXAMPLE
        Watch-IntuneTenant -IntervalSeconds 60 -MaxIterations 10

        Runs 10 compliance checks 60 seconds apart, then exits.

    .EXAMPLE
        # Alert via Slack webhook when non-compliant % exceeds 15
        $slackWebhook = 'https://hooks.slack.com/services/T00/B00/XXXX'

        $alertCallback = {
            param($Summary, $Percent)
            $payload = @{
                text = ":warning: Intune compliance alert: $Percent% non-compliant " +
                       "($($Summary.NonCompliantCount) of $($Summary.DeviceCount) devices)"
            } | ConvertTo-Json
            Invoke-RestMethod -Uri $using:slackWebhook -Method POST `
                -ContentType 'application/json' -Body $payload
        }

        $nonCompliantCallback = {
            param($Devices)
            Write-Host "New non-compliant devices: $($Devices.Count)"
            $Devices | Format-Table DeviceName, UserPrincipalName, ComplianceState
        }

        Watch-IntuneTenant -AlertThresholdPercent 15 `
            -OnAlert $alertCallback `
            -OnNonCompliant $nonCompliantCallback

    .EXAMPLE
        $job = Watch-IntuneTenant -IntervalSeconds 120 -AsJob
        # ... do other work ...
        Receive-Job $job
        Stop-Job $job

        Runs the watcher in a background job.

    .OUTPUTS
        Nothing when running in the foreground (callbacks receive data).
        System.Management.Automation.Job when -AsJob is used.

    .NOTES
        The -OnNonCompliant callback receives newly non-compliant devices detected
        between iterations. On the very first poll all currently non-compliant
        devices are treated as "new" to give an accurate baseline snapshot.

        This function requires the same permissions as Get-IntuneTenantSummary and
        Get-IntuneComplianceStatus.
    #>
    [CmdletBinding()]
    param(
        [int]$IntervalSeconds = 300,

        [int]$MaxIterations = 0,

        [scriptblock]$OnNonCompliant,

        [scriptblock]$OnAlert,

        [int]$AlertThresholdPercent = 20,

        [switch]$AsJob
    )

    # Build the polling scriptblock; used both inline and inside Start-Job
    $pollerBlock = {
        param(
            [int]$IntervalSeconds,
            [int]$MaxIterations,
            [scriptblock]$OnNonCompliant,
            [scriptblock]$OnAlert,
            [int]$AlertThresholdPercent
        )

        $iteration        = 0
        $previousIds      = $null   # set of non-compliant device ids seen last cycle

        while ($true) {
            $iteration++
            $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

            try {
                # ---- pull current compliance summary --------------------------
                $summary = Get-IntuneTenantSummary

                $totalDevices       = ConvertTo-IaSafeInt $summary.DeviceCount 0
                $nonCompliantCount  = ConvertTo-IaSafeInt $summary.NonCompliantCount 0
                $nonCompliantPct    = if ($totalDevices -gt 0) {
                    [math]::Round(($nonCompliantCount / $totalDevices) * 100, 1)
                } else { 0 }

                Write-Verbose "[$ts] Iteration $iteration — Total: $totalDevices | NonCompliant: $nonCompliantCount ($nonCompliantPct%) | Threshold: $AlertThresholdPercent%"

                # ---- detect newly non-compliant devices -----------------------
                if ($OnNonCompliant) {
                    $currentNonCompliant = @(
                        Get-IntuneDeviceInventory -ComplianceState noncompliant 2>$null |
                            Select-Object -Property * -ErrorAction SilentlyContinue
                    )
                    $currentIds = [System.Collections.Generic.HashSet[string]]::new(
                        @($currentNonCompliant | ForEach-Object { $_.Device ?? $_.Id })
                    )

                    if ($null -eq $previousIds) {
                        # First iteration — treat all non-compliant devices as new
                        $newDevices = $currentNonCompliant
                    } else {
                        $newDevices = @($currentNonCompliant | Where-Object {
                            $key = $_.Device ?? $_.Id
                            -not $previousIds.Contains($key)
                        })
                    }

                    $previousIds = $currentIds

                    if ($newDevices.Count -gt 0) {
                        Write-Verbose "[$ts] $($newDevices.Count) newly non-compliant device(s) detected."
                        try { & $OnNonCompliant $newDevices } catch { Write-Warning "OnNonCompliant callback error: $_" }
                    }
                }

                # ---- threshold alert ------------------------------------------
                if ($OnAlert -and $nonCompliantPct -gt $AlertThresholdPercent) {
                    Write-Verbose "[$ts] Non-compliant % ($nonCompliantPct) exceeds threshold ($AlertThresholdPercent). Invoking OnAlert."
                    try { & $OnAlert $summary $nonCompliantPct } catch { Write-Warning "OnAlert callback error: $_" }
                }

            } catch {
                Write-Warning "[$ts] Error during compliance poll (iteration $iteration): $_"
            }

            # ---- stop condition ----------------------------------------------
            if ($MaxIterations -gt 0 -and $iteration -ge $MaxIterations) {
                Write-Verbose "[$ts] Reached MaxIterations ($MaxIterations). Stopping."
                break
            }

            Start-Sleep -Seconds $IntervalSeconds
        }
    }

    if ($AsJob) {
        $jobParams = @{
            ScriptBlock  = $pollerBlock
            ArgumentList = @(
                $IntervalSeconds,
                $MaxIterations,
                $OnNonCompliant,
                $OnAlert,
                $AlertThresholdPercent
            )
        }
        $job = Start-Job @jobParams
        Write-Verbose "Watch-IntuneTenant started as background job Id $($job.Id)."
        return $job
    }

    # Foreground: invoke directly so Verbose flows to the caller's stream
    & $pollerBlock `
        -IntervalSeconds $IntervalSeconds `
        -MaxIterations $MaxIterations `
        -OnNonCompliant $OnNonCompliant `
        -OnAlert $OnAlert `
        -AlertThresholdPercent $AlertThresholdPercent
}
