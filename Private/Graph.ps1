# Microsoft Graph access layer. Every Graph call funnels through Invoke-IaRequest
# so the whole module is unit-testable: Pester mocks Invoke-IaRequest and the
# higher-level helpers (paging, count, assign) come along for free.

# The module standardizes on the BETA endpoint everywhere — it exposes the richer
# data set (extra properties, newer resource types) the TUI relies on. The -V1
# switch on Resolve-IaUri / Get-IaCollection is kept for call-site compatibility but
# now also resolves to beta; flip $script:IaGraphV1 back to /v1.0 if you ever need it.
$script:IaGraphBase = 'https://graph.microsoft.com/beta'
$script:IaGraphV1   = 'https://graph.microsoft.com/beta'

# ---- live call log: every Graph call is recorded here (a ring buffer) so the
# TUI can show a "graph calls" pane and Get-IntuneCallLog can replay it.
$script:IaCallLog     = [System.Collections.Generic.List[object]]::new()
$script:IaCallLogCap  = 1000
$script:IaCallLogOn   = $true
$script:IaCallSink    = $null   # optional scriptblock invoked per call (TUI live stream)

function Add-IaCall {
    param([string]$Method, [string]$Uri, [int]$Status, [double]$Ms, [int]$Count, [string]$ErrorText)
    if (-not $script:IaCallLogOn) { return }
    $short = $Uri -replace '^https://graph\.microsoft\.com', '' -replace '\?.*$', '?…'
    $full  = $Uri -replace '^https://graph\.microsoft\.com', ''   # host-stripped, query KEPT (copy-paste)
    $entry = [pscustomobject]@{
        Time = (Get-Date); Method = $Method; Uri = $short; Full = $full
        Status = $Status; Ms = [math]::Round($Ms); Count = $Count; Error = $ErrorText
    }
    $script:IaCallLog.Add($entry)
    if ($script:IaCallLog.Count -gt $script:IaCallLogCap) { $script:IaCallLog.RemoveAt(0) }
    if ($script:IaCallSink) { try { & $script:IaCallSink $entry } catch { } }
}

function Get-IaCallLogEntries { , @($script:IaCallLog.ToArray()) }
function Clear-IaCallLog { $script:IaCallLog.Clear() }
function Set-IaCallSink { param([scriptblock]$Sink) $script:IaCallSink = $Sink }

function Resolve-IaUri {
    param([Parameter(Mandatory)][string]$Path, [switch]$V1)
    if ($Path -match '^https?://') { return $Path }
    $base = if ($V1) { $script:IaGraphV1 } else { $script:IaGraphBase }
    "$base/$($Path.TrimStart('/'))"
}

function ConvertTo-IaODataValue {
    # Make a user value safe inside an OData string literal in a URL query. Two
    # escapings, in order: double single-quotes (OData), then percent-encode (URL).
    # So O'Brien → O''Brien → O%27%27Brien, which Graph URL-decodes to O''Brien and
    # OData reads as O'Brien. Use as: "displayName eq '$(ConvertTo-IaODataValue $x)'".
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    [uri]::EscapeDataString($Value.Replace("'", "''"))
}

# ---- transient-failure handling: Graph throttles (429) and occasionally returns
# 503/504; every call honors Retry-After and retries with exponential backoff so the
# TUI doesn't die mid-page on a busy tenant.
$script:IaMaxRetry    = 4       # transient retries before giving up
$script:IaRetryBaseMs = 1000    # backoff base when the server sends no Retry-After
$script:IaMgFeatures  = $null   # cached Invoke-MgGraphRequest capability probe

function Get-IaMgFeatures {
    # Probe optional Invoke-MgGraphRequest params once. Modern SDKs expose
    # -StatusCodeVariable (real status on success); older ones don't, so we fall back.
    if ($null -ne $script:IaMgFeatures) { return $script:IaMgFeatures }
    $f = [pscustomobject]@{ StatusCode = $false }
    try { $f.StatusCode = (Get-Command Invoke-MgGraphRequest -ErrorAction Stop).Parameters.ContainsKey('StatusCodeVariable') } catch { }
    $script:IaMgFeatures = $f
    $f
}

function Get-IaErrorStatus {
    # Best-effort HTTP status from a Graph error record — the SDK surfaces it in
    # different shapes across versions, so probe several then fall back to the text.
    param($ErrorRecord)
    $ex = $ErrorRecord.Exception
    foreach ($probe in @({ [int]$ex.Response.StatusCode }, { [int]$ex.StatusCode }, { [int]$ex.Response.StatusCode.value__ })) {
        try { $v = & $probe; if ($v -ge 100 -and $v -lt 600) { return $v } } catch { }
    }
    $msg = "$($ErrorRecord.Exception.Message) $($ErrorRecord.ErrorDetails.Message)"
    if ($msg -match 'Too Many Requests')                       { return 429 }
    if ($msg -match '\b(429|503|504|500|404|403|401|400)\b')   { return [int]$Matches[1] }
    return 0
}

function Test-IaRetryable {
    # 429 (throttled) is always safe to retry — the request was rejected before it
    # ran. 503/504 are retried on idempotent verbs, but NOT on POST: a 504 can fire
    # after the backend already created the object, so retrying a POST risks a
    # duplicate. 500 is retried on GET only (a write may have partially applied).
    param([int]$Status, [string]$Method)
    if ($Status -eq 429) { return $true }
    if ($Status -in 503, 504 -and $Method -ne 'POST') { return $true }
    if ($Status -eq 500 -and $Method -eq 'GET') { return $true }
    $false
}

