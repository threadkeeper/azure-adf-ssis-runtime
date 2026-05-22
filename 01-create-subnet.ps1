# ============================================================
# 01 - Create a dedicated subnet for the Azure-SSIS IR
#      Delegates to Microsoft.Batch/batchAccounts (required for
#      both Express and Standard VNet Injection)
# ============================================================
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load shared parameters
. "$PSScriptRoot\params.ps1"

Write-Host "=== Step 1: Create subnet for Azure-SSIS IR ===" -ForegroundColor Cyan

# Set subscription context
az account set --subscription $SubscriptionId
Write-Host "Subscription set to: $SubscriptionId"

# Check if subnet already exists
$ErrorActionPreference = "SilentlyContinue"
$existing = az network vnet subnet show `
    --resource-group $VNetResourceGroup `
    --vnet-name $VNetName `
    --name $SubnetName `
    --query "name" -o tsv 2>$null
$ErrorActionPreference = "Stop"

if ($existing) {
    Write-Host "Subnet '$SubnetName' already exists. Skipping creation." -ForegroundColor Yellow
} else {
    Write-Host "Creating subnet '$SubnetName' ($SubnetPrefix) in VNet '$VNetName'..."

    az network vnet subnet create `
        --resource-group $VNetResourceGroup `
        --vnet-name $VNetName `
        --name $SubnetName `
        --address-prefixes $SubnetPrefix `
        --delegations Microsoft.Batch/batchAccounts

    Write-Host "Subnet '$SubnetName' created with Batch delegation." -ForegroundColor Green
}

# Verify the subnet
Write-Host "`nSubnet details:" -ForegroundColor Cyan
az network vnet subnet show `
    --resource-group $VNetResourceGroup `
    --vnet-name $VNetName `
    --name $SubnetName `
    --query "{Name:name, AddressPrefix:addressPrefix, Delegations:delegations[].serviceName}" `
    -o table

Write-Host "`n=== Subnet setup complete ===" -ForegroundColor Green
Write-Host "Next: Run 02-create-adf.ps1"
