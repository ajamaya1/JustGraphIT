# ── Intune / Win32 error-code lookup ─────────────────────────────────────────
# Maps common 0x87Dxxxxx / HRESULT codes to { Short; Hint } so FAIL rows in
# deployment-summary, app-install and restore views show plain English instead
# of raw integers. Keys are uppercase 0xNNNNNNNN hex strings.

$script:IaWin32ErrorTable = [ordered]@{
    '0x87D1041A' = @{ Short = 'Installation failed';                Hint = 'Check the Intune Management Extension log (%ProgramData%\Microsoft\IntuneManagementExtension\Logs) for the installer exit code.' }
    '0x87D1041B' = @{ Short = 'Insufficient disk space';            Hint = 'Free at least 500 MB on the device and retry.' }
    '0x87D1041C' = @{ Short = 'App not detected post-install';      Hint = 'Verify detection rules match the installed product (path, registry key, or MSI product code).' }
    '0x87D1041D' = @{ Short = 'Unexpected installer exit code';     Hint = 'Add the exit code to the app''s allowed return codes list, or review the Windows application event log.' }
    '0x87D10191' = @{ Short = 'Required dependency missing';        Hint = 'Deploy required app dependencies before this app.' }
    '0x87D10195' = @{ Short = 'App superseded';                     Hint = 'Remove the superseded assignment — a newer version of this app already covers the target.' }
    '0x87D10FFF' = @{ Short = 'Installation cancelled';             Hint = 'User or security software (e.g. AV) blocked the install; check AV exclusions and whether UAC elevation is permitted.' }
    '0x87D013B5' = @{ Short = 'Download failed';                    Hint = 'Verify the device can reach the content CDN; check proxy, firewall, and connectivity to intunecdnpeasd2.azureedge.net.' }
    '0x87D00693' = @{ Short = 'Not applicable to this device';      Hint = 'The app''s requirement rules or assignment filter excludes this device; review applicability rules.' }
    '0x87D1FDE8' = @{ Short = 'Remediation script failed';          Hint = 'Check the remediation script exit code and output in the Intune Management Extension log.' }
    '0x87D1FD73' = @{ Short = 'Retry limit exceeded';               Hint = 'The device exceeded the maximum install retry count; investigate and resolve the persistent blocking condition first.' }
    '0x87D20001' = @{ Short = 'Policy not applicable';              Hint = 'The configuration policy does not apply to this device''s OS version or edition.' }
    '0x87D30002' = @{ Short = 'Configuration policy conflict';      Hint = 'Two or more overlapping profiles define the same setting differently; deduplicate or merge them.' }
    '0xC0E90002' = @{ Short = 'Setting conflict';                   Hint = 'Overlapping policies contain conflicting settings; review and consolidate assignment targets.' }
    '0x80070002' = @{ Short = 'File not found';                     Hint = 'A file or path referenced by the installer is missing; verify the deployment package contents and extraction path.' }
    '0x80070005' = @{ Short = 'Access denied';                      Hint = 'The installer requires elevated privileges; verify UAC settings and local admin requirements on the device.' }
    '0x80070070' = @{ Short = 'Not enough storage space';           Hint = 'Free disk space on the device and retry.' }
    '0x80070032' = @{ Short = 'Request not supported';              Hint = 'The operation is not supported by this OS version or edition.' }
    '0x80004005' = @{ Short = 'Unspecified error';                  Hint = 'Check the Intune Management Extension log for detailed failure information.' }
    '0x8024200B' = @{ Short = 'Windows Update: incomplete';         Hint = 'The update operation did not complete; restart the device and retry.' }
    '0x8024402C' = @{ Short = 'Windows Update: cannot connect';     Hint = 'Check network access to Windows Update endpoints; review proxy and firewall rules.' }
    '0x80180001' = @{ Short = 'Enrollment: not authorised';         Hint = 'The user account is not licensed or authorised for MDM enrollment; verify Intune license assignment.' }
    '0x80180003' = @{ Short = 'Enrollment: already enrolled';       Hint = 'The device is already enrolled; check for duplicate enrollment and retire/wipe if needed.' }
    '0x80040154' = @{ Short = 'COM component not registered';       Hint = 'A COM dependency is missing; the device may need a reboot or a prerequisite software install.' }
}

# installStateDetail string → friendly label (Graph returns camelCase strings)
$script:IaInstallDetailTable = @{
    'installFailed'                     = 'Installation failed'
    'downloadFailed'                    = 'Download failed'
    'noContentAvailable'                = 'No content available'
    'installedTimedOut'                 = 'Timed out'
    'installedNotApplicable'            = 'Not applicable'
    'userCancelledInstallation'         = 'User cancelled'
    'superseded'                        = 'Superseded by newer version'
    'notInstalled'                      = 'Not installed'
    'installedPendingReboot'            = 'Installed — reboot pending'
    'rebootRequired'                    = 'Reboot required'
    'seeInstallErrorCode'               = 'See error code'
    'contentDownloaded'                 = 'Downloaded — install pending'
    'maintenanceWindowExpired'          = 'Maintenance window expired'
    'removeAssignment'                  = 'Assignment removed — uninstall pending'
    'dependencyFailedToInstall'         = 'Dependency failed to install'
    'dependencyWithRequirementsNotMet'  = 'Dependency requirements not met'
    'powershellScriptError'             = 'PowerShell script error'
}

function Resolve-IaErrorCode {
    # Convert a numeric Intune/Win32 error code (signed int, long, or hex string)
    # to a { Short; Hint } object, or $null for zero / unrecognised codes.
    param([object]$Code)
    if (-not $Code -or $Code -eq 0) { return $null }
    try {
        [long]$n = if ($Code -is [string] -and $Code -match '^0[xX]') {
            [Convert]::ToInt64($Code, 16)
        } else { [long]$Code }
        # Mask to 32 bits. Use decimal 4294967295 rather than 0xFFFFFFFF — the hex
        # literal is typed as signed int32 (-1) in PowerShell, which widens to
        # 0xFFFFFFFFFFFFFFFF and leaves negative longs unchanged.
        $hex = '0x{0:X8}' -f ($n -band 4294967295)
        $script:IaWin32ErrorTable[$hex]
    } catch { $null }
}

function Resolve-IaInstallDetail {
    # Convert an installStateDetail camelCase string to a friendly label.
    param([string]$Detail)
    if (-not $Detail) { return $null }
    $script:IaInstallDetailTable[$Detail] ?? $Detail   # fall back to raw if unknown
}
