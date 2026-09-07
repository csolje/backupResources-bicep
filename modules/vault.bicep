// Recovery Services vault with sensible security defaults.
@description('Name of the Recovery Services vault.')
param vaultName string

@description('Azure region for the vault. Protected VMs must be in the same region.')
param location string = resourceGroup().location

@description('Storage redundancy for backup data.')
@allowed([
  'LocallyRedundant'
  'ZoneRedundant'
  'GeoRedundant'
])
param storageRedundancy string = 'GeoRedundant'

@description('Enable cross-region restore. Only valid with GeoRedundant storage.')
param crossRegionRestore bool = false

@description('Soft-delete retention in days (14-180).')
@minValue(14)
@maxValue(180)
param softDeleteRetentionDays int = 14

@description('Tags to apply to the vault.')
param tags object = {}

resource vault 'Microsoft.RecoveryServices/vaults@2024-04-01' = {
  name: vaultName
  location: location
  tags: tags
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    securitySettings: {
      softDeleteSettings: {
        softDeleteState: 'Enabled'
        softDeleteRetentionPeriodInDays: softDeleteRetentionDays
      }
      immutabilitySettings: {
        state: 'Disabled'
      }
    }
  }
}

// Storage redundancy must be set before any item is protected; it is locked afterwards.
resource storageConfig 'Microsoft.RecoveryServices/vaults/backupstorageconfig@2024-04-01' = {
  parent: vault
  name: 'vaultstorageconfig'
  properties: {
    storageModelType: storageRedundancy
    storageType: storageRedundancy
    crossRegionRestoreFlag: storageRedundancy == 'GeoRedundant' ? crossRegionRestore : false
  }
}

output vaultId string = vault.id
output vaultName string = vault.name
output principalId string = vault.identity.principalId
