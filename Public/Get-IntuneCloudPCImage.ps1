function Get-IntuneCloudPCImage {
    <#
    .SYNOPSIS
        List Windows 365 gallery and custom OS images.

    .DESCRIPTION
        Returns available OS images for Cloud PC provisioning. Gallery images are
        Microsoft-managed; custom images are uploaded by the tenant. Use -Status
        to filter custom images by their upload/processing status.

    .PARAMETER Type
        Which image source to query: 'Gallery', 'Custom', or 'All' (default).

    .PARAMETER Status
        Filter custom images by status (e.g. 'ready', 'failed'). Only applies
        when Type is 'Custom' or 'All'.

    .EXAMPLE
        Get-IntuneCloudPCImage -Type Gallery

        All Microsoft gallery images.

    .EXAMPLE
        Get-IntuneCloudPCImage -Type Custom -Status ready

        Tenant-uploaded images that have finished processing.

    .OUTPUTS
        PSCustomObject: Name, Type, OS, Version, Status, SizeGB, Id.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Gallery', 'Custom', 'All')][string]$Type = 'All',
        [string]$Status
    )

    $results = [System.Collections.Generic.List[object]]::new()

    if ($Type -in 'Gallery', 'All') {
        $gallery = Get-IaCollection (Get-IaW365Path 'galleryImages')
        foreach ($img in $gallery) {
            [void]$results.Add([pscustomobject][ordered]@{
                Name    = $img.displayName
                Type    = 'Gallery'
                OS      = $img.operatingSystem
                Version = $img.version
                Status  = 'available'
                SizeGB  = if ($img.PSObject.Properties['sizeInGB']) { $img.sizeInGB } else { $null }
                Id      = $img.id
            })
        }
    }

    if ($Type -in 'Custom', 'All') {
        $custom = Get-IaCollection (Get-IaW365Path 'deviceImages')
        foreach ($img in $custom) {
            if ($Status -and $img.status -ne $Status) { continue }
            [void]$results.Add([pscustomobject][ordered]@{
                Name    = $img.displayName
                Type    = 'Custom'
                OS      = $img.operatingSystem
                Version = $img.version
                Status  = $img.status
                SizeGB  = if ($img.PSObject.Properties['sizeInGB']) { $img.sizeInGB } else { $null }
                Id      = $img.id
            })
        }
    }

    $results.ToArray()
}
