@{
    RootModule        = 'IntuneTide.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b7e4a2c1-9f3d-4e6a-8c2b-1a5d7e9f0c34'
    Author            = 'Aaron'
    Description       = 'TIDE (Targeted Intune Deployment & Endpoints) — inspect, manage and report on Microsoft Intune assignments across every assignable area: list/reverse-lookup/compare/what-if, copy & selectively mirror, bulk-assign, templates, audit, deployment/install/compliance reporting, HTML report, and an interactive Deep Sea Spectre.Console TUI. Cross-platform (macOS/Windows/Linux) via the Microsoft Graph PowerShell SDK.'
    PowerShellVersion = '7.2'

    # Not hard-required so the module imports cleanly; cmdlets check at runtime
    # and give actionable install hints:
    #   Microsoft.Graph.Authentication  (all cmdlets)
    #   PwshSpectreConsole              (Start-IntuneTide TUI only)

    FunctionsToExport = @(
        'Connect-IntuneTide',
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
        # --- device actions & detail ---
        'Invoke-IntuneDeviceAction',
        'Get-IntuneDeviceDetail',
        'Get-IntuneBitLockerKey',
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
        'Start-IntuneTide'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('tide')

    PrivateData = @{
        PSData = @{
            Tags       = @('Intune', 'MicrosoftGraph', 'MEM', 'Assignments', 'Endpoint', 'TUI', 'Spectre')
            ProjectUri = 'https://github.com/ajamaya1/IntuneTide'
            LicenseUri = 'https://github.com/ajamaya1/IntuneTide/blob/main/LICENSE'
        }
    }
}
