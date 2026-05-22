# ============================================================
# 02 - Create the Azure Data Factory instance
# ============================================================
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load shared parameters
. "$PSScriptRoot\params.ps1"

Write-Host "=== Step 2: Create Azure Data Factory ===" -ForegroundColor Cyan

# Set subscription context
az account set --subscription $SubscriptionId

# Check if ADF already exists
$ErrorActionPreference = "SilentlyContinue"
$existing = az datafactory show `
    --resource-group $ResourceGroup `
    --name $AdfName `
    --query "name" -o tsv 2>$null
$ErrorActionPreference = "Stop"

if ($existing) {
    Write-Host "Data Factory '$AdfName' already exists. Skipping creation." -ForegroundColor Yellow
} else {
    Write-Host "Creating Azure Data Factory '$AdfName' in '$Location'..."

    az datafactory create `
        --resource-group $ResourceGroup `
        --name $AdfName `
        --location $Location

    Write-Host "Data Factory '$AdfName' created successfully." -ForegroundColor Green
}

# Verify
Write-Host "`nData Factory details:" -ForegroundColor Cyan
az datafactory show `
    --resource-group $ResourceGroup `
    --name $AdfName `
    --query "{Name:name, Location:location, ProvisioningState:provisioningState, ResourceGroup:resourceGroup}" `
    -o table

Write-Host "`n=== ADF setup complete ===" -ForegroundColor Green
Write-Host "Next: Run 03-create-ssis-ir.ps1"
