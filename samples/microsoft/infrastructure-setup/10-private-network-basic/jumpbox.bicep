/*
  Windows Jumpbox VM with Azure Bastion
  
  Description: 
  - Creates a Windows Server 2022 VM that can be accessed via Azure Bastion
  - Includes all necessary networking components for the jumpbox
*/

@description('Name prefix for all jumpbox resources')
param namePrefix string

@description('Location for all resources')
param location string

@description('Admin username for the jumpbox VM')
param adminUsername string = 'azureuser'

@description('Admin password for the jumpbox VM')
@secure()
param adminPassword string

@description('Jumpbox subnet ID')
param jumpboxSubnetId string

@description('Bastion subnet ID')
param bastionSubnetId string

/*
  Azure Bastion Resources
*/
resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${namePrefix}-bastion-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastionHost 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: '${namePrefix}-bastion'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: {
            id: bastionSubnetId
          }
          publicIPAddress: {
            id: bastionPublicIp.id
          }
        }
      }
    ]
  }
}

/*
  Windows Jumpbox VM Resources
*/
resource jumpboxNic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: '${namePrefix}-jumpbox-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'internal'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: jumpboxSubnetId
          }
        }
      }
    ]
  }
}

resource jumpboxVm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: '${namePrefix}-jumpbox'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    osProfile: {
      computerName: 'jumpbox'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: jumpboxNic.id
        }
      ]
    }
  }
}

/*
  Auto-shutdown schedule for the jumpbox VM
*/
resource jumpboxAutoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${jumpboxVm.name}'
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: '0100'
    }
    timeZoneId: 'UTC'
    targetResourceId: jumpboxVm.id
    notificationSettings: {
      status: 'Disabled'
    }
  }
}

// Outputs
output jumpboxVmName string = jumpboxVm.name
output jumpboxVmId string = jumpboxVm.id
output bastionHostName string = bastionHost.name
output bastionHostId string = bastionHost.id
output jumpboxPrivateIp string = jumpboxNic.properties.ipConfigurations[0].properties.privateIPAddress
output jumpboxNicId string = jumpboxNic.id
