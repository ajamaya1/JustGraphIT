# Licensing helpers — translate the cryptic SKU part numbers Graph returns
# (e.g. "SPE_E5") into the names admins actually recognise ("Microsoft 365 E5").

# Curated subset of the most common commercial SKUs. Anything not listed falls
# back to the raw skuPartNumber, so the lookup degrades gracefully.
$script:IaSkuFriendlyName = @{
    'SPE_E3'                              = 'Microsoft 365 E3'
    'SPE_E5'                              = 'Microsoft 365 E5'
    'SPE_F1'                              = 'Microsoft 365 F3'
    'SPB'                                 = 'Microsoft 365 Business Premium'
    'O365_BUSINESS_PREMIUM'               = 'Microsoft 365 Business Standard'
    'O365_BUSINESS_ESSENTIALS'            = 'Microsoft 365 Business Basic'
    'ENTERPRISEPACK'                      = 'Office 365 E3'
    'ENTERPRISEPREMIUM'                   = 'Office 365 E5'
    'ENTERPRISEPREMIUM_NOPSTNCONF'        = 'Office 365 E5 (without Audio Conferencing)'
    'STANDARDPACK'                        = 'Office 365 E1'
    'DESKLESSPACK'                        = 'Office 365 F3'
    'EMS'                                 = 'Enterprise Mobility + Security E3'
    'EMSPREMIUM'                          = 'Enterprise Mobility + Security E5'
    'INTUNE_A'                            = 'Intune Plan 1'
    'INTUNE_A_D'                          = 'Intune (device)'
    'Microsoft_Intune_Suite'             = 'Intune Suite'
    'AAD_PREMIUM'                         = 'Entra ID P1'
    'AAD_PREMIUM_P2'                      = 'Entra ID P2'
    'WIN10_PRO_ENT_SUB'                   = 'Windows 10/11 Enterprise E3'
    'WIN10_VDA_E5'                        = 'Windows 10/11 Enterprise E5'
    'Windows_365_Enterprise_2_8_128'      = 'Windows 365 Enterprise 2vCPU/8GB/128GB'
    'Windows_365_Enterprise_4_16_256'     = 'Windows 365 Enterprise 4vCPU/16GB/256GB'
    'CPC_E_2C_8GB_128GB'                  = 'Windows 365 Enterprise 2vCPU/8GB/128GB'
    'POWER_BI_PRO'                        = 'Power BI Pro'
    'PROJECTPROFESSIONAL'                 = 'Project Plan 3'
    'VISIOCLIENT'                         = 'Visio Plan 2'
    'FLOW_FREE'                           = 'Power Automate Free'
    'TEAMS_EXPLORATORY'                   = 'Teams Exploratory'
    'DEFENDER_ENDPOINT_P1'                = 'Defender for Endpoint P1'
    'DEFENDER_ENDPOINT_P2'                = 'Defender for Endpoint P2'
    'MCOMEETADV'                          = 'Microsoft 365 Audio Conferencing'
    'PHONESYSTEM_VIRTUALUSER'             = 'Microsoft Teams Phone Resource Account'
}

function Get-IaLicenseName {
    # Friendly product name for a SKU part number; falls back to the raw value.
    param([string]$SkuPartNumber)
    if ([string]::IsNullOrWhiteSpace($SkuPartNumber)) { return '(unknown)' }
    if ($script:IaSkuFriendlyName.ContainsKey($SkuPartNumber)) { return $script:IaSkuFriendlyName[$SkuPartNumber] }
    $SkuPartNumber
}
