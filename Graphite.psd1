@{
    RootModule        = 'Graphite.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b7e4a2c1-9f3d-4e6a-8c2b-1a5d7e9f0c34'
    Author            = 'Aaron'
    Description       = 'GRAPHITE (Microsoft Intune & Entra management) — inspect, manage and report on Microsoft Intune assignments across every assignable area: list/reverse-lookup/compare/what-if, copy & selectively mirror, bulk-assign, templates, audit, deployment/install/compliance reporting, HTML report, and an interactive Deep Sea terminal UI rendered by a self-contained ANSI engine (no external TUI dependency). Cross-platform (macOS/Windows/Linux) via the Microsoft Graph PowerShell SDK.'
    PowerShellVersion = '7.2'

    # Not hard-required so the module imports cleanly; cmdlets check at runtime
    # and give actionable install hints:
    #   Microsoft.Graph.Authentication  (all cmdlets)
    # The interactive TUI (Start-Graphite) renders via the built-in ANSI engine
    # in Private/Tui.ps1 — there is NO external terminal-UI dependency.

    FunctionsToExport = @(
        'Connect-Graphite',
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
        'Clear-IntuneCallLog',
        # --- Teams push ---
        'Send-IntuneReportToTeams',
        # --- device actions & detail ---
        'Invoke-IntuneDeviceAction',
        'Get-IntuneDeviceDetail',
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
        'Start-Graphite'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('graphite', 'tide')

    PrivateData = @{
        PSData = @{
            Tags       = @('Intune', 'MicrosoftGraph', 'MEM', 'Assignments', 'Endpoint', 'TUI', 'ANSI')
            ProjectUri = 'https://github.com/ajamaya1/IntuneTide'
            LicenseUri = 'https://github.com/ajamaya1/IntuneTide/blob/main/LICENSE'
        }
    }
}
