function Connect-JustGraphIT {
    <#
    .SYNOPSIS
        Sign in to Microsoft Graph for Intune assignment management.
    .DESCRIPTION
        Wraps Connect-MgGraph. Supports interactive sign-in, device code
        (great over SSH / for headless Macs), and app-only auth with a client
        secret or certificate. Runs anywhere pwsh + Microsoft.Graph.Authentication
        run (macOS, Windows, Linux).
    .EXAMPLE
        Connect-JustGraphIT -UseDeviceCode
    .EXAMPLE
        Connect-JustGraphIT -TenantId contoso.com -ClientId <id> -ClientSecret <secret>
    #>
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param(
        [string]$TenantId,
        [Parameter(ParameterSetName = 'Interactive')]
        [switch]$UseDeviceCode,
        [Parameter(ParameterSetName = 'Secret', Mandatory)]
        [string]$ClientId,
        [Parameter(ParameterSetName = 'Secret', Mandatory)]
        [string]$ClientSecret,
        [Parameter(ParameterSetName = 'Certificate', Mandatory)]
        [string]$CertClientId,
        [Parameter(ParameterSetName = 'Certificate', Mandatory)]
        [string]$CertificateThumbprint,
        [string[]]$Scopes = @(
            'DeviceManagementConfiguration.ReadWrite.All',
            'DeviceManagementApps.ReadWrite.All',
            'DeviceManagementServiceConfig.ReadWrite.All',
            'DeviceManagementManagedDevices.Read.All',
            'CloudPC.ReadWrite.All',
            'Group.Read.All',
            'Directory.Read.All',
            'RoleManagementPolicy.Read.Directory',
            'RoleEligibilitySchedule.Read.Directory',
            'RoleAssignmentSchedule.ReadWrite.Directory',
            # --- Entra identity management (Phase 2+) ---
            'User.ReadWrite.All',
            'Group.ReadWrite.All',
            'GroupMember.ReadWrite.All',
            'UserAuthenticationMethod.ReadWrite.All',
            'Organization.Read.All',
            # --- Entra reporting / access / security ---
            'AuditLog.Read.All',
            'Policy.Read.All',
            'Policy.ReadWrite.ConditionalAccess',
            'IdentityRiskyUser.ReadWrite.All',
            'IdentityRiskEvent.Read.All',
            'Application.Read.All',
            'RoleManagement.Read.Directory',
            'SecurityEvents.Read.All',
            'Reports.Read.All',
            'ConfigurationMonitoring.Read.All'
        )
    )

    if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
        throw "Microsoft.Graph.Authentication is required. Install it with: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser"
    }

    switch ($PSCmdlet.ParameterSetName) {
        'Secret' {
            $sec = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
            $cred = [System.Management.Automation.PSCredential]::new($ClientId, $sec)
            Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $cred -NoWelcome -ErrorAction Stop
        }
        'Certificate' {
            Connect-MgGraph -TenantId $TenantId -ClientId $CertClientId -CertificateThumbprint $CertificateThumbprint -NoWelcome -ErrorAction Stop
        }
        default {
            $p = @{ Scopes = $Scopes; NoWelcome = $true; ErrorAction = 'Stop' }
            if ($TenantId) { $p.TenantId = $TenantId }
            if ($UseDeviceCode) { $p.UseDeviceCode = $true }
            Connect-MgGraph @p
        }
    }

    Reset-IaDirectoryCache
    $ctx = Get-MgContext
    [pscustomobject]@{
        TenantId = $ctx.TenantId
        Account  = $ctx.Account
        AppName  = $ctx.AppName
        Scopes   = ($ctx.Scopes -join ', ')
    }
}
