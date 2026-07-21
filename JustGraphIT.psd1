@{
    RootModule        = 'JustGraphIT.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b7e4a2c1-9f3d-4e6a-8c2b-1a5d7e9f0c34'
    Author            = 'Aaron Amaya'
    CompanyName       = 'Aaron Amaya'
    Copyright         = '(c) 2026 Aaron Amaya. Released under the MIT License.'
    Description       = 'Cross-platform PowerShell 7 module and terminal UI to inspect, manage and report on Microsoft Intune and Entra ID (Azure AD) via Microsoft Graph — assignments, devices, identities, app consent, roles and Conditional Access — with CSV / Excel / HTML / Teams output. Rendered by a self-contained ANSI engine (no external TUI dependency).'
    PowerShellVersion = '7.2'

    # Not hard-required so the module imports cleanly; cmdlets check at runtime
    # and give actionable install hints:
    #   Microsoft.Graph.Authentication  (all cmdlets)
    # The interactive TUI (Start-JustGraphIT) renders via the built-in ANSI engine
    # in Private/Tui.ps1 — there is NO external terminal-UI dependency.

    FunctionsToExport = @(
        'Connect-JustGraphIT',
        'Get-IntuneAssignment',
        'Get-IntuneGroupAssignment',
        'Compare-IntuneAssignment',
        'Get-IntuneEffectiveAssignment',
        'Copy-IntuneAssignment',
        'Add-IntuneBulkAssignment',
        'Export-IntuneAssignmentTemplate',
        'Import-IntuneAssignmentTemplate',
        'Get-IntuneAssignmentAudit',
        'Export-IntuneAssignmentReport',
        'Export-IntuneExcel',
        'Export-IntuneHtmlReport',
        # --- backup / restore / drift ---
        'Backup-IntuneAssignment',
        'Restore-IntuneAssignment',
        'Get-IntuneAssignmentDrift',
        'Backup-IntuneConfig',
        'Restore-IntuneConfig',
        # --- reporting & auditing ---
        'Get-IntuneReportCatalog',
        'Export-IntuneReport',
        'Get-IntuneAppInstallStatus',
        'Get-IntuneConfigurationStatus',
        'Get-IntuneComplianceStatus',
        'Get-IntuneDeploymentSummary',
        'Get-IntuneAuditLog',
        'Get-IntuneApprovalRequest',
        'Get-IntunePatchReport',
        # --- device reporting ---
        'Get-IntuneDeviceInventory',
        'Get-IntuneTenantSummary',
        # --- PIM (privileged role elevation) ---
        'Get-IntuneEligibleRole',
        'Enable-IntuneAdminRole',
        'Get-IntuneActiveRole',
        'Get-IntunePimActivation',
        # --- diagnostics ---
        'Get-IntuneCallLog',
        'Invoke-IntuneHealthCheck',
        'Export-IntuneChangeLog',
        'Clear-IntuneCallLog',
        # --- Teams push ---
        # --- device actions & detail ---
        'Invoke-IntuneDeviceAction',
        'Get-IntuneDeviceDetail',
        'Get-IntuneDiscoveredApp',
        'Sync-IntuneDiscoveredAppGroup',
        'Get-IntuneConnectorHealth',
        'Get-IntuneBitLockerEscrowGap',
        'Get-EntraMfaRegistration',
        'Get-TenantConfigMonitor',
        'Get-TenantConfigDrift',
        'Get-TenantConfigMonitorResult',
        'Export-IntuneHealthReport',
        'Get-IntuneStaleDevice',
        'Get-IntuneDeviceCategory',
        'Set-IntuneDevicePrimaryUser',
        'Set-IntuneDeviceCategory',
        'Get-IntuneBitLockerKey',
        'Get-IntuneLapsCredential',
        'Get-IntuneDeviceGroupMembership',
        'Get-IntuneDeviceManagedApp',
        'Get-IntuneDeviceComplianceDetail',
        'Get-IntuneDeviceConfigConflict',
        'Get-IntuneUserDevice',
        'Get-IntuneUserGroupMembership',
        'Get-IntuneUserLicense',
        'Get-IntuneUserSignIn',
        'Get-IntuneUserAuthMethod',
        # --- Windows 365 Cloud PC ---
        'Get-IntuneCloudPC',
        'Invoke-IntuneCloudPCAction',
        'Get-IntuneCloudPCProvisioningPolicy',
        'New-IntuneCloudPCProvisioningPolicy',
        'Set-IntuneCloudPCProvisioningPolicy',
        'Remove-IntuneCloudPCProvisioningPolicy',
        'Get-IntuneCloudPCConnection',
        'Test-IntuneCloudPCConnection',
        'Get-IntuneCloudPCImage',
        'Get-IntuneCloudPCServicePlan',
        'Get-IntuneCloudPCSnapshot',
        'Get-IntuneCloudPCReport',
        'Get-IntuneCloudPCUserSetting',
        # --- settings catalog (configurationPolicies) ---
        'Get-IntuneConfigurationPolicy',
        'New-IntuneConfigurationPolicy',
        'Set-IntuneConfigurationPolicy',
        'Remove-IntuneConfigurationPolicy',
        'Copy-IntuneConfigurationPolicy',
        # --- compliance policies ---
        'Get-IntuneCompliancePolicy',
        'New-IntuneCompliancePolicy',
        'Remove-IntuneCompliancePolicy',
        # --- scripts (Windows PowerShell + macOS shell) ---
        'Get-IntuneScript',
        'New-IntuneScript',
        'Remove-IntuneScript',
        # --- remediations (device health scripts) ---
        'Get-IntuneRemediation',
        'New-IntuneRemediation',
        'Remove-IntuneRemediation',
        'Invoke-IntuneRemediation',
        # --- apps (Win32, Store, LOB, VPP, iOS, Android, macOS) ---
        'Get-IntuneApp',
        'Get-IntuneWin32App',
        'Set-IntuneAppAssignment',
        'Remove-IntuneApp',
        # --- Windows Update (rings, feature, driver) ---
        'Get-IntuneUpdateRing',
        'New-IntuneUpdateRing',
        'Remove-IntuneUpdateRing',
        'Get-IntuneFeatureUpdate',
        'New-IntuneFeatureUpdate',
        'Get-IntuneDriverUpdate',
        # --- assignment filters ---
        'Get-IntuneAssignmentFilter',
        'New-IntuneAssignmentFilter',
        'Remove-IntuneAssignmentFilter',
        # --- RBAC ---
        'Get-IntuneRbacRole',
        'Get-IntuneRbacAssignment',
        # --- Autopilot & enrollment ---
        'Get-IntuneAutopilotDevice',
        'Set-IntuneAutopilotDevice',
        'Get-IntuneAutopilotProfile',
        'Get-IntuneEnrollmentRestriction',
        'Get-IntuneESP',
        # --- legacy device configurations ---
        'Get-IntuneDeviceConfiguration',
        'Remove-IntuneDeviceConfiguration',
        # --- administrative templates (ADMX) ---
        'Get-IntuneAdminTemplate',
        # --- endpoint security baselines & templates ---
        'Get-IntuneSecurityBaseline',
        'New-IntuneSecurityBaseline',
        'Get-IntuneSecurityTemplate',
        # --- monitoring ---
        'Watch-IntuneTenant',
        # --- conditional access ---
        'Get-IntuneConditionalAccess',
        # --- app protection (MAM) ---
        'Get-IntuneAppProtectionPolicy',
        # --- administrative templates (ADMX) CRUD ---
        'New-IntuneAdminTemplate',
        'Remove-IntuneAdminTemplate',
        # --- Windows Update (remove operations) ---
        'Remove-IntuneFeatureUpdate',
        'Remove-IntuneDriverUpdate',
        'Set-IntuneUpdateRing',
        # ====================== Entra (Azure AD) ======================
        # --- users (Phase 2: actionable) ---
        'Get-EntraUser',
        'Set-EntraUser',
        'Reset-EntraUserPassword',
        'Revoke-EntraUserSession',
        'Add-EntraUserToGroup',
        'Remove-EntraUserFromGroup',
        'Set-EntraUserLicense',
        'Get-EntraUserAuthMethod',
        'Reset-EntraUserMfa',
        'New-EntraUserTempAccessPass',
        'New-EntraUser',
        'Get-EntraUserManager',
        'Remove-EntraUserManager',
        'Get-EntraInactiveUser',
        'Get-EntraGuestUser',
        # --- licensing ---
        'Get-EntraLicense',
        # --- groups (Phase 3: lifecycle) ---
        'Get-EntraGroup',
        'Get-EntraGroupMember',
        'Get-EntraGroupOwner',
        'New-EntraGroup',
        'Set-EntraGroup',
        'Add-EntraGroupMember',
        'Add-EntraGroupMemberBulk',
        'Remove-EntraGroupMember',
        'Add-EntraGroupOwner',
        'Remove-EntraGroupOwner',
        'Set-EntraGroupLicense',
        'Remove-EntraGroup',
        # --- access & sign-ins (Phase 5) ---
        'Get-EntraSignIn',
        'Get-EntraConditionalAccessPolicy',
        'Set-EntraConditionalAccessState',
        'New-EntraConditionalAccessPolicy',
        'Set-EntraConditionalAccessPolicy',
        'Remove-EntraConditionalAccessPolicy',
        'Get-EntraNamedLocation',
        'New-EntraNamedLocation',
        'Remove-EntraNamedLocation',
        'Get-EntraRiskyUser',
        'Get-EntraRiskDetection',
        'Set-EntraRiskyUser',
        # --- applications & identities (Phase 4) ---
        'Get-EntraAppRegistration',
        'Get-EntraAppCredential',
        'Get-EntraEnterpriseApp',
        'Get-EntraManagedIdentity',
        'Get-EntraAppPermission',
        'Get-EntraRiskyAppPermission',
        'Remove-EntraAppRoleAssignment',
        'Remove-EntraOAuth2Grant',
        # --- app-registration & provisioning writes (Phase 1: do-it-from-the-CLI) ---
        'Get-EntraAppRequestedPermission',
        'Add-EntraAppPermission',
        'Remove-EntraAppPermission',
        'New-EntraServicePrincipal',
        'Grant-EntraAdminConsent',
        'New-EntraGuestInvitation',
        'New-EntraTeam',
        # --- Teams depth (Phase 5) ---
        'Get-EntraTeamChannel',
        'New-EntraTeamChannel',
        'Remove-EntraTeamChannel',
        'Get-EntraTeamMember',
        'Add-EntraTeamMember',
        'Remove-EntraTeamMember',
        # --- app-registration lifecycle (Phase 2) ---
        'New-EntraAppRegistration',
        'Set-EntraAppRegistration',
        'Remove-EntraAppRegistration',
        'New-EntraAppSecret',
        'Add-EntraAppRedirectUri',
        'Remove-EntraAppRedirectUri',
        'Get-EntraAppOwner',
        'Add-EntraAppOwner',
        'Remove-EntraAppOwner',
        # --- app governance / hygiene reports ---
        'Get-EntraExpiringSecret',
        'Get-EntraAppWithoutOwner',
        'Get-EntraAppCredentialSummary',
        # --- devices blade (Entra device objects) ---
        'Get-EntraDevice',
        'Set-EntraDevice',
        'Remove-EntraDevice',
        'Get-EntraDeviceRegisteredOwner',
        # --- tenant settings & properties blade ---
        'Get-EntraAuthorizationPolicy',
        'Set-EntraAuthorizationPolicy',
        'Get-EntraSecurityDefault',
        'Set-EntraSecurityDefault',
        # --- custom roles (unified RBAC role definitions) ---
        'Get-EntraRoleDefinition',
        'Get-EntraRoleAction',
        'New-EntraRoleDefinition',
        'Set-EntraRoleDefinition',
        'Remove-EntraRoleDefinition',
        # --- directory recycle bin (soft-deleted users/groups/apps) ---
        'Get-EntraDeletedItem',
        'Restore-EntraDeletedItem',
        'Remove-EntraDeletedItem',
        # --- device recovery secrets (BitLocker / Windows LAPS) ---
        'Get-EntraBitLockerKey',
        'Get-EntraLapsCredential',
        # --- per-user authentication (MFA state, phone methods) ---
        'Get-EntraUserMfaState',
        'Set-EntraUserMfaState',
        'Add-EntraUserPhoneMethod',
        # --- directory roles & PIM ---
        'Get-EntraDirectoryRole',
        'Get-EntraRoleAssignment',
        'Get-EntraPimEligibility',
        'Get-EntraPimActive',
        # --- role & PIM writes (Phase 3) ---
        'New-EntraRoleAssignment',
        'Remove-EntraRoleAssignment',
        'New-EntraPimEligibility',
        'Remove-EntraPimEligibility',
        'Enable-EntraPimRole',
        # --- security / XDR ---
        'Get-EntraSecureScore',
        'Get-EntraSecurityAlert',
        'Get-EntraSecurityIncident',
        # --- usage & quota reports (M365) ---
        'Get-EntraMailboxUsage',
        'Get-EntraOneDriveUsage',
        'Get-EntraSharePointUsage',
        'Get-EntraTeamsUsage',
        'Get-EntraM365AppUsage',
        'Start-JustGraphIT'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('jgi', 'jgit')

    PrivateData = @{
        PSData = @{
            Tags         = @('Intune', 'Entra', 'EntraID', 'AzureAD', 'MicrosoftGraph', 'MEM', 'Endpoint', 'Assignments', 'CloudPC', 'TUI', 'PowerShell7', 'CrossPlatform')
            ProjectUri   = 'https://github.com/ajamaya1/JustGraphIT'
            LicenseUri   = 'https://github.com/ajamaya1/JustGraphIT/blob/main/LICENSE'
            ReleaseNotes = 'v1.0.0 — first public release. Read AND write across Microsoft Intune and Entra ID from a cross-platform terminal UI: assignment inspect / compare / mirror, device and identity management, app-consent audit and revoke, custom roles, Conditional Access, deleted-item restore, and BitLocker / LAPS recovery. Self-contained ANSI engine (no external TUI dependency); CSV / Excel / JSON / HTML export and Teams push; secret-bearing views are export-disabled. 327 offline tests.'
        }
    }
}
