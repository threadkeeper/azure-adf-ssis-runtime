<p align="center">
  <img src="https://img.shields.io/badge/Built%20with-GitHub%20Copilot-8957e5?style=for-the-badge&logo=githubcopilot&logoColor=white" alt="GitHub Copilot" />
  <img src="https://img.shields.io/badge/Powered%20by-Claude%20Opus%204.6-d97706?style=for-the-badge&logo=anthropic&logoColor=white" alt="Claude" />
</p>

# Azure-SSIS Integration Runtime on SQL Managed Instance

Deploy an Azure-SSIS Integration Runtime (IR) in Azure Data Factory, connected to an existing Azure SQL Managed Instance via Express VNet Injection.

## Architecture

```
rg-sql (southafricanorth)
└── vnet-sql-dev-001
    ├── ManagedInstance       → sql-dev-001 (hosts SSISDB catalog)
    ├── snet-ssis-ir /27     → Azure-SSIS IR (Express VNet Injection)
    ├── snet-vnetaccesslinks → Fabric VNet Access Links
    ├── snet-privateendpoints→ Private Endpoints
    ├── snet-vnetdatagw      → VNet Data Gateway
    └── GatewaySubnet        → VPN/ExpressRoute Gateway

rg-integration (southafricanorth)
├── adf-dev-001              → Azure Data Factory
└── ssis-ir-001              → Azure-SSIS Integration Runtime
```

The Azure-SSIS IR is injected into the same VNet as the SQL Managed Instance, giving it direct private network access. No public endpoints are required.

## Prerequisites

- **Azure CLI** (`az`) v2.50+ with the `datafactory` extension
- An Azure subscription with Contributor access
- The `Microsoft.Batch` resource provider registered on the subscription
- An existing **Azure SQL Managed Instance** (e.g. `sql-dev-001`)
- The ADF system-assigned managed identity (e.g. `adf-dev-001`) added to the SQL MI with permission to deploy and manage SSISDB.
- An available **/27 address block** in the MI's VNet (default: `10.0.5.0/27`)

### One-time setup

```powershell
az extension add --name datafactory --upgrade
az provider register --namespace Microsoft.Batch --wait
```

### SQL MI Permission Setup (Entra ID Auth)

Before creating the SSIS IR, grant the ADF managed identity the permissions to create and manage the SSISDB catalog on the SQL Managed Instance. 

Connect to the SQL MI's `master` database using an Entra ID Admin account, and run:

```sql
-- 1. Create a server login for the ADF system-assigned Managed Identity
CREATE LOGIN [<your-adf-name>] FROM EXTERNAL PROVIDER;

-- 2. Add to server roles to allow creating and configuring SSISDB
ALTER SERVER ROLE dbcreator ADD MEMBER [<your-adf-name>];
ALTER SERVER ROLE securityadmin ADD MEMBER [<your-adf-name>];
```

## Configuration

Copy `params.sample.ps1` to `params.ps1` and update the values:

```powershell
Copy-Item params.sample.ps1 params.ps1
```

| Parameter | Description |
|-----------|-------------|
| `$SubscriptionId` | Your Azure subscription ID |
| `$ResourceGroup` | Resource group for ADF and SSIS IR (e.g. `rg-integration`) |
| `$Location` | Azure region — **must match the VNet/MI region** |
| `$MIEndpoint` | Full FQDN of the SQL MI |
| `$VNetResourceGroup` | Resource group containing the VNet (may differ from `$ResourceGroup`) |
| `$SubnetPrefix` | Free /27 CIDR block in the VNet (verify no overlap) |

> **Note:** `params.ps1` is excluded from source control via `.gitignore`.

## Scripts

Run the scripts in order:

| Script | Purpose |
|--------|---------|
| `01-create-subnet.ps1` | Creates a /27 subnet in the existing VNet for the SSIS IR |
| `02-create-adf.ps1` | Creates the Azure Data Factory instance |
| `03-create-ssis-ir.ps1` | Creates the Azure-SSIS IR with Express VNet Injection and SSISDB catalog |
| `04-manage-ssis-ir.ps1` | Start, stop, check status, or delete the IR |

### Quick start

```powershell
# 1. Deploy infrastructure
.\01-create-subnet.ps1
.\02-create-adf.ps1
.\03-create-ssis-ir.ps1

# 2. Day-to-day management
.\04-manage-ssis-ir.ps1 -Action Start
.\04-manage-ssis-ir.ps1 -Action Status
.\04-manage-ssis-ir.ps1 -Action Stop
```

## Express VNet Injection

These scripts use **Express VNet Injection** (recommended):

| Aspect | Express | Standard (Legacy) |
|--------|---------|-------------------|
| Startup time | ~5-20 min | ~20-30 min |
| Subnet delegation | Microsoft.Batch/batchAccounts | Not used |
| NSG rules | Not needed | Complex inbound/outbound rules required |
| UDR / Route table | Not needed | Required for ADF management traffic |

## Deploying SSIS Packages

Once the IR is running, deploy packages to the SSISDB catalog on the MI using:

1. **SSMS** — Connect to the MI and use the Integration Services Catalogs node
2. **SSDT / Visual Studio** — Deploy directly from an SSIS project
3. **dtutil** / **ISDeploymentWizard** — Command-line deployment
4. **ADF Pipeline** — Use an "Execute SSIS Package" activity referencing the IR

## Cost Management

The SSIS IR is billed per node while running (~$0.36/hr for Standard_D2_v3). Stop the IR when not in use:

```powershell
.\04-manage-ssis-ir.ps1 -Action Stop
```

Express VNet Injection makes restarts faster than Standard (~5-20 min), so stopping between runs is practical for intermittent workloads.

## Cleanup

To remove the SSIS IR (SSISDB on the MI is preserved):

```powershell
.\04-manage-ssis-ir.ps1 -Action Delete
```

To fully clean up, also delete the ADF and subnet via the Azure Portal or CLI.
