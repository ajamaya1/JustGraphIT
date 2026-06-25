function Get-IntuneDeviceDetail {
    <#
    .SYNOPSIS
        Comprehensive details for a single Intune-managed device.

    .DESCRIPTION
        Returns hardware, network, enrollment, security, compliance, storage and
        user fields for a single device. Add switches to enrich the result with
        detected apps, configuration profile states, and compliance policy states.

    .PARAMETER Device
        Device name or managed device GUID.

    .PARAMETER IncludeApps
        Append a list of detected applications on the device.

    .PARAMETER IncludeConfigState
        Append configuration profile compliance states.

    .PARAMETER IncludeComplianceState
        Append compliance policy states.

    .EXAMPLE
        Get-IntuneDeviceDetail -Device DESKTOP-ABC123

    .EXAMPLE
        Get-IntuneDeviceDetail -Device LAPTOP-X -IncludeApps -IncludeComplianceState

    .OUTPUTS
        PSCustomObject with Core, Network, Enrollment, Security, Compliance,
        Storage, User fields, plus optional Apps/ConfigStates/ComplianceStates.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Device,
        [switch]$IncludeApps,
        [switch]$IncludeConfigState,
        [switch]$IncludeComplianceState
    )

    $id = Resolve-IaManagedDeviceId -Value $Device
    $d  = Invoke-IaRequest -Method GET -Uri (Resolve-IaUri "deviceManagement/managedDevices/$id")

    $result = [pscustomobject][ordered]@{
        # Core
        Device              = $d.deviceName
        Id                  = $d.id
        SerialNumber        = $d.serialNumber
        OS                  = $d.operatingSystem
        OSVersion           = $d.osVersion
        Platform            = $d.deviceType
        Model               = $d.model
        Manufacturer        = $d.manufacturer
        # Network
        IMEI                = $d.imei
        MEID                = $d.meid
        WiFiMacAddress      = $d.wiFiMacAddress
        EthernetMacAddress  = $d.ethernetMacAddress
        IPAddressV4         = $d.ipAddressV4
        SubscriberCarrier   = $d.subscriberCarrier
        # Enrollment
        EnrolledAt          = $d.enrolledDateTime
        EnrollmentType      = $d.deviceEnrollmentType
        ManagementAgent     = $d.managementAgent
        JoinType            = $d.joinType
        OwnerType           = $d.ownerType
        # Security
        Encrypted           = $d.isEncrypted
        ActivationLock      = $d.activationLockEnabled
        JailBroken          = $d.jailBroken
        # Compliance
        ComplianceState         = $d.complianceState
        ComplianceGracePeriodEnd = $d.complianceGracePeriodExpirationDateTime
        # Azure AD
        AzureADDeviceId     = $d.azureADDeviceId
        AzureADRegistered   = $d.azureADRegistered
        # Storage
        TotalStorageGB      = if ($d.totalStorageSpaceInBytes) { [math]::Round($d.totalStorageSpaceInBytes / 1GB, 1) } else { $null }
        FreeStorageGB       = if ($d.freeStorageSpaceInBytes)  { [math]::Round($d.freeStorageSpaceInBytes  / 1GB, 1) } else { $null }
        # User
        UserDisplayName     = $d.userDisplayName
        UserEmail           = $d.emailAddress
        UserPrincipalName   = $d.userPrincipalName
        # Sync
        LastSyncAt          = $d.lastSyncDateTime
    }

    if ($IncludeApps) {
        $apps = @(Get-IaCollection (Resolve-IaUri "deviceManagement/managedDevices/$id/detectedApps") |
            ForEach-Object { [pscustomobject][ordered]@{ App = $_.displayName; Version = $_.version; Id = $_.id } })
        $result | Add-Member -NotePropertyName Apps -NotePropertyValue $apps
    }

    if ($IncludeConfigState) {
        $cs = @(Get-IaCollection (Resolve-IaUri "deviceManagement/managedDevices/$id/deviceConfigurationStates"))
        $result | Add-Member -NotePropertyName ConfigStates -NotePropertyValue $cs
    }

    if ($IncludeComplianceState) {
        $cp = @(Get-IaCollection (Resolve-IaUri "deviceManagement/managedDevices/$id/deviceCompliancePolicyStates"))
        $result | Add-Member -NotePropertyName ComplianceStates -NotePropertyValue $cp
    }

    $result
}
