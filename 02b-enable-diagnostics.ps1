# ============================================================
# 02b - Enable diagnostics for the Azure-SSIS IR
#       Creates a Log Analytics workspace (if missing) and
#       configures ADF diagnostic settings so that IR
#       start/stop events and SSIS package logs are captured.
#
#       Run AFTER 02-create-adf.ps1 and BEFORE 03-create-ssis-ir.ps1
#       so the very first IR start is logged.
# ============================================================
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load shared parameters
. "$PSScriptRoot\params.ps1"

Write-Host "=== Step 2b: Enable SSIS IR diagnostics ===" -ForegroundColor Cyan

# Set subscription context
az account set --subscription $SubscriptionId

# --- 1. Ensure the Log Analytics workspace exists ---
$ErrorActionPreference = "SilentlyContinue"
$workspaceId = az monitor log-analytics workspace show `
    --resource-group $LogAnalyticsResourceGroup `
    --workspace-name $LogAnalyticsWorkspace `
    --query "id" -o tsv 2>$null
$ErrorActionPreference = "Stop"

if ($workspaceId) {
    Write-Host "Log Analytics workspace '$LogAnalyticsWorkspace' already exists." -ForegroundColor Yellow
} else {
    Write-Host "Creating Log Analytics workspace '$LogAnalyticsWorkspace' in '$Location'..."
    az monitor log-analytics workspace create `
        --resource-group $LogAnalyticsResourceGroup `
        --workspace-name $LogAnalyticsWorkspace `
        --location $Location | Out-Null

    $workspaceId = az monitor log-analytics workspace show `
        --resource-group $LogAnalyticsResourceGroup `
        --workspace-name $LogAnalyticsWorkspace `
        --query "id" -o tsv
    Write-Host "Workspace created." -ForegroundColor Green
}

# --- 2. Configure ADF diagnostic settings ---
$adfId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.DataFactory/factories/$AdfName"

# SSIS-focused log categories: IR start/stop + package execution telemetry
$logCategories = @(
    "SSISIntegrationRuntimeLogs",
    "SSISPackageEventMessages",
    "SSISPackageExecutableStatistics",
    "SSISPackageEventMessageContext",
    "SSISPackageExecutionComponentPhases",
    "SSISPackageExecutionDataStatistics"
)

$logs    = $logCategories | ForEach-Object { @{ category = $_; enabled = $true } }
$metrics = @( @{ category = "AllMetrics"; enabled = $true } )

# ConvertTo-Json in PS 5.1 collapses single-element arrays to objects; force array form.
function ConvertTo-JsonArray($items) {
    $json = $items | ConvertTo-Json -Depth 4
    if ($json -notmatch '^\s*\[') { $json = "[$json]" }
    return $json
}

$logsFile    = [System.IO.Path]::GetTempFileName()
$metricsFile = [System.IO.Path]::GetTempFileName()
ConvertTo-JsonArray $logs    | Set-Content -Path $logsFile -Encoding utf8
ConvertTo-JsonArray $metrics | Set-Content -Path $metricsFile -Encoding utf8

Write-Host "Configuring diagnostic setting '$DiagnosticSettingName' on ADF '$AdfName'..."
try {
    az monitor diagnostic-settings create `
        --name $DiagnosticSettingName `
        --resource $adfId `
        --workspace $workspaceId `
        --export-to-resource-specific true `
        --logs "@$logsFile" `
        --metrics "@$metricsFile" | Out-Null
} finally {
    Remove-Item $logsFile, $metricsFile -ErrorAction SilentlyContinue
}

Write-Host "Diagnostic setting applied. SSIS IR start/stop and package logs now flow to '$LogAnalyticsWorkspace'." -ForegroundColor Green

# --- 3. Verify ---
Write-Host "`nDiagnostic settings on ADF:" -ForegroundColor Cyan
az monitor diagnostic-settings list `
    --resource $adfId `
    --query "value[].{Name:name, EnabledLogs:logs[?enabled].category}" `
    -o json

Write-Host "`n=== Diagnostics setup complete ===" -ForegroundColor Green
Write-Host "Next: Run 03-create-ssis-ir.ps1"
Write-Host "Tip: After an IR start, query logs with:" -ForegroundColor DarkGray
Write-Host "  ADFSSISIntegrationRuntimeLogs | where TimeGenerated > ago(2h) | order by TimeGenerated asc" -ForegroundColor DarkGray
