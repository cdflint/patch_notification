function Parse-PatchNotificationToJson {
    param (
        [string[]]$notificationArray
    )

    $result = @{
        InstalledComponents = @{}
        AvailableUpdates = @{
            "ArcGIS Data Store" = @()
            "ArcGIS Server" = @()
            "Portal for ArcGIS" = @()
        }
        InstalledPatches = @()
    }

    $currentSection = ""
    $currentComponent = ""

    foreach ($line in $notificationArray) {
        switch -Regex ($line) {
            "^Installed Components$" {
                $currentSection = "InstalledComponents"
                continue
            }
            "^Available Updates$" {
                $currentSection = "AvailableUpdates"
                continue
            }
            "^Installed Patches$" {
                $currentSection = "InstalledPatches"
                continue
            }
            "^\s*$" {
                continue
            }
            "^\s*================================================================================\s*$" {
                continue
            }
            default {
                if ($currentSection -eq "InstalledComponents") {
                    if ($line -match "^\s*(.+?)\s+(\d+\.\d+)\s*$") {
                        $component = $matches[1].Trim()
                        $version = $matches[2].Trim()
                        $result.InstalledComponents[$component] = $version
                    }
                } elseif ($currentSection -eq "AvailableUpdates") {
                    if ($line -match "^\s*(ArcGIS Data Store|ArcGIS Server|Portal for ArcGIS)\s*$") {
                        $currentComponent = $matches[1].Trim()
                    } elseif ($line -match "^\s*-\s*(.+?)\s*$") {
                        $update = $matches[1].Trim()
                        $result.AvailableUpdates[$currentComponent] += @{
                            "description" = $update
                        }
                    } elseif ($line -match "^\s*(https?://\S+)\s*$") {
                        $url = $matches[1].Trim()
                        $result.AvailableUpdates[$currentComponent][-1]["url"] = $url
                    } elseif ($line -match "^\s*Release Date:\s*(.+?)\s*$") {
                        $releaseDate = $matches[1].Trim()
                        $result.AvailableUpdates[$currentComponent][-1]["releaseDate"] = $releaseDate
                    } elseif ($line -match "^\s*\(no updates available\)\s*$") {
                        $result.AvailableUpdates[$currentComponent] += @{
                            "description" = "no updates available"
                        }
                    }
                } elseif ($currentSection -eq "InstalledPatches") {
                    if ($line -match "^\s*\(none\)\s*$") {
                        $result.InstalledPatches = @("none")
                    }
                }
            }
        }
    }

    return $result
}

function Send-PatchNotificationWebhook {
    param (
        [hashtable]$parsedResult,
        [string]$webhookUrl
    )

    $jsonBody = $parsedResult | ConvertTo-Json -Depth 4
    Invoke-RestMethod -Uri $webhookUrl -Method Post -ContentType 'application/json' -Body $jsonBody
    return $jsonBody
}

# Example notification output:
# $notificationArray = @(
#     "================================================================================",
#     "",
#     "Installed Components",
#     "",
#     "    ArcGIS Data Store                             11.4",
#     "    ArcGIS Server                                 11.4",
#     "    Portal for ArcGIS                             11.4",
#     "",
#     "================================================================================",
#     "",
#     "Available Updates",
#     "",
#     " ArcGIS Data Store",
#     "    (no updates available)",
#     "",
#     " ArcGIS Server",
#     "    - ArcGIS Server 11.4 Spatial Analysis Patch",
#     "      https://support.esri.com/en-us/patches-updates/2024/arcgis-server-11-4-spatial-analysis-patch",
#     "      Release Date: 11/25/24",
#     "",
#     "    - ArcGIS Server 11.4 Print Service Vector Tile Labels Patch",
#     "      https://support.esri.com/en-us/patches-updates/2025/arcgis-server-11-4-print-service-vector-tile-labels-patch",
#     "      Release Date: 2/5/25",
#     "",
#     " Portal for ArcGIS",
#     "    (no updates available)",
#     "",
#     "================================================================================",
#     "",
#     "Installed Patches",
#     "    (none)",
#     "",
#     "================================================================================"
# )

# Get to Patch notification dir and run a check
Set-Location -Path 'C:\Program Files\ArcGIS\Portal\tools\patchnotification\'
$notificationArray = .\patchnotification.bat -c
$jsonResult = Parse-PatchNotificationToJson -notificationArray $notificationArray

# Send out response data to webhook
$webhookUrl = 'https://prod-189.westus.logic.azure.com:443/workflows/7b8c02f32100433c8e465fc6e45ef47a/triggers/manual/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=Y1O5Ge5PA8cs7x28Z_MllAadc7U1aYWWCGCqsNlmpsQ'
# $webhookUrl = 'https://prod-126.westus.logic.azure.com:443/workflows/a4e718d79cf046a18a82b4b49cf46603/triggers/manual/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=I9xrCFjUXK8rMBmeUdY-QL6yAhfUjeSWa3FHraet4b4'
Send-PatchNotificationWebhook -parsedResult $jsonResult -webhookUrl $webhookUrl

# Write-Output $jsonResult
# $jsonResult | ConvertTo-Json -Depth 4 | Out-File -FilePath "c:/temp/notifications.json"
# Move back to working dir for script
Set-Location -Path 'c:/tools/ent_admin'
