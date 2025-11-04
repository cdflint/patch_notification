#############################################################################################
# Variables section, adjust as needed for implementation in your environment
#############################################################################################

# Specify the role of the ArcGIS Enterprise component 
$Role = "Portal"

# Provide your webhook URL here from Power Automate Flow or set in ENV Var
# $webhookUrl = ''
$webhookUrl = $env:PATCH_NOTIFICATION_WEBHOOK_URL

##############################################################################################
# Functions section
##############################################################################################

<#
.SYNOPSIS
Parses the output of the ArcGIS patch notification tool into a structured JSON object.

.DESCRIPTION
The `Parse-PatchNotificationToJson` function processes an array of strings representing the output of the ArcGIS patch notification tool. 
It organizes the data into a structured hashtable containing information about installed components, available updates, and installed patches. 
The resulting hashtable can be easily converted to JSON for further processing or integration with other systems.

.PARAMETER notificationArray
An array of strings representing the lines of output from the ArcGIS patch notification tool.

.OUTPUTS
Hashtable
A structured hashtable containing the following keys:
- `InstalledComponents`: A hashtable mapping component names to their installed versions.
- `AvailableUpdates`: A hashtable mapping component names to an array of available updates, each with a description, URL, and release date.
- `InstalledPatches`: An array of installed patches or a single value of "none" if no patches are installed.

.EXAMPLE
$notificationArray = @(
    "================================================================================",
    "",
    "Installed Components",
    "",
    "    ArcGIS Data Store                             11.4",
    "    ArcGIS Server                                 11.4",
    "    Portal for ArcGIS                             11.4",
    "",
    "================================================================================",
    "",
    "Available Updates",
    "",
    " ArcGIS Data Store",
    "    (no updates available)",
    "",
    " ArcGIS Server",
    "    - ArcGIS Server 11.4 Spatial Analysis Patch",
    "      https://support.esri.com/en-us/patches-updates/2024/arcgis-server-11-4-spatial-analysis-patch",
    "      Release Date: 11/25/24",
    "",
    "    - ArcGIS Server 11.4 Print Service Vector Tile Labels Patch",
    "      https://support.esri.com/en-us/patches-updates/2025/arcgis-server-11-4-print-service-vector-tile-labels-patch",
    "      Release Date: 2/5/25",
    "",
    " Portal for ArcGIS",
    "    (no updates available)",
    "",
    "================================================================================",
    "",
    "Installed Patches",
    "    (none)",
    "",
    "================================================================================"
)

$result = Parse-PatchNotificationToJson -notificationArray $notificationArray
Write-Output $result

.NOTES
- Ensure the input array is properly formatted as expected by the function.
- The function assumes specific patterns in the input data to identify sections and extract information.
#>


function Parse-PatchNotificationToJson {
    param (
        [string[]]$notificationArray
    )

    $result = @{
        MachineName = $env:COMPUTERNAME
        FQDN = [System.Net.Dns]::GetHostByName($env:computerName).HostName
        IPV4 = [System.Net.Dns]::GetHostByName($env:computerName).AddressList.IPAddressToString
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

<#
.SYNOPSIS
Sends parsed ArcGIS patch notification data to a specified webhook URL.

.DESCRIPTION
The `Send-PatchNotificationWebhook` function takes a parsed hashtable containing ArcGIS patch notification data and sends it as a JSON payload to a specified webhook URL. 
This function is useful for integrating patch notification data with external systems, such as Power Automate, Slack, or other webhook-compatible services.

.PARAMETER parsedResult
A hashtable containing the parsed ArcGIS patch notification data. This data is typically generated by the `Parse-PatchNotificationToJson` function.

.PARAMETER webhookUrl
The URL of the webhook endpoint where the JSON payload will be sent.

.OUTPUTS
String
The JSON payload that was sent to the webhook.

.EXAMPLE
$parsedResult = @{
    InstalledComponents = @{
        "ArcGIS Data Store" = "11.4"
        "ArcGIS Server" = "11.4"
        "Portal for ArcGIS" = "11.4"
    }
    AvailableUpdates = @{
        "ArcGIS Data Store" = @(
            @{
                description = "no updates available"
            }
        )
        "ArcGIS Server" = @(
            @{
                description = "ArcGIS Server 11.4 Spatial Analysis Patch"
                url = "https://support.esri.com/en-us/patches-updates/2024/arcgis-server-11-4-spatial-analysis-patch"
                releaseDate = "11/25/24"
            }
        )
    }
    InstalledPatches = @("none")
}

$webhookUrl = "https://example.com/webhook"
$jsonBody = Send-PatchNotificationWebhook -parsedResult $parsedResult -webhookUrl $webhookUrl
Write-Output $jsonBody

.NOTES
- Ensure the webhook URL is valid and accessible.
- The function uses `Invoke-RestMethod` to send the JSON payload, so it requires internet access or network connectivity to the webhook endpoint.
- The JSON payload is converted with a depth of 4 to ensure nested structures are properly serialized.
#>

function Send-PatchNotificationWebhook {
    param (
        [hashtable]$parsedResult,
        [string]$webhookUrl
    )

    $jsonBody = $parsedResult | ConvertTo-Json -Depth 4
    Invoke-RestMethod -Uri $webhookUrl -Method Post -ContentType 'application/json' -Body $jsonBody
    return $jsonBody
}


#############################################################################################
# Main Script section
#############################################################################################

# Set proper Enterprise path based on role
switch ($Role) {
    "Portal" { $EnterprisePath = 'C:\Program Files\ArcGIS\Portal' }
    "Server" { $EnterprisePath = 'C:\Program Files\ArcGIS\Server' }
    "DataStore" { $EnterprisePath = 'C:\Program Files\ArcGIS\Datastore' }
    Default { throw "Invalid Role specified. Use 'Portal', 'Server', or 'Datastore'." }
}


try {
    # Path to this scripts parent directory
    $toolPath = Get-Location

    # Change to the Patch notification tool directory
    Set-Location -Path "$($EnterprisePath)\tools\patchnotification\" # Set to run in Portal tools dir

    # Run patch notification tool and capture output
    $notificationArray = .\patchnotification.bat -c
    $jsonResult = Parse-PatchNotificationToJson -notificationArray $notificationArray

    # Send out response data to webhook
    Send-PatchNotificationWebhook -parsedResult $jsonResult -webhookUrl $webhookUrl

    # For debugging purposes in Powershell
    # Write-Output $jsonResult
    # $jsonResult | ConvertTo-Json -Depth 4 | Out-File -FilePath "$($toolPath)/notifications.json"

    # Move back to working dir for script
    Set-Location -Path $toolPath
    exit 0
}
catch {
    <#Do this if a terminating exception happens#>
    Write-Host "An error occurred: $($_.Exception.Message)"
    exit 1
}
