# ============================================================
# watch-ir.ps1 - Live monitor / log tail for the Azure-SSIS IR
#
#   Streams ALL ADFSSISIntegrationRuntimeLogs rows as they are
#   ingested while polling the IR control-plane status. Exits when
#   the IR reaches 'Started' or the start 'Failed'.
#
#   Requires diagnostics enabled first (run 02b-enable-diagnostics.ps1).
#
# Usage:
#   .\watch-ir.ps1                       # tail logs + status until Started/Failed
#   .\watch-ir.ps1 -StopOnError          # also auto-stop the IR on first SQL/connection error
#   .\watch-ir.ps1 -IntervalSeconds 20   # change poll interval
#   .\watch-ir.ps1 -TimeoutMinutes 90    # change max watch time
# ============================================================
#Requires -Version 5.1
param(
    [int]$IntervalSeconds = 30,
    [int]$TimeoutMinutes  = 60,
    [switch]$StopOnError
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# Load shared parameters
. "$PSScriptRoot\params.ps1"

az account set --subscription $SubscriptionId | Out-Null

# Resolve the Log Analytics workspace GUID used by the query API
$wsGuid = az monitor log-analytics workspace show `
    --resource-group $LogAnalyticsResourceGroup `
    --workspace-name $LogAnalyticsWorkspace `
    --query "customerId" -o tsv 2>$null
if (-not $wsGuid) {
    Write-Host "Could not resolve workspace '$LogAnalyticsWorkspace'. Run 02b-enable-diagnostics.ps1 first." -ForegroundColor Red
    return
}

$deadline    = (Get-Date).AddMinutes($TimeoutMinutes)
$lastSeenUtc = (Get-Date).ToUniversalTime().AddHours(-2)   # show up to 2h of history on first pass
$printed     = New-Object System.Collections.Generic.HashSet[string]
$errPattern  = '18456|login failed|cannot open|permission denied|already exist|failed to connect|connection failure|AzureSqlConnectionFailure|sql error'

Write-Host "=== Watching SSIS IR '$IrName' (logs + status) ===" -ForegroundColor Cyan
Write-Host "Workspace: $LogAnalyticsWorkspace  |  Interval: ${IntervalSeconds}s  |  StopOnError: $StopOnError`n"

while ((Get-Date) -lt $deadline) {
    # --- 1. Control-plane status ---
    $statusJson = az datafactory integration-runtime get-status `
        -g $ResourceGroup --factory-name $AdfName --name $IrName -o json 2>$null | ConvertFrom-Json
    $state      = $statusJson.properties.state
    $lastResult = $statusJson.properties.lastOperation.result
    $lastErr    = $statusJson.properties.lastOperation.errorCode
    $lastMsg    = ($statusJson.properties.lastOperation.parameters) -join ' | '

    # --- 2. Pull ALL log rows since the last one we printed ---
    $kql = "ADFSSISIntegrationRuntimeLogs | where TimeGenerated > datetime($($lastSeenUtc.ToString('o'))) | order by TimeGenerated asc | project TimeGenerated, OperationName, Message"
    $body = @{ query = $kql } | ConvertTo-Json
    $bf = [System.IO.Path]::GetTempFileName()
    $body | Set-Content -Path $bf -Encoding utf8
    $resp = az rest --method post `
        --uri "https://api.loganalytics.io/v1/workspaces/$wsGuid/query" `
        --resource "https://api.loganalytics.io" `
        --headers "Content-Type=application/json" `
        --body "@$bf" -o json 2>$null | ConvertFrom-Json
    Remove-Item $bf -ErrorAction SilentlyContinue

    $errorHit = $null
    if ($resp -and $resp.tables -and $resp.tables[0].rows) {
        foreach ($row in $resp.tables[0].rows) {
            $key = "$($row[0])|$($row[2])"
            if ($printed.Add($key)) {
                Write-Host ("[{0}] {1,-10} {2}" -f $row[0], $row[1], $row[2])
                $rowUtc = [DateTime]::Parse($row[0]).ToUniversalTime()
                if ($rowUtc -gt $lastSeenUtc) { $lastSeenUtc = $rowUtc }
                if (-not $errorHit -and "$($row[2])" -match $errPattern) { $errorHit = $row }
            }
        }
    }

    # --- 3. Act on terminal conditions ---
    if ($StopOnError -and $errorHit) {
        Write-Host "`n*** FIRST FAILED SQL / CONNECTION ERROR DETECTED ***" -ForegroundColor Red
        Write-Host ("Message: {0}" -f $errorHit[2])
        Write-Host "Stopping IR immediately..." -ForegroundColor Yellow
        az datafactory integration-runtime stop -g $ResourceGroup --factory-name $AdfName --name $IrName --no-wait 2>$null
        Write-Host "RESULT=ERROR_DETECTED_STOPPED"
        return
    }
    if ($lastResult -eq "Failed") {
        Write-Host "`n*** IR START FAILED ***" -ForegroundColor Red
        Write-Host ("ErrorCode: {0}" -f $lastErr)
        Write-Host ("Message:   {0}" -f $lastMsg)
        Write-Host "RESULT=FAILED"
        return
    }
    if ($state -eq "Started") {
        Write-Host "`n*** IR STARTED SUCCESSFULLY ***" -ForegroundColor Green
        Write-Host "RESULT=STARTED"
        return
    }

    Write-Host ("[{0:HH:mm:ss}] state={1} lastResult={2}" -f (Get-Date), $state, $lastResult) -ForegroundColor DarkGray
    Start-Sleep -Seconds $IntervalSeconds
}

Write-Host "RESULT=TIMEOUT ($TimeoutMinutes min elapsed)" -ForegroundColor Yellow
