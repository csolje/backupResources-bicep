// Example: create a Linux VM and back it up in the same deployment.
//
// Deploys a vault, a VM backup policy, a small VNet + NIC + VM, then enrols the
// new VM into the vault. Everything lands in one resource group.
//
//   az deployment group create -g rg-backup-demo -f examples/vm-with-backup.bicep \
//     -p examples/vm-with-backup.bicepparam
targetScope = 'resourceGroup'

@description('Region for all resources.')
param location string = resourceGroup().location

@description('Name of the Recovery Services vault.')
param vaultName string = 'rsv-demo-${uniqueString(resourceGroup().id)}'

@description('Name of the VM to create.')
param vmName string = 'vm-demo-01'

@description('VM size.')
param vmSize string = 'Standard_B2s'

@description('Admin username for the VM.')
param adminUsername string

@description('SSH public key for the admin user.')
@secure()
param adminSshPublicKey string

@description('Tags applied to all resources.')
param tags object = {
  environment: 'demo'
}

// ---------------------------------------------------------------------------
// Vault + policy (reuse the shared modules)
// ---------------------------------------------------------------------------
module vault '../modules/vault.bicep' = {
  name: 'demo-vault'
  params: {
    vaultName: vaultName
    location: location
    storageRedundancy: 'LocallyRedundant' // cheaper for a demo
    tags: tags
  }
}

module vmPolicy '../modules/vm-backup-policy.bicep' = {
  name: 'demo-vm-policy'
  params: {
    vaultName: vault.outputs.vaultName
    policyName: 'DailyVmPolicy'
    dailyRetentionDays: 7
    weeklyRetentionWeeks: 0
    monthlyRetentionMonths: 0
  }
}

// ---------------------------------------------------------------------------
// Network
// ---------------------------------------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-${vmName}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.10.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.10.0.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${vmName}'
  location: location
  tags: tags
  properties: {
    securityRules: [] // no inbound access; reach the VM via Bastion or serial console
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${vmName}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// VM
// ---------------------------------------------------------------------------
resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminSshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        name: 'osdisk-${vmName}'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

// ---------------------------------------------------------------------------
// Back it up
// ---------------------------------------------------------------------------
// Passing vm.id makes Bicep wait for the VM before enrolling it.
module protectVm '../modules/protect-vm.bicep' = {
  name: 'demo-protect-${vmName}'
  params: {
    vaultName: vault.outputs.vaultName
    policyId: vmPolicy.outputs.policyId
    vmResourceId: vm.id
  }
}

output vaultId string = vault.outputs.vaultId
output vmId string = vm.id
output protectedItemId string = protectVm.outputs.protectedItemId
