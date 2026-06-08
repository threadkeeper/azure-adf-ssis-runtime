# ============================================================
# Shared parameters for Azure-SSIS IR deployment
# Update these values to match your environment before running
# ============================================================

# --- Subscription & Resource Group ---
$SubscriptionId       = "<your-subscription-id>"
$ResourceGroup        = "<your-resource-group>"
$Location             = "<your-azure-region>"               # Must match the VNet region

# --- Existing SQL Managed Instance ---
$MIName               = "<your-mi-name>"
$MIEndpoint           = "<your-mi-name>.<unique-id>.database.windows.net"  # Replace with actual MI FQDN
# Authentication uses the ADF system-assigned managed identity (no SQL credentials needed).
# Ensure the ADF managed identity is added as a login on the MI with dbcreator/securityadmin roles.

# --- Existing VNet ---
$VNetName             = "<your-vnet-name>"
$VNetResourceGroup    = "<your-vnet-resource-group>"        # RG that contains the VNet

# --- New Subnet for SSIS IR (Express VNet Injection) ---
$SubnetName           = "<your-subnet-name>"
$SubnetPrefix         = "<your-subnet-cidr>"                # /27 = 32 IPs, minimum for SSIS IR

# --- Azure Data Factory ---
$AdfName              = "<your-adf-name>"

# --- Azure-SSIS Integration Runtime ---
$IrName               = "<your-ir-name>"
$NodeSize             = "Standard_D2_v3"                    # D2_v3 = 2 vCPU, 8 GB (good general purpose)
$NodeCount            = 1                                    # Scale out later if needed
$Edition              = "Standard"                           # Standard or Enterprise

# --- Diagnostics (SSIS IR start/stop + package logs to Log Analytics) ---
$LogAnalyticsWorkspace    = "<your-log-analytics-workspace>" # Workspace name (created if missing)
$LogAnalyticsResourceGroup = $ResourceGroup                 # RG for the workspace (defaults to ADF RG)
$DiagnosticSettingName    = "adf-ssis-diagnostics"          # Name of the ADF diagnostic setting

# --- Derived values (do not edit) ---
$VNetId = "/subscriptions/$SubscriptionId/resourceGroups/$VNetResourceGroup/providers/Microsoft.Network/virtualNetworks/$VNetName"
