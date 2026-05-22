# ============================================================
# 04 - Manage the Azure-SSIS Integration Runtime
#      Start, Stop, check Status, or Delete
#
# Usage:
#   .\04-manage-ssis-ir.ps1 -Action Start
#   .\04-manage-ssis-ir.ps1 -Action Stop
#   .\04-manage-ssis-ir.ps1 -Action Status
#   .\04-manage-ssis-ir.ps1 -Action Delete
# ============================================================
#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Start", "Stop", "Status", "Delete")]
    [string]$Action
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load shared parameters
. "$PSScriptRoot\params.ps1"

az account set --subscription $SubscriptionId

switch ($Action) {
    "Start" {
        Write-Host "Starting SSIS IR '$IrName'... (~5-20 min with Express VNet Injection)" -ForegroundColor Cyan
        az datafactory integration-runtime start `
            --resource-group $ResourceGroup `
            --factory-name $AdfName `
            --name $IrName
        Write-Host "IR '$IrName' started." -ForegroundColor Green
    }
    "Stop" {
        Write-Host "Stopping SSIS IR '$IrName'..." -ForegroundColor Yellow
        az datafactory integration-runtime stop `
            --resource-group $ResourceGroup `
            --factory-name $AdfName `
            --name $IrName --yes
        Write-Host "IR '$IrName' stopped. No compute charges while stopped." -ForegroundColor Green
    }
    "Status" {
        Write-Host "Checking status of SSIS IR '$IrName'..." -ForegroundColor Cyan
        az datafactory integration-runtime get-status `
            --resource-group $ResourceGroup `
            --factory-name $AdfName `
            --name $IrName `
            -o table
    }
    "Delete" {
        Write-Host "WARNING: This will delete the SSIS IR '$IrName'. SSISDB on the MI is NOT deleted." -ForegroundColor Red
        $confirm = Read-Host "Type 'yes' to confirm deletion"
        if ($confirm -eq "yes") {
            az datafactory integration-runtime delete `
                --resource-group $ResourceGroup `
                --factory-name $AdfName `
                --name $IrName --yes
            Write-Host "IR '$IrName' deleted." -ForegroundColor Green
        } else {
            Write-Host "Deletion cancelled." -ForegroundColor Yellow
        }
    }
}
