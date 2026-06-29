function Get-EntraLicense {
    <#
    .SYNOPSIS
        Tenant licenses (subscribed SKUs) with consumed / available counts and the
        service plans each contains. Beta Graph: GET /beta/subscribedSkus.
    .DESCRIPTION
        One row per SKU: friendly name, part number, how many are consumed vs enabled,
        how many are free, warning/suspended units, and the service-plan list. -Detailed
        also emits one row per service plan (provisioning status).
    .PARAMETER Detailed
        Expand each SKU's service plans into their own rows.
    .OUTPUTS
        PSCustomObject per SKU (or per service plan with -Detailed).
    #>
    [CmdletBinding()]
    param([switch]$Detailed)

    $skus = @(Get-IaCollection (Resolve-IaUri -Path "subscribedSkus"))

    if ($Detailed) {
        return @($skus | ForEach-Object {
            $sku = $_
            foreach ($sp in @($sku.servicePlans)) {
                [pscustomobject][ordered]@{
                    Sku           = (Get-IaLicenseName -SkuPartNumber $sku.skuPartNumber)
                    SkuPartNumber = $sku.skuPartNumber
                    ServicePlan   = $sp.servicePlanName
                    Provisioning  = $sp.provisioningStatus
                    AppliesTo     = $sp.appliesTo
                }
            }
        })
    }

    @($skus | ForEach-Object {
        $enabled = ConvertTo-IaSafeInt (@($_.prepaidUnits.enabled)[0]) 0
        $used    = ConvertTo-IaSafeInt (@($_.consumedUnits)[0]) 0
        [pscustomobject][ordered]@{
            DisplayName   = (Get-IaLicenseName -SkuPartNumber $_.skuPartNumber)
            SkuPartNumber = $_.skuPartNumber
            Consumed      = $used
            Enabled       = $enabled
            Available     = ($enabled - $used)
            Warning       = ConvertTo-IaSafeInt (@($_.prepaidUnits.warning)[0]) 0
            Suspended     = ConvertTo-IaSafeInt (@($_.prepaidUnits.suspended)[0]) 0
            Status        = $_.capabilityStatus
            ServicePlans  = (@($_.servicePlans | ForEach-Object { $_.servicePlanName }) -join ', ')
            SkuId         = $_.skuId
        }
    } | Sort-Object SkuPartNumber)
}
