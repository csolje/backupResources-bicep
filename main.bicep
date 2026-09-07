// Deploys a Recovery Services vault, a daily VM backup policy, and enrols existing
// VMs and file shares into the vault.
//
// Deploy into the resource group that should hold the vault:
//   az deployment group create -g <rg> -f main.bicep -p main.bicepparam
targetScope = 'resourceGroup'

@description('Name of the Recovery Services vault.')
@minLength(2)
@maxLength(50)
param vaultName string

@description('Region for the vault. Protected resources must be in the same region.')
param location string = resourceGroup().location

@description('Backup storage redundancy. Cannot be changed once items are protected.')
@allowed([
  'LocallyRedundant'
  'ZoneRedundant'
  'GeoRedundant'
])
param storageRedundancy string = 'GeoRedundant'

@description('Enable cross-region restore (GeoRedundant only).')
param crossRegionRestore bool = false

@description('Resource IDs of existing VMs to protect. Can be in other resource groups in this subscription.')
param vmResourceIds array = []

@description('Daily VM backup time (UTC).')
param vmBackupTime string = '2024-01-01T02:00:00Z'

@description('Days to keep daily VM recovery points.')
param vmDailyRetentionDays int = 30

@description('Weeks to keep weekly VM recovery points. 0 to disable.')
param vmWeeklyRetentionWeeks int = 12

@description('Months to keep monthly VM recovery points. 0 to disable.')
param vmMonthlyRetentionMonths int = 12

@description('''
File shares to protect. Each entry:
{
  storageAccountId: '/subscriptions/.../Microsoft.Storage/storageAccounts/<name>'
  shareNames: [ 'share1', 'share2' ]
}
''')
param fileShares array = []

@description('Tags applied to the vault.')
param tags object = {}

// ---------------------------------------------------------------------------
// Vault
// ---------------------------------------------------------------------------
module vault 'modules/vault.bicep' = {
  name: 'rsv-${uniqueString(deployment().name)}'
  params: {
    vaultName: vaultName
    location: location
    storageRedundancy: storageRedundancy
    crossRegionRestore: crossRegionRestore
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// VM backup policy
// ---------------------------------------------------------------------------
module vmPolicy 'modules/vm-backup-policy.bicep' = {
  name: 'rsv-vmpolicy-${uniqueString(deployment().name)}'
  params: {
    vaultName: vault.outputs.vaultName
    policyName: 'DailyVmPolicy'
    scheduleRunTime: vmBackupTime
    dailyRetentionDays: vmDailyRetentionDays
    weeklyRetentionWeeks: vmWeeklyRetentionWeeks
    monthlyRetentionMonths: vmMonthlyRetentionMonths
  }
}

// ---------------------------------------------------------------------------
// Add resources to the vault
// ---------------------------------------------------------------------------
// The vault only accepts one configuration operation at a time, so enrol serially.
@batchSize(1)
module protectVms 'modules/protect-vm.bicep' = [for (vmId, i) in vmResourceIds: {
  name: 'rsv-vm-${i}-${uniqueString(deployment().name)}'
  params: {
    vaultName: vault.outputs.vaultName
    policyId: vmPolicy.outputs.policyId
    vmResourceId: vmId
  }
}]

@batchSize(1)
module protectFileShares 'modules/protect-fileshare.bicep' = [for (fs, i) in fileShares: {
  name: 'rsv-fs-${i}-${uniqueString(deployment().name)}'
  params: {
    vaultName: vault.outputs.vaultName
    storageAccountId: fs.storageAccountId
    fileShareNames: fs.shareNames
  }
  dependsOn: [
    protectVms
  ]
}]

output vaultId string = vault.outputs.vaultId
output vaultPrincipalId string = vault.outputs.principalId
output vmPolicyId string = vmPolicy.outputs.policyId
output protectedVmIds array = [for (vmId, i) in vmResourceIds: protectVms[i].outputs.protectedItemId]
