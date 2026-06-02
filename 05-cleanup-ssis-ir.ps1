# ============================================================
# 05 - Clean up all resources created by this project
#      Removes (in reverse order of creation, only if present):
#        1. Azure-SSIS Integration Runtime  (ssis-ir-001)
#        2. Azure Data Factory              (adf-jva-001)
#        3. SSIS IR subnet                  (snet-ssis-ir)
#
#      NOTE: The SQL Managed Instance, its VNet, and the SSISDB
#      catalog are NOT touched by this script.
#
# Usage:
#   .\05-cleanup-ssis-ir.ps1            # prompts for confirmation
#   .\05-cleanup-ssis-ir.ps1 -Force     # skips confirmation
# ============================================================
#Requires -Version 5.1
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load shared parameters
. "$PSScriptRoot\params.ps1"

Write-Host "=== Step 5: Clean up Azure-SSIS IR resources ===" -ForegroundColor Cyan

# Set subscription context
az account set --subscription $SubscriptionId
Write-Host "Subscription set to: $SubscriptionId"

# Confirmation
if (-not $Force) {
    Write-Host ""
    Write-Host "This will DELETE the following resources if they exist:" -ForegroundColor Red
    Write-Host "  - SSIS Integration Runtime : $IrName (in $AdfName)"
    Write-Host "  - Azure Data Factory       : $AdfName ($ResourceGroup)"
    Write-Host "  - Subnet                   : $SubnetName ($VNetName / $VNetResourceGroup)"
    Write-Host ""
    Write-Host "The SQL MI, VNet, and SSISDB catalog are NOT affected." -ForegroundColor Yellow
    $confirm = Read-Host "Type 'yes' to confirm cleanup"
    if ($confirm -ne "yes") {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        return
    }
}

# Helper: check existence quietly
function Test-AzResourceExists {
    param([scriptblock]$Query)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    $result = & $Query 2>$null
    $ErrorActionPreference = $prev
    return [bool]$result
}

# ------------------------------------------------------------
# 1. Delete the SSIS Integration Runtime
# ------------------------------------------------------------
Write-Host "`n[1/3] Integration Runtime '$IrName'..." -ForegroundColor Cyan

$irExists = Test-AzResourceExists {
    az datafactory integration-runtime show `
        --resource-group $ResourceGroup `
        --factory-name $AdfName `
        --name $IrName `
        --query "name" -o tsv
}

if ($irExists) {
    # Stop the IR first if it is running (ignore errors if already stopped)
    Write-Host "  Stopping IR (if running)..."
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    az datafactory integration-runtime stop `
        --resource-group $ResourceGroup `
        --factory-name $AdfName `
        --name $IrName --yes 2>$null
    $ErrorActionPreference = $prev

    Write-Host "  Deleting IR '$IrName'..."
    az datafactory integration-runtime delete `
        --resource-group $ResourceGroup `
        --factory-name $AdfName `
        --name $IrName --yes
    Write-Host "  IR '$IrName' deleted." -ForegroundColor Green
} else {
    Write-Host "  IR '$IrName' not found. Skipping." -ForegroundColor Yellow
}

# ------------------------------------------------------------
# 2. Delete the Azure Data Factory
# ------------------------------------------------------------
Write-Host "`n[2/3] Data Factory '$AdfName'..." -ForegroundColor Cyan

$adfExists = Test-AzResourceExists {
    az datafactory show `
        --resource-group $ResourceGroup `
        --name $AdfName `
        --query "name" -o tsv
}

if ($adfExists) {
    Write-Host "  Deleting Data Factory '$AdfName'..."
    az datafactory delete `
        --resource-group $ResourceGroup `
        --name $AdfName --yes
    Write-Host "  Data Factory '$AdfName' deleted." -ForegroundColor Green
} else {
    Write-Host "  Data Factory '$AdfName' not found. Skipping." -ForegroundColor Yellow
}

# ------------------------------------------------------------
# 3. Delete the SSIS IR subnet
# ------------------------------------------------------------
Write-Host "`n[3/3] Subnet '$SubnetName'..." -ForegroundColor Cyan

$subnetExists = Test-AzResourceExists {
    az network vnet subnet show `
        --resource-group $VNetResourceGroup `
        --vnet-name $VNetName `
        --name $SubnetName `
        --query "name" -o tsv
}

if ($subnetExists) {
    Write-Host "  Deleting subnet '$SubnetName'..."
    az network vnet subnet delete `
        --resource-group $VNetResourceGroup `
        --vnet-name $VNetName `
        --name $SubnetName
    Write-Host "  Subnet '$SubnetName' deleted." -ForegroundColor Green
} else {
    Write-Host "  Subnet '$SubnetName' not found. Skipping." -ForegroundColor Yellow
}

Write-Host "`n=== Cleanup complete ===" -ForegroundColor Green
Write-Host "The SQL MI, VNet, and SSISDB catalog were left untouched."