function Get-IaRetryDelayMs {
    # Wait before the next attempt: honor the server's Retry-After header if present,
    # else exponential backoff (base·2^(n-1), capped at 30s) with a little jitter.
    param($ErrorRecord, [int]$Attempt)
    try {
        $ra = $ErrorRecord.Exception.Response.Headers.RetryAfter
        if ($ra) {
            if ($null -ne $ra.Delta) { return [int][math]::Max(0, $ra.Delta.TotalMilliseconds) }
            if ($null -ne $ra.Date)  { return [int][math]::Max(0, ($ra.Date - (Get-Date)).TotalMilliseconds) }
        }
    } catch { }
    $backoff = [math]::Min($script:IaRetryBaseMs * [math]::Pow(2, $Attempt - 1), 30000)
    [int]($backoff + (Get-Random -Minimum 0 -Maximum 250))
}

function Invoke-IaRequest {
    # The single seam over Microsoft.Graph's Invoke-MgGraphRequest. Returns the
    # response as a PSObject (so .value / '@odata.nextLink' are property access).
    # Retries throttled/transient failures honoring Retry-After.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [object]$Body,
        [hashtable]$Headers
    )
    $params = @{ Method = $Method; Uri = $Uri; OutputType = 'PSObject'; ErrorAction = 'Stop' }
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 30 -Compress)
        $params.ContentType = 'application/json'
    }
    if ($Headers) { $params.Headers = $Headers }
    if ((Get-IaMgFeatures).StatusCode) { $params.StatusCodeVariable = 'IaStatus' }

    $max = $script:IaMaxRetry
    $attempt = 0
    while ($true) {
        $attempt++
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $IaStatus = $null
            $resp = Invoke-MgGraphRequest @params
            $sw.Stop()
            $status = if ($IaStatus) { [int]$IaStatus } else { 200 }
            $count  = if ($resp -and $resp.PSObject.Properties['value']) { @($resp.value).Count } else { 0 }
            Add-IaCall -Method $Method -Uri $Uri -Status $status -Ms $sw.Elapsed.TotalMilliseconds -Count $count
            return $resp
        } catch {
            $sw.Stop()
            $status = Get-IaErrorStatus $_
            if ((Test-IaRetryable -Status $status -Method $Method) -and $attempt -le $max) {
                $delay = Get-IaRetryDelayMs -ErrorRecord $_ -Attempt $attempt
                Add-IaCall -Method $Method -Uri $Uri -Status $status -Ms $sw.Elapsed.TotalMilliseconds -Count 0 -ErrorText "transient $status — retry $attempt/$max in $([int]$delay)ms"
                Start-Sleep -Milliseconds $delay
                continue
            }
            Add-IaCall -Method $Method -Uri $Uri -Status $status -Ms $sw.Elapsed.TotalMilliseconds -Count 0 -ErrorText $_.Exception.Message
            throw
        }
    }
}

function Get-IaCollection {
    # GET a collection, following @odata.nextLink to completion. -ConsistencyLevel sets
    # the 'eventual' header advanced directory queries need ($count=true, not/ne/endsWith,
    # filter on extensionAttributes, $search, $orderby+$filter).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [switch]$V1, [switch]$ConsistencyLevel)
    $items = [System.Collections.Generic.List[object]]::new()
    $uri = Resolve-IaUri -Path $Path -V1:$V1
    $headers = if ($ConsistencyLevel) { @{ ConsistencyLevel = 'eventual' } } else { $null }
    while ($uri) {
        $resp = if ($headers) { Invoke-IaRequest -Method GET -Uri $uri -Headers $headers } else { Invoke-IaRequest -Method GET -Uri $uri }
        if ($resp.value) { foreach ($v in $resp.value) { [void]$items.Add($v) } }
        $uri = $resp.'@odata.nextLink'
    }
    # Emit the collection normally (no leading unary comma). A `, $arr` return keeps an
    # assignment like `$x = Get-IaCollection` intact, but it forces the function to emit the
    # WHOLE collection as a single pipeline object — so `@(Get-IaCollection …)`,
    # `Get-IaCollection … | ForEach-Object { … }` and `… | Where/Select` all collapse to one
    # element (a count-1 table whose cells are the values concatenated). Those wrap/pipe forms
    # are the dominant idiom across the module, so we emit element-by-element and let the
    # pipeline enumerate. Assignment-then-foreach consumers still work in PowerShell 7, where
    # both $null and a scalar answer .Count and `foreach` correctly.
    $items.ToArray()
}

function Get-IaCount {
    # $count endpoint (requires the advanced-query ConsistencyLevel header).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [switch]$V1)
    try {
        $uri = Resolve-IaUri -Path $Path -V1:$V1
        $r = Invoke-IaRequest -Method GET -Uri $uri -Headers @{ ConsistencyLevel = 'eventual' }
        return [int]$r
    } catch { return -1 }  # unknown (e.g. no permission) — caller must not treat as empty
}

function Invoke-IaAssign {
    # POST the /assign action. The action replaces the whole assignment set, so
    # callers always read-merge-write the complete list.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ListPath,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][hashtable]$Body
    )
    $uri = Resolve-IaUri -Path "$ListPath/$Id/assign"
    Invoke-IaRequest -Method POST -Uri $uri -Body $Body | Out-Null
}
