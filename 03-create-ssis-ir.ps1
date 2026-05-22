# ============================================================
# 03 - Create and start the Azure-SSIS Integration Runtime
#      Express VNet Injection into the SQL MI VNet
# ============================================================
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load shared parameters
. "$PSScriptRoot\params.ps1"

Write-Host "=== Step 3: Create Azure-SSIS Integration Runtime ===" -ForegroundColor Cyan

# Set subscription context
az account set --subscription $SubscriptionId



# Check if the IR already exists
$ErrorActionPreference = "SilentlyContinue"
$existing = az datafactory integration-runtime show `
    --resource-group $ResourceGroup `
    --factory-name $AdfName `
    --name $IrName `
    --query "name" -o tsv 2>$null
$ErrorActionPreference = "Stop"

if ($existing) {
    Write-Host "Integration Runtime '$IrName' already exists." -ForegroundColor Yellow
    Write-Host "To recreate, delete it first with: 04-manage-ssis-ir.ps1 -Action Delete" -ForegroundColor Yellow
} else {
    Write-Host "Creating Azure-SSIS IR '$IrName'..."
    Write-Host "  Node size  : $NodeSize"
    Write-Host "  Node count : $NodeCount"
    Write-Host "  Edition    : $Edition"
    Write-Host "  VNet       : $VNetName / $SubnetName"
    Write-Host "  Catalog    : $MIEndpoint (SSISDB)"
    Write-Host ""

    # Build the full IR definition using the REST API format
    # Uses customerVirtualNetwork (Express VNet Injection) matching portal behaviour
    $SubnetId = "$VNetId/subnets/$SubnetName"

    $irBody = @{
        properties = @{
            type = "Managed"
            typeProperties = @{
                computeProperties = @{
                    location = $Location
                    nodeSize = $NodeSize
                    numberOfNodes = [int]$NodeCount
                    maxParallelExecutionsPerNode = 2
                }
                customerVirtualNetwork = @{
                    subnetId = $SubnetId
                }
                ssisProperties = @{
                    catalogInfo = @{
                        catalogServerEndpoint = $MIEndpoint
                    }
                    edition = $Edition
                }
            }
        }
    }

    $bodyFile = [System.IO.Path]::GetTempFileName()
    $irBody | ConvertTo-Json -Depth 6 | Set-Content -Path $bodyFile -Encoding utf8

    $uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.DataFactory/factories/$AdfName/integrationRuntimes/$($IrName)?api-version=2018-06-01"

    try {
        az rest --method PUT --uri $uri --body "@$bodyFile"
    } finally {
        Remove-Item $bodyFile -ErrorAction SilentlyContinue
    }

    Write-Host "Integration Runtime '$IrName' created successfully." -ForegroundColor Green
}

# Show the IR status
Write-Host "`nIntegration Runtime details:" -ForegroundColor Cyan
az datafactory integration-runtime show `
    --resource-group $ResourceGroup `
    --factory-name $AdfName `
    --name $IrName `
    -o table

# Ask if user wants to start the IR now
Write-Host ""
$startNow = Read-Host "Start the SSIS IR now? This takes ~5-20 minutes with Express VNet Injection (y/N)"
if ($startNow -eq "y" -or $startNow -eq "Y") {
    Write-Host "Starting '$IrName'... (this will take a few minutes)" -ForegroundColor Cyan
    az datafactory integration-runtime start `
        --resource-group $ResourceGroup `
        --factory-name $AdfName `
        --name $IrName

    Write-Host "Integration Runtime '$IrName' is now running." -ForegroundColor Green
} else {
    Write-Host "IR not started. You can start it later with: 04-manage-ssis-ir.ps1 -Action Start"
}

Write-Host "`n=== SSIS IR setup complete ===" -ForegroundColor Green
