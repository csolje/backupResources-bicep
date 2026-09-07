// Enrols an existing Azure VM into a Recovery Services vault.
// Deploy this module at the scope of the resource group that holds the VAULT.
// The VM may live in any resource group in the same subscription and region.
@description('Name of the existing Recovery Services vault.')
param vaultName string

@description('Resource ID of the backup policy to apply.')
param policyId string

@description('Full resource ID of the VM to protect.')
param vmResourceId string

// The protected item name encodes the VM's resource group and name.
var vmResourceGroup = split(vmResourceId, '/')[4]
var vmName = last(split(vmResourceId, '/'))
var containerName = 'iaasvmcontainer;iaasvmcontainerv2;${vmResourceGroup};${vmName}'
var protectedItemName = 'vm;iaasvmcontainerv2;${vmResourceGroup};${vmName}'

resource protectedVm 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2024-04-01' = {
  name: '${vaultName}/Azure/${containerName}/${protectedItemName}'
  properties: {
    protectedItemType: 'Microsoft.Compute/virtualMachines'
    policyId: policyId
    sourceResourceId: vmResourceId
  }
}

output protectedItemId string = protectedVm.id
