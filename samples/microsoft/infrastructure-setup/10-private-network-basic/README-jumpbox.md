# AI Foundry with Private Network and Windows Jumpbox

This sample demonstrates how to deploy an AI Foundry account with private network access and a Windows jumpbox VM for secure connectivity.

## Architecture

The solution consists of two main Bicep templates:

### 1. main.bicep
The main template that deploys:
- AI Foundry (Cognitive Services) account with public access disabled
- Virtual network with multiple subnets
- Private endpoints for AI Services
- Private DNS zones for name resolution
- GPT-4o-mini model deployment
- AI Foundry project

### 2. jumpbox.bicep
A modular template that deploys:
- Azure Bastion host with public IP
- Windows Server 2022 jumpbox VM
- Network interface for the VM

## Network Configuration

| Subnet | Address Space | Purpose |
|--------|---------------|---------|
| pe-subnet | 192.168.0.0/24 | Private endpoints |
| AzureBastionSubnet | 192.168.1.0/26 | Azure Bastion |
| jumpbox-subnet | 192.168.2.0/28 | Jumpbox VM |

## Deployment

### Prerequisites
- Azure CLI or Azure PowerShell
- Appropriate Azure subscription permissions

### Deploy the solution

```bash
# Create resource group
az group create --name rg-aifoundry-private --location eastus

# Deploy the template
az deployment group create \
  --resource-group rg-aifoundry-private \
  --template-file main.bicep \
  --parameters adminPassword="YourSecurePassword123!"
```

### Parameters

| Parameter | Description | Default Value |
|-----------|-------------|---------------|
| aiFoundryName | Unique name for AI Foundry resources | foundrypnadisabled |
| location | Azure region | eastus |
| defaultProjectName | Name of the AI Foundry project | {aiFoundryName}-proj |
| vnetName | Virtual network name | private-vnet |
| peSubnetName | Private endpoint subnet name | pe-subnet |
| jumpboxSubnetName | Jumpbox subnet name | jumpbox-subnet |
| adminUsername | VM admin username | azureuser |
| adminPassword | VM admin password | (required) |

## Accessing the Environment

1. **Via Azure Bastion**: Navigate to the jumpbox VM in the Azure portal and click "Connect" > "Bastion"
2. **From the jumpbox**: Access AI Foundry resources using private endpoints
3. **DNS Resolution**: Private DNS zones ensure proper name resolution for AI services

## Security Features

- Public network access disabled on AI Foundry account
- Private endpoints for secure connectivity
- Network isolation with dedicated subnets
- Azure Bastion for secure VM access (no public RDP)
- Windows Server 2022 with automatic updates enabled

## Outputs

The deployment provides the following outputs:
- Account ID and name
- Project name
- Jumpbox VM name and private IP
- Bastion host name

## Clean Up

```bash
az group delete --name rg-aifoundry-private --yes --no-wait
```
